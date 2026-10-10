import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_download_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_download_store.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_service.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

const _rain = AudioSource(
  id: 'pcloud:100',
  kind: AudioSourceKind.pCloud,
  displayName: 'Rain.MP3',
  reference: '100',
);

void main() {
  late Directory root;
  late _ControlledPCloud cloud;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pcloud-downloads-');
    cloud = _ControlledPCloud()..contentLength = 4;
  });
  tearDown(() => root.delete(recursive: true));

  PCloudDownloadController controller() => PCloudDownloadController(
    service: cloud.service,
    store: PCloudDownloadStore(directory: root),
  );

  test(
    'a completed transfer is available offline and survives a restart',
    () async {
      final downloads = controller();
      final download = downloads.download(_rain);
      final transfer = await cloud.nextTransfer();
      transfer.add([1, 2]);
      await pumpEventQueue();

      expect(downloads.stateOf(_rain).status, PCloudDownloadStatus.downloading);
      expect(downloads.stateOf(_rain).receivedBytes, 2);
      expect(downloads.stateOf(_rain).totalBytes, 4);
      expect(downloads.offlineCopyOf(_rain), isNull);

      transfer.add([3, 4]);
      await transfer.close();
      await download;

      final copy = downloads.offlineCopyOf(_rain)!;
      expect(downloads.stateOf(_rain).status, PCloudDownloadStatus.available);
      expect(await File(copy.path).readAsBytes(), [1, 2, 3, 4]);

      final restarted = controller();
      await restarted.load();
      final restored = restarted.offlineCopyOf(_rain)!;
      expect(restored.source.id, 'pcloud:100');
      expect(restored.source.kind, AudioSourceKind.pCloud);
      expect(restored.source.reference, '100');
      expect(restored.source.storedSize, 4);
      expect(await File(restored.path).readAsBytes(), [1, 2, 3, 4]);
    },
  );

  test(
    'cancel stops a stalled transfer, leaves no copy, and retry completes',
    () async {
      final downloads = controller();
      final canceled = downloads.download(_rain);
      final first = await cloud.nextTransfer();
      first.add([1, 2]);
      await pumpEventQueue();

      downloads.cancel(_rain);
      await canceled;

      expect(first.isCanceled, isTrue);
      expect(
        downloads.stateOf(_rain).status,
        PCloudDownloadStatus.notDownloaded,
      );
      expect(await root.list().toList(), isEmpty);
      final restarted = controller();
      await restarted.load();
      expect(restarted.offlineCopyOf(_rain), isNull);

      final retried = downloads.download(_rain);
      final second = await cloud.nextTransfer();
      second.add([5, 6, 7, 8]);
      await second.close();
      await retried;

      expect(await File(downloads.offlineCopyOf(_rain)!.path).readAsBytes(), [
        5,
        6,
        7,
        8,
      ]);
    },
  );

  group('cancel while the download request is still pending', () {
    test(
      'takes effect at once and a new download ignores the late response',
      () async {
        cloud.holdResponses = true;
        final downloads = controller();
        final abandoned = downloads.download(_rain);
        final first = await cloud.nextTransfer();

        downloads.cancel(_rain);

        expect(
          downloads.stateOf(_rain).status,
          PCloudDownloadStatus.notDownloaded,
        );

        final retried = downloads.download(_rain);
        final second = await cloud.nextTransfer();
        expect(cloud.transferCount, 2);

        first.respond();
        await abandoned;
        expect(first.isCanceled, isTrue);
        expect(
          downloads.stateOf(_rain).status,
          PCloudDownloadStatus.downloading,
        );

        second.respond();
        second.add([5, 6, 7, 8]);
        await second.close();
        await retried;
        expect(await File(downloads.offlineCopyOf(_rain)!.path).readAsBytes(), [
          5,
          6,
          7,
          8,
        ]);
        expect(await root.list().map((entry) => entry.path).toList(), [
          '${root.path}/100',
        ]);
      },
    );

    test('stays not downloaded when the abandoned request fails', () async {
      cloud.holdResponses = true;
      final downloads = controller();
      final abandoned = downloads.download(_rain);
      final transfer = await cloud.nextTransfer();

      downloads.cancel(_rain);
      transfer.failResponse(http.ClientException('Connection reset'));
      await abandoned;

      expect(
        downloads.stateOf(_rain).status,
        PCloudDownloadStatus.notDownloaded,
      );
    });
  });

  test('dispose stops in-flight transfers without later updates', () async {
    final downloads = controller();
    final download = downloads.download(_rain);
    final transfer = await cloud.nextTransfer();
    transfer.add([1, 2]);
    await pumpEventQueue();

    downloads.dispose();
    transfer.add([3, 4]);
    await transfer.close();
    await download;

    expect(transfer.isCanceled, isTrue);
    expect(await root.list().toList(), isEmpty);
  });

  group(
    'a failed transfer reports why, leaves no copy, and can be retried',
    () {
      Future<void> expectFailedThenRetried(
        PCloudDownloadController downloads,
        Future<void> failed,
        String message,
      ) async {
        await failed;
        expect(downloads.stateOf(_rain).status, PCloudDownloadStatus.failed);
        expect(downloads.stateOf(_rain).errorMessage, message);
        expect(downloads.offlineCopyOf(_rain), isNull);
        expect(await root.list().toList(), isEmpty);

        cloud.offline = false;
        final retried = downloads.download(_rain);
        final transfer = await cloud.nextTransfer();
        transfer.add([1, 2, 3, 4]);
        await transfer.close();
        await retried;
        expect(downloads.stateOf(_rain).status, PCloudDownloadStatus.available);
      }

      const connectionMessage =
          'Download of Rain.MP3 failed. Check your connection and retry.';

      test('when the connection drops mid-transfer', () async {
        final downloads = controller();
        final failed = downloads.download(_rain);
        final transfer = await cloud.nextTransfer();
        transfer.add([1, 2]);
        transfer.fail(http.ClientException('Connection reset'));
        await expectFailedThenRetried(downloads, failed, connectionMessage);
      });

      test('when the transfer ends before the announced length', () async {
        final downloads = controller();
        final failed = downloads.download(_rain);
        final transfer = await cloud.nextTransfer();
        transfer.add([1, 2]);
        await transfer.close();
        await expectFailedThenRetried(downloads, failed, connectionMessage);
      });

      test('when the device is offline', () async {
        cloud.offline = true;
        final downloads = controller();
        await expectFailedThenRetried(
          downloads,
          downloads.download(_rain),
          connectionMessage,
        );
      });

      test('when storage runs out', () async {
        var full = true;
        final downloads = PCloudDownloadController(
          service: cloud.service,
          store: PCloudDownloadStore(
            directory: root,
            writeChunk: (file, chunk) async {
              if (full) {
                full = false;
                throw FileSystemException(
                  'Write failed',
                  file.path,
                  const OSError('No space left on device', 28),
                );
              }
              await file.writeFrom(chunk);
            },
          ),
        );
        final failed = downloads.download(_rain);
        final transfer = await cloud.nextTransfer();
        transfer.add([1, 2]);
        await expectFailedThenRetried(
          downloads,
          failed,
          'Not enough storage to download Rain.MP3. Free up space and retry.',
        );
        expect(transfer.isCanceled, isTrue);
      });
    },
  );

  test('repeated downloads share one transfer and one copy', () async {
    final downloads = controller();
    final first = downloads.download(_rain);
    final repeated = downloads.download(_rain);
    final transfer = await cloud.nextTransfer();
    transfer.add([1, 2, 3, 4]);
    await transfer.close();
    await Future.wait([first, repeated]);
    await downloads.download(_rain);

    expect(cloud.transferCount, 1);
    expect(await root.list().map((entry) => entry.path).toList(), [
      '${root.path}/100',
    ]);
  });

  test(
    'restart drops interrupted staging and does not advertise broken copies',
    () async {
      final downloads = controller();
      final download = downloads.download(_rain);
      final transfer = await cloud.nextTransfer();
      transfer.add([1, 2, 3, 4]);
      await transfer.close();
      await download;
      final committed = File(downloads.offlineCopyOf(_rain)!.path);
      await committed.writeAsBytes([1, 2]);
      await Directory('${root.path}/.200-interrupted').create();
      await Directory('${root.path}/300').create();

      final restarted = controller();
      await restarted.load();

      expect(restarted.offlineCopyOf(_rain), isNull);
      expect(
        await root.list().map((entry) => entry.path).toList(),
        isNot(contains('${root.path}/.200-interrupted')),
      );

      final redownload = restarted.download(_rain);
      final again = await cloud.nextTransfer();
      again.add([5, 6, 7, 8]);
      await again.close();
      await redownload;
      expect(await File(restarted.offlineCopyOf(_rain)!.path).readAsBytes(), [
        5,
        6,
        7,
        8,
      ]);
    },
  );

  group('restart when the download directory is not fully accessible', () {
    Future<void> setMode(String mode) async {
      final result = await Process.run('chmod', [mode, root.path]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    test('starts with no offline copies when it cannot be listed', () async {
      await setMode('000');
      addTearDown(() => setMode('700'));

      final restarted = controller();
      await restarted.load();

      expect(restarted.offlineCopyOf(_rain), isNull);
    });

    test('keeps committed copies when staging cannot be removed', () async {
      final downloads = controller();
      final download = downloads.download(_rain);
      final transfer = await cloud.nextTransfer();
      transfer.add([1, 2, 3, 4]);
      await transfer.close();
      await download;
      await Directory('${root.path}/.200-interrupted').create();
      await setMode('500');
      addTearDown(() => setMode('700'));

      final restarted = controller();
      await restarted.load();

      expect(restarted.stateOf(_rain).status, PCloudDownloadStatus.available);
    });
  });
}

/// pCloud API whose file transfers are fed chunk by chunk by the test.
class _ControlledPCloud {
  final _transfers = StreamController<_Transfer>();
  late final StreamIterator<_Transfer> _pending = StreamIterator(
    _transfers.stream,
  );

  /// Announced length of every transfer; null when the server omits it.
  int? contentLength;

  int transferCount = 0;

  /// Set to make every request fail as if the device were offline.
  bool offline = false;

  /// Set to hold each file response until the test calls [_Transfer.respond]
  /// or [_Transfer.failResponse].
  bool holdResponses = false;

  late final PCloudService service = PCloudService(
    session: const _FakeSession(),
    client: MockClient.streaming((request, _) async {
      if (offline) throw http.ClientException('Network is unreachable');
      if (request.url.path == '/getfilelink') {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'result': 0,
                'hosts': ['c1.pcloud.com'],
                'path': '/dl/${request.url.queryParameters['fileid']}',
              }),
            ),
          ),
          200,
        );
      }
      final transfer = _Transfer();
      transferCount++;
      _transfers.add(transfer);
      if (holdResponses) await transfer._response.future;
      return http.StreamedResponse(
        transfer._bytes.stream,
        200,
        contentLength: contentLength,
      );
    }),
  );

  /// Waits for the next file transfer request.
  Future<_Transfer> nextTransfer() async {
    await _pending.moveNext();
    return _pending.current;
  }
}

class _Transfer {
  final _bytes = StreamController<List<int>>();
  final _response = Completer<void>();

  void respond() => _response.complete();
  void failResponse(Object error) => _response.completeError(error);

  bool get isCanceled => _canceled;
  bool _canceled = false;

  void add(List<int> chunk) => _bytes.add(chunk);
  void fail(Object error) => _bytes.addError(error);
  Future<void> close() => _bytes.close();

  _Transfer() {
    _bytes.onCancel = () => _canceled = true;
  }
}

class _FakeSession implements PCloudSessionProvider {
  const _FakeSession();

  @override
  String? get authToken => 'tok';

  @override
  String? get apiHost => 'api.pcloud.com';
}
