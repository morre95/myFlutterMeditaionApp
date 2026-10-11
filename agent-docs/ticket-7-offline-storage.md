# Ticket #7: Offline mode and device-storage management

Implemented on `ticket/7-offline-storage` (based on
`integration/meditation-offline-storage`); ticket source:
https://github.com/morre95/myFlutterMeditaionApp/issues/7.

Pieces: `AppSettingsController.isOfflineMode`/`setOfflineMode` (persisted by
`SharedPreferencesAppSettingsRepository` under `app_settings_offline_mode_v1`,
switch in Settings); `library/application/device_sound_catalog.dart`
(`DeviceSoundCatalog`, shared from `AppDependencies.deviceSoundCatalog`)
combining the two catalogs #6 left separate; `library/presentation/
device_storage_screen.dart` opened from the Library "Device storage" card.

Offline filtering: Meditate setup lists `DeviceSoundCatalog.load()` (imports
plus verified pCloud downloads) in both modes. Offline hides "Choose from
pCloud", and a remembered pCloud sound without a copy shows "<name> is not
available offline. Choose another sound." with Start disabled. Online keeps
the browser and streaming of undownloaded pCloud sounds. The cloud-request
guarantee lives in `PCloudPlaybackSourceResolver` (now requires
`isOffline:`): offline, a pCloud source without an intact copy throws
`NotAvailableOfflineException` before any `getfilelink`, so Music playlists,
Meditate and bells can never stream offline.

Missing copies: `PCloudDownloadController.verifiedCopyOf` checks the audio
file still exists with its `storedSize` (`PCloudDownloadStore.isIntact`) and
forgets a vanished copy (row returns to "Not downloaded"). The resolver and
catalog only use verified copies; online a vanished copy falls back to
streaming. A missing import already failed Start ("Could not play"), so no
silent session can begin from a missing file.

Removal: explicit only, with a confirm dialog; nothing evicts automatically.
`LocalAudioLibrary.removeSound` derives the directory from the `import:` id
(never the reference), so originals cannot be touched;
`PCloudDownloadController.remove` deletes `pcloud_downloads/<fileid>/` and
makes no pCloud request. Both rename the directory to a hidden name first,
which withdraws availability atomically; download `load()` already cleans
hidden leftovers, the import catalog only ignores them. Playlists keep their
tracks; a removed import then fails to play like any missing file.

Active-file protection: `AppDependencies._isInActiveSession` matches the
sound id against the Meditate session (loading/running/paused or still
silencing) and the Music player (loading/playing/paused). The catalog throws
`SoundInUseException` ("<name> is playing in an active session. End the
session before removing it.") and the screen shows it. It is conservative: a
pCloud copy is protected while the same id streams in Music.

Tests (no user-confirmed seams in this run; chosen at the public APIs used by
earlier tickets, with real temp files): settings persistence through real
SharedPreferences; resolver offline refusal with a request counter and a
vanished copy; controller removal + restart + zero requests; import removal
keeps the original; catalog listing sizes, removal across restart, active
refusal; storage screen sizes/remove/protection message; Meditate offline
listing, playback from the copy with zero requests, unavailable remembered
pCloud sound, and an end-to-end active-session refusal via Library; an
AppDependencies test for Music protection; Settings switch. Full suite: 262
passed; `flutter analyze`: no issues.

Gotchas: resolution of a downloaded copy now does real I/O, so widget tests
that play one must poll after `pumpAndSettle` (the #6 Music offline test was
updated). The Meditate test harness now resolves through the app's resolver
via a delegating `_AppResolver` and injects an unreachable `PCloudService`
that counts requests. Settings tests find bell switches by label, since
Offline mode adds a `SwitchListTile`. Tap storage rows only after the route
transition settles.

Music and Library offline (`ticket/7-offline-filter`):
`DeviceSoundCatalog.isAvailableOffline` (imports, or pCloud sounds with an
advertised copy; the resolver still verifies it on disk) is the one
offline-availability check. Offline, Music marks undownloaded pCloud tracks
"Not available offline" with Play disabled, plays a playlist with only its
available tracks (Play disabled when none), and "Add files" picks device
files without offering pCloud. Library shows the pCloud card disabled with
"Unavailable in Offline mode.". Online is unchanged. Tests: Music offline
listing/skip/zero requests and online playability; Library card in both
modes.

Open: Meditate still times a downloaded pCloud sound as a stream
(`_isStream` is by kind, inherited from #5/#6). Switching to Offline mode
while a playlist already plays does not re-filter its queue; an undownloaded
next track then fails with "Could not play" (no cloud request). Pending for #11
(device acceptance, not run here): airplane-mode Meditate/Music on Android,
removal while a background session plays, storage sizes against Android
settings, and persistence after a real restart.
