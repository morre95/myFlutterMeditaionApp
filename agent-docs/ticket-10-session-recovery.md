# Ticket #10: recover interrupted sessions without automatic playback

Implemented on `ticket/10-session-recovery` (based on
`integration/meditation-session-recovery`, `1403075`); ticket source:
https://github.com/morre95/myFlutterMeditaionApp/issues/10. Builds on #8's
history identities/deduplication and #9's background controls.

## Design

`MeditationCheckpoint` (`meditation/domain`) holds the history session ID,
sound (`AudioSource` JSON, so pCloud identity survives), planned duration,
measured active duration, sound position, bell and bell-enabled setting.
`SharedPreferencesMeditationCheckpointRepository` stores at most one, under
`meditation_checkpoint_v1`, separate from `meditation_settings_v1`; a `false`
write/remove is treated as a failure. `MeditationSessionController` takes it as
a required `checkpoints:` dependency.

Writes: one at Start, then every `checkpointInterval` (5 s, wall-clock periodic
timer) while the session is loading or running, plus an immediate write whenever
the session becomes paused (Pause, interruptions/headphones via the #9 handler,
stream stall/failure, denied focus). Paused sessions do not rewrite. All saves
and the clear go through one serialized chain, so a slow earlier write can never
land after a later write or after the clear. Resolution (deadline completion,
End, failure returning to setup) stops further saves for the session, records
history once, and clears the checkpoint only after that history write succeeds.
If the write fails, or the process dies before it lands, the checkpoint survives
and the next launch offers the session again. The deferred clear is skipped when
a newer session has queued its own checkpoint meanwhile, so a late history write
never removes another session's recovery.

Restore (`load()` at startup, after remembered settings): the controller enters
`paused` with the checkpoint's identity, sound, duration and bell, and nothing is
loaded natively. Home opens Meditate on its first frame when a session was
restored, showing the paused countdown with Resume and End. Background controls
publish paused with `playing=false`, so no foreground service starts; only an
explicit Resume (screen or media Play) plays.

Resume of a restored session goes through the normal resolver, so a pCloud sound
uses its offline copy or a fresh link and a local file must still exist; it then
seeks to the saved position. It claims `PlaybackOwnershipController` because a
restored session never started in this process (Music playing meanwhile is
stopped; it does not end the paused session). If the source cannot play, the
session stays paused with the player's error ("Could not play rain.wav.") and
the checkpoint intact: no countdown runs and Resume can retry, or End records the
saved time. Fresh, non-restored local failures keep #3's return-to-setup.

End of a restored session records the saved active time as `endedEarly` under
the original ID. If termination lands after the history write but before the
checkpoint clear, the next launch asks `HistoryController.hasRecorded(id)` and
discards an already-recorded checkpoint instead of offering it again; history's
ID deduplication is the second guard.

Process downtime is excluded by construction: active time is restored from the
checkpoint and only counts again once the player reports playing in the new
process (the monotonic clock is per process).

## Progress-loss bounds

Derived: at most one checkpoint interval (< 5 s) of active time is lost on
termination while playing, plus SharedPreferences flush latency (asynchronous;
see #8 notes, no immediate disk flush is guaranteed). Paused sessions lose
nothing beyond that flush latency. The local sound position is the last native
report (audioplayers position updater, 200 ms) at checkpoint time, so the
restored position may be up to ~200 ms behind restored active time; streamed
sessions save the counted media position exactly. A kill during a repeat reload
restores position 0 of the next play-through.

Measured (fake-time controller tests): kill 2 s after the 15 s checkpoint
restores 45 s of a 60 s session (2 s lost); Pause then interruption restores the
exact 18 s; 5 minutes of downtime consume nothing. This is not sample-exact crash
recovery. Device measurement of real termination/restart is pending in #11.

## TDD evidence

Seams: `MeditationSessionController` public API with fake native audio over real
(mocked) SharedPreferences storage, "kill" = dispose without End then construct a
new controller/history on the same storage; the Home -> Meditate widget flow
with real files and reconstructed `AppDependencies`. Red/green observed for:
restored paused state (was setup); Resume seek (was null); immediate pause
checkpoint (45 s instead of 42 s); missing sound staying paused (was setup);
already-recorded checkpoint not offered (was paused); launch opening Meditate
paused (no Resume found); restored Resume taking over Music (Music kept playing).
Characterization tests (green at first run, guarding already-built behavior):
End recorded once with saved time across repeated launches, slow write vs End
race, restored stream fresh link + seek.

Full suite: 256 passed. `flutter analyze`: no issues. `git diff --check`: clean.

## Gotchas and open items

- `test/widget_test.dart` flakes about 1 in 5 runs with `MissingPluginException`
  from real audioplayers creation; reproduced on the unmodified base `1403075`,
  so it is pre-existing and not addressed here.
- `dart format lib` also reformats the unrelated
  `shared_preferences_app_settings_repository.dart` with this SDK; format only
  touched files.
- Pending for #11 (device): real process kill and phone restart recovery, actual
  progress loss on Android storage, restored pCloud offline/stream Resume, missing
  file after restart, and media-notification behavior for a restored paused
  session. None are claimed here.
