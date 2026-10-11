# Ticket #11: verify the complete meditation experience on Android

Ticket source: https://github.com/morre95/myFlutterMeditaionApp/issues/11.
Acceptance runs against `integration/meditation-android-acceptance`. Device
checks stay pending until they are done on a physical phone; fake-player tests
alone do not complete acceptance.

## Defects found on device

Device: Samsung Galaxy S24, Android API 36. Both fixes were merged into
`integration/meditation-android-acceptance` (`6c276d3`) and re-checked on the
device (see Physical release evidence).

### Playlist and track ids collided after a restart

`PlaylistController` started its `playlist-N` / `track-N` counters at 0 every
launch, so a playlist created after a restart could take an existing
playlist's id. Imports then went into the wrong playlist, and `removeTrack`
(which filters by id) could remove the wrong track or several tracks.

Fix: new ids are `playlist-<microseconds>-<seq>` / `track-<microseconds>-<seq>`,
checked against every id the controller already holds. Ids are not reused after
a delete, so favorites left behind by a deleted playlist never attach to a new
one.

Repair of data saved before the fix: `load()` looks for playlist ids shared by
two or more playlists, and track ids repeated within or across playlists. The
first occurrence, in stored order (playlists in list order, then tracks in
playlist order), keeps its id. Each later duplicate gets a fresh id. No
playlist or track is dropped or merged, the order stays the same, and the
repaired list is saved right away. Data without duplicates is not rewritten.

Other places that use these ids:

- Favorites (`favorites_v1`) store bare playlist and track ids. A favorite
  saved under a duplicated id cannot be traced back to the entry that was
  starred. It stays on the first occurrence (the one that keeps the id), and
  the renamed duplicates come back unstarred. Re-star them by hand if needed.
- Selection and the playback queue live only in memory and are empty when
  `load()` runs at startup, so the repair cannot leave them stale.
- The Music screen compares ids live (selected/active playlist, current track,
  remove, favorite toggles), so it picks up the repaired ids.

### .m4a files greyed out in the system picker

`PlatformFilePickerClient` used `FileType.custom` with `allowedExtensions`.
With file_picker 12.1.1 (android_file_picker 1.0.2), Android turns each
extension into a MIME type through `MimeTypeMap` and passes those as
`EXTRA_MIME_TYPES` to `ACTION_OPEN_DOCUMENT`. MediaStore reports `.m4a` as
`audio/mp4`, which is not in that list, so the files were not selectable.

Fix: pick with `FileType.audio`. On Android this sends `ACTION_GET_CONTENT`
with `audio/*`, which opens in the audio root. The app still filters the picked
files to wav, mp3, flac, ogg, m4a and aac, because the Context7 file_picker
docs say a system picker may not enforce the filter it is given. The custom
bell picker in Settings goes through the same client, so it is fixed too.
There are no other `FilePicker` calls in the app.

On the device all six accepted formats, including .m4a, could be picked and
imported from Library. Music "Add files" and the Settings bell picker use the
same client but were not exercised on the device.

## Physical release evidence

Device: Samsung Galaxy S24 (SM-S921B), Android 16 / API 36, build
`BP4A.251205.006.S921BXXSHDZI1`. Release APK built from `6c276d3`
(versionName 1.0.0, versionCode 1, not debuggable), SHA256
`5255dbbbadf8d82aa1d9eee8314e053d759bf1b0888bcae44402a59b68326fc6`, installed
over the existing app data. Automated suite at the same commit: 291 tests
passed, `flutter analyze` clean. Raw captures (state logs, logcat extracts,
screenshots, fixture hashes) are in `/tmp/meditation-issue-11-evidence`.

Session timing comes from native `MediaPlayerNative` logcat timestamps.
Media-session states were polled from `dumpsys media_session` about every
0.5–1.5 s, so those timestamps are only as precise as the poll.

