//
//  MediaSystemController.swift
//  OmiIsland
//
//  Small media/system-control layer for the built-in notch media plugin.
//

import AppKit
import Combine
import CoreAudio
import Darwin
import Foundation
import SwiftUI

struct NowPlayingInfo: Equatable, Sendable {
    var appName: String = "No media"
    var title: String = "Nothing playing"
    var artist: String = "Works with browser, Music, Spotify and media apps"
    var isPlaying: Bool = false
    var hasMetadata: Bool = false
    var artworkURL: String?
    var position: Double?
    var duration: Double?
    var sourceURL: String?

    var progress: Double? {
        guard let position, let duration, duration > 0 else { return nil }
        return max(0, min(1, position / duration))
    }
}

@MainActor
final class MediaSystemController: ObservableObject {
    static let shared = MediaSystemController()

    @Published private(set) var nowPlaying = NowPlayingInfo()
    @Published private(set) var mediaVisible = false
    @Published private(set) var outputVolume: Int = 0
    @Published private(set) var displayBrightness: Int = 50
    @Published private(set) var outputMuted: Bool = false
    @Published private(set) var outputDeviceName: String = "Output"
    @Published private(set) var hudEventTapActive = false
    @Published private(set) var volumeReplacementActive = false
    @Published private(set) var brightnessReplacementActive = false
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var hudReplacementStatus = "Replacement inactive"

    private var refreshTask: Task<Void, Never>?
    private var mediaCollapseTask: Task<Void, Never>?
    private var metadataFetchTask: Task<Void, Never>?
    private var brightnessRefreshTask: Task<Void, Never>?
    private var globalMediaMonitor: Any?
    private var localMediaMonitor: Any?
    private var defaultsObserver: Any?
    private var appActiveObserver: Any?
    private var hudEventTap: CFMachPort?
    private var hudRunLoopSource: CFRunLoopSource?
    private var lastHUDDiagnostic = ""
    private var didSeedOutputDevice = false

    private enum MediaKey {
        static let soundUp = 0
        static let soundDown = 1
        static let mute = 7
        static let brightnessUp = 2
        static let brightnessDown = 3
        static let play = 16
        static let next = 17
        static let previous = 18
    }

    private init() {}

    private var shouldShowSystemLevelIsland: Bool {
        UserDefaults.standard.object(forKey: "showSystemLevelIsland") as? Bool ?? true
    }

