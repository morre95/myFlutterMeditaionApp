# Ticket #6: pCloud downloads and offline playback

Implemented on `ticket/6-pcloud-downloads` (based on
`integration/meditation-pcloud-downloads`); ticket source:
https://github.com/morre95/myFlutterMeditaionApp/issues/6.

Pieces (all in `features/cloud/pcloud/application/` unless noted):
`PCloudService.openDownload` (fresh `getfilelink` URL, then a streamed GET;
pCloud documents `getfilelink` as the download link, confirmed via Context7
`/websites/pcloud`), `PCloudDownloadStore` (disk), `PCloudDownloadController`
(per-file transfer state, shared from `AppDependencies` and loaded in
`init()`), the existing `PCloudPlaybackSourceResolver` (now prefers a copy),
and `library/presentation/pcloud_download_actions.dart` shown as the subtitle
of each audio file in the existing `PCloudBrowserScreen` (Library and Music
pass the shared controller).

Storage reuses the #2 commit approach: bytes and `sound.json` are flushed in
a hidden `.<fileid>-<random>` staging directory and published by renaming to
`pcloud_downloads/<fileid>/`. The metadata is the unchanged pCloud
`AudioSource` (`pcloud:<fileid>` id, `pCloud` kind, file id reference) plus
`storedSize`; the audio path is derived from the directory, so identity and
provider reference survive and playlists keep their existing pCloud tracks.
It is a separate catalog from `LocalAudioLibrary`: that library rewrites
`reference` to a file path and Meditate lists it, so mixing them would lose
the file id. #7 can combine both catalogs for its offline filter.

Availability is only advertised after rename. `load()` lists a copy only when
its metadata parses, is pCloud, matches its directory, and its audio length
equals `storedSize`; it deletes `.`-prefixed staging left by a killed app.
The controller checks the stream length before the store commits: empty or
shorter than `Content-Length` is a failed transfer. One directory per file id
plus a per-file in-flight map means repeated Download taps join the running
transfer and an available file is never fetched again; a broken leftover
destination is replaced on the next commit.

Cancel works while bytes are stalled: `_ActiveTransfer.guard` proxies the
response stream and injects a cancel error immediately, which unwinds the
store's write loop (staging deleted) and cancels the HTTP stream. Cancel
after the last byte lets the commit finish. Failures: `ENOSPC` (errno 28,
Android/Linux) -> "Not enough storage ... Free up space and retry."; other
file errors -> "Could not save ..."; `PCloudException` messages as-is; any
other transfer exception (offline, reset, truncated) -> "Download of <name>
failed. Check your connection and retry." Retry is just Download again.
Removal is #7's job; nothing evicts copies.

Tests (seams given by the caller: controlled fake transfers, real temporary
files, cancel/retry, restart, availability UI, local-copy preference):
controller tests drive the real `PCloudService` through
`MockClient.streaming` with test-fed byte streams and a temp store
(completion + restart, stalled cancel + retry, mid-stream drop, truncation,
offline, ENOSPC via the store's injected `writeChunk`, duplicate taps,
interrupted staging/broken copy on restart); a resolver test; a browser
widget test for Download/progress/Cancel/failure/Retry/Available offline;
and a Music test that restarts with pCloud disconnected and plays the
downloaded copy's bytes from a playlist. Full suite: 198 passed; static
analysis: no issues.

Gotchas: `AppDependencies.init()` now reads the download directory, so
tests calling it pass `pcloudDownloadStore:` with a temp directory and run
`init` inside `tester.runAsync` (otherwise path_provider is missing or the
real I/O never completes). Pump/settle the browser route transition before
tapping row actions; mid-transition taps land off-screen. The Music test
reaches the app's own resolver through a small delegating resolver because
the injected playback controller must exist before `AppDependencies`.
`PCloudBrowserScreen.downloads` is optional: null hides download actions,
which keeps #5's Meditate selection browser unchanged.
`PCloudPlaybackSourceResolver` now requires `downloads:`; callers merged from
#5 (its Meditate screen test) must pass one. No physical Android download,
ENOSPC, or airplane-mode playback was run; ticket #11 owns device acceptance.
