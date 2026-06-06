import 'package:flutter/foundation.dart';

import '../domain/pcloud_config.dart';
import 'pcloud_login_service.dart';
import 'pcloud_session_store.dart';

/// What the pCloud service needs to make authenticated requests.
abstract interface class PCloudSessionProvider {
  String? get authToken;

  String? get apiHost;
}

/// Manages the pCloud connection: logs in with username/password, persists the
/// resulting auth token, and exposes connection state to the UI.
class PCloudAuthController extends ChangeNotifier
    implements PCloudSessionProvider {
  PCloudAuthController({
    PCloudLoginService? loginService,
    PCloudSessionStore? store,
  }) : _loginService = loginService ?? PCloudLoginService(),
       _store = store ?? SecureStoragePCloudSessionStore();

  final PCloudLoginService _loginService;
  final PCloudSessionStore _store;

  PCloudSession? _session;

  bool get isConnected => _session != null;

  @override
  String? get authToken => _session?.authToken;

  @override
  String? get apiHost => _session?.apiHost;

  /// Restores a previously-saved session. Failures (e.g. no secure storage in a
  /// test environment) are treated as "not connected".
  Future<void> loadStoredSession() async {
    try {
      _session = await _store.read();
    } catch (_) {
      _session = null;
    }
    notifyListeners();
  }

  /// Logs in and stores the session. Throws [PCloudTfaRequiredException] if the
  /// account uses 2FA, or [PCloudException] for bad credentials / region.
  Future<void> login({
    required String email,
    required String password,
    required PCloudRegion region,
  }) async {
    final session = await _loginService.login(
      email: email,
      password: password,
      region: region,
    );
    await _store.write(session);
    _session = session;
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _store.clear();
    _session = null;
    notifyListeners();
  }
}
