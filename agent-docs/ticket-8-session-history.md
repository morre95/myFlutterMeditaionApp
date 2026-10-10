# Ticket 8 — Actual session time and outcomes

Issue: https://github.com/morre95/myFlutterMeditaionApp/issues/8

Branch `ticket/8-session-history` began exactly at `integration/meditation-history` (`ecda087`). Work is limited to ticket 8. User approved three public seams: Meditate/Music/Timer lifecycle → history, persistence/load/streak, and Progress UI.

## Behavior

Each Start allocates a session identity independent of track identity. Repeats, Pause/Resume, and Music skips retain it; finalization clears it before notifying listeners or issuing native cleanup. Meditate and Timer store requested duration, actual active duration capped at their deadline, and completed/endedEarly. Ending after the measured deadline is completed even before a refresh callback. Music stores optional known planned metadata and measured active time; unknown track lengths no longer suppress completion, repeated tracks accumulate active time, and a later selected start only plans its remaining known tracks. Music seeks do not add elapsed time. New outcomes count toward streaks only when completed; pauses preserve eligibility.

Meditate reuses existing conservative native media-progress accounting for streamed sources, including excluded load/reload/paused gaps. Local Meditate and Music use injected monotonic clocks while playback reports playing; silent Timer now uses a Stopwatch clock instead of decrementing tick counts. Timer refresh callbacks redraw/check actual elapsed time. AppDependencies passes its elapsed clock to application-owned Music and Meditate, and Timer screen passes it to its timer.

The existing `sessions_v1` backend and legacy durationSeconds field remain. Actual time is nullable: old records load as completed with historical reported duration, never fabricated measured time. New records persist microsecond actual/planned durations, stable ID, mode, and outcome. History serializes initial load and all writes and deduplicates IDs. Failed saves retain their original records for retry on the next public load/record; lifecycle callers catch failures. SharedPreferences false writes are treated as failures. SharedPreferences asynchronously persists and does not guarantee immediate disk flush, so this is not crash-exact durability. Root fetched Context7 `/websites/pub_dev_packages_shared_preferences` confirming that documented limitation; no backend migration or dependency was added.

Progress shows actual active time and Completed/Ended early, includes planned time when known, and explicitly labels legacy historical duration / Actual time unknown. Existing local calendar-date normalization and previous-calendar-day calculation preserve streak day rules (including the spring DST boundary fixture).

## TDD evidence

Vertical slices, each followed by only the required implementation:

- History stable ID, actual/planned fields and outcomes: initial compile red (`/tmp/ticket8-red-history.log`), then history public tests green.
- Meditate measured End across 8 seconds loading, 7 + 5 seconds active and 30 seconds paused: initial missing history injection red (`/tmp/ticket8-red-meditate.log`), then green.
- Timer 12.5 seconds measured active across Pause/Resume with no refresh ticks: missing clock injection red (`/tmp/ticket8-red-timer.log`), then green.
- Unknown-length repeated Music: missing clock injection red (`/tmp/ticket8-red-music.log`), then green; old unknown-length assertion updated to new acceptance behavior.
- Progress: runtime finder failure for 12s active (`/tmp/ticket8-red-ui.log`), then green.
- Meditate completion listener synchronously End: runtime null-check failure (`/tmp/ticket8-red-race.log`), then captured entry/obsolete bell guard green.
- Timer Reset during running notification: runtime unwanted later notifications (`/tmp/ticket8-red-timer-race.log`), then lifecycle/tick guards green.
- Failed save retry: runtime restored 60s instead of original 15s (`/tmp/ticket8-red-retry.log`), then retained pending-record retry green.
- Music starting at track 2: runtime 12m planned instead of 7m (`/tmp/ticket8-red-plan.log`), then remaining-track plan green.

Additional acceptance coverage: delayed load/write + overlapping records and duplicate identity preserve old data through reconstruction; real SharedPreferences legacy JSON roundtrip and calendar boundaries; streamed unknown metadata/repeat/load/pause followed by completion produces one measured minute and streak eligibility; repeated End and late native completion never duplicate records.

## Validation and limits

Full suite: 211 passed. Analyze and formatting validated on touched files. The first full run found one existing timer ownership test using fake ticks without injecting elapsed clock; its system clock seam is now explicit. No physical Android timing/network test was performed. Music's native adapter has no buffering-status signal: its active clock follows reported playing status, so undetected native stalls remain a real-device limitation for ticket 11, rather than a new buffering/recovery subsystem in this ticket. Streamed Meditate retains ticket 5's conservative reporting/poll precision limits. Failed writes can be retried during the process lifetime; failed writes are not claimed to survive process termination.