| Check | Result |
| --- | --- |
| Playlists after id repair | Existing playlists loaded with no tracks lost; new playlist got its own id and received all 8 imports. The 7 fixtures misfiled into "Left 《》Right" before the fix were removed one by one without touching the user's own tracks. |
| Formats | 180 s tones in wav, mp3, flac, ogg, m4a, aac and a 4 s wav loop each ran a 1-minute Meditate session (countdown advancing, no native error). A random-byte `.mp3` imported, then Start showed "Could not play issue11-corrupt.mp3." and no countdown ran. Import does not validate decoding; failure is reported at playback. |
| Local long sound, locked, bell | 1 min with the 180 s wav, screen off (Dozing). Native start 10:52:04.708, deadline pause 10:53:04.459. Volume fade ~5 s, Bell 1 (3.0 s) followed, active position 60000, foreground service released after the bell. |
| Short-sound loop, locked, no bell | 4 s wav looped 15 times (≈0.26 s reload gap each) for 1 min; first start → final pause 60.224 s wall, ~5 s fade, no bell, position 60000. |
| Streamed pCloud, locked | 4 min with a 16.6 MB pCloud mp3 streamed then completed at 240000. The file was fully buffered within ~1 s over Wi-Fi, so cutting the network mid-stream did not interrupt playback. |
| Network loss + manual Resume | Paused (84400 ms), Wi-Fi and data off, Resume: old player stopped, reload failed, session stayed Paused with "Could not play …", no countdown. Network back, UI Resume: source seeked to 84400 and continued to completion. Note: Samsung keeps Wi-Fi on in airplane mode when it was used there before; network loss must be forced with `svc wifi/data disable`. |
| Audio focus taken by another app | Spotify started via a stray media key: meditation paused at 23892 and did not resume by itself. |
| Headphone removal | Bose QC35 II (Bluetooth A2DP). Disconnect 11:26:41.566 → session Paused by 11:26:41.833 at 9486 ms, stayed paused. User repeated it later during another session with the same outcome. |
| Notification / quick-panel controls | Play → PLAYING from 9486 with foreground; Pause → PAUSED 24503 without foreground; End → NONE, setup screen, no foreground service. Targeted `cmd media_session monitor` play/pause also controlled the locked session. |
| Downloads | Download completes and shows "Available offline"; Cancel at 38% of a large wav returns to "Not downloaded" with no stored remnant; download with no network shows "Download of stereo_test.wav failed. Check your connection and retry." and Retry succeeds once online. Downloads survive force-stop. |
| Removal and originals | Removing a pCloud copy and an imported copy updates the total (126.8 → 123.3 MB); both dialogs say the original is kept. SHA256 of all 8 originals in `Download/Issue11` identical before and after. |
| Offline mode | Persisted across force-stop. Wi-Fi and data off: Meditate list shows imports and downloads only, "Choose from pCloud" hidden, Library pCloud card "Unavailable in Offline mode.". 4-minute session on the downloaded pCloud wav completed with 0 HTTP requests. |
| Process death | Force-stop after ~30.1 s active; 20 s downtime; relaunch showed Paused 03:31 left (~29 s saved, ~1 s lost), no audio started. Resume seeked the source to 29449 ms. |
| Phone restart | Session paused at 03:24 left, `adb reboot`, relaunch after unlock: Paused at 03:24, no audio. End recorded one "36s active · Ended early" entry; two further relaunches offered no recovery and added no duplicate. |
| History | Completed and early-ended entries recorded with active time only (2 m 45 s wall with pauses → 24 s active). Current streak "1 day" matches the history (all entries today). |

Observations (not acceptance failures):

- A downloaded pCloud copy that is shorter than the session reloads each loop
  through CONNECTING (~0.4 s), visible as a flicker on lock-screen controls.
  Reload time is excluded from active time, so 4 minutes active took 4 m 13 s
  wall. This is the open "Meditate times a downloaded pCloud sound as
  streaming" item from #7.
- The local short-sound loop (imported file) does not exclude its ~0.26 s
  reload gaps: 60 s active ≈ 60.2 s wall.
- While playing, the app updates the media session and notification about
  five times per second.

Pending, not claimed:

- Genuine incoming phone call (the user will verify it).
- User-confirmed audibility of the fade, bell and loop on the locked phone.
- A multi-day streak (needs history on consecutive days).
- The Settings bell picker and Music "Add files" picking .m4a.
