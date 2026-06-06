import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/pcloud_config.dart';

/// Exchanges a pCloud username + password for an auth token via the
/// `userinfo?getauth=1` endpoint (sent over HTTPS only).
///
/// See https://docs.pcloud.com/methods/intro/authentication.html
class PCloudLoginService {
  PCloudLoginService({http.Client? client})
    : _client = client ?? http.Client();

  // pCloud result code returned when the account requires 2FA.
  static const int _tfaRequiredCode = 2297;

  final http.Client _client;

  Future<PCloudSession> login({
    required String email,
    required String password,
    required PCloudRegion region,
  }) async {
    final uri = Uri.https(region.apiHost, '/userinfo', {
      'getauth': '1',
      'logout': '1',
      'username': email,
      'password': password,
    });

    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw PCloudException('Login failed (${response.statusCode}).');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final result = json['result'] as int? ?? -1;
    if (result == _tfaRequiredCode) {
      throw const PCloudTfaRequiredException();
    }
    if (result != 0) {
      final error = json['error'] as String? ?? 'Invalid email or password.';
      throw PCloudException(error);
    }

    final auth = json['auth'] as String?;
    if (auth == null || auth.isEmpty) {
      throw const PCloudException('pCloud did not return an auth token.');
    }
    return PCloudSession(authToken: auth, apiHost: region.apiHost);
  }
}
