# Omi-Island Agent Guide

## Scope

This repo is the macOS notch app **Omi-Island** (public name; built product `Omi-Island.app`). The Xcode project, scheme, Swift module, **target name, and source folder are all `OmiIsland`**. Bundle id: `dev.krishna09.omiisland`. Keep it a simple Version 1 app. Current version: `1.0.0-test`. Public repo: https://github.com/krishna09-dev/Omi-Island

Build/run uses `-project OmiIsland.xcodeproj -scheme OmiIsland`; source lives under `OmiIsland/`.

Active Version 1 features:
- Always visible notch.
- Pet/icon + green dot base identity.
- Music/media visualizer.
- Compact hover music panel.
- Simple volume/brightness custom island.
- One clean settings page.
- Optional compact Claude/Codex usage strip.
- Headphone connect/disconnect animation.
- Optional headphone battery when macOS exposes it.
- Optional sound effects.

Do not bring back:
- Session list UI.
- Approval UI.
- Ask-user/question/completion panels.
- Old Dev dashboard.
- Plugin UI/store/dock.
- Huge media player panel.
- WhatsApp or generic browser audio.
- Complex old settings tabs.

## Before You Edit

- Read `AGENTS.md`, `PROJECT_CONTEXT.md`, and `CURRENT_STATUS.md` first.
- Do not visually test with screenshot/computer/browser automation unless the user explicitly asks. Build verification only; the user runs manual UI/hardware tests.

## Usage Status UI

The compact Claude/Codex usage strip lives in `NotchMenuView.swift` (`TinyUsageStatusView`).

- Status icon style: **SF Symbols** at 14pt bold, hierarchical rendering, in a fixed 18pt-wide slot so Claude/Codex rows align. Tinted by `color(for:)`. (Emoji faces were tried but didn't fit the clean notch design, so we reverted to SF Symbols with distinct glyph shapes + larger size.)
  - healthy → `checkmark.circle.fill` (green)
  - warning → `exclamationmark.circle.fill` (yellow)
  - low → `exclamationmark.triangle.fill` (red)
  - limit reached → `battery.0percent` (red, empty-battery look)
  - unavailable → `questionmark.circle.fill` (muted gray)
- Color thresholds (by % left): `40%+` green, `15–39%` yellow, `1–14%` red, `0%`/limit reached red. When only used % is known, left = `100 − used`. The tint is applied to the **icon**; the used/left value text stays neutral (red only on limit reached) for readability.
- Limit-reached animation: subtle one-shot pulse (scale + tint flash) that fires only on transition into limit reached (`onChange` of `isLimit`), not every refresh, never looping.

## Sound Effects (working — do not break)

`OmiIsland/Core/SoundEffectsService.swift`. Toggles live in Settings.

- Toggles: Sound Effects (master), Usage Limit Sounds, Device Connection Sounds.
- Claude/Codex limit sound plays only on transition into limit reached, with a 10-minute (600s) cooldown.
- Headphone sounds play only on connection-state change. Missing system sounds fail silently.

## Commands

Build:

```sh
xcodebuild -project OmiIsland.xcodeproj -scheme OmiIsland -configuration Debug build CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""
```

Run Debug build:

```sh
open "$HOME/Library/Developer/Xcode/DerivedData/OmiIsland-*/Build/Products/Debug/Omi-Island.app"
```

Check process:

```sh
ps aux | rg "Omi-Island"
```

## Safety Rules

- Run `git status` and `git diff --stat` before editing.
- If there is uncommitted work, create a backup commit before changes.
- Do not reset, clean, or delete user WIP.
- Do not rename the visible app; it must remain exactly `Omi-Island` (set via Info.plist `CFBundleName`/`CFBundleDisplayName` and `PRODUCT_NAME`).
- Do not claim hardware behavior was verified unless tested on real hardware.

## Important Files

- `OmiIsland/UI/Views/NotchView.swift`: compact notch, level island, headphone animation.
- `OmiIsland/UI/Views/NotchMenuView.swift`: compact hover music panel and usage strip.
- `OmiIsland/UI/Views/SystemSettingsView.swift`: V1 settings.
- `OmiIsland/Services/Media/MediaSystemController.swift`: media detection, volume/brightness island, headphone events.
- `OmiIsland/Services/Session/RateLimitMonitor.swift`: Claude usage polling, only when Show Usage Info is on.
- `OmiIsland/Services/Session/CodexUsage.swift`: Codex usage parsing, only when Show Usage Info is on.
- `OmiIsland/Core/SoundEffectsService.swift`: optional V1 sound effects.
- `OmiIsland/App/AppDelegate.swift`: defaults and usage polling start/stop.
- `OmiIsland/Assets.xcassets/AppIcon.appiconset`: app icon — black background with a centered pixel-art white "O" (10 sizes 16→1024). Regenerated via a CoreGraphics script; keep it original (no third-party/brand logos).
- The **sync / CodeLight backend is removed**: `Services/Sync/*` (ServerConnection, SyncManager, MessageRelay, RPCExecutor, CapabilityScanner, TerminalWriter, PermissionAlertNotifier), `RedeemCodeSection`, `UpgradeRequiredCoordinator`, the redemption/subscription/launch-preset models+services, and the `SocketIO`/`CodeLightProtocol`/`CodeLightCrypto` Swift packages were all deleted (not used by V1). The one still-needed piece, the Accessibility-repair helper, was moved to `OmiIsland/Services/Permissions/TCCPermissionFixer.swift`.
- Auto-update is **removed**: the Sparkle dependency and `UpdaterManager` are gone; there is no appcast feed. About → "Check for Updates" opens https://github.com/krishna09-dev/Omi-Island/releases.
- The app is **English-only** and **CJK-free**. The Automation/AppleScript permission popup (`NSAppleEventsUsageDescription` in `Info.plist`) is English-only.
- Maintainer: **krishna09-dev**. Licensed CC BY-NC 4.0; `LICENSE.md` + README credit the original **CodeIsland/MioIsland** author **Kris Wang (xmqywx)** (legal/ethical attribution) — the only place old names intentionally remain.
- **Privacy:** local-first, no telemetry/analytics. The only network call is the optional Claude usage poll to `api.anthropic.com` (own token, only when `showUsageInfo` is on); Codex usage is local files. See `PRIVACY.md`. Do not add data collection/telemetry/auto-update.
- No `codeisland`/`codelight` names remain in source. The old `BuddyReader`/`BuddyASCIIView` subsystem (and its `~/.claude/.codeisland-*` cache reads) was removed; the V1 pet/green-dot glyph (`IslandPetGlyphView` → `PixelCharacterView`) is self-contained. The hook IPC socket is `/tmp/omiisland.sock`.

## Manual Test Checklist

- App launches as `Omi-Island`.
- Idle notch remains visible with pet + green dot.
- Hover opens compact panel.
- Spotify, YouTube, YouTube Music, and Apple Music behave as supported sources.
- Instagram/Reels, Facebook, TikTok, WhatsApp, and generic Safari/Chrome tab audio do NOT appear, and Instagram is never mislabeled as YouTube. Browser media is classified strictly from the **active tab** URL host (`MediaSystemController.classifyBrowserSource`: denylist + URL allowlist, no title guessing).
- Volume/brightness island appears and returns to idle/media state.
- Headphone connect/disconnect animation appears for about 3 seconds.
- Usage Info off: no Claude/Codex text.
- Usage Info on: compact usage strip only, no session list.
- Sound Effects off: no app sounds.
- Sound Effects on: limit/device sounds play once per transition, not every refresh.
