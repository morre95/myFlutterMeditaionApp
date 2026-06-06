import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_login_service.dart';
import 'package:my_meditation_app/features/cloud/pcloud/domain/pcloud_config.dart';

void main() {
  test('returns an auth token and host on success', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'eapi.pcloud.com');
      expect(request.url.path, '/userinfo');
      expect(request.url.queryParameters['getauth'], '1');
      expect(request.url.queryParameters['username'], 'a@b.com');
      expect(request.url.queryParameters['password'], 'secret');
      return http.Response(jsonEncode({'result': 0, 'auth': 'TOKEN'}), 200);
    });
    final service = PCloudLoginService(client: client);

    final session = await service.login(
      email: 'a@b.com',
      password: 'secret',
      region: PCloudRegion.eu,
    );

    expect(session.authToken, 'TOKEN');
    expect(session.apiHost, 'eapi.pcloud.com');
  });

  test('throws PCloudTfaRequiredException when pCloud asks for a code', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'result': 2064,
          'error': "Please provide 'code'.",
          'token': 'TFATOKEN',
        }),
        200,
      );
    });
    final service = PCloudLoginService(client: client);

    await expectLater(
      () => service.login(
        email: 'a@b.com',
        password: 'secret',
        region: PCloudRegion.us,
      ),
      throwsA(
        isA<PCloudTfaRequiredException>().having(
          (e) => e.token,
          'token',
          'TFATOKEN',
        ),
      ),
    );
  });

  test('verifyTfaCode sends the code and token and returns the session', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['code'], '123456');
      expect(request.url.queryParameters['token'], 'TFATOKEN');
      return http.Response(jsonEncode({'result': 0, 'auth': 'TOKEN'}), 200);
    });
    final service = PCloudLoginService(client: client);

    final session = await service.verifyTfaCode(
      email: 'a@b.com',
      password: 'secret',
      region: PCloudRegion.us,
      code: '123456',
      token: 'TFATOKEN',
    );

    expect(session.authToken, 'TOKEN');
  });

  test('throws PCloudException with the API error on bad credentials', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'result': 2000, 'error': 'Log in failed.'}),
        200,
      );
    });
    final service = PCloudLoginService(client: client);

    await expectLater(
      () => service.login(
        email: 'a@b.com',
        password: 'wrong',
        region: PCloudRegion.us,
      ),
      throwsA(
        isA<PCloudException>().having(
          (e) => e.message,
          'message',
          'Log in failed.',
        ),
      ),
    );
  });
}
