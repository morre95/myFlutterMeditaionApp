import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/favorites/application/favorites_controller.dart';
import 'package:my_meditation_app/features/favorites/infrastructure/shared_preferences_favorites_repository.dart';

void main() {
  test('toggles playlist and track favorites independently', () async {
    final repo = _FakeFavoritesRepository();
    final controller = FavoritesController(repository: repo);

    await controller.togglePlaylist('p1');
    await controller.toggleTrack('t1');

    expect(controller.isPlaylistFavorite('p1'), isTrue);
    expect(controller.isTrackFavorite('t1'), isTrue);
    expect(controller.isPlaylistFavorite('t1'), isFalse);

    await controller.togglePlaylist('p1');
    expect(controller.isPlaylistFavorite('p1'), isFalse);
  });

  test('persists and restores favorites', () async {
    final repo = _FakeFavoritesRepository();
    final first = FavoritesController(repository: repo);
    await first.togglePlaylist('p1');
    await first.toggleTrack('t9');

    final restored = FavoritesController(repository: repo);
    await restored.load();

    expect(restored.isPlaylistFavorite('p1'), isTrue);
    expect(restored.isTrackFavorite('t9'), isTrue);
  });
}

class _FakeFavoritesRepository implements FavoritesRepository {
  FavoritesData _data = const FavoritesData.empty();

  @override
  Future<FavoritesData> load() async => _data;

  @override
  Future<void> save(FavoritesData data) async => _data = data;
}
