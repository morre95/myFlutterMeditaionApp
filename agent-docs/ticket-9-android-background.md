# Issue #9: Android locked-screen playback

Spec: https://github.com/morre95/myFlutterMeditaionApp/issues/9 (dependency #3 closed).
Integration base: `integration/meditation-android-background`, `ecda087`.
Owned implementation branch: `ticket/9-android-background`.

## Design

`MeditationAudioHandler` wraps the app-owned `MeditationSessionController`; there
is no second player, timer, or session. Native Pause/Play/Stop map to the same
Pause/Resume/End commands as the screen. Background Play cannot start a session
from setup. MediaItem duration and position describe active session time rather
than a looping source. Loading publishes playing=true to start the foreground
media service; pauses retain it for explicit background Resume on Android 15+.
End/automatic completion retain foreground protection while native Stop is
pending. Stop failure falls back to Pause; if both fail, End remains available,
new Start is blocked, and a successful retry releases the service.

`MeditationBackgroundAudio` configures audio_session and owns focus, serializes
focus activation/release, and forwards all interruption begins (including duck)
and headphone becoming-noisy to Pause. Interruption-end events never Resume.
The Android meditation player's native focus is disabled so audioplayers cannot
independently regain focus or auto-resume. Other platforms/Music retain their
existing native focus behavior. Session command generations cancel stale work
while acquiring focus, preparing volume, resolving/loading sources, or waiting
for native Pause. Pause now also handles initial loading.

The release main manifest contains INTERNET, WAKE_LOCK, FOREGROUND_SERVICE and
FOREGROUND_SERVICE_MEDIA_PLAYBACK plus AudioService and MediaButtonReceiver;
MainActivity extends AudioServiceActivity. Notification icon and plugin transport
icons are retained explicitly under release resource shrinking. Screen wakelock
is not used as proof of background support.

## Controls and compatibility

Use native media controls for notification and supported lock-screen surfaces.
audio_service 0.18.19 does not include custom actions in pre-Android13 notification
buttons; custom-only controls would leave those devices with no usable actions.
A guarded public customAction API also accepts `pause:<sessionId>`,
`resume:<sessionId>` and `end:<sessionId>` with matching `sessionId` extras.
Session IDs include a process epoch. Old tagged controls cannot affect a new
session. Native standard media transport carries no originating media-item ID,
so an ancient standard Pause/Stop delivered during a newly started session cannot
be distinguished from a current media-button press. After End, every Resume and
Pause is harmless, and none can create a duplicate session or restart audio.

## Documentation

Context7 official package documentation fetched for audio_service/audio_session
and /bluefireteam/audioplayers. Sources include:
- https://github.com/ryanheise/audio_service/blob/minor/audio_service/README.md
- https://github.com/ryanheise/audio_session/blob/master/README.md
- https://github.com/bluefireteam/audioplayers/blob/main/getting_started.md
- https://github.com/bluefireteam/audioplayers/blob/main/packages/audioplayers_platform_interface/lib/src/api/audio_context.dart

## Automated evidence

User confirmed public session and AudioHandler test boundaries. System fakes are
only native audio, source resolution and time. TDD red/green observed for:
- interruption during initial loading (previously audio completed the session);
- background control adapter missing, then Pause/Resume/End over the same session;
- old tagged controls rejected while current tagged Pause works;
- End racing a delayed audio-focus grant;
- interruption recovery requiring explicit Resume;
- foreground protection until pending native Stop actually lands;
- local native Pause failure falling back to Stop;
- fresh-launch stale End without a sound (caught null metadata exception);
- dual native Stop/Pause failure staying recoverable and blocking Start.

Additional regression checks cover focus denial, latest Resume winning over an
older delayed focus result, active-time preservation and existing streamed-source
recovery/looping/fade/bell/ownership behavior. Final test/analyze results are
recorded in the implementation handoff. Full suite: 210 tests passed; session/
handler suite: 55 tests passed. `flutter analyze`: no issues after final formatting.
`git diff --check`: clean.

## Physical release evidence

Pending parent verification on SM-S921B / Android 16 API 36. No physical-device
claim is made by the implementer. Required checks: local 90-second sound and
4-second looping sound in a one-minute session, navigating away, screen locked
through the deadline, notification and supported lock-screen controls, genuine
call interruption and headphone disconnection, no auto-resume, explicit background
Resume and silence after End, plus release networking/manifest/resource inspection.
Prepared fixtures: `/tmp/meditation-issue-9-evidence/issue9-long-90s.wav` and
`issue9-loop-4s.wav`. Parent owns device interaction and evidence capture.
