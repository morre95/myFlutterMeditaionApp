import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_session_store.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_token_service.dart';
import 'package:my_meditation_app/features/cloud/pcloud/domain/pcloud_config.dart';

void main() {
  test('connectWithToken stores the session when the token is valid', () async {
    final store = _FakeSessionStore();
    final controller = PCloudAuthController(
      tokenService: _StubTokenService(valid: true),
      store: store,
    );

    await controller.connectWithToken(token: 'tok', region: PCloudRegion.eu);

    expect(controller.isConnected, isTrue);
    expect(controller.authToken, 'tok');
    expect(controller.apiHost, 'eapi.pcloud.com');
    expect(store.session?.authToken, 'tok');
  });

  test('connectWithToken throws and stores nothing for an invalid token', () async {
    final store = _FakeSessionStore();
    final controller = PCloudAuthController(
      tokenService: _StubTokenService(valid: false),
      store: store,
    );

    await expectLater(
      () => controller.connectWithToken(token: 'bad', region: PCloudRegion.us),
      throwsA(isA<PCloudException>()),
    );
    expect(controller.isConnected, isFalse);
    expect(store.session, isNull);
  });

  test('disconnect clears the session and store', () async {
    final store = _FakeSessionStore()
      ..session = const PCloudSession(authToken: 't', apiHost: 'h');
    final controller = PCloudAuthController(
      tokenService: _StubTokenService(valid: true),
      store: store,
    );

    await controller.disconnect();

    expect(controller.isConnected, isFalse);
    expect(store.session, isNull);
  });

  test('loadStoredSession tolerates a failing store', () async {
    final controller = PCloudAuthController(
      tokenService: _StubTokenService(valid: true),
      store: _ThrowingSessionStore(),
    );

    await controller.loadStoredSession();

    expect(controller.isConnected, isFalse);
  });
}

class _StubTokenService implements PCloudTokenService {
  _StubTokenService({required this.valid});

  final bool valid;

  @override
  Future<bool> validate({
    required String token,
    required PCloudRegion region,
  }) async => valid;
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
