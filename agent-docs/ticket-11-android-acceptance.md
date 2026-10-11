# Ticket #11: verify the complete meditation experience on Android

Ticket source: https://github.com/morre95/myFlutterMeditaionApp/issues/11.
Acceptance runs against `integration/meditation-android-acceptance`. Device
checks stay pending until they are done on a physical phone; fake-player tests
alone do not complete acceptance.

## Defects found on device

Device: Samsung Galaxy S24, Android API 36. Both fixes are on
`fix/11-playlist-ids-and-m4a` and need re-checking on the device.

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

Still to check on the device: .m4a, .aac, .flac and .ogg can be picked from
Library, Music and the Settings bell picker.
