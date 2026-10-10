# Ticket 5 — Streamed pCloud meditation

Ticket: https://github.com/morre95/myFlutterMeditaionApp/issues/5

Base: ticket/5-pcloud-streaming started exactly at integration/meditation-pcloud-streaming (ae4c3eb). Scope is ticket 5 only. The user approved the controller Start/Pause/Resume/End seam with controlled source/native player events, and the visible Meditate selection/recovery seam before tests were written.

## Behavior and design

Meditate reuses connectToPCloud and PCloudBrowserScreen in a selection mode. Choosing a cloud sound closes the browser, retains the pCloud file ID as its durable reference, and enables Start without importing/downloading it. Existing local selection still revalidates against the current library. The existing PCloudPlaybackSourceResolver obtains a fresh temporary link on Start, repeats, and every explicit streamed Resume. Settings persist the cloud source, never the temporary link.

Local sessions retain monotonic clock accounting. Streamed sessions count only positive native media-position changes while the player is playing. Neither a native play acknowledgement nor source loading/seek notifications can consume active time. No extrapolation across stalled gaps occurs. The screen stays in Preparing sound until the first advancing position. Completion does not infer an unplayed tail from metadata duration; loops preserve accumulated active time and exclude fresh loading.

Audioplayers exposes no buffering status. A five-second watchdog without advancing media therefore pauses the session, silences the native player, keeps progress and media position, and presents Resume. Playback/source errors do the same. Resume loads a fresh URL and seeks the preserved position before playing; it remains loading until further advancing positions arrive. User Pause also holds active time and Resume reloads the fresh source. Stream fade/completion follows reported active positions.

The native adapter uses a 200ms TimerPositionUpdater instead of frame-driven position polling. All three subscribed streams have error handlers because audioplayers forwards platform errors through its streams. Position notifications during loading/idle/completed are ignored by the playback controller. Playback generations invalidate obsolete resolves, loads, and seeks; the session additionally checks its entry identity after initial volume preparation and after pending Pause. Repeated Resume while loading is ignored.

## Documentation evidence

Context7 resolve-library-id selected /bluefireteam/audioplayers (high reputation). query-docs confirmed TimerPositionUpdater configuration and that player streams emit native platform errors via onError. Source: https://github.com/bluefireteam/audioplayers/blob/main/getting_started.md. Installed 6.6.0 source inspection confirmed no buffering state and the default frame updater.

## Verification

Vertical red/green slices demonstrated: streamed play acknowledgements incorrectly started the clock before the fix; native stream failures were unhandled and retained running playback before error recovery; stale Start after End during volume preparation could audibly revive before the identity guard; failed native Pause left the stream sounding before recovery handling. The visible browser/Resume slice initially failed without service injection/selection controls and now passes.

Controller coverage includes initial loading/stalls, native failure with fresh URL + saved seek, retry resolving after End/new session, repeated Resume, loop metadata tails, final completion, End during volume preparation, a rejected native Pause, and Resume clicked before a pending native Pause finishes (late old positions are ignored). Visible widget coverage browses an undownloaded pCloud file from Meditate, chooses it, starts, observes preparing, interrupts it via native error, explicitly resumes, and ends. The visible selection test first picks a local sound and verifies that its displayed selection disappears after choosing cloud audio. Existing local, Music, timer and bell tests remain in the full suite.

No physical Android/network run was performed. Position-based accounting is conservative: unreported sub-poll audio at a loop boundary is not inferred from duration metadata. The watchdog is a fallback for the package's missing buffering signal, not a claim of a native buffering event. Native notification streams do not carry load generation IDs; generation checks protect asynchronous commands/resolution, and nonplaying position events are ignored.

Final validation: `flutter test --no-pub` — 191 passed; `flutter analyze --no-pub` — no issues; `dart format` and `git diff --check` clean.
