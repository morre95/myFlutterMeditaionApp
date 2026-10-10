# Ticket #4: fade, optional bell, remembered choices

Implemented on `ticket/4-fade-bell` (based on
`integration/meditation-fade-bell`); ticket source:
https://github.com/morre95/myFlutterMeditaionApp/issues/4.

Fade is driven by remaining active time, not by tick count. `_startCounting`
arms a one-shot timer for `remaining - fadeDuration` (5 s), which then applies
`volume = remaining / 5 s` every 100 ms through the new
`LocalAudioPlaybackController.setVolume` (added to `LocalAudioPlayer`, so every
test fake implements it). `_stopCounting` cancels it with the other timers, so
Pause holds both volume and countdown and Resume re-arms from the same
remaining time; completion still comes from the single deadline timer, so a
resumed fade completes once. Native volume persists across loads, so Start
resets it to 1 before playing (a previous session ended near silent).

Completion order: deadline -> status `completed` -> `await player.stop()` ->
ring the bell if enabled. The bell is checked against the session entry
(`identical(_entry, entry)`), so End or another mode taking over before the
stop lands keeps it silent. A bell failure only sets `errorMessage`
("Could not play <bell>.") on the completed state, shown in the active view;
the sound is never reloaded and Done clears it (`_returnToSetup` now clears
the error unless it passes one). `end()` also stops the bell, because it is
the ownership `deactivate` callback: Music/Timer taking over silences a
ringing bell.

Reuse rather than parallel code: Timer's bell logic moved into
`timer/application/bell_ringer.dart` (`BellRinger`: built-in lookup, custom
bell resolution, serialised native commands; throws
`UnavailableBellException` for an unknown built-in) and its dropdown into
`timer/presentation/widgets/bell_dropdown.dart`. Timer behaviour and messages
are unchanged. Meditate gets its own `BellRinger`/`TimerBellPlayer`
(injectable as `AppDependencies(meditationBellPlayer:)`) and the bell list
comes from `AppSettingsController` like Timer's.

Persistence mirrors Timer: `MeditationSettings` (sound as full `AudioSource`
JSON, duration minutes, `BellSelection`, enabled flag) under
`meditation_settings_v1`, saved on every setup change, restored by
`MeditationSessionController.load()` from `AppDependencies.init()` (setup's
dropdowns read `initialValue` once, so loading must finish before Meditate
opens). Saves are chained: concurrent `SharedPreferences.getInstance()` calls
resume in a different order than issued (the first caller resumes last), so
unchained saves lost the latest choice.

Revalidation: setup re-reads the library each time it appears; a remembered
sound missing from it shows "<name> is no longer available. Choose another
sound." and Start stays disabled. Start selects the library's copy before
starting, so a remembered locator that moved is never played.

Tests: controller tests (fake player and fake bell sharing one ordered log,
`fakeAsync`, real `SharedPreferences` mock) cover fade levels and ordering,
pause during fade, chosen/disabled/failing bell, single completion after
resume, bell silenced by Music, locked bell choices, and remembered choices.
Screen tests add the bell switch, relaunch restore (`_App.relaunch` rebuilds
`AppDependencies` on the same storage and runs `init()`), a deleted remembered
sound, and a moved locator. Full suite: 183 passed; static analysis: no
issues.

Gotchas: controller and screen tests now need
`SharedPreferences.setMockInitialValues` because every setup change saves. The
fade test disables the bell so the log ends with `stop`. Built-in bell failure
text uses `BellSelection.displayName`, which is the id (`bell_1`), as in Timer.
Audible fade smoothness and bell playback on a physical Android device are not
verified here; ticket #11 owns device acceptance.

Review fixes (`ticket/4-review-fixes`): the bell setup shows and the bell
completion rings now come from one rule, `availableBell` in
`bell_selection.dart` (the choice while Settings still offers it, else the
first enabled built-in). `BellDropdown` and
`AppSettingsController.availableBellFor` both use it, and Meditate's
`MeditationSessionController.bell` (the controller now takes `appSettings`)
is what setup displays and `_stopThenRingBell` rings. `state.bell` stays the
remembered choice, like a remembered sound, so re-adding or re-enabling that
bell restores it. Timer still rings its raw `settings.bell` because
`TimerController` has no `AppSettingsController`: a removed or disabled Timer
bell shows the fallback but rings the stale choice. That gap predates this
ticket and is left out of it. A failed volume reset at Start returns to setup
with "Could not play <sound>." like a play failure; a failed fade step is
logged and the session still ends at its deadline. Full suite: 187 passed.
