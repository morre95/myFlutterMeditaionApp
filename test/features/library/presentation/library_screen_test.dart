import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/app/app_dependencies.dart';
import 'package:my_meditation_app/app/app_scope.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_session_store.dart';
import 'package:my_meditation_app/features/cloud/pcloud/domain/pcloud_config.dart';
import 'package:my_meditation_app/features/library/presentation/library_screen.dart';
import 'package:my_meditation_app/features/playlists/application/playlist_controller.dart';
import 'package:my_meditation_app/features/playlists/domain/playlist.dart';
import 'package:my_meditation_app/features/playlists/domain/playlist_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final isOffline in [true, false]) {
    testWidgets('Library ${isOffline ? 'withholds' : 'offers'} pCloud browsing '
        '${isOffline ? 'in' : 'outside'} Offline mode', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final auth = PCloudAuthController(store: _ConnectedSessionStore());
      await auth.loadStoredSession();
      final playlists = PlaylistController(repository: _OnePlaylist());
      await playlists.load();
      final deps = AppDependencies(
        playlistController: playlists,
        pcloudAuthController: auth,
      );
      await deps.appSettingsController.setOfflineMode(isOffline);
      await tester.pumpWidget(
        AppScope(
          dependencies: deps,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );

      final pCloud = tester.widget<ListTile>(
        find.ancestor(of: find.text('pCloud'), matching: find.byType(ListTile)),
      );

      expect(
        find.text('Unavailable in Offline mode.'),
        isOffline ? findsOneWidget : findsNothing,
      );
      expect(pCloud.onTap, isOffline ? isNull : isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      deps.dispose();
    });
  }
}

class _ConnectedSessionStore implements PCloudSessionStore {
  @override
  Future<PCloudSession?> read() async =>
      const PCloudSession(authToken: 't', apiHost: 'eapi.pcloud.com');

  @override
  Future<void> write(PCloudSession session) async {}

  @override
  Future<void> clear() async {}
}

class _OnePlaylist implements PlaylistRepository {
  @override
  Future<List<Playlist>> loadAll() async => [
    Playlist(
      id: 'morning',
      name: 'Morning',
      tracks: const [],
      createdAt: DateTime(2026),
    ),
  ];

  @override
  Future<void> saveAll(List<Playlist> playlists) async {}
}
