# Ticket #3: timed meditation with one local sound

Implemented on `ticket/3-timed-session` (based on
`integration/meditation-timed-session`); ticket source:
https://github.com/morre95/myFlutterMeditaionApp/issues/3.

`AppDependencies.meditationSessionController` is application-owned, like Music,
so leaving and re-entering Meditate keeps the session. It drives its own
`LocalAudioPlaybackController` rather than sharing Music's: Music's listener
reacts to any player error, so a shared player would leak Meditate failures into
Music state. Both register with `PlaybackOwnershipController`; another mode
taking over calls Meditate's `end`, and a Start queued behind a handoff is
dropped if End happened meanwhile (`canRun` checks the session's entry).

Active time is `ElapsedClock` (monotonic `Duration Function()`, a Stopwatch in
production, injectable through `AppDependencies(clock:)`) accumulated only while
the player reports `playing`. A one-shot deadline timer stops the sound; a 1 s
periodic timer only redraws and re-checks the deadline from the clock, so late
or missing ticks can end an overdue session but never extend it. Shorter sounds
repeat by reloading the same entry on completion; the reload gap is not counted.
Pause during that reload stops instead of pausing, and Resume reloads, so a
paused session is never audible. Player errors return to setup with the error
message, so no countdown exists without audio. Duration and sound are locked
once a session starts. Completion shows "Session complete" with Done; fade, bell,
history, pCloud and device acceptance remain for #4, #5, #8 and #11.

Timer's progress ring moved to `shared/presentation/countdown_circle.dart`
(keys renamed to `countdown-*`) and is reused by the active session view.

Tests: controller behaviour through its public API with a fake native player
under `fakeAsync` (clock = `async.elapsed`, or a hand-driven variable for the
late-refresh case), plus Home -> Meditate widget tests with real imported temp
files. Full suite: 163 passed; static analysis: no issues.

Gotchas: inside `tester.runAsync` the sound-list spinner never lets
`pumpAndSettle` settle, so the tests poll with a small `_pumpUntil` helper. The
setup view re-reads the library each time it appears (e.g. after End or a load
error); the test teardown waits for that read before deleting the temp
directory, otherwise a `PathNotFoundException` surfaces after the test. Whether
a fast loading->setup bounce remounts setup depends on frame timing, so tests do
not assert on the re-read list. Adding the Home card pushed Settings below the
fold in `widget_test.dart`, which now scrolls to it. `dart format lib test`
reformats unrelated files with this SDK; format only touched files.
