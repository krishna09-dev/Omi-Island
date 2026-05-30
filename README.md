# Omi-Island

A free, open-source macOS notch companion app.

Omi-Island lives in your Mac's notch and shows music, optional Claude/Codex usage status, headphone connect/disconnect, sound effects, and custom volume/brightness islands — all in a compact Dynamic-Island style.

## Features

- Always-visible notch with a pet/icon + green dot identity.
- Compact hover music panel with album artwork and a thin media visualizer.
- Optional compact Claude/Codex usage strip with SF Symbol status icons (green/yellow/red health).
- Custom volume/brightness island.
- Headphone connect/disconnect animation (with best-effort battery percentage when macOS exposes it).
- Optional, subtle sound effects (usage limit + device connection), each with their own toggle.
- One clean settings window (General, Media, Behavior, About, …).
- Supported media sources only: Spotify, Apple Music, YouTube, YouTube Music.

## Requirements

- macOS 15 or later.

## Build

```sh
xcodebuild -project OmiIsland.xcodeproj -scheme OmiIsland -configuration Debug build CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""
```

> Public app/product name is **Omi-Island** (`Omi-Island.app`). The Xcode project, scheme, Swift module, target, and source folder are all **OmiIsland**. Bundle id: `dev.krishna09.omiisland`.

## Run locally

After building, open the app from the build products directory:

```sh
open "$HOME/Library/Developer/Xcode/DerivedData/OmiIsland-*/Build/Products/Debug/Omi-Island.app"
```

(The DerivedData folder has a per-machine hash suffix — the glob above resolves it. Look for `Omi-Island.app` under `DerivedData/OmiIsland-*/Build/Products/Debug/`.)

## Media filtering

Only these sources are shown in the notch:

- **Spotify** (app or `open.spotify.com`)
- **Apple Music / Music.app**
- **YouTube** (`youtube.com` / `youtu.be`)
- **YouTube Music** (`music.youtube.com`)

Everything else is intentionally **not** shown — including **Instagram / Reels**, Facebook, TikTok, WhatsApp audio, and generic Safari/Chrome tab audio. Browser media is classified strictly by the **active tab's** URL host; ambiguous/unknown tabs are never shown and never guessed as YouTube.

### Unsigned app warning

This is an unsigned build. The first time you open it, macOS Gatekeeper may block it. To run it:

**Right-click the app → Open**, then confirm in the dialog. (Or System Settings → Privacy & Security → "Open Anyway".)

## Version

Current version: **1.0.0-test**

## Open source

Omi-Island is a free, open-source test project, maintained by **krishna09-dev**.

- Repository: https://github.com/krishna09-dev/Omi-Island
- Issues / feedback: https://github.com/krishna09-dev/Omi-Island/issues
- Releases: https://github.com/krishna09-dev/Omi-Island/releases

## Privacy

Omi-Island is local-first: **no telemetry, analytics, or data collection**. With
"Show Usage Info" off it makes **no network requests**. With it on, the only
request goes to `api.anthropic.com` carrying *your own* Claude token to read
*your own* usage — no media/browser/device data is ever sent. Media detection is
local; GitHub links open only when clicked. Full details: [`PRIVACY.md`](PRIVACY.md).

## License & Credits

Licensed under **Creative Commons Attribution-NonCommercial 4.0 (CC BY-NC 4.0)** — see [`LICENSE.md`](LICENSE.md).

Omi-Island is maintained by **krishna09-dev** and is based on ideas and portions of the
original **CodeIsland / MioIsland** project by **Kris Wang (xmqywx)**. Attribution is kept
for legal and ethical credit; the old names appear only here in credits, not as the app's
branding.

## Manual testing checklist

- App launches and shows in the notch as **Omi-Island**.
- Idle notch shows pet + green dot.
- Hover opens the compact music panel; play/pause/next/prev work.
- Spotify / Apple Music / YouTube / YouTube Music show as sources.
- **Instagram Reels**, Facebook, TikTok, WhatsApp audio, and generic Safari/Chrome tab audio do **not** show, and Instagram is never mislabeled as YouTube.
- Usage Info off: no Claude/Codex text. Usage Info on: compact usage strip with SF Symbol status icons (green/yellow/red), readable used/left + reset time.
- Limit reached shows a subtle one-shot pulse (not looping, not every refresh).
- Volume/brightness island appears on hardware keys and returns to idle.
- Headphone connect/disconnect animation appears for ~3 seconds; battery % shows only if macOS provides it.
- Sound Effects off: silent. On: limit sounds once per transition (10-min cooldown); headphone sounds once per connection change.
- About page shows Omi-Island, version 1.0.0-test, and working GitHub / Issues / Releases buttons.

## Known limitations

- Auto-update is **removed** (no Sparkle, no appcast feed). "Check for Updates" opens GitHub Releases.
- The app is English-only; the macOS Automation/AppleScript permission popup is English-only.
- macOS brightness HUD suppression is best-effort and may still appear.
- Headphone battery % is best-effort and only shows when macOS exposes it.
- Apple Music artwork may fall back to an icon (no artwork URL via AppleScript).
- The app is **English-only** and CJK-free.

## For contributors / agents

- Read `AGENTS.md`, `PROJECT_CONTEXT.md`, and `CURRENT_STATUS.md` before editing.
- Verify changes with the build command above. Do **not** visually test with screenshot/computer automation unless explicitly asked — manual UI/hardware testing is done by the maintainer.
