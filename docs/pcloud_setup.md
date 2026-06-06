# pCloud setup

The app can stream audio from a user's pCloud account. pCloud is optional — the
app runs fully (timer, music, history, favorites, local audio) without it.

There is **no app registration or client id required**. The app signs in with
your pCloud email and password using pCloud's direct login endpoint.

## Connecting

1. Open **Settings** (or **Library → pCloud**) and tap **Connect**.
2. Enter your pCloud **email** and **password**, and choose your **data region**:
   - **United States** → `api.pcloud.com`
   - **Europe** → `eapi.pcloud.com`

   If login fails with the wrong region, switch the region and try again.
3. Once connected, browse and add audio from **Library → pCloud**.

## How it works

- **Login**: `GET https://{region-host}/userinfo?getauth=1&username=…&password=…`
  over HTTPS returns a long-lived `auth` token
  (see https://docs.pcloud.com/methods/intro/authentication.html).
- **Token storage**: only the `auth` token + region host are stored, in the
  platform secure storage (`flutter_secure_storage`). Your password is sent
  once to pCloud over HTTPS and is **never stored**.
- **Browsing**: `listfolder` lists folders and audio files.
- **Streaming**: at playback time `getfilelink` resolves a fresh temporary URL
  that audioplayers streams via `UrlSource`. Links are short-lived and never
  persisted — only the pCloud file id is stored in the playlist.
- Disconnect from **Settings** clears the stored token.

## Two-factor authentication (2FA)

Direct login does not support accounts with 2FA enabled. If your account uses
2FA, the app shows a clear message; disable 2FA in pCloud settings to connect.

## Other cloud providers

`AudioSourceKind` also defines `googleDrive`, `oneDrive`, and `dropbox`, but only
pCloud is implemented. They are intentionally out of scope.
