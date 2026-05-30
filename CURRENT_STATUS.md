# Current Status

## Build

Use:

```sh
xcodebuild -project OmiIsland.xcodeproj -scheme OmiIsland -configuration Debug build CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""
```

Run:

```sh
open "$HOME/Library/Developer/Xcode/DerivedData/OmiIsland-*/Build/Products/Debug/Omi-Island.app"
```

## Current Behavior

- App name is `Omi-Island` (version `1.0.0-test`). Built product: `Omi-Island.app`. Xcode project/scheme/module/target/source-folder all `OmiIsland`. Bundle id `dev.krishna09.omiisland`. App is English-only and CJK-free, including the Automation/AppleScript permission popup.
- About page is public/open-source: name, description, version, and GitHub / Issues / Releases buttons (no WeChat/placeholder content). App icon is a black background with a pixel-art white "O".
- Version 1 settings are in General, Media, and About. The old CodeLight / Pair-iPhone settings tabs and `PairPhoneView` were removed.
- Media: only Spotify / Apple Music / YouTube / YouTube Music; Instagram/Reels, Facebook, TikTok, WhatsApp, and generic browser audio are blocked (active-tab URL allowlist + denylist).
- Auto-update is removed (Sparkle dependency + `UpdaterManager` deleted, no appcast feed); "Check for Updates" opens GitHub Releases.
- Privacy: local-first, no telemetry/analytics. By default (Show Usage Info off) **no network requests**. Only outbound: optional Claude usage poll to `api.anthropic.com` (own Keychain token / own usage). Codex usage = local files. See `PRIVACY.md`.
- Compact notch should always show pet/icon + green dot.
- Hover opens the compact music panel.
- Usage Info controls the compact Claude/Codex usage strip.
- Sound Effects controls all app sound effects and defaults off.

## Usage Status Logic

The usage strip shows:

- Used percentage.
- Left percentage when calculable.
- Reset/remaining time when known.
- Stale/unavailable when data is not current.

Status thresholds:

- 40% or more left: healthy/green.
- 15% to 39% left: warning/yellow.
- 1% to 14% left: low/red.
- 0% left or explicit limit reached: red limit reached.

If only used percentage is available, left is calculated as `100 - used`.

Status icons are **SF Symbols** (current): `checkmark.circle.fill` (healthy), `exclamationmark.circle.fill` (warning), `exclamationmark.triangle.fill` (low), `battery.0percent` (limit reached), `questionmark.circle.fill` (unavailable). They are 14pt bold, hierarchical rendering, in a fixed 18pt-wide slot for row alignment, tinted green/yellow/red/gray by health. (History: plain text faces → SF Symbols → emoji faces → back to SF Symbols, this time larger with distinct glyph shapes so the states are clearly different.) The tint is on the icon; the used/left value text stays neutral (red only on limit reached). The limit-reached pulse is a subtle one-shot triggered only on transition into limit reached.

## Sound Status Logic

Sound effects are disabled by default.

When enabled:

- Claude/Codex limit sounds trigger only when state changes from not-limit-reached to limit-reached.
- Limit sounds have a 10-minute cooldown.
- Headphone sounds trigger once per connect/disconnect event.
- Missing system sounds do not crash the app.

## Manual Testing Needed

- Toggle Sound Effects off/on.
- Toggle Usage Limit Sounds and Device Connection Sounds.
- Confirm no sounds play when Sound Effects is off.
- Confirm usage strip shows used vs left clearly.
- Confirm Codex weekly is not confused with remaining.
- Confirm limit reached pulse is subtle and one-shot.
- Confirm usage status SF Symbols render cleanly, align across Claude/Codex rows, and are tinted correctly per health level (green/yellow/red/gray); confirm each state looks clearly different.
- Confirm headphone connect/disconnect sound plays only once per event.
- Confirm no old session/dev/plugin/approval UI appears.

## Remaining Cleanup Debt

- **Chinese:** none (source, UI, Info.plist incl. the Automation popup, comments, localization). The app is English-only; `L10n.tr` is single-arg English.
- **Localization:** `Localization.swift` was pruned from 336 to ~30 members — only active-V1 strings remain (removed all sync/redemption/subscription/pairing/CodeLight/old-tab/plugin/session/completion/report labels).
- **Buddy:** the `BuddyReader`/`BuddyASCIIView`/`WyHash` subsystem (unused, read `~/.claude/.codeisland-*`) was removed. The V1 pet/green dot is self-contained.
- **Sync / CodeLight / SocketIO:** fully removed — `Services/Sync/*`, `RedeemCodeSection`, `UpgradeRequiredCoordinator`, redemption/subscription/launch-preset models+services, and the `SocketIO`/`CodeLightProtocol`/`CodeLightCrypto` packages + `LocalPackages/`. The active Accessibility-repair helper moved to `Services/Permissions/TCCPermissionFixer.swift`.
- **Old names:** none in user-visible text or branding. Intentionally kept:
  - `LICENSE.md` + README credit the original **CodeIsland/MioIsland** author **Kris Wang (xmqywx)** (CC BY-NC 4.0 attribution; legal/ethical, not branding).
  - No `codeisland`/`codelight` names remain in source. The `BuddyReader`/`BuddyASCIIView`/`WyHash` subsystem and its `~/.claude/.codeisland-*` cache reads were removed; the V1 pet/green-dot glyph is self-contained (`IslandPetGlyphView` → `PixelCharacterView`).
- **UserDefaults / IPC:** old `MioIsland.*` / `mio.*` keys are now `dev.krishna09.omiisland.*`; the hook IPC socket is `/tmp/omiisland.sock` (ephemeral). No migration needed (non-V1/internal/ephemeral, no important persisted data).
- HUD replacement is **best-effort** (macOS limits full suppression of the system volume/brightness HUD); headphone battery is **best-effort** and only shows when macOS exposes battery data. Both need real-device testing.
