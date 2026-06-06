# pCloud setup

The app can stream audio from a pCloud account. pCloud is optional — the app
runs fully (timer, music, history, favorites, local audio) without it.

## Why an access token (and not email/password)

pCloud's direct username/password API **cannot complete two-factor
authentication** (there is no 2FA method in their API and the `code` parameter
is ignored), and pCloud has **disabled creation of new OAuth apps**, so the app
cannot register its own `client_id`.

The reliable way to connect — and the only way for a 2FA-protected account — is
to paste a pCloud **access token** obtained out of band.

## Getting a token with rclone

[rclone](https://rclone.org/pcloud/) ships its own pCloud OAuth client and runs
the sign-in (including 2FA) in your browser:

```bash
rclone authorize "pcloud"
```

It opens pCloud's web login; sign in (complete 2FA if prompted). rclone then
prints JSON like:

```json
{"access_token":"XXXXXXXX","token_type":"bearer","expiry":"..."}
```

Copy the **`access_token`** value.

## Connecting in the app

1. **Settings → pCloud → Connect** (or **Library → pCloud**).
2. Paste the `access_token` and choose your **data region**:
   - **United States** → `api.pcloud.com`
   - **Europe** → `eapi.pcloud.com`

   (If unsure, try one; a wrong region rejects the token and you can retry.)
3. The app validates the token and, once connected, lets you browse and add
   pCloud audio from **Library → pCloud**.

## How it works

- The token is validated with `GET /userinfo?access_token=…` and stored in the
  platform secure storage (`flutter_secure_storage`).
- **Browsing**: `listfolder` lists folders and audio files.
- **Streaming**: at playback time `getfilelink` resolves a fresh temporary URL
  that audioplayers streams via `UrlSource`. Links are short-lived and never
  persisted — only the pCloud file id is stored in the playlist.
- pCloud OAuth tokens do not expire unless revoked, so this is a one-time setup.
  Disconnect from **Settings** clears the stored token.

## Other cloud providers

`AudioSourceKind` also defines `googleDrive`, `oneDrive`, and `dropbox`, but only
pCloud is implemented. They are intentionally out of scope.
