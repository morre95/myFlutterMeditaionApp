import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/oauth_authenticator.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_session_store.dart';
import 'package:my_meditation_app/features/cloud/pcloud/domain/pcloud_config.dart';

void main() {
  group('parseCallback', () {
    test('reads the access token and hostname from the fragment', () {
      final session = PCloudAuthController.parseCallback(
        'mymeditation://oauth#access_token=tok123&token_type=bearer'
        '&hostname=eapi.pcloud.com',
      );

      expect(session.accessToken, 'tok123');
      expect(session.apiHost, 'eapi.pcloud.com');
    });

    test('maps locationid 2 to the EU host', () {
      final session = PCloudAuthController.parseCallback(
        'mymeditation://oauth#access_token=tok&locationid=2',
      );

      expect(session.apiHost, 'eapi.pcloud.com');
    });

    test('defaults to the US host when no region is given', () {
      final session = PCloudAuthController.parseCallback(
        'mymeditation://oauth#access_token=tok',
      );

      expect(session.apiHost, 'api.pcloud.com');
    });

    test('throws when the token is missing', () {
      expect(
        () =>
            PCloudAuthController.parseCallback('mymeditation://oauth#error=1'),
        throwsA(isA<PCloudException>()),
      );
    });
  });

  test('disconnect clears the session and store', () async {
    final store = _FakeSessionStore()
      ..session = const PCloudSession(accessToken: 't', apiHost: 'h');
    final controller = PCloudAuthController(
      authenticator: _FakeAuthenticator(''),
      store: store,
    );

    await controller.disconnect();

    expect(controller.isConnected, isFalse);
    expect(store.session, isNull);
  });
}

class _FakeAuthenticator implements OAuthAuthenticator {
  _FakeAuthenticator(this.callback);

  final String callback;

  @override
  Future<String> authenticate({
    required String url,
    required String callbackUrlScheme,
  }) async => callback;
}

class _FakeSessionStore implements PCloudSessionStore {
  PCloudSession? session;

  @override
  Future<PCloudSession?> read() async => session;

  @override
  Future<void> write(PCloudSession s) async => session = s;

  @override
  Future<void> clear() async => session = null;
}
