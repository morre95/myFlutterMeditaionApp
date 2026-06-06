import 'package:flutter/foundation.dart';

import '../domain/pcloud_config.dart';
import 'pcloud_session_store.dart';
import 'pcloud_token_service.dart';

/// What the pCloud service needs to make authenticated requests.
abstract interface class PCloudSessionProvider {
  String? get authToken;

  String? get apiHost;
}

/// Manages the pCloud connection. Because pCloud disabled new OAuth apps and its
/// direct API login cannot complete 2FA, the app connects with a user-supplied
/// access token (obtained out of band, e.g. via `rclone authorize "pcloud"`).
class PCloudAuthController extends ChangeNotifier
    implements PCloudSessionProvider {
  PCloudAuthController({
    PCloudTokenService? tokenService,
    PCloudSessionStore? store,
  }) : _tokenService = tokenService ?? PCloudTokenService(),
       _store = store ?? SecureStoragePCloudSessionStore();

  final PCloudTokenService _tokenService;
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

  /// Validates and stores a pasted access token. Throws [PCloudException] if the
  /// token is rejected (wrong token or wrong region).
  Future<void> connectWithToken({
    required String token,
    required PCloudRegion region,
  }) async {
    final valid = await _tokenService.validate(token: token, region: region);
    if (!valid) {
      throw const PCloudException(
        'pCloud rejected that token. Check the token and the selected region.',
      );
    }
    final session = PCloudSession(authToken: token, apiHost: region.apiHost);
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
