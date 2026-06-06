# My Meditation App

A Flutter meditation app: meditation timer with custom bells, music playlists,
session history & streaks, favorites, and optional pCloud audio streaming.

## Running the app

Requires the Flutter SDK (stable channel) — verify with `flutter doctor`.

```bash
flutter pub get          # fetch dependencies
flutter devices          # list available devices/emulators
flutter run              # build & run on the selected device/emulator
```

To stream audio from pCloud, see [Connecting to pCloud](#connecting-to-pcloud).

## Tests & linting

```bash
flutter test             # run all tests
flutter test test/features/timer/                    # run a folder
flutter test test/features/timer/application/timer_controller_test.dart  # one file
flutter test --coverage  # write coverage to coverage/lcov.info

flutter analyze          # static analysis + lints (uses analysis_options.yaml)
dart format .            # format code
dart format --output=none --set-exit-if-changed .    # check formatting (CI-style)
```

Linting is configured via `analysis_options.yaml` (the `flutter_lints` rule set);
`flutter analyze` is the linter — there is no separate lint command.

## Connecting to pCloud

pCloud is optional — the app works fully without it. Because pCloud's direct
API cannot complete two-factor authentication and pCloud has disabled new OAuth
app registration, the app connects using a **pasted access token**.

1. **Get a token with [rclone](https://rclone.org/downloads/)** (it runs the
   pCloud sign-in, including 2FA, in your browser):

   ```bash
   rclone authorize "pcloud"
   ```

   Sign in in the browser it opens, then copy the **`access_token`** value from
   the JSON it prints:

   ```json
   {"access_token":"XXXXXXXX","token_type":"bearer", ...}
   ```

2. **In the app:** go to **Settings → pCloud → Connect** (or **Library →
   pCloud**), paste the token, and choose your **data region**:
   - **United States** → `api.pcloud.com`
   - **Europe** → `eapi.pcloud.com`

   The app validates the token immediately. Once connected, browse and add
   pCloud audio from **Library → pCloud**; tracks stream on demand. Disconnect
   from **Settings** clears the stored token.

pCloud access tokens don't expire unless revoked, so this is a one-time setup.
More detail: [docs/pcloud_setup.md](docs/pcloud_setup.md).

---

## License

[MIT](LICENSE) — use, modify, and distribute freely.
