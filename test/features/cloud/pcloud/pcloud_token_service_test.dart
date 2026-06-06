import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_token_service.dart';
import 'package:my_meditation_app/features/cloud/pcloud/domain/pcloud_config.dart';

void main() {
  test(
    'validate returns true and sends the token on the chosen region',
    () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'eapi.pcloud.com');
        expect(request.url.path, '/userinfo');
        expect(request.url.queryParameters['access_token'], 'tok');
        return http.Response(jsonEncode({'result': 0, 'userid': 1}), 200);
      });
      final service = PCloudTokenService(client: client);

      expect(
        await service.validate(token: 'tok', region: PCloudRegion.eu),
        isTrue,
      );
    },
  );

  test('validate returns false for a rejected token', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'result': 2094, 'error': 'Invalid access_token.'}),
        200,
      );
    });
    final service = PCloudTokenService(client: client);

    expect(
      await service.validate(token: 'bad', region: PCloudRegion.us),
      isFalse,
    );
  });
}
