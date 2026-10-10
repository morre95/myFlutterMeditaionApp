import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_download_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_download_store.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_playback_source_resolver.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_service.dart';
import 'package:my_meditation_app/features/player/application/playback_source_resolver.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

void main() {
  PCloudService serviceReturning(String streamUrl) {
    final uri = Uri.parse(streamUrl);
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'result': 0,
          'hosts': [uri.host],
          'path': uri.path,
        }),
        200,
      );
    });
    return PCloudService(session: _FakeSession(), client: client);
  }

  PCloudDownloadController noDownloads() => PCloudDownloadController(
    service: serviceReturning('https://unused'),
    store: PCloudDownloadStore(directory: Directory.systemTemp),
  );

  test('resolves a pCloud source to a streaming URL', () async {
    final resolver = PCloudPlaybackSourceResolver(
      service: serviceReturning('https://edge.pcloud.com/stream/rain.mp3'),
      downloads: noDownloads(),
    );
    const source = AudioSource(
      id: 'pcloud:100',
      kind: AudioSourceKind.pCloud,
      displayName: 'rain.mp3',
      reference: '100',
    );

    final media = await resolver.resolve(source);

    expect(media.kind, PlayableMediaKind.url);
    expect(media.locator, 'https://edge.pcloud.com/stream/rain.mp3');
  });

  test('delegates local sources to the local resolver', () async {
    final resolver = PCloudPlaybackSourceResolver(
      service: serviceReturning('https://unused'),
      downloads: noDownloads(),
    );
    const source = AudioSource(
      id: 'local:/music/rain.wav',
      kind: AudioSourceKind.localFile,
      displayName: 'rain.wav',
      reference: '/music/rain.wav',
    );

    final media = await resolver.resolve(source);

    expect(media.kind, PlayableMediaKind.file);
    expect(media.locator, '/music/rain.wav');
  });

  test('prefers a downloaded copy without contacting pCloud', () async {
    final root = await Directory.systemTemp.createTemp('resolver-downloads-');
    addTearDown(() => root.delete(recursive: true));
    const source = AudioSource(
      id: 'pcloud:100',
      kind: AudioSourceKind.pCloud,
      displayName: 'rain.mp3',
      reference: '100',
    );
    final online = PCloudService(
      session: _FakeSession(),
      client: MockClient((request) async {
        if (request.url.path == '/getfilelink') {
          return http.Response(
            jsonEncode({
              'result': 0,
              'hosts': ['c1.pcloud.com'],
              'path': '/dl/rain.mp3',
            }),
            200,
          );
        }
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );
    await PCloudDownloadController(
      service: online,
      store: PCloudDownloadStore(directory: root),
    ).download(source);
    final offline = PCloudService(
      session: _FakeSession(),
      client: MockClient((_) => throw http.ClientException('offline')),
    );
    final downloads = PCloudDownloadController(
      service: offline,
      store: PCloudDownloadStore(directory: root),
    );
    await downloads.load();
    final resolver = PCloudPlaybackSourceResolver(
      service: offline,
      downloads: downloads,
    );

    final media = await resolver.resolve(source);

    expect(media.kind, PlayableMediaKind.file);
    expect(await File(media.locator).readAsBytes(), [1, 2, 3]);
  });
}

class _FakeSession implements PCloudSessionProvider {
  @override
  String? get authToken => 'tok';

  @override
  String? get apiHost => 'api.pcloud.com';
}
