import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/pcloud_config.dart';

/// Persists the pCloud session (access token + API host). Tokens are sensitive,
/// so the concrete implementation uses the platform secure storage.
abstract interface class PCloudSessionStore {
  Future<PCloudSession?> read();

  Future<void> write(PCloudSession session);

  Future<void> clear();
}

class SecureStoragePCloudSessionStore implements PCloudSessionStore {
  SecureStoragePCloudSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'pcloud_auth_token';
  static const _hostKey = 'pcloud_api_host';

  final FlutterSecureStorage _storage;

  @override
  Future<PCloudSession?> read() async {
    final token = await _storage.read(key: _tokenKey);
    final host = await _storage.read(key: _hostKey);
    if (token == null || host == null) return null;
    return PCloudSession(authToken: token, apiHost: host);
  }

  @override
  Future<void> write(PCloudSession session) async {
    await _storage.write(key: _tokenKey, value: session.authToken);
    await _storage.write(key: _hostKey, value: session.apiHost);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _hostKey);
  }
}
