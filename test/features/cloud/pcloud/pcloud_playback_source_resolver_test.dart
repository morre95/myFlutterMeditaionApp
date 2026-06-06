import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
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

  test('resolves a pCloud source to a streaming URL', () async {
    final resolver = PCloudPlaybackSourceResolver(
      service: serviceReturning('https://edge.pcloud.com/stream/rain.mp3'),
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
}

class _FakeSession implements PCloudSessionProvider {
  @override
  String? get accessToken => 'tok';

  @override
  String? get apiHost => 'api.pcloud.com';
}
