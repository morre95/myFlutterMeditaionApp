import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/pcloud_config.dart';

/// Validates a user-supplied pCloud OAuth access token by making a lightweight
/// authenticated call. Used for the "paste access token" connect flow, which is
/// the only way to reach a 2FA-protected account (the token is obtained out of
/// band, e.g. via `rclone authorize "pcloud"`).
class PCloudTokenService {
  PCloudTokenService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// Returns true if [token] authenticates successfully against [region].
  Future<bool> validate({
    required String token,
    required PCloudRegion region,
  }) async {
    final uri = Uri.https(region.apiHost, '/userinfo', {'access_token': token});
    final http.Response response;
    try {
      response = await _client.get(uri);
    } catch (_) {
      throw const PCloudException('Could not reach pCloud.');
    }
    if (response.statusCode != 200) return false;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['result'] as int? ?? -1) == 0;
  }
}
