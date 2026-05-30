# Omi-Island Project Context

## Direction

Omi-Island is a free, open-source macOS Dynamic Island/notch app (public repo: https://github.com/krishna09-dev/Omi-Island). Version 1 is intentionally small and stable. The project was pruned from an older developer-dashboard app; keep future work inside the Version 1 scope unless the user explicitly changes direction.

The visible/public app name is **Omi-Island** (`CFBundleName`/`CFBundleDisplayName` + `PRODUCT_NAME`, built as `Omi-Island.app`). The Xcode project, scheme, Swift module, target name, and source folder are all **OmiIsland** (`OmiIsland.xcodeproj`, scheme `OmiIsland`, folder `OmiIsland/`). Bundle id: `dev.krishna09.omiisland`. Current version: `1.0.0-test` (`MARKETING_VERSION`). The app icon is a black background with a centered pixel-art white "O" (`Assets.xcassets/AppIcon.appiconset`, original art, no third-party logos).

The app is **English-only**: `L10n.tr(en, zh)` always returns the English string and `L10n.isChinese` is always `false`, so no Chinese is ever shown. (Legacy Chinese string literals remain as ignored second arguments in `Localization.swift` — see remaining debt in CURRENT_STATUS.md.)

Auto-update is removed: the Sparkle dependency and `UpdaterManager` are gone and there is no appcast feed. About → "Check for Updates" opens GitHub Releases. The app is English-only and CJK-free, including the Automation/AppleScript permission popup (`NSAppleEventsUsageDescription`).

## Version 1 Features

- Always visible black notch pill.
- Selected pet/icon and green dot always visible.
- Thin music visualizer when supported media is playing.
- Compact hover music panel.
- Simple volume/brightness island.
- Simple settings page.
- Optional compact Claude/Codex usage strip.
- Headphone connect/disconnect animation.
- Optional headphone battery display if macOS exposes it.
- Optional soft sound effects.

## Removed Legacy Features

Do not restore these:

- Claude/Codex session lists.
- Dev dashboard tabs.
- Approval/deny workflow.
- Ask-user question UI.
- Completion panel.
- Plugin marketplace/store/dock/header UI.
- Native plugin runtime.
- Huge media player layout.
- WhatsApp/generic browser media display.
- iPhone sync / CodeLight backend (`Services/Sync/*`), redemption/subscription/launch-preset code, and the `SocketIO`/`CodeLightProtocol`/`CodeLightCrypto` packages — all removed.

Maintainer: **krishna09-dev**. Licensed CC BY-NC 4.0; original **CodeIsland/MioIsland** author **Kris Wang (xmqywx)** is credited in `LICENSE.md`/README for legal/ethical attribution (the only place old names remain).

Privacy: local-first, no telemetry/analytics/tracking. By default (Show Usage Info off) there are no network requests. The only outbound call is the optional Claude usage poll to `api.anthropic.com` (the user's own Keychain token, own usage). Codex usage is read from local files. Media detection is local; GitHub links open only on click. See `PRIVACY.md`. Never add data collection, telemetry, or auto-update.

## Media Rules

Supported display sources:

- Spotify app or Spotify web if clearly identified.
- Apple Music / Music.app.
- YouTube.
- YouTube Music.

Unsupported (never shown, never guessed as YouTube):

- Instagram / Instagram Reels.
- Facebook, TikTok.
- WhatsApp audio.
- Generic Safari/Chrome/Arc/Edge/Brave media unless clearly identified as YouTube, YouTube Music, or Spotify.
- System sounds.

Browser media is classified strictly from the **active tab** URL host (`MediaSystemController.classifyBrowserSource`): a denylist (instagram/reel/facebook/tiktok/whatsapp) runs first, then a URL allowlist (youtube/youtu.be/music.youtube.com/open.spotify.com). There is no title-only guessing, so ambiguous tabs are not shown.

## Usage UI Rules

Usage Info is optional and defaults off. When off:

- Do not poll Claude/Codex usage.
- Do not show Claude/Codex text.
- Keep the panel focused on music/pet identity.

When on:

- Show only compact usage statistics.
- No session list.
- No latest sessions.
- No completed tool list.
- Label values honestly as used and left.
- If data is stale or unavailable, say so.
- Limit reached should be red and compact.

Status icon style: each row (Claude/Codex) shows a small **SF Symbol** beside the service name, tinted by health color — `checkmark.circle.fill` (healthy/green), `exclamationmark.circle.fill` (warning/yellow), `exclamationmark.triangle.fill` (low/red), `battery.0percent` (limit reached/red), `questionmark.circle.fill` (unavailable/gray). Icons are 14pt bold in a fixed 18pt-wide slot so rows align. (Emoji faces were tried but didn't fit the clean notch look; we reverted to SF Symbols, made them larger and gave each state a distinct glyph shape.) The threshold tint is on the icon; used/left value text stays neutral (red only on limit reached). Limit reached triggers a subtle one-shot pulse only on transition, never looping.

## Sound Effects

Sound effects are optional and default off.

Toggles:

- Sound Effects.
- Usage Limit Sounds.
- Device Connection Sounds.

Events:

- Claude limit reached.
- Codex limit reached.
- Headphones connected.
- Headphones disconnected.

Limit sounds play only on transition into limit reached and use a cooldown. Device sounds play on connection state changes. Missing system sounds should fail silently.

## Known Limitations

- macOS brightness HUD suppression is best-effort and may still show depending on macOS/display support.
- Headphone battery is best-effort via macOS-exposed device data and may be unavailable.
- Browser artwork/source details depend on what macOS/browser media metadata exposes.
- Some sync/session model files remain because shared models still depend on them; they should not be surfaced in V1 UI.

## Backup Notes

- Safety commit before this sound/usage work: `caf77c29 backup: before sound and usage status feature`.
- Earlier cleanup backup: `546aae3a backup: before deep legacy cleanup`.
