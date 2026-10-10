import '../features/library/application/local_audio_library.dart';
import '../features/meditation/application/meditation_session_controller.dart';
import '../features/library/application/local_wav_picker_service.dart';
import '../features/cloud/pcloud/application/pcloud_auth_controller.dart';
import '../features/cloud/pcloud/application/pcloud_playback_source_resolver.dart';
import '../features/cloud/pcloud/application/pcloud_service.dart';
import '../features/favorites/application/favorites_controller.dart';
import '../features/favorites/infrastructure/shared_preferences_favorites_repository.dart';
import '../features/history/application/history_controller.dart';
import '../features/history/infrastructure/shared_preferences_session_repository.dart';
import '../features/player/application/playback_source_resolver.dart';
import '../features/player/application/local_audio_playback_controller.dart';
import '../features/player/application/playback_ownership_controller.dart';
import '../features/playlists/application/playlist_playback_controller.dart';
import '../features/playlists/application/playlist_controller.dart';
import '../features/playlists/infrastructure/shared_preferences_playlist_repository.dart';
import '../features/settings/application/app_settings_controller.dart';
import '../features/settings/infrastructure/shared_preferences_app_settings_repository.dart';
import '../features/timer/infrastructure/shared_preferences_timer_settings_repository.dart';

/// Owns the application's shared, long-lived singletons.
///
/// Built once in `main()` before the widget tree is created. Screens read these
/// via [AppScope]. Music and Meditate playback belong to the application so
/// navigation does not interrupt them. Silent timers remain screen-scoped.
class AppDependencies {
  AppDependencies._({
    required this.playlistController,
    required this.localAudioLibrary,
    required this.localAudioPicker,
    required this.appSettingsController,
    required this.historyController,
    required this.favoritesController,
    required this.pcloudAuthController,
    required this.pcloudService,
    required this.timerSettingsRepository,
    required this.playbackSourceResolver,
    LocalAudioPlaybackController? playbackController,
    LocalAudioPlaybackController? meditationPlaybackController,
    required this.clock,
  }) : _playbackController = playbackController,
       _meditationPlaybackController = meditationPlaybackController;

  factory AppDependencies({
    PlaylistController? playlistController,
    LocalAudioLibrary? localAudioLibrary,
    LocalAudioFilePicker? localAudioPicker,
    AppSettingsController? appSettingsController,
    HistoryController? historyController,
    FavoritesController? favoritesController,
    PCloudAuthController? pcloudAuthController,
    TimerSettingsRepository? timerSettingsRepository,
    PlaybackSourceResolver? playbackSourceResolver,
    LocalAudioPlaybackController? playbackController,
    LocalAudioPlaybackController? meditationPlaybackController,
    ElapsedClock? clock,
  }) {
    final library = localAudioLibrary ?? LocalAudioLibrary();
    final auth = pcloudAuthController ?? PCloudAuthController();
    final service = PCloudService(session: auth);
    return AppDependencies._(
      localAudioLibrary: library,
      localAudioPicker:
          localAudioPicker ?? ManagedLocalAudioPicker(library: library),
      playlistController:
          playlistController ??
          PlaylistController(repository: SharedPreferencesPlaylistRepository()),
      appSettingsController:
          appSettingsController ??
          AppSettingsController(
            repository: SharedPreferencesAppSettingsRepository(),
          ),
      historyController:
          historyController ??
          HistoryController(repository: SharedPreferencesSessionRepository()),
      favoritesController:
          favoritesController ??
          FavoritesController(
            repository: SharedPreferencesFavoritesRepository(),
          ),
      pcloudAuthController: auth,
      pcloudService: service,
      playbackController: playbackController,
      meditationPlaybackController: meditationPlaybackController,
      clock: clock ?? _stopwatchClock(),
      timerSettingsRepository:
          timerSettingsRepository ?? SharedPreferencesTimerSettingsRepository(),
      playbackSourceResolver:
          playbackSourceResolver ??
          PCloudPlaybackSourceResolver(service: service),
    );
  }

  static ElapsedClock _stopwatchClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  final LocalAudioLibrary localAudioLibrary;
  final LocalAudioFilePicker localAudioPicker;
  final PlaylistController playlistController;
  final AppSettingsController appSettingsController;
  final HistoryController historyController;
  final FavoritesController favoritesController;
  final PCloudAuthController pcloudAuthController;
  final PCloudService pcloudService;
  final TimerSettingsRepository timerSettingsRepository;
  final PlaybackSourceResolver playbackSourceResolver;

  /// Monotonic time for measuring active session time.
  final ElapsedClock clock;

  final PlaybackOwnershipController playbackOwnershipController =
      PlaybackOwnershipController();
  LocalAudioPlaybackController? _playbackController;
  PlaylistPlaybackController? _playlistPlaybackController;
  LocalAudioPlaybackController? _meditationPlaybackController;
  MeditationSessionController? _meditationSessionController;

  LocalAudioPlaybackController get playbackController => _playbackController ??=
      LocalAudioPlaybackController(resolver: playbackSourceResolver);

  PlaylistPlaybackController get playlistPlaybackController =>
      _playlistPlaybackController ??= PlaylistPlaybackController(
        player: playbackController,
        history: historyController,
        ownership: playbackOwnershipController,
      );

  MeditationSessionController get meditationSessionController =>
      _meditationSessionController ??= MeditationSessionController(
        player: _meditationPlaybackController ??= LocalAudioPlaybackController(
          resolver: playbackSourceResolver,
        ),
        ownership: playbackOwnershipController,
        clock: clock,
      );

  /// Loads persisted state. Call once at startup before `runApp`.
  Future<void> init() async {
    await Future.wait([
      playlistController.load(),
      appSettingsController.load(),
      historyController.load(),
      favoritesController.load(),
      pcloudAuthController.loadStoredSession(),
    ]);
  }

  void dispose() {
    _playlistPlaybackController?.dispose();
    _playbackController?.dispose();
    _meditationSessionController?.dispose();
    _meditationPlaybackController?.dispose();
    playlistController.dispose();
    appSettingsController.dispose();
    historyController.dispose();
    favoritesController.dispose();
    pcloudAuthController.dispose();
  }
}
