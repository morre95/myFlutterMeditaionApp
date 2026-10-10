import '../features/library/application/local_audio_library.dart';
import '../features/meditation/application/meditation_session_controller.dart';
import '../features/meditation/infrastructure/shared_preferences_meditation_settings_repository.dart';
import '../features/library/application/local_wav_picker_service.dart';
import '../features/cloud/pcloud/application/pcloud_auth_controller.dart';
import '../features/cloud/pcloud/application/pcloud_download_controller.dart';
import '../features/cloud/pcloud/application/pcloud_download_store.dart';
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
import '../features/timer/application/bell_ringer.dart';
import '../features/timer/application/timer_bell_player.dart';
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
    required this.pcloudDownloadController,
    required this.timerSettingsRepository,
    required this.meditationSettingsRepository,
    required this.playbackSourceResolver,
    LocalAudioPlaybackController? playbackController,
    LocalAudioPlaybackController? meditationPlaybackController,
    BellPlayer? meditationBellPlayer,
    required this.clock,
  }) : _playbackController = playbackController,
       _meditationPlaybackController = meditationPlaybackController,
       _meditationBellPlayer = meditationBellPlayer;

  factory AppDependencies({
    PlaylistController? playlistController,
    LocalAudioLibrary? localAudioLibrary,
    LocalAudioFilePicker? localAudioPicker,
    AppSettingsController? appSettingsController,
    HistoryController? historyController,
    FavoritesController? favoritesController,
    PCloudAuthController? pcloudAuthController,
    PCloudService? pcloudService,
    PCloudDownloadStore? pcloudDownloadStore,
    TimerSettingsRepository? timerSettingsRepository,
    MeditationSettingsRepository? meditationSettingsRepository,
    PlaybackSourceResolver? playbackSourceResolver,
    LocalAudioPlaybackController? playbackController,
    LocalAudioPlaybackController? meditationPlaybackController,
    BellPlayer? meditationBellPlayer,
    ElapsedClock? clock,
  }) {
    final library = localAudioLibrary ?? LocalAudioLibrary();
    final auth = pcloudAuthController ?? PCloudAuthController();
    final service = pcloudService ?? PCloudService(session: auth);
    final downloads = PCloudDownloadController(
      service: service,
      store: pcloudDownloadStore ?? PCloudDownloadStore(),
    );
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
      pcloudDownloadController: downloads,
      playbackController: playbackController,
      meditationPlaybackController: meditationPlaybackController,
      meditationBellPlayer: meditationBellPlayer,
      clock: clock ?? _stopwatchClock(),
      timerSettingsRepository:
          timerSettingsRepository ?? SharedPreferencesTimerSettingsRepository(),
      meditationSettingsRepository:
          meditationSettingsRepository ??
          SharedPreferencesMeditationSettingsRepository(),
      playbackSourceResolver:
          playbackSourceResolver ??
          PCloudPlaybackSourceResolver(service: service, downloads: downloads),
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
  final PCloudDownloadController pcloudDownloadController;
  final TimerSettingsRepository timerSettingsRepository;
  final MeditationSettingsRepository meditationSettingsRepository;
  final PlaybackSourceResolver playbackSourceResolver;

  /// Monotonic time for measuring active session time.
  final ElapsedClock clock;

  final PlaybackOwnershipController playbackOwnershipController =
      PlaybackOwnershipController();
  LocalAudioPlaybackController? _playbackController;
  PlaylistPlaybackController? _playlistPlaybackController;
  LocalAudioPlaybackController? _meditationPlaybackController;
  final BellPlayer? _meditationBellPlayer;
  MeditationSessionController? _meditationSessionController;

  LocalAudioPlaybackController get playbackController => _playbackController ??=
      LocalAudioPlaybackController(resolver: playbackSourceResolver);

  PlaylistPlaybackController get playlistPlaybackController =>
      _playlistPlaybackController ??= PlaylistPlaybackController(
        player: playbackController,
        history: historyController,
        clock: clock,
        ownership: playbackOwnershipController,
      );

  MeditationSessionController get meditationSessionController =>
      _meditationSessionController ??= MeditationSessionController(
        player: _meditationPlaybackController ??= LocalAudioPlaybackController(
          resolver: playbackSourceResolver,
        ),
        bell: BellRinger(
          player: _meditationBellPlayer ?? TimerBellPlayer(),
          sourceResolver: playbackSourceResolver,
        ),
        repository: meditationSettingsRepository,
        ownership: playbackOwnershipController,
        appSettings: appSettingsController,
        clock: clock,
        history: historyController,
      );

  /// Loads persisted state. Call once at startup before `runApp`.
  Future<void> init() async {
    await Future.wait([
      playlistController.load(),
      appSettingsController.load(),
      historyController.load(),
      favoritesController.load(),
      pcloudAuthController.loadStoredSession(),
      pcloudDownloadController.load(),
      meditationSessionController.load(),
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
    pcloudDownloadController.dispose();
  }
}
