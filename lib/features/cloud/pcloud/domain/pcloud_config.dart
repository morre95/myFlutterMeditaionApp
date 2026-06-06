/// Static configuration for the pCloud OAuth integration.
///
/// The OAuth client id must be supplied at build time and is never committed:
///   flutter run --dart-define=PCLOUD_CLIENT_ID=your_client_id
///
/// Register an app at https://docs.pcloud.com/ and set its redirect URI to
/// [redirectUri]. The implicit ("token") flow is used because the app is a
/// public client with no backend to hold a client secret.
class PCloudConfig {
  const PCloudConfig._();

  static const String clientId = String.fromEnvironment('PCLOUD_CLIENT_ID');

  static const String callbackUrlScheme = 'mymeditation';
  static const String redirectUri = 'mymeditation://oauth';
  static const String authorizeEndpoint =
      'https://my.pcloud.com/oauth2/authorize';

  static bool get isConfigured => clientId.isNotEmpty;
}

class PCloudSession {
  const PCloudSession({required this.accessToken, required this.apiHost});

  final String accessToken;

  /// The region-specific API host, e.g. `api.pcloud.com` (US) or
  /// `eapi.pcloud.com` (EU).
  final String apiHost;
}

class PCloudException implements Exception {
  const PCloudException(this.message);

  final String message;

  @override
  String toString() => 'PCloudException: $message';
}
