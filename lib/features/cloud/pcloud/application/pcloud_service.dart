import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../shared/domain/audio_source.dart';
import '../domain/pcloud_config.dart';
import '../domain/pcloud_listing.dart';
import 'pcloud_auth_controller.dart';

/// Thin client over the pCloud HTTP API. Browses folders and resolves
/// temporary streaming links for audio files.
///
/// See https://docs.pcloud.com/ for the endpoint contracts.
class PCloudService {
  PCloudService({required PCloudSessionProvider session, http.Client? client})
    : _session = session,
      _client = client ?? http.Client();

  static const int rootFolderId = 0;

  final PCloudSessionProvider _session;
  final http.Client _client;

  /// Lists the contents of [folderId], returning sub-folders and audio files.
  Future<PCloudListing> listFolder(int folderId) async {
    final json = await _get('listfolder', {'folderid': '$folderId'});
    final metadata = json['metadata'] as Map<String, dynamic>?;
    final contents = (metadata?['contents'] as List<dynamic>?) ?? const [];

    final folders = <PCloudFolder>[];
    final audioFiles = <AudioSource>[];
    for (final entry in contents.cast<Map<String, dynamic>>()) {
      final name = entry['name'] as String;
      final isFolder = entry['isfolder'] as bool? ?? false;
      if (isFolder) {
        folders.add(PCloudFolder(id: entry['folderid'] as int, name: name));
        continue;
      }
      final fileId = entry['fileid'];
      if (fileId == null) continue;
      final source = AudioSource(
        id: 'pcloud:$fileId',
        kind: AudioSourceKind.pCloud,
        displayName: name,
        reference: '$fileId',
      );
      if (source.isSupportedAudio) audioFiles.add(source);
    }

    folders.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    audioFiles.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return PCloudListing(folders: folders, audioFiles: audioFiles);
  }

  /// Resolves a fresh, temporary streaming URL for a pCloud file id. Links are
  /// short-lived, so this is called at playback time and never persisted.
  Future<String> getFileLink(String fileId) async {
    final json = await _get('getfilelink', {'fileid': fileId});
    final hosts = (json['hosts'] as List<dynamic>?)?.cast<String>() ?? const [];
    final path = json['path'] as String?;
    if (hosts.isEmpty || path == null) {
      throw const PCloudException('pCloud did not return a streaming link.');
    }
    return 'https://${hosts.first}$path';
  }

  /// Opens a byte transfer of a pCloud file from a fresh file link.
  Future<PCloudTransfer> openDownload(String fileId) async {
    final link = await getFileLink(fileId);
    final response = await _client.send(http.Request('GET', Uri.parse(link)));
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw PCloudException('pCloud download failed (${response.statusCode}).');
    }
    return PCloudTransfer(
      bytes: response.stream,
      length: response.contentLength,
    );
  }

  Future<Map<String, dynamic>> _get(
    String endpoint,
    Map<String, String> params,
  ) async {
    final token = _session.authToken;
    final host = _session.apiHost;
    if (token == null || host == null) {
      throw const PCloudException('Not connected to pCloud.');
    }

    final uri = Uri.https(host, '/$endpoint', {
      ...params,
      'access_token': token,
    });
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw PCloudException('pCloud request failed (${response.statusCode}).');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final result = json['result'] as int? ?? -1;
    if (result != 0) {
      final error = json['error'] as String? ?? 'unknown error';
      throw PCloudException('pCloud error $result: $error');
    }
    return json;
  }
}

/// The body of a pCloud file download; [length] is null when not announced.
class PCloudTransfer {
  const PCloudTransfer({required this.bytes, required this.length});

  final Stream<List<int>> bytes;
  final int? length;
}
