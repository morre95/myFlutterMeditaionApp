import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_service.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_session_store.dart';
import 'package:my_meditation_app/features/cloud/pcloud/domain/pcloud_config.dart';
import 'package:my_meditation_app/features/library/application/local_wav_picker_service.dart';
import 'package:my_meditation_app/features/music_mode/application/audio_duration_probe.dart';
import 'package:my_meditation_app/features/music_mode/presentation/music_mode_screen.dart';
import 'package:my_meditation_app/features/player/application/local_audio_playback_controller.dart';
import 'package:my_meditation_app/features/player/application/playback_source_resolver.dart';
import 'package:my_meditation_app/features/playlists/application/playlist_controller.dart';
import 'package:my_meditation_app/features/playlists/domain/playlist.dart';
import 'package:my_meditation_app/features/playlists/domain/playlist_repository.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

void main() {
  testWidgets('shows empty state when no playlists exist', (tester) async {
    final repo = _FakePlaylistRepository([]);
    final controller = PlaylistController(repository: repo);
    final player = _FakeLocalAudioPlayer();
    final playbackController = LocalAudioPlaybackController(player: player);

    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: MusicModeScreen(
          playlistController: controller,
          picker: const _FakeLocalAudioFilePicker([]),
          playbackController: playbackController,
          durationProbe: const _FakeDurationProbe(Duration(minutes: 3)),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('No playlists yet. Tap New to create one.'),
      findsOneWidget,
    );

    playbackController.dispose();
    controller.dispose();
  });

  testWidgets('creates a playlist and adds picked audio files', (tester) async {
    final repo = _FakePlaylistRepository([]);
    final controller = PlaylistController(repository: repo);
    final player = _FakeLocalAudioPlayer();
    final playbackController = LocalAudioPlaybackController(player: player);

    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: MusicModeScreen(
          playlistController: controller,
          picker: _FakeLocalAudioFilePicker(const [
            AudioSource(
              id: 'rain',
              kind: AudioSourceKind.localFile,
              displayName: 'rain.wav',
              reference: '/music/rain.wav',
            ),
            AudioSource(
              id: 'forest',
              kind: AudioSourceKind.localFile,
              displayName: 'forest.wav',
              reference: '/music/forest.wav',
            ),
          ]),
          playbackController: playbackController,
          durationProbe: const _FakeDurationProbe(Duration(minutes: 3)),
        ),
      ),
    );
    await tester.pump();

    // Create a playlist via the "New" button.
    await tester.tap(find.text('New'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Chill session');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Chill session'), findsAtLeast(1));

    // Add audio files to the selected playlist.
    await tester.tap(find.text('Add files'));
    await tester.pump();

    expect(find.text('rain.wav'), findsOneWidget);
    expect(find.text('forest.wav'), findsOneWidget);
    expect(find.text('Added 2 audio files to the playlist.'), findsOneWidget);
    // Each track shows its probed duration (3:00).
    expect(find.textContaining('3:00'), findsNWidgets(2));

    playbackController.dispose();
    controller.dispose();
  });

  testWidgets('plays a playlist and opens the now-playing page', (
    tester,
  ) async {
    final source = const AudioSource(
      id: 'rain',
      kind: AudioSourceKind.localFile,
      displayName: 'rain.wav',
      reference: '/music/rain.wav',
    );
    final playlist = Playlist(
      id: 'p1',
      name: 'Morning',
      tracks: [PlaylistTrack(id: 't1', source: source)],
      createdAt: DateTime(2026),
    );

    final repo = _FakePlaylistRepository([playlist]);
    final controller = PlaylistController(repository: repo);
    final player = _FakeLocalAudioPlayer();
    final playbackController = LocalAudioPlaybackController(player: player);

    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: MusicModeScreen(
          playlistController: controller,
          picker: const _FakeLocalAudioFilePicker([]),
          playbackController: playbackController,
          durationProbe: const _FakeDurationProbe(Duration(minutes: 3)),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Morning'), findsAtLeast(1));

    // Tap the play icon next to the playlist; this navigates to the
    // NowPlayingScreen.
    await tester.tap(find.byTooltip('Play Morning'));
    await tester.pumpAndSettle();

    expect(player.loadedPath, '/music/rain.wav');
    // NowPlayingScreen shows the track filename and playlist name.
    expect(find.text('rain.wav'), findsAtLeast(1));
    expect(find.text('Morning'), findsAtLeast(1));

    player.setDuration(const Duration(minutes: 3));
    player.setPosition(const Duration(seconds: 42));
    await tester.pump();
    await tester.pump();

    expect(find.text('0:42'), findsOneWidget);
    expect(find.text('3:00'), findsOneWidget);

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeEnd?.call(
      const Duration(minutes: 2).inMilliseconds.toDouble(),
    );
    await tester.pump();

    expect(player.seekPosition, const Duration(minutes: 2));

    playbackController.dispose();
    controller.dispose();
  });

  testWidgets('auto-advances to next track on completion', (tester) async {
    final sources = [
      const AudioSource(
        id: 'rain',
        kind: AudioSourceKind.localFile,
        displayName: 'rain.wav',
        reference: '/music/rain.wav',
      ),
      const AudioSource(
        id: 'forest',
        kind: AudioSourceKind.localFile,
        displayName: 'forest.wav',
        reference: '/music/forest.wav',
      ),
    ];
    final playlist = Playlist(
      id: 'p1',
      name: 'Nature',
      tracks: [
        PlaylistTrack(id: 't1', source: sources[0]),
        PlaylistTrack(id: 't2', source: sources[1]),
      ],
      createdAt: DateTime(2026),
    );

    final repo = _FakePlaylistRepository([playlist]);
    final controller = PlaylistController(repository: repo);
    final player = _FakeLocalAudioPlayer();
    final playbackController = LocalAudioPlaybackController(player: player);

    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: MusicModeScreen(
          playlistController: controller,
          picker: const _FakeLocalAudioFilePicker([]),
          playbackController: playbackController,
          durationProbe: const _FakeDurationProbe(Duration(minutes: 3)),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Play Nature'));
    await tester.pumpAndSettle();

    expect(player.loadedPath, '/music/rain.wav');

    // Simulate track completion — should advance to forest.wav.
    player.complete();
    await tester.pump();
    await tester.pump();

    expect(player.loadedPath, '/music/forest.wav');
    expect(find.text('forest.wav'), findsAtLeast(1));

    playbackController.dispose();
    controller.dispose();
  });

  testWidgets('Add files offers a pCloud source when connected', (tester) async {
    final controller = PlaylistController(repository: _FakePlaylistRepository([]));
    await controller.load();
    await controller.create('Morning');
    final player = _FakeLocalAudioPlayer();
    final playbackController = LocalAudioPlaybackController(player: player);

    final auth = PCloudAuthController(
      store: _StubSessionStore(
        const PCloudSession(authToken: 't', apiHost: 'eapi.pcloud.com'),
      ),
    );
    await auth.loadStoredSession();
    final service = PCloudService(
      session: auth,
      client: MockClient((_) async => http.Response('{"result":0}', 200)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MusicModeScreen(
          playlistController: controller,
          picker: const _FakeLocalAudioFilePicker([]),
          playbackController: playbackController,
          durationProbe: const _FakeDurationProbe(Duration(minutes: 3)),
          pcloudAuthController: auth,
          pcloudService: service,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Add files'));
    await tester.pumpAndSettle();

    expect(find.text('From this device'), findsOneWidget);
    expect(find.text('From pCloud'), findsOneWidget);

    playbackController.dispose();
    controller.dispose();
    auth.dispose();
  });
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _FakePlaylistRepository implements PlaylistRepository {
  _FakePlaylistRepository(this._playlists);

  final List<Playlist> _playlists;

  @override
  Future<List<Playlist>> loadAll() async => List.from(_playlists);

  @override
  Future<void> saveAll(List<Playlist> playlists) async {
    _playlists
      ..clear()
      ..addAll(playlists);
  }
}

class _FakeLocalAudioFilePicker implements LocalAudioFilePicker {
  const _FakeLocalAudioFilePicker(this.sources);

  final List<AudioSource> sources;

  @override
  Future<List<AudioSource>> pickAudioFiles() async => sources;
}

class _FakeDurationProbe implements AudioDurationProbe {
  const _FakeDurationProbe(this.duration);

  final Duration duration;

  @override
  Future<Duration?> durationOf(AudioSource source) async => duration;
}

class _StubSessionStore implements PCloudSessionStore {
  _StubSessionStore(this._session);

  PCloudSession? _session;

  @override
  Future<PCloudSession?> read() async => _session;

  @override
  Future<void> write(PCloudSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}

class _FakeLocalAudioPlayer implements LocalAudioPlayer {
  final StreamController<bool> _completedController =
      StreamController<bool>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();

  String? loadedPath;
  int playCount = 0;
  Duration? seekPosition;

  @override
  Stream<bool> get completedStream => _completedController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Future<void> load(PlayableMedia media) async {
    loadedPath = media.locator;
  }

  @override
  Future<void> play() async {
    playCount++;
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {
    seekPosition = position;
  }

  @override
  Future<void> stop() async {}

  void setPosition(Duration position) {
    _positionController.add(position);
  }

  void setDuration(Duration duration) {
    _durationController.add(duration);
  }

  void complete() => _completedController.add(true);

  @override
  void dispose() {
    unawaited(_completedController.close());
    unawaited(_positionController.close());
    unawaited(_durationController.close());
  }
}
