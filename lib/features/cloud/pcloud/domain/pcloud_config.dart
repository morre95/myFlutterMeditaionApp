/// pCloud accounts live in one of two data regions, each with its own API host.
enum PCloudRegion {
  us('api.pcloud.com', 'United States'),
  eu('eapi.pcloud.com', 'Europe');

  const PCloudRegion(this.apiHost, this.label);

  final String apiHost;
  final String label;
}

/// An authenticated pCloud session: the long-lived auth token plus the region
/// API host it belongs to. Obtained via username/password login.
class PCloudSession {
  const PCloudSession({required this.authToken, required this.apiHost});

  final String authToken;
  final String apiHost;
}

class PCloudException implements Exception {
  const PCloudException(this.message);

  final String message;

  @override
  String toString() => 'PCloudException: $message';
}
