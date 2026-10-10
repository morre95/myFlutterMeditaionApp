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
media service; pauses release foreground protection and explicit background
Resume publishes playing=true before acquiring focus to restart it.
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

## Independent review fix: ending bell lifetime

Review `/tmp/issue-9-review.md` identified that foreground/focus protection ended
before custom bell resolution/playback, which can deny bell focus on locked
Android 15+. The session now retains protection through resolution, native start
and actual bell completion. `BellPlaybackLifecycle` supplies a separate completion
future; `BellRinger.ring` still returns when start is accepted, preserving the
silent Timer API and permitting End to enter the serialized stop queue immediately.
The Android meditation bell uses native focus=none under the already-active
session focus. Native completion/error, End and interruptions release protection;
interruptions during the bell preserve the completed session and zero remaining
time and never resume the bell. End cancels pending resolution via session identity.

Observed red/green through the approved controller/handler seam: a held custom
bell resolver previously made the handler idle at deadline; now it stays ready
with End available during resolution and audible playback, then becomes idle on
completion. An interruption during the ending bell now stops it while preserving
completion/accounting, rather than ignoring it or restarting a session. Parent
must verify audible built-in and custom bell at the locked release deadline.

Review-fix final verification: `flutter analyze` clean; full suite 212 tests passed
(`/tmp/issue-9-bell-final-tests.log`); `git diff --check` clean. Phone untouched.


## Physical QA fix: release resources while MainActivity remains bound

Release `b152671` on SM-S921B/Android16 completed a one-minute bell-disabled
session with media state NONE(0), position60000 and active=false, but the service
remained foreground and held its partial wakelock for over75 seconds.
Evidence: `/tmp/meditation-issue-9-evidence/long-after-deadline.json`.
Installed audio_service0.18.19 native `stop()` calls stopSelf; an Activity binding
prevents onDestroy, where foreground/wakelock cleanup otherwise occurs.

Use supported `androidStopForegroundOnPause:true` (the documented default):
playing true->false calls exitForegroundState and releases the wakelock even
while bound. Existing handler semantics keep playing=true through native Stop
and completion-bell resolution/playback, then publish false only after protection
is no longer needed. Explicit Resume publishes playing=true before requesting
focus and restarting audio; notification user interaction must permit the Android
12+ foreground restart, to be verified physically on Android16 by the parent.
No public dynamic configuration setter was found in package docs/API; no plugin
fork, reflection or battery-optimization bypass was introduced.

Context7 refreshed official config docs and README:
https://github.com/ryanheise/audio_service/blob/minor/_autodocs/configuration.md
https://github.com/ryanheise/audio_service/blob/minor/audio_service/README.md
The README warns that background foreground-service restarts are restricted on
Android12+. This change therefore requires actual locked notification Resume,
completion/End lock release and bell lifetime evidence, beyond Dart fake tests.
This section supersedes earlier plans to keep the service foreground on pause.

Resource-release fix automated verification: `flutter analyze` clean; all212
existing session/handler, bell and application tests passed
(`/tmp/issue-9-resource-release-tests.log`); `git diff --check` clean. Existing
approved seam tests confirm Pause publishes playing=false, Resume publishes true,
Stop and bell completion stay protected until native completion. The binding and
partial-wakelock issue requires native evidence, so no additional fake-only test
is claimed to prove its resolution. Parent owns physical recheck.
