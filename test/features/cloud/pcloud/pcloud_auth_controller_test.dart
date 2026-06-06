import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_login_service.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_session_store.dart';
import 'package:my_meditation_app/features/cloud/pcloud/domain/pcloud_config.dart';

void main() {
  test('login stores the session and exposes connection state', () async {
    final store = _FakeSessionStore();
    final controller = PCloudAuthController(
      loginService: _StubLoginService(
        const PCloudSession(authToken: 'tok', apiHost: 'api.pcloud.com'),
      ),
      store: store,
    );

    await controller.login(
      email: 'a@b.com',
      password: 'pw',
      region: PCloudRegion.us,
    );

    expect(controller.isConnected, isTrue);
    expect(controller.authToken, 'tok');
    expect(controller.apiHost, 'api.pcloud.com');
    expect(store.session?.authToken, 'tok');
  });

  test('disconnect clears the session and store', () async {
    final store = _FakeSessionStore()
      ..session = const PCloudSession(authToken: 't', apiHost: 'h');
    final controller = PCloudAuthController(
      loginService: _StubLoginService(
        const PCloudSession(authToken: 't', apiHost: 'h'),
      ),
      store: store,
    );

    await controller.disconnect();

    expect(controller.isConnected, isFalse);
    expect(store.session, isNull);
  });

  test('loadStoredSession tolerates a failing store', () async {
    final controller = PCloudAuthController(
      loginService: _StubLoginService(
        const PCloudSession(authToken: 't', apiHost: 'h'),
      ),
      store: _ThrowingSessionStore(),
    );

    await controller.loadStoredSession();

    expect(controller.isConnected, isFalse);
  });
}

class _StubLoginService implements PCloudLoginService {
  _StubLoginService(this._session);

  final PCloudSession _session;

  @override
  Future<PCloudSession> login({
    required String email,
    required String password,
    required PCloudRegion region,
  }) async => _session;

  @override
  Future<PCloudSession> verifyTfaCode({
    required String email,
    required String password,
    required PCloudRegion region,
    required String code,
    String? token,
  }) async => _session;
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

class _ThrowingSessionStore implements PCloudSessionStore {
  @override
  Future<PCloudSession?> read() async => throw Exception('no secure storage');

  @override
  Future<void> write(PCloudSession s) async {}

  @override
  Future<void> clear() async {}
}