    func start() {
        guard refreshTask == nil else { return }
        refresh()
        installMediaKeyMonitors()
        installDefaultsObserver()
        installAppActiveObserver()
        // HUD event-tap setup is retried because on a fresh launch / login the
        // Accessibility trust state and the WindowServer event tap registration
        // are not always ready on the first attempt (issue: HUD replacement
        // doesn't survive restart). Retry immediately, then at 1s and 3s.
        configureHUDReplacementTap()
        scheduleHUDReplacementRetries()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    self?.refresh()
                }
            }
        }
    }

    /// Retry the HUD event-tap install shortly after launch. Each attempt is a
    /// no-op once a tap is already active, so the retries are safe and cheap.
    private func scheduleHUDReplacementRetries() {
        for delay in [1.0, 3.0] {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                await MainActor.run {
                    guard let self, self.replaceSystemHUDEnabled, self.hudEventTap == nil else { return }
                    DebugLogger.log("HUD", "retry event tap install after \(delay)s")
                    self.configureHUDReplacementTap()
                }
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        mediaCollapseTask?.cancel()
        mediaCollapseTask = nil
        metadataFetchTask?.cancel()
        metadataFetchTask = nil
        brightnessRefreshTask?.cancel()
        brightnessRefreshTask = nil
        if let globalMediaMonitor {
            NSEvent.removeMonitor(globalMediaMonitor)
            self.globalMediaMonitor = nil
        }
        if let localMediaMonitor {
            NSEvent.removeMonitor(localMediaMonitor)
            self.localMediaMonitor = nil
        }
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
            self.appActiveObserver = nil
        }
        removeHUDReplacementTap()
    }

    func refresh() {
        // Re-check Accessibility trust on every tick rather than trusting the
        // value captured at launch (issue: permission randomly shows missing).
        // If it just became trusted and HUD replacement is on, recover the
        // event tap without requiring an app restart. We never prompt here —
        // AXIsProcessTrusted() is a passive query, not a prompt.
        let wasTrusted = accessibilityTrusted
        refreshPermissionStatus()
        if accessibilityTrusted && !wasTrusted && replaceSystemHUDEnabled && hudEventTap == nil {
            DebugLogger.log("HUD", "accessibility became trusted; recovering event tap")
            configureHUDReplacementTap()
        }

        refreshNowPlayingAsync()
        outputVolume = readOutputVolume()
        outputMuted = readOutputMuted()
        if let brightness = readDisplayBrightnessPercent() {
            displayBrightness = brightness
        }
        let device = readOutputDeviceName()
        if device != outputDeviceName {
            let wasExternal = isExternalOutputDeviceName(outputDeviceName)
            let isExternal = isExternalOutputDeviceName(device)
            outputDeviceName = device
            if didSeedOutputDevice && shouldShowSystemLevelIsland && wasExternal != isExternal {
                showAudioDeviceActivity(isConnected: isExternal, deviceName: device)
            }
            didSeedOutputDevice = true
        } else if !didSeedOutputDevice {
            outputDeviceName = device
            didSeedOutputDevice = true
        }
    }

    func playPause() {
        postMediaKey(MediaKey.play)
        nowPlaying.isPlaying.toggle()
        mediaVisible = true
        refreshSoon()
    }

    func nextTrack() {
        postMediaKey(MediaKey.next)
        refreshSoon()
    }

    func previousTrack() {
        postMediaKey(MediaKey.previous)
        refreshSoon()
    }

    func setVolume(_ value: Int) {
        let clamped = max(0, min(100, value))
        Task.detached {
            _ = Self.runAppleScript("set volume output volume \(clamped)")
        }
        outputVolume = clamped
        outputMuted = clamped == 0 ? true : outputMuted
        showVolumeActivity(value: clamped)
    }

    func adjustVolume(by delta: Int) {
        setVolume(outputVolume + delta)
    }

    func toggleMute() {
        let nextMuted = !outputMuted
        Task.detached {
            _ = Self.runAppleScript("set volume \(nextMuted ? "with" : "without") output muted")
        }
        outputMuted = nextMuted
        showVolumeActivity(value: nextMuted ? 0 : outputVolume, label: nextMuted ? "Mute" : "\(outputVolume)%")
    }

    func brightnessUp() {
        postMediaKey(MediaKey.brightnessUp)
        refreshBrightnessSoon(fallbackDelta: 8)
    }

    func brightnessDown() {
        postMediaKey(MediaKey.brightnessDown)
        refreshBrightnessSoon(fallbackDelta: -8)
    }

    private func refreshSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            await MainActor.run { self?.refresh() }
        }
    }

    private func refreshSystemLevelSoon(type: NotchActivityType) {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard let self else { return }
            switch type {
            case .volume:
                let fallback = await MainActor.run { self.outputVolume }
                let nextVolume = await Task.detached {
                    Self.readOutputVolume(fallback: fallback)
                }.value
                await MainActor.run {
                    self.outputVolume = nextVolume
                    self.outputMuted = self.readOutputMuted()
                    self.showVolumeActivity(value: nextVolume, label: self.outputMuted ? "Mute" : "\(nextVolume)%")
                }
            case .brightness:
                await MainActor.run { self.refreshBrightnessSoon(fallbackDelta: 0) }
            default:
                break
            }
        }
    }

    private func refreshBrightnessSoon(fallbackDelta: Int) {
        brightnessRefreshTask?.cancel()
        let previous = displayBrightness
        brightnessRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(115))
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.brightnessRefreshTask = nil
                if let actual = self.readDisplayBrightnessPercent() {
                    self.displayBrightness = actual
                    self.showBrightnessActivity(label: "\(actual)%", value: CGFloat(actual) / 100)
                } else if fallbackDelta != 0 {
                    let fallback = max(0, min(100, previous + fallbackDelta))
                    self.displayBrightness = fallback
                    self.showBrightnessActivity(label: "\(fallback)%", value: CGFloat(fallback) / 100)
                } else {
                    self.showBrightnessActivity(label: "--", value: CGFloat(previous) / 100)
                }
            }
        }
    }

    private func refreshNowPlayingAsync() {
        guard metadataFetchTask == nil else { return }
        let previous = nowPlaying
        let visible = mediaVisible
        metadataFetchTask = Task { [weak self] in
            let info = await Task.detached {
                Self.readNowPlaying(previous: previous, mediaVisible: visible)
            }.value
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.metadataFetchTask = nil
                if self.nowPlaying != info {
                    self.nowPlaying = info
                }
                self.updateMediaVisibility(for: info)
            }
        }
    }

    private func updateMediaVisibility(for info: NowPlayingInfo) {
        guard info.hasMetadata else {
            if mediaVisible && mediaCollapseTask == nil {
                scheduleMediaCollapse(after: 1.6)
            }
            return
        }

        mediaCollapseTask?.cancel()
        mediaCollapseTask = nil

        if info.isPlaying {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                mediaVisible = true
            }
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                mediaVisible = true
            }
            scheduleMediaCollapse(after: 2.2)
        }
    }

    private func scheduleMediaCollapse(after delay: TimeInterval) {
        mediaCollapseTask?.cancel()
        mediaCollapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                    self.mediaVisible = false
                }
            }
        }
    }

    nonisolated private static func readNowPlaying(previous: NowPlayingInfo, mediaVisible: Bool) -> NowPlayingInfo {
        var pausedRichInfo: NowPlayingInfo?

        if isAppRunning("Spotify"),
           let info = parseNowPlaying(script: """
           tell application "Spotify"
             set artworkValue to ""
             try
               set artworkValue to artwork url of current track
             end try
             set positionValue to player position
             set durationValue to (duration of current track) / 1000
             if player state is playing then
               return "Spotify\n" & name of current track & "\n" & artist of current track & "\nplaying\n" & artworkValue & "\n" & positionValue & "\n" & durationValue
             else
               return "Spotify\n" & name of current track & "\n" & artist of current track & "\npaused\n" & artworkValue & "\n" & positionValue & "\n" & durationValue
             end if
           end tell
           """) {
            if info.isPlaying {
                return info
            }
            pausedRichInfo = info
        }

        if isAppRunning("Music"),
           let info = parseNowPlaying(script: """
           tell application "Music"
             set positionValue to player position
             set durationValue to duration of current track
             if player state is playing then
               return "Music\n" & name of current track & "\n" & artist of current track & "\nplaying\n\n" & positionValue & "\n" & durationValue
             else
               return "Music\n" & name of current track & "\n" & artist of current track & "\npaused\n\n" & positionValue & "\n" & durationValue
             end if
           end tell
           """) {
            if info.isPlaying {
                return info
            }
            pausedRichInfo = pausedRichInfo ?? info
        }

        if let assertionInfo = readSystemAudioAssertion() {
            return assertionInfo
        }

        if let pausedRichInfo {
            return pausedRichInfo
        }

        return NowPlayingInfo()
    }

    nonisolated private static func parseNowPlaying(script: String) -> NowPlayingInfo? {
        guard let raw = runAppleScript(script), !raw.isEmpty else { return nil }
        let parts = raw.components(separatedBy: "\n")
        guard parts.count >= 4 else { return nil }
        return NowPlayingInfo(
            appName: parts[0],
            title: parts[1].isEmpty ? "Unknown track" : parts[1],
            artist: parts[2].isEmpty ? parts[0] : parts[2],
            isPlaying: parts[3] == "playing",
            hasMetadata: true,
            artworkURL: parts.count > 4 && !parts[4].isEmpty ? parts[4] : nil,
            position: parts.count > 5 ? Double(parts[5]) : nil,
            duration: parts.count > 6 ? Double(parts[6]) : nil,
            sourceURL: nil
        )
    }

    nonisolated private static func isAppRunning(_ appName: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.localizedName == appName }
    }

    private func readOutputVolume() -> Int {
        Self.readOutputVolume(fallback: outputVolume)
    }

    private func readOutputMuted() -> Bool {
        Self.readOutputMuted(fallback: outputMuted)
    }

    nonisolated private static func readOutputVolume(fallback: Int) -> Int {
        guard let raw = runAppleScript("output volume of (get volume settings)") else { return fallback }
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback
    }

    nonisolated private static func readOutputMuted(fallback: Bool) -> Bool {
        guard let raw = runAppleScript("output muted of (get volume settings)") else { return fallback }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveContains("true")
    }

    nonisolated private static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else {
            return nil
        }
        return descriptor.stringValue
    }

    nonisolated private static func readSystemAudioAssertion() -> NowPlayingInfo? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "assertions"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8) else { return nil }

            let lowered = output.lowercased()
            if lowered.contains("webkit media playback") || lowered.contains("htmlmediaelement playback") {
                let fallbackSource: String
                if lowered.contains("safari") {
                    fallbackSource = "Safari"
                } else if lowered.contains("chrome") {
                    fallbackSource = "Chrome"
                } else if lowered.contains("edge") {
                    fallbackSource = "Edge"
                } else if lowered.contains("brave") {
                    fallbackSource = "Brave"
                } else if lowered.contains("firefox") {
                    fallbackSource = "Firefox"
                } else {
                    fallbackSource = "Browser media"
                }
                guard let browserInfo = readBrowserMediaInfo(fallbackSource: fallbackSource) else {
                    return nil
                }
                let source = browserInfo.source
                let title = browserInfo.title ?? "\(source) media"
                return NowPlayingInfo(
                    appName: source,
                    title: title,
                    artist: browserInfo.artist,
                    isPlaying: true,
                    hasMetadata: true,
                    artworkURL: browserInfo.artworkURL,
                    sourceURL: browserInfo.sourceURL
                )
            }
        } catch {
            return nil
        }

        return nil
    }

    nonisolated private static func readBrowserMediaInfo(fallbackSource: String) -> (source: String, title: String?, artist: String, artworkURL: String?, sourceURL: String)? {
        let candidates: [(app: String, script: String)] = [
            (
                "Safari",
                """
                tell application "Safari"
                  if (count of windows) > 0 and (count of tabs of front window) > 0 then
                    return (URL of current tab of front window) & "\n" & (name of current tab of front window)
                  end if
                end tell
                """
            ),
            ("Google Chrome", chromiumTabScript(appName: "Google Chrome")),
            ("Brave Browser", chromiumTabScript(appName: "Brave Browser")),
            ("Microsoft Edge", chromiumTabScript(appName: "Microsoft Edge")),
            ("Arc", chromiumTabScript(appName: "Arc"))
        ]

        for candidate in candidates where isAppRunning(candidate.app) {
            guard let raw = runAppleScript(candidate.script), !raw.isEmpty else { continue }
            let parts = raw.components(separatedBy: "\n")
            let url = parts.first ?? ""
            let title = parts.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let classified = classifyBrowserSource(url: url, title: title, fallbackSource: fallbackSource) {
                return classified
            }
        }

        return nil
    }

    nonisolated private static func chromiumTabScript(appName: String) -> String {
        // Only inspect the ACTIVE tab of the front window. Scanning every tab
        // for a youtube.com URL caused false positives: Instagram Reels (or any
        // other audio) playing while a YouTube tab sat in the background would
        // be mislabeled as YouTube. The active tab is the only one we can
        // reasonably attribute the current playback to.
        """
        tell application "\(appName)"
          if (count of windows) > 0 then
            return (URL of active tab of front window) & "\n" & (title of active tab of front window)
          end if
        end tell
        """
    }

    nonisolated private static func classifyBrowserSource(
        url: String,
        title: String?,
        fallbackSource: String
    ) -> (source: String, title: String?, artist: String, artworkURL: String?, sourceURL: String)? {
        let loweredURL = url.lowercased()
        let loweredTitle = (title ?? "").lowercased()
        let cleanedTitle = cleanBrowserTitle(title)

        // Denylist — never surface these as media, even if the system reports
        // webkit playback and even if a stray "youtube" token appears elsewhere.
        let denied = [
            "instagram.com", "/reel", "reels", "facebook.com", "fb.watch",
            "tiktok.com", "whatsapp", "web.whatsapp.com"
        ]
        for token in denied where loweredURL.contains(token) || loweredTitle.contains(token) {
            return nil
        }

        // Allowlist — classify strictly by URL host. We do NOT guess from the
        // title alone, so an ambiguous/unknown tab is simply not shown.
        if loweredURL.contains("music.youtube.com") {
            return ("YouTube Music", cleanedTitle, "YouTube Music", nil, url)
        }
        if loweredURL.contains("youtube.com") || loweredURL.contains("youtu.be") {
            return ("YouTube", cleanedTitle, "YouTube", nil, url)
        }
        if loweredURL.contains("open.spotify.com") || loweredURL.contains("spotify.com") {
            return ("Spotify", cleanedTitle, "Spotify", nil, url)
        }
        return nil
    }

    nonisolated private static func cleanBrowserTitle(_ title: String?) -> String? {
        guard var value = title?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        for suffix in [" - YouTube Music", " - YouTube", " | YouTube Music", " | YouTube"] {
            if value.hasSuffix(suffix) {
                value.removeLast(suffix.count)
                break
            }
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func installMediaKeyMonitors() {
        guard globalMediaMonitor == nil, localMediaMonitor == nil else { return }
        globalMediaMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            Task { @MainActor in self?.handleSystemDefinedEvent(event) }
        }
        localMediaMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            Task { @MainActor in self?.handleSystemDefinedEvent(event) }
            return event
        }
    }

    private func installDefaultsObserver() {
        guard defaultsObserver == nil else { return }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor in
                controller.configureHUDReplacementTap()
            }
        }
    }

    private func installAppActiveObserver() {
        guard appActiveObserver == nil else { return }
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor in
                controller.configureHUDReplacementTap()
            }
        }
    }

    private func refreshPermissionStatus() {
        let trusted = AXIsProcessTrusted()
        if trusted != accessibilityTrusted {
            accessibilityTrusted = trusted
        }
        if replaceSystemHUDEnabled && !trusted {
            hudReplacementStatus = "Replacement inactive: Accessibility missing"
        }
    }

    private var replaceSystemHUDEnabled: Bool {
        UserDefaults.standard.bool(forKey: "replaceSystemHUD")
    }

    /// Manually re-check Accessibility trust and (re)attempt the HUD event tap.
    /// Backs the "Refresh status" button so the user can recover after granting
    /// permission without restarting the app. Does not prompt.
    func refreshHUDStatus() {
        refreshPermissionStatus()
        configureHUDReplacementTap()
    }

    func requestHUDReplacementPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        configureHUDReplacementTap()
    }

    private func configureHUDReplacementTap() {
        refreshPermissionStatus()
        guard replaceSystemHUDEnabled else {
            updateHUDDiagnostic("Replacement inactive", log: "setting=off trusted=\(accessibilityTrusted)")
            removeHUDReplacementTap()
            return
        }
        guard accessibilityTrusted else {
            updateHUDDiagnostic("Replacement inactive: Accessibility missing", log: "setting=on trusted=false")
            removeHUDReplacementTap()
            return
        }
        guard hudEventTap == nil else { return }

        let mask = CGEventMask(1 << 14)
        updateHUDDiagnostic("Creating event tap", log: "setting=on trusted=true mask=\(mask)")
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.hudEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            hudEventTapActive = false
            volumeReplacementActive = false
            brightnessReplacementActive = false
            updateHUDDiagnostic("Replacement unavailable: event tap failed", log: "tapCreate failed; macOS may require Input Monitoring or may not deliver hardware keys")
            return
        }

        hudEventTap = tap
        hudRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let hudRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), hudRunLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        hudEventTapActive = true
        volumeReplacementActive = true
        brightnessReplacementActive = false
        updateHUDDiagnostic(
            "Replacement active: volume/mute active · brightness best effort",
            log: "event tap created/enabled; volume/mute swallowed; brightness swallowed only when DisplayServicesSetBrightness succeeds"
        )
    }

    private func removeHUDReplacementTap() {
        if let tap = hudEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = hudRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        hudRunLoopSource = nil
        hudEventTap = nil
        if hudEventTapActive {
            hudEventTapActive = false
        }
        volumeReplacementActive = false
        brightnessReplacementActive = false
    }

    private func updateHUDDiagnostic(_ status: String, log: String) {
        hudReplacementStatus = status
        let diagnostic = "\(status)|\(log)"
        guard diagnostic != lastHUDDiagnostic else { return }
        lastHUDDiagnostic = diagnostic
        DebugLogger.log("HUD", log)
    }

    private nonisolated static let hudEventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<MediaSystemController>.fromOpaque(refcon).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DebugLogger.log("HUD", "event tap disabled by macOS type=\(type.rawValue); attempting re-enable")
            Task { @MainActor in controller.configureHUDReplacementTap() }
            return Unmanaged.passUnretained(event)
        }

        guard type.rawValue == 14,
              UserDefaults.standard.bool(forKey: "replaceSystemHUD"),
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = (nsEvent.data1 & 0xFFFF0000) >> 16
        let keyState = (nsEvent.data1 & 0x0000FF00) >> 8
        guard keyState == 0x0A else { return Unmanaged.passUnretained(event) }

        switch keyCode {
        case MediaKey.soundUp:
            DebugLogger.log("HUD", "received volumeUp key; swallowing system event")
            Task { @MainActor in controller.adjustVolume(by: 6) }
            return nil
        case MediaKey.soundDown:
            DebugLogger.log("HUD", "received volumeDown key; swallowing system event")
            Task { @MainActor in controller.adjustVolume(by: -6) }
            return nil
        case MediaKey.mute:
            DebugLogger.log("HUD", "received mute key; swallowing system event")
            Task { @MainActor in controller.toggleMute() }
            return nil
        case MediaKey.brightnessUp, MediaKey.brightnessDown:
            let delta = keyCode == 2 ? 8 : -8
            Task { @MainActor in controller.adjustBrightnessForReplacement(by: delta) }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleSystemDefinedEvent(_ event: NSEvent) {
        guard event.subtype.rawValue == 8 else { return }
        let keyCode = (event.data1 & 0xFFFF0000) >> 16
        let keyState = (event.data1 & 0x0000FF00) >> 8
        guard keyState == 0x0A else { return }

        switch keyCode {
        case MediaKey.soundUp, MediaKey.soundDown, MediaKey.mute:
            refreshSoon()
            refreshSystemLevelSoon(type: .volume)
        case MediaKey.brightnessUp:
            refreshBrightnessSoon(fallbackDelta: 8)
        case MediaKey.brightnessDown:
            refreshBrightnessSoon(fallbackDelta: -8)
        case MediaKey.play:
            nowPlaying.isPlaying.toggle()
            mediaVisible = true
            refreshSoon()
        case MediaKey.next, MediaKey.previous:
            refreshSoon()
        default:
            break
        }
    }

    private func showBrightnessActivity(label: String? = nil, value: CGFloat? = nil) {
        guard shouldShowSystemLevelIsland else { return }
        let level = value ?? CGFloat(displayBrightness) / 100
        NotchActivityCoordinator.shared.showActivity(
            type: .brightness,
            value: max(0, min(1, level)),
            label: label ?? "\(displayBrightness)%",
            duration: 0.9
        )
    }

    private func showVolumeActivity(value: Int, label: String? = nil) {
        guard shouldShowSystemLevelIsland else { return }
        NotchActivityCoordinator.shared.showActivity(
            type: .volume,
            value: CGFloat(value) / 100,
            label: label ?? "\(value)%",
            duration: 0.9
        )
    }

    private func showAudioDeviceActivity(isConnected: Bool, deviceName: String) {
        SoundEffectsService.shared.playHeadphoneConnection(isConnected: isConnected)
        let fallbackLabel = isConnected ? "" : ""
        guard isConnected else {
            NotchActivityCoordinator.shared.showActivity(
                type: .audioDevice,
                value: 0,
                label: fallbackLabel,
                duration: 3.0
            )
            return
        }

        Task {
            let battery = await Task.detached {
                Self.readHeadphoneBatteryPercent(deviceName: deviceName)
            }.value
            let label = battery.map { "\($0)%" } ?? fallbackLabel
            NotchActivityCoordinator.shared.showActivity(
                type: .audioDevice,
                value: 1,
                label: label,
                duration: 3.0
            )
        }
    }

    private func adjustBrightnessForReplacement(by delta: Int) {
        let next = max(0, min(100, displayBrightness + delta))
        if setDisplayBrightnessPercent(next) {
            displayBrightness = next
            brightnessReplacementActive = true
            showBrightnessActivity(label: "\(next)%", value: CGFloat(next) / 100)
            updateHUDDiagnostic(
                "Replacement active: volume/mute active · brightness active",
                log: "brightness set via DisplayServicesSetBrightness"
            )
        } else {
            brightnessReplacementActive = false
            showBrightnessActivity(label: "\(displayBrightness)%", value: CGFloat(displayBrightness) / 100)
            updateHUDDiagnostic(
                "Brightness replacement unavailable; system HUD may still appear",
                log: "DisplayServicesSetBrightness unavailable or failed"
            )
        }
    }

    private func readDisplayBrightnessPercent() -> Int? {
        guard let displayID = activeBrightnessDisplayID() else { return nil }
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY
        ) else { return nil }
        defer { dlclose(handle) }

        typealias DisplayBrightnessReader = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        guard let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        let readBrightness = unsafeBitCast(symbol, to: DisplayBrightnessReader.self)
        var rawBrightness: Float = 0
        guard readBrightness(displayID, &rawBrightness) == 0 else { return nil }
        let clamped = max(0, min(1, Double(rawBrightness)))
        return Int((clamped * 100).rounded())
    }

    private func setDisplayBrightnessPercent(_ percent: Int) -> Bool {
        guard let displayID = activeBrightnessDisplayID() else { return false }
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY
        ) else { return false }
        defer { dlclose(handle) }

        typealias DisplayBrightnessWriter = @convention(c) (CGDirectDisplayID, Float) -> Int32
        guard let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { return false }
        let setBrightness = unsafeBitCast(symbol, to: DisplayBrightnessWriter.self)
        let raw = Float(max(0, min(100, percent))) / 100
        return setBrightness(displayID, raw) == 0
    }

    private func activeBrightnessDisplayID() -> CGDirectDisplayID? {
        let screen = NSScreen.builtin ?? NSScreen.main
        return screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func isExternalOutputDeviceName(_ name: String) -> Bool {
        let normalized = name.lowercased()
        guard !normalized.isEmpty else { return false }
        let builtInNames = ["output", "speaker", "macbook", "display audio", "built-in"]
        return !builtInNames.contains { normalized.contains($0) }
    }

    nonisolated private static func readHeadphoneBatteryPercent(deviceName: String) -> Int? {
        guard let output = runProcess(
            executable: "/usr/sbin/ioreg",
            arguments: ["-r", "-c", "AppleDeviceManagementHIDEventService", "-l"]
        ) else { return nil }

        let requestedName = deviceName.lowercased()
        var currentProduct = ""
        var currentBattery: Int?
        var fallbackBattery: Int?

        func isLikelyAudioProduct(_ value: String) -> Bool {
            let lower = value.lowercased()
            return lower.contains("airpod")
                || lower.contains("beats")
                || lower.contains("headphone")
                || lower.contains("earbud")
                || lower.contains("buds")
        }

        func flushCurrent() -> Int? {
            guard let currentBattery else { return nil }
            let product = currentProduct.lowercased()
            if !requestedName.isEmpty, !product.isEmpty,
               (product.contains(requestedName) || requestedName.contains(product)),
               currentBattery >= 0, currentBattery <= 100 {
                return currentBattery
            }
            if fallbackBattery == nil, isLikelyAudioProduct(currentProduct), currentBattery >= 0, currentBattery <= 100 {
                fallbackBattery = currentBattery
            }
            return nil
        }

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.contains("\"Product\" =") || line.contains("\"ProductName\" =") || line.contains("\"DeviceName\" =") {
                if let match = flushCurrent() { return match }
                currentProduct = line.components(separatedBy: "=").dropFirst().joined(separator: "=")
                    .replacingOccurrences(of: "\"", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                currentBattery = nil
            } else if line.contains("\"BatteryPercent\" =") || line.contains("\"BatteryPercentSingle\" =") {
                let digits = line.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if let value = Int(digits), value >= 0, value <= 100 {
                    currentBattery = value
                }
            }
        }
        if let match = flushCurrent() { return match }
        return fallbackBattery
    }

    nonisolated private static func runProcess(executable: String, arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func postMediaKey(_ keyCode: Int) {
        postMediaKey(keyCode, keyState: 0x0A)
        postMediaKey(keyCode, keyState: 0x0B)
    }

    private func postMediaKey(_ keyCode: Int, keyState: Int) {
        let data1 = (keyCode << 16) | (keyState << 8)
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
            timestamp: Date.timeIntervalSinceReferenceDate,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: CGEventTapLocation.cghidEventTap)
    }

    private func readOutputDeviceName() -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr else {
            return "Output"
        }

        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfName: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &size, &cfName) == noErr else {
            return "Output"
        }
        return cfName as String
    }
}
