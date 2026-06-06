import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

/// Launches an OAuth authorize URL and returns the full callback URL the
/// provider redirects to. Abstracted so it can be faked in tests.
abstract interface class OAuthAuthenticator {
  Future<String> authenticate({
    required String url,
    required String callbackUrlScheme,
  });
}

class FlutterWebAuthAuthenticator implements OAuthAuthenticator {
  const FlutterWebAuthAuthenticator();

  @override
  Future<String> authenticate({
    required String url,
    required String callbackUrlScheme,
  }) {
    return FlutterWebAuth2.authenticate(
      url: url,
      callbackUrlScheme: callbackUrlScheme,
    );
  }
}
