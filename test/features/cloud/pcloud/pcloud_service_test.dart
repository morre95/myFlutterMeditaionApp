import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_service.dart';
import 'package:my_meditation_app/features/cloud/pcloud/domain/pcloud_config.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

void main() {
  const session = _FakeSession(token: 'tok', host: 'api.pcloud.com');

  test('listFolder returns sub-folders and audio files only', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'api.pcloud.com');
      expect(request.url.path, '/listfolder');
      expect(request.url.queryParameters['folderid'], '0');
      expect(request.url.queryParameters['access_token'], 'tok');
      return http.Response(
        jsonEncode({
          'result': 0,
          'metadata': {
            'contents': [
              {'name': 'Sleep', 'isfolder': true, 'folderid': 42},
              {'name': 'rain.mp3', 'isfolder': false, 'fileid': 100},
              {'name': 'notes.txt', 'isfolder': false, 'fileid': 101},
            ],
          },
        }),
        200,
      );
    });
    final service = PCloudService(session: session, client: client);

    final listing = await service.listFolder(PCloudService.rootFolderId);

    expect(listing.folders.single.name, 'Sleep');
    expect(listing.folders.single.id, 42);
    expect(listing.audioFiles.single.displayName, 'rain.mp3');
    expect(listing.audioFiles.single.kind, AudioSourceKind.pCloud);
    expect(listing.audioFiles.single.reference, '100');
  });

  test('getFileLink builds a streaming URL from hosts and path', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/getfilelink');
      expect(request.url.queryParameters['fileid'], '100');
      return http.Response(
        jsonEncode({
          'result': 0,
          'hosts': ['edge1.pcloud.com', 'edge2.pcloud.com'],
          'path': '/stream/rain.mp3',
        }),
        200,
      );
    });
    final service = PCloudService(session: session, client: client);

    final url = await service.getFileLink('100');

    expect(url, 'https://edge1.pcloud.com/stream/rain.mp3');
  });

  test('throws PCloudException on a non-zero API result', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'result': 2094, 'error': 'Invalid access token.'}),
        200,
      );
    });
    final service = PCloudService(session: session, client: client);

    expect(() => service.listFolder(0), throwsA(isA<PCloudException>()));
  });
}

class _FakeSession implements PCloudSessionProvider {
  const _FakeSession({required this.token, required this.host});

  final String token;
  final String host;

  @override
  String? get authToken => token;

  @override
  String? get apiHost => host;
}
