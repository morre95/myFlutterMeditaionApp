# pCloud setup

The app can stream audio from a user's pCloud account. pCloud is optional — the
app runs fully (timer, music, history, favorites, local audio) without it. When
no client id is provided, the pCloud UI shows a "not configured" state.

## 1. Register a pCloud app

1. Go to https://docs.pcloud.com/ → **My applications** and create an app.
2. Set the **redirect URI** to:

   ```
   mymeditation://oauth
   ```

   This must match `PCloudConfig.redirectUri` /
   `PCloudConfig.callbackUrlScheme` in
   `lib/features/cloud/pcloud/domain/pcloud_config.dart`.
3. Copy the app's **client id**.

## 2. Run / build with the client id

The client id is supplied at build time and never committed:

```bash
flutter run --dart-define=PCLOUD_CLIENT_ID=your_client_id
# or
flutter build apk --dart-define=PCLOUD_CLIENT_ID=your_client_id
```

## 3. How it works

- **Auth**: OAuth 2.0 implicit ("token") flow via `flutter_web_auth_2`. Suitable
  for a public mobile client with no backend (no client secret).
- **Token storage**: the access token + region API host are stored in the
  platform secure storage (`flutter_secure_storage`), never in shared
  preferences.
- **Browsing**: `listfolder` lists folders and audio files
  (`Library → pCloud`).
- **Streaming**: at playback time, `getfilelink` resolves a fresh temporary URL
  that audioplayers streams via `UrlSource`. Links are short-lived and never
  persisted — only the pCloud file id is stored in the playlist.

## Android

`android/app/src/main/AndroidManifest.xml` registers the
`flutter_web_auth_2` `CallbackActivity` for the `mymeditation` scheme. If you
change the scheme, update both the manifest and `PCloudConfig`.

## Other cloud providers

`AudioSourceKind` also defines `googleDrive`, `oneDrive`, and `dropbox`, but only
pCloud is implemented. They are intentionally out of scope.
