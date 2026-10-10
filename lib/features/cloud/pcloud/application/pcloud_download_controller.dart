import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../shared/domain/audio_source.dart';
import '../domain/pcloud_config.dart';
import 'pcloud_download_store.dart';
import 'pcloud_service.dart';

enum PCloudDownloadStatus { notDownloaded, downloading, available, failed }

class PCloudDownloadState {
  const PCloudDownloadState._({
    required this.status,
    this.receivedBytes = 0,
    this.totalBytes,
    this.copy,
    this.errorMessage,
  });

  const PCloudDownloadState.notDownloaded()
    : this._(status: PCloudDownloadStatus.notDownloaded);

  const PCloudDownloadState.downloading({
    required int receivedBytes,
    int? totalBytes,
  }) : this._(
         status: PCloudDownloadStatus.downloading,
         receivedBytes: receivedBytes,
         totalBytes: totalBytes,
       );

  const PCloudDownloadState.available(PCloudOfflineCopy copy)
    : this._(status: PCloudDownloadStatus.available, copy: copy);

  const PCloudDownloadState.failed(String message)
    : this._(status: PCloudDownloadStatus.failed, errorMessage: message);

  final PCloudDownloadStatus status;
  final int receivedBytes;

  /// Announced transfer size; null when pCloud does not send a length.
  final int? totalBytes;

  /// Whole percent received; null while the size is unknown.
  int? get progressPercent {
    final total = totalBytes;
    if (total == null || total == 0) return null;
    return receivedBytes * 100 ~/ total;
  }

  final PCloudOfflineCopy? copy;
  final String? errorMessage;
}

/// Downloads pCloud sounds into [PCloudDownloadStore] and tracks each file's
/// transfer and offline availability by pCloud file id.
class PCloudDownloadController extends ChangeNotifier {
  PCloudDownloadController({
    required PCloudService service,
    required PCloudDownloadStore store,
  }) : _service = service,
       _store = store;

  final PCloudService _service;
  final PCloudDownloadStore _store;
  final Map<String, PCloudDownloadState> _states = {};
  final Map<String, _ActiveTransfer> _active = {};

  PCloudDownloadState stateOf(AudioSource source) =>
      _states[source.reference] ?? const PCloudDownloadState.notDownloaded();

  /// The committed local copy of [source], if one is available offline.
  PCloudOfflineCopy? offlineCopyOf(AudioSource source) => stateOf(source).copy;

  /// Restores copies committed before the app restarted.
  Future<void> load() async {
    for (final copy in await _store.load()) {
      _states[copy.source.reference] = PCloudDownloadState.available(copy);
    }
    notifyListeners();
  }

  /// Starts a transfer unless [source] is already downloading or available;
  /// a repeated request joins the running transfer.
  Future<void> download(AudioSource source) {
    final fileId = source.reference;
    final running = _active[fileId];
    if (running != null) return running.done;
    if (stateOf(source).status == PCloudDownloadStatus.available) {
      return Future.value();
    }
    final active = _active[fileId] = _ActiveTransfer();
    return active.done = _download(source, active);
  }

  Future<void> _download(AudioSource source, _ActiveTransfer active) async {
    final fileId = source.reference;
    _set(fileId, const PCloudDownloadState.downloading(receivedBytes: 0));
    try {
      final transfer = await _service.openDownload(fileId);
      final copy = await _store.save(
        source,
        _tracked(fileId, active, transfer.bytes, transfer.length),
      );
      _settle(fileId, active, PCloudDownloadState.available(copy));
    } on _DownloadCanceled {
      // cancel() already reset the state.
    } on FileSystemException catch (error) {
      debugPrint('pCloud download could not be stored: $error');
      _settle(
        fileId,
        active,
        PCloudDownloadState.failed(
          error.osError?.errorCode == _noSpaceLeftOnDevice
              ? 'Not enough storage to download ${source.displayName}. '
                    'Free up space and retry.'
              : 'Could not save ${source.displayName} on this device.',
        ),
      );
    } on PCloudException catch (error) {
      _settle(fileId, active, PCloudDownloadState.failed(error.message));
    } on Exception catch (error) {
      debugPrint('pCloud download transfer failed: $error');
      _settle(
        fileId,
        active,
        PCloudDownloadState.failed(
          'Download of ${source.displayName} failed. '
          'Check your connection and retry.',
        ),
      );
    } finally {
      // A canceled transfer may already be replaced by a new one.
      if (identical(_active[fileId], active)) _active.remove(fileId);
    }
  }

  /// Reports progress whenever its shown percent changes and rejects a
  /// transfer that ends short or empty, before the store can commit it.
  Stream<List<int>> _tracked(
    String fileId,
    _ActiveTransfer active,
    Stream<List<int>> bytes,
    int? length,
  ) async* {
    var received = 0;
    await for (final chunk in active.guard(bytes)) {
      received += chunk.length;
      final progress = PCloudDownloadState.downloading(
        receivedBytes: received,
        totalBytes: length,
      );
      // Every row listens to this controller, so skip invisible changes.
      if (progress.progressPercent != _states[fileId]?.progressPercent) {
        _settle(fileId, active, progress);
      }
      yield chunk;
    }
    if (received == 0 || (length != null && received != length)) {
      throw const _IncompleteTransfer();
    }
  }

  /// Stops [source]'s transfer at once, whether its request is still pending
  /// or no bytes are arriving; anything the abandoned transfer reports later
  /// is ignored.
  void cancel(AudioSource source) {
    final fileId = source.reference;
    final active = _active.remove(fileId);
    if (active == null) return;
    active.cancel();
    _states.remove(fileId);
    notifyListeners();
  }

  /// Cancels in-flight transfers so none reports after disposal.
  @override
  void dispose() {
    for (final active in _active.values) {
      active.cancel();
    }
    _active.clear();
    super.dispose();
  }

  /// Records [state] unless [active] was canceled.
  void _settle(
    String fileId,
    _ActiveTransfer active,
    PCloudDownloadState state,
  ) {
    if (!active.isCanceled) _set(fileId, state);
  }

  void _set(String fileId, PCloudDownloadState state) {
    _states[fileId] = state;
    notifyListeners();
  }
}

/// ENOSPC on Android and Linux.
const _noSpaceLeftOnDevice = 28;

class _IncompleteTransfer implements Exception {
  const _IncompleteTransfer();
}

class _DownloadCanceled implements Exception {
  const _DownloadCanceled();
}

class _ActiveTransfer {
  final _canceled = Completer<void>();
  late final Future<void> done;

  bool get isCanceled => _canceled.isCompleted;

  void cancel() {
    if (!_canceled.isCompleted) _canceled.complete();
  }

  /// Forwards [bytes] until [cancel], which ends the stream with
  /// [_DownloadCanceled] and releases the network transfer, also when the
  /// transfer only starts after [cancel].
  Stream<List<int>> guard(Stream<List<int>> bytes) {
    late final StreamSubscription<List<int>> source;
    final output = StreamController<List<int>>();
    output
      ..onListen = () {
        source = bytes.listen(
          output.add,
          onError: output.addError,
          onDone: output.close,
        );
        _canceled.future.then((_) {
          if (output.isClosed) return;
          source.cancel();
          output
            ..addError(const _DownloadCanceled())
            ..close();
        });
      }
      ..onPause = (() => source.pause())
      ..onResume = (() => source.resume())
      ..onCancel = (() => source.cancel());
    return output.stream;
  }
}
