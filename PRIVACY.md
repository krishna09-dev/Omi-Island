# Privacy

Omi-Island is a local-first macOS notch app. It does **not** collect, sell, or
upload your data.

## What Omi-Island does NOT do

- Does not collect or sell any data.
- Does not upload media titles, artists, browser tabs/URLs, usage status, or
  device info to any server.
- No telemetry. No analytics. No tracking. No crash reporting.
- No automatic/background "phone home", no auto-update checks, no appcast.

## Network activity

By default Omi-Island makes **no network requests at all**.

There is exactly one optional outbound request, and only when **you turn on
"Show Usage Info"** in Settings:

- **Claude usage:** Omi-Island reads *your own* Claude Code OAuth token from the
  macOS Keychain and calls `https://api.anthropic.com/api/oauth/usage` to fetch
  *your own* usage numbers (polled every 60s while enabled). Only the auth token
  (to Anthropic, the token's issuer) is sent — no media, browser, device, or
  activity data. Turn off "Show Usage Info" to stop all network activity.
- **Codex usage** is read from local files only (`~/.codex/sessions/*.jsonl`) —
  no network.

GitHub links (Star / Feedback / Releases / "Check for Updates") open in your
browser **only when you click them**. There are no GitHub API calls.

## Media detection (AppleScript / Automation)

- Used only to detect the current track from supported sources: Apple Music,
  Spotify, and the **active/front browser tab** when it is YouTube, YouTube
  Music, or Spotify Web.
- Only the active/front tab is read — Omi-Island does not scrape all tabs.
- Instagram/Reels, Facebook, TikTok, WhatsApp, and other tabs are explicitly
  denied and never displayed.
- Tab URLs/titles are used in memory to show the current track and are **never
  stored persistently or sent anywhere**.

## Local data storage

- **Preferences (UserDefaults, local only):** e.g. `showUsageInfo`, `islandPet`,
  sound-effect toggles, `replaceSystemHUD`, notch customization, optional
  Anthropic proxy URL, volume/mute. These never leave the device.
- **Keychain:** read-only. Omi-Island reads (never writes/stores) the existing
  "Claude Code-credentials" token solely to authorize the usage request above.
- **Local diagnostic log:** `~/.claude/.omiisland.log` — minimal, local-only.
  It does not record tokens, media titles, browser URLs, or usage details.
- **Local IPC:** an ephemeral UNIX socket `/tmp/omiisland.sock` (recreated each
  launch); local-only, not network.
- The current track title/artist is transient (in memory); it is not persisted.
- No user tokens, secrets, or personal data are stored by the app.

## Sound effects

- Use macOS system/named sounds (`NSSound`) only — nothing is downloaded.
- Triggering a sound never sends an event anywhere.
- All sounds can be turned off (Sound Effects master + Usage Limit Sounds +
  Device Connection Sounds). Usage-limit sounds fire only on transition into
  "limit reached" and are rate-limited (10-minute cooldown).

## Permissions requested

- **Automation / Apple Events** (`NSAppleEventsUsageDescription`): to read Now
  Playing info from supported media apps and the active browser tab. The popup
  text is English-only and accurate.
- **Accessibility** (requested at runtime, not via an Info.plist string): only
  for the optional Volume/Brightness HUD replacement (a global event tap). If
  you don't enable HUD replacement, this isn't required for core features.
- No camera, microphone, location, contacts, photos, or similar permissions.

## Known limitations

- HUD replacement is **best-effort** — macOS limits full suppression of the
  system volume/brightness HUD.
- Headphone battery is **best-effort** and only appears when macOS exposes
  battery data for the device.
- The app is **not sandboxed** (it needs AppleScript automation and read access
  to `~/.claude` / `~/.codex` for the optional usage feature). It is distributed
  unsigned for testing — right-click → Open on first launch.

## Summary

**Does Omi-Island send user data anywhere?** No. With "Show Usage Info" off it
makes no network requests. With it on, the only request goes to Anthropic with
*your own* token to read *your own* Claude usage — no personal content, media,
browser, or device data is ever transmitted.
