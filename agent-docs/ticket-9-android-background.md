# Issue #9: Android locked-screen playback

## PR #18 conflict resolution against main

Merged `origin/main` at `8a1ed65` (session history #8 and pCloud downloads #6).
Preserved both history recording and Android audio-focus/command protections.
History record IDs are separate from the background-control session tokens.
Completion followed by synchronous End now balances the pending native-stop
counter even when the completion listener takes over stopping; the existing
reentrant-End test verifies one completed history record, silence and idle media
state with no lingering protection. All 245 tests pass, including 60 session
tests; `flutter analyze` reports no issues and `git diff --check` is clean.
Physical evidence below applies to the earlier release APK identified there;
the conflict-resolution merge was verified automatically, without reinstalling
on the device. Genuine incoming-call verification remains pending.

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
recorded in the implementation handoff. Final full suite: 212 tests passed.
`flutter analyze`: no issues after final formatting.
`git diff --check`: clean.

## Physical release evidence

Physical QA uses a Galaxy S24 (SM-S921B), Android 16 / API 36. Final release
APK at code merge `92c19a8` has SHA256
`9a6c2826b7c4962ddc6dac5a0aad6a1d80373f147f02e2c724f014ba09d3d115`.
Main release manifest permissions and retained transport icons were inspected
in the APK; DEBUGGABLE is absent. INTERNET is in the main manifest.

Local low-volume WAV fixtures (90 seconds and a 4-second loop) were imported
into a separate `Issue9Verification` playlist. User confirmed the long tone
continued with the screen off, and confirmed both looping tone and Bell 1 at
completion. Long-source deadline native timestamps differ by 60.060 seconds.
Loop source completes at position 60000; loop reloads exclude their brief native
loading time. Foreground service and partial CPU wakelock remain through bell
playback and are released afterward in the final release.

Final-release lock-screen Pause freezes position at 36307 ms; a snapshot 26.884
seconds later has the same position. Pause releases foreground status and the
partial wakelock. Actual lock-screen Resume restores playing, foreground status
and the partial wakelock without a foreground-start exception.

Evidence captures are in `/tmp/meditation-issue-9-evidence`: `long-*.json`,
`controls-paused-ack.json`, `controls-paused-later.json`,
`controls-resumed.json`, and `loop-bell-*.json`. Samples show screen wake changes
during the loop run; this is not claimed as uninterrupted screen-off timing.
User confirmed audible screen-off playback and ending bell. At the loop deadline,
position stays 60000 with playing=true/speed=0 and the CPU lock retained through
the bell; native idle follows 3.256 seconds later and releases protection.

Headphone disconnection: user confirmed silence and no automatic Resume. An
intermediate playing observation was explained by the user's explicit Resume.
After disconnecting again, `headphone-followup-state.json` and
`headphone-final-paused.json` both show PAUSED at 230701 ms, 10.776 seconds apart,
without foreground status or a partial CPU wakelock. Headphone connection type
was not recorded. This verifies actual disconnection, silence and stopped
accounting; automated interruption-end tests cover no automatic Resume.

Lock-screen End was repeated successfully by the user. `end-user-confirmed.json`
shows media active=false, NONE(0), position=0, startRequested=false, no foreground
status and no partial CPU wakelock. Subsequent Play/Pause/Play commands through
`cmd media_session monitor media-session` targeted meditation specifically and
left that exact ended state unchanged (`end-stale-controls.json`), without
starting another app or a new session. Earlier screen taps were missed while
dozing or used a mismatched Samsung card layout; those earlier attempts are not
claimed as successful End evidence.

Android notification-panel controls were exercised separately on the final
release: Pause yielded PAUSED at 36817 ms, Resume yielded PLAYING from the same
36817 ms with foreground/CPU protection restored, and End yielded inactive
NONE(0), position=0 with the service stopped and no CPU lock. Evidence:
`notification-pause.json`, `notification-resume.json`, `notification-end.json`.

Genuine incoming-call verification remains pending because the
user has no second phone available. No simulated interruption is presented as
physical call evidence. Keep PR #18 draft until the remaining physical acceptance
checks are complete. Final independent code review approved `92c19a8` with no
new actionable findings.
Parent owns device interaction and evidence capture.

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
