import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/pcloud_config.dart';

/// Exchanges a pCloud username + password for an auth token via the
/// `userinfo?getauth=1` endpoint (sent over HTTPS only).
///
/// Accounts with two-factor authentication require a second step: the first
/// request is rejected asking for a `code`, which [verifyTfaCode] then supplies.
///
/// See https://docs.pcloud.com/methods/intro/authentication.html
class PCloudLoginService {
  PCloudLoginService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<PCloudSession> login({
    required String email,
    required String password,
    required PCloudRegion region,
  }) {
    return _authRequest(region, {
      'getauth': '1',
      'logout': '1',
      'username': email,
      'password': password,
    });
  }

  /// Completes login for a 2FA-protected account by resending the credentials
  /// together with the user's authenticator [code] (and the [token] from the
  /// initial prompt, when pCloud provided one).
  Future<PCloudSession> verifyTfaCode({
    required String email,
    required String password,
    required PCloudRegion region,
    required String code,
    String? token,
  }) {
    return _authRequest(region, {
      'getauth': '1',
      'logout': '1',
      'username': email,
      'password': password,
      'code': code,
      'token': ?token,
    });
  }

  Future<PCloudSession> _authRequest(
    PCloudRegion region,
    Map<String, String> params,
  ) async {
    final uri = Uri.https(region.apiHost, '/userinfo', params);
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw PCloudException('Login failed (${response.statusCode}).');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final result = json['result'] as int? ?? -1;

    if (result == 0) {
      final auth = json['auth'] as String?;
      if (auth == null || auth.isEmpty) {
        throw const PCloudException('pCloud did not return an auth token.');
      }
      return PCloudSession(authToken: auth, apiHost: region.apiHost);
    }

    final error = json['error'] as String? ?? 'Invalid email or password.';
    final token = json['token'] as String?;
    // Credentials were accepted but pCloud wants a verification code, indicated
    // either by a verification token or an error explicitly asking for a code.
    if (!params.containsKey('code') &&
        (token != null || error.toLowerCase().contains('code'))) {
      throw PCloudTfaRequiredException(token: token);
    }
    // Surface the numeric result code to make diagnosing login issues possible.
    throw PCloudException('$error (pCloud result $result)');
  }
}
