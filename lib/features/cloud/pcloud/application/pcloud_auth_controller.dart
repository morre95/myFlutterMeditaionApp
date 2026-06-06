import 'package:flutter/foundation.dart';

import '../domain/pcloud_config.dart';
import 'oauth_authenticator.dart';
import 'pcloud_session_store.dart';

/// What the pCloud service needs to make authenticated requests.
abstract interface class PCloudSessionProvider {
  String? get accessToken;

  String? get apiHost;
}

/// Manages the pCloud connection: launches OAuth, persists the session, and
/// exposes connection state to the UI.
class PCloudAuthController extends ChangeNotifier
    implements PCloudSessionProvider {
  PCloudAuthController({
    OAuthAuthenticator? authenticator,
    PCloudSessionStore? store,
  }) : _authenticator = authenticator ?? const FlutterWebAuthAuthenticator(),
       _store = store ?? SecureStoragePCloudSessionStore();

  final OAuthAuthenticator _authenticator;
  final PCloudSessionStore _store;

  PCloudSession? _session;

  bool get isConfigured => PCloudConfig.isConfigured;

  bool get isConnected => _session != null;

  @override
  String? get accessToken => _session?.accessToken;

  @override
  String? get apiHost => _session?.apiHost;

  /// Restores a previously-saved session. No-op (and no secure-storage access)
  /// when pCloud is not configured for this build.
  Future<void> loadStoredSession() async {
    if (!isConfigured) return;
    _session = await _store.read();
    notifyListeners();
  }

  Future<void> connect() async {
    if (!isConfigured) {
      throw const PCloudException('pCloud client id is not configured.');
    }
    final authUrl = Uri.parse(PCloudConfig.authorizeEndpoint).replace(
      queryParameters: {
        'client_id': PCloudConfig.clientId,
        'response_type': 'token',
        'redirect_uri': PCloudConfig.redirectUri,
      },
    ).toString();

    final callback = await _authenticator.authenticate(
      url: authUrl,
      callbackUrlScheme: PCloudConfig.callbackUrlScheme,
    );

    final session = parseCallback(callback);
    await _store.write(session);
    _session = session;
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _store.clear();
    _session = null;
    notifyListeners();
  }

  /// Parses the OAuth redirect URL. pCloud's implicit flow returns the token in
  /// the URL fragment along with the region (`hostname` or `locationid`).
  @visibleForTesting
  static PCloudSession parseCallback(String callbackUrl) {
    final uri = Uri.parse(callbackUrl);
    final raw = uri.fragment.isNotEmpty ? uri.fragment : uri.query;
    final params = Uri.splitQueryString(raw);

    final token = params['access_token'];
    if (token == null || token.isEmpty) {
      throw const PCloudException('No access token in the pCloud response.');
    }
    final host = params['hostname'] ?? _hostForLocation(params['locationid']);
    return PCloudSession(accessToken: token, apiHost: host);
  }

  static String _hostForLocation(String? locationId) =>
      locationId == '2' ? 'eapi.pcloud.com' : 'api.pcloud.com';
}
