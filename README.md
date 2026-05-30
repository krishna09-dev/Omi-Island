# Omi-Island

A free, open-source macOS notch companion app.

Omi-Island lives in your Mac’s notch and shows music, usage status, headphone connection updates, sound effects, and custom volume/brightness islands in a compact Dynamic-Island style.

## Features

- Always-visible notch with a small pet/icon and status dot
- Compact hover music panel with album artwork and media visualizer
- Support for Spotify, Apple Music, YouTube, and YouTube Music
- Optional Claude/Codex usage status with simple health indicators
- Custom volume and brightness island
- Headphone connect/disconnect animation
- Best-effort headphone battery percentage when macOS provides it
- Optional sound effects for usage limits and device connection changes
- Clean settings window with simple controls

## Requirements

- macOS 15 or later
- Apple Silicon or Intel Mac

## Installation

Download the latest build from the Releases page:

https://github.com/krishna09-dev/Omi-Island/releases

Because the app is currently unsigned, macOS may block it the first time you open it.

To open it:

1. Right-click `Omi-Island.app`
2. Click **Open**
3. Confirm the security dialog

You can also allow it from:

```text
System Settings → Privacy & Security → Open Anyway
```

## Build from source

```sh
git clone https://github.com/krishna09-dev/Omi-Island.git
cd Omi-Island

xcodebuild -project OmiIsland.xcodeproj -scheme OmiIsland -configuration Debug build CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""
```

Open the built app:

```sh
open "$(find ~/Library/Developer/Xcode/DerivedData -name 'Omi-Island.app' -type d | head -n 1)"
```

## Supported media sources

Omi-Island only shows media from supported sources:

- Spotify app
- Spotify Web
- Apple Music / Music.app
- YouTube
- YouTube Music

Other browser audio is intentionally ignored, including Instagram, Facebook, TikTok, WhatsApp, and unknown Safari/Chrome tabs.

## Privacy

Omi-Island is local-first.

- No telemetry
- No analytics
- No tracking
- No media history collection
- No browser history collection
- No device data collection

With **Show Usage Info** turned off, Omi-Island makes no network requests.

With **Show Usage Info** turned on, the only network request is to Anthropic’s usage endpoint to read your own Claude usage status. Media, browser, and device information are never sent.

Read the full privacy details in [`PRIVACY.md`](PRIVACY.md).

## Version

Current version: **1.0.0-test**

## Roadmap

Planned improvements:

- Better first-time setup guide
- Smarter usage alerts
- More pet/icon options
- More polished media display
- GitHub release update checker

## License

Licensed under **Creative Commons Attribution-NonCommercial 4.0 (CC BY-NC 4.0)**.

See [`LICENSE.md`](LICENSE.md).

## Credits

Omi-Island is maintained by **krishna09-dev**.

This project is based on ideas and portions of the original **CodeIsland / MioIsland** project by **Kris Wang (xmqywx)**. Attribution is preserved for legal and ethical credit.
