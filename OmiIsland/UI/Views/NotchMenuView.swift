//
//  NotchMenuView.swift
//  OmiIsland
//
//  Minimal menu matching Dynamic Island aesthetic
//

import Combine
import SwiftUI

private func menuTheme() -> ThemeResolver {
    ThemeResolver(theme: NotchCustomizationStore.shared.customization.theme)
}

// MARK: - NotchMenuView

struct NotchMenuView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var media = MediaSystemController.shared
    private var theme: ThemeResolver { menuTheme() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Music")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(theme.primaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(theme.overlay.opacity(0.18)))

                Spacer()

                Button {
                    SystemSettingsWindow.shared.show()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(theme.secondaryText)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(theme.overlay.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .help("Open Settings")
            }

            MusicExpandedPanel()
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.background.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(theme.overlay.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.top, 5)
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear {
            media.start()
        }
    }
}

private struct MusicExpandedPanel: View {
    @ObservedObject private var media = MediaSystemController.shared
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared
    @ObservedObject private var codexUsage = CodexUsageMonitor.shared
    @ObservedObject private var claudeUsage = RateLimitMonitor.shared
    @AppStorage("showUsageInfo") private var showUsageInfo: Bool = false
    private var theme: ThemeResolver { ThemeResolver(theme: notchStore.customization.theme) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            AlbumArtworkView(info: media.nowPlaying)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.nowPlaying.hasMetadata ? media.nowPlaying.title : "Nothing playing")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(media.nowPlaying.hasMetadata ? media.nowPlaying.artist : "Start Spotify or Apple Music")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 8) {
                        Text(media.nowPlaying.appName)
                        Circle().fill(theme.mutedText).frame(width: 4, height: 4)
                        Text(media.nowPlaying.isPlaying ? "Playing" : "Paused")
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(theme.mutedText)
                }

                if let progress = media.nowPlaying.progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.overlay.opacity(0.22))
                            Capsule()
                                .fill(theme.primaryText.opacity(0.9))
                                .frame(width: max(8, geo.size.width * progress))
                        }
                    }
                    .frame(height: 2.5)
                }

                HStack(spacing: 9) {
                    mediaButton("backward.fill") { media.previousTrack() }
                    mediaButton(media.nowPlaying.isPlaying ? "pause.fill" : "play.fill", large: true) { media.playPause() }
                    mediaButton("forward.fill") { media.nextTrack() }
                }
                .padding(.top, 1)
            }

            if showUsageInfo {
                TinyUsageStatusView(
                    claudeInfo: claudeUsage.rateLimitInfo,
                    claudeLastRefreshAt: claudeUsage.lastRefreshAt,
                    claudeLastError: claudeUsage.lastRefreshError,
                    codexSnapshot: codexUsage.snapshot,
                    codexLastRefreshAt: codexUsage.lastRefreshAt
                )
                .frame(width: 150)
            } else {
                PanelMascotView()
                    .frame(width: 60, height: 58)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mediaButton(_ icon: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: large ? 12 : 10, weight: .semibold))
                .foregroundColor(large ? theme.inverseText : theme.primaryText)
                .frame(width: large ? 30 : 24, height: large ? 30 : 24)
                .background(Circle().fill(large ? theme.primaryText : theme.overlay.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }
}

private struct TinyUsageStatusView: View {
    let claudeInfo: RateLimitDisplayInfo?
    let claudeLastRefreshAt: Date?
    let claudeLastError: String?
    let codexSnapshot: CodexUsageSnapshot?
    let codexLastRefreshAt: Date?
    private var theme: ThemeResolver { menuTheme() }

    /// Re-render every 30s so the "resets in …" countdown stays fresh even
    /// when the underlying usage data hasn't changed.
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    @State private var tick = 0
    @State private var claudeLimitPulse = false
    @State private var codexLimitPulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            usageBlock(claude, pulse: claudeLimitPulse)
            Divider().overlay(theme.overlay.opacity(0.18))
            usageBlock(codex, pulse: codexLimitPulse)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(theme.overlay.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(theme.overlay.opacity(0.16), lineWidth: 0.5)
                )
        )
        .onReceive(ticker) { _ in tick &+= 1 }
        .onChange(of: claude.isLimit) { oldValue, newValue in
            triggerClaudeLimitPulse(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: codex.isLimit) { oldValue, newValue in
            triggerCodexLimitPulse(oldValue: oldValue, newValue: newValue)
        }
    }

    // MARK: - Row model

    private enum UsageHealth {
        case healthy
        case warning
        case low
        case limit
        case unavailable
    }

    private struct UsageRow {
        let label: String
        let headline: String
        let detail: String?
        let health: UsageHealth
        let isLimit: Bool
        let isStale: Bool
    }

    @ViewBuilder
    private func usageBlock(_ row: UsageRow, pulse: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: statusSymbol(for: row.health))
                    .font(.system(size: 14, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(color(for: row.health))
                    .frame(width: 18, alignment: .center)
                Text(row.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(theme.secondaryText)
                if row.isStale && !row.isLimit {
                    Text("stale")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(theme.mutedText)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(theme.overlay.opacity(0.22)))
                }
            }
            Text(row.headline)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(row.isLimit ? theme.errorColor : theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail = row.detail {
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, pulse ? 4 : 0)
        .padding(.vertical, pulse ? 2 : 0)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(row.isLimit && pulse ? theme.errorColor.opacity(0.14) : Color.clear)
        )
        .scaleEffect(pulse ? 1.03 : 1.0, anchor: .center)
        .offset(x: pulse ? 1 : 0)
    }

    // MARK: - Claude

    private var claude: UsageRow {
        _ = tick
        guard let claudeInfo else {
            return UsageRow(label: "Claude", headline: "Unavailable",
                            detail: claudeLastError, health: .unavailable,
                            isLimit: false, isStale: false)
        }
        let stale = isStale(claudeLastRefreshAt) || claudeLastError != nil
        let maxUsed = max(claudeInfo.fiveHourPercent ?? 0, claudeInfo.sevenDayPercent ?? 0)
        let health = healthFromUsed(maxUsed)
        if maxUsed >= 100 {
            let reset = claudeInfo.fiveHourResetAt ?? claudeInfo.sevenDayResetAt
            return UsageRow(label: "Claude", headline: "Limit reached",
                            detail: resetDetail("5h", reset, stale: stale),
                            health: .limit, isLimit: true, isStale: stale)
        }
        let headline = usageLine(label: "5h", usedPercent: claudeInfo.fiveHourPercent)
            ?? usageLine(label: "7d", usedPercent: claudeInfo.sevenDayPercent)
            ?? "Unavailable"
        let weekly = usageLine(label: "7d", usedPercent: claudeInfo.sevenDayPercent)
        // Prefer the 5h reset; fall back to the 7d reset so we still show a
        // remaining time rather than "reset unknown".
        let resetLabel = claudeInfo.fiveHourResetAt != nil ? "5h" : "7d"
        let reset = claudeInfo.fiveHourResetAt ?? claudeInfo.sevenDayResetAt
        let detail = [weekly, resetDetail(resetLabel, reset, stale: stale)]
            .compactMap { $0 }
            .joined(separator: " · ")
        return UsageRow(label: "Claude", headline: headline,
                        detail: detail.isEmpty ? nil : detail,
                        health: health, isLimit: false, isStale: stale)
    }

    // MARK: - Codex

    private var codexLimitReached: Bool {
        guard let codexSnapshot else { return false }
        return codexSnapshot.rateLimitReachedType != nil ||
            codexSnapshot.windows.contains(where: { $0.usedPercentage >= 100 })
    }

    private var codex: UsageRow {
        _ = tick
        guard let codexSnapshot else {
            return UsageRow(label: "Codex", headline: "Unavailable",
                            detail: nil, health: .unavailable,
                            isLimit: false, isStale: false)
        }
        let stale = isStale(codexSnapshot.capturedAt ?? codexLastRefreshAt)
        let resetWindow = codexSnapshot.windows.first(where: { $0.resetsAt != nil })
        let reset = resetWindow?.resetsAt
        let resetLabel = resetWindow?.label ?? "reset"

        // Limit reached takes priority over stale — never show "stale/available"
        // when the rollout says the limit was hit.
        if codexLimitReached {
            return UsageRow(label: "Codex", headline: "Limit reached",
                            detail: resetDetail(resetLabel, reset, stale: stale),
                            health: .limit, isLimit: true, isStale: stale)
        }
        let first = codexSnapshot.windows.first
        let weekly = codexSnapshot.windows.dropFirst().first
        let headline = first.map { usageLine(label: $0.label, usedPercent: Int($0.usedPercentage.rounded())) ?? "Unavailable" }
            ?? "Unavailable"
        let weeklyLine = weekly.flatMap {
            usageLine(label: $0.label, usedPercent: Int($0.usedPercentage.rounded()))
        }
        let minLeft = codexSnapshot.windows.map(\.leftPercentage).min()
        let detail = [weeklyLine, resetDetail(resetLabel, reset, stale: stale)]
            .compactMap { $0 }
            .joined(separator: " · ")
        return UsageRow(label: "Codex", headline: headline,
                        detail: detail.isEmpty ? nil : detail,
                        health: healthFromLeft(minLeft.map { Int($0.rounded()) }),
                        isLimit: false, isStale: stale)
    }

    // MARK: - Helpers

    private func usageLine(label: String, usedPercent: Int?) -> String? {
        guard let usedPercent else { return nil }
        let used = max(0, min(100, usedPercent))
        let left = max(0, 100 - used)
        return "\(label) \(used)% used · \(left)% left"
    }

    private func healthFromUsed(_ used: Int) -> UsageHealth {
        healthFromLeft(max(0, 100 - used))
    }

    private func healthFromLeft(_ left: Int?) -> UsageHealth {
        guard let left else { return .unavailable }
        if left <= 0 { return .limit }
        if left < 15 { return .low }
        if left < 40 { return .warning }
        return .healthy
    }

    private func color(for health: UsageHealth) -> Color {
        switch health {
        case .healthy: return theme.doneColor
        case .warning: return Color(red: 1.0, green: 0.74, blue: 0.26)
        case .low, .limit: return theme.errorColor
        case .unavailable: return theme.mutedText
        }
    }

    /// SF Symbol per usage health, tinted by `color(for:)`. Distinct glyph
    /// shapes (circle → triangle → empty battery) plus the green/yellow/red
    /// tint keep the four states clearly different at small size, while
    /// staying clean and on-brand against the dark notch.
    private func statusSymbol(for health: UsageHealth) -> String {
        switch health {
        case .healthy: return "checkmark.circle.fill"        // plenty left
        case .warning: return "exclamationmark.circle.fill"  // medium
        case .low: return "exclamationmark.triangle.fill"    // low
        case .limit: return "battery.0percent"               // limit reached / empty
        case .unavailable: return "questionmark.circle.fill" // no data
        }
    }

    private func triggerClaudeLimitPulse(oldValue: Bool, newValue: Bool) {
        guard !oldValue, newValue else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) {
            claudeLimitPulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.22)) {
                claudeLimitPulse = false
            }
        }
    }

    private func triggerCodexLimitPulse(oldValue: Bool, newValue: Bool) {
        guard !oldValue, newValue else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) {
            codexLimitPulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.22)) {
                codexLimitPulse = false
            }
        }
    }

    /// Honest reset string. When data is stale we mark the figure as the last
    /// known value rather than presenting it as live.
    private func resetDetail(_ label: String, _ date: Date?, stale: Bool) -> String? {
        guard let date else {
            return stale ? "stale · reset unknown" : "reset unknown"
        }
        let seconds = date.timeIntervalSinceNow
        let remaining: String
        if seconds <= 0 {
            remaining = "due"
        } else if seconds < 3600 {
            remaining = "\(max(1, Int(seconds / 60)))m"
        } else if seconds < 86_400 {
            let h = Int(seconds / 3600)
            let m = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            remaining = m > 0 ? "\(h)h \(m)m" : "\(h)h"
        } else {
            remaining = "\(Int(seconds / 86_400))d"
        }
        if stale {
            return "last known: \(label) resets in \(remaining)"
        }
        return "\(label) resets in \(remaining)"
    }

    private func isStale(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Date().timeIntervalSince(date) > 95
    }
}

private struct PanelMascotView: View {
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared
    @State private var breathe = false
    private var theme: ThemeResolver { menuTheme() }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                mascotGlyph
                    .scaleEffect(breathe ? 1.06 : 0.96)
                    .offset(y: breathe ? -1 : 1)
                Circle()
                    .fill(theme.doneColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: theme.doneColor.opacity(breathe ? 0.75 : 0.35), radius: breathe ? 5 : 2)
            }
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(theme.primaryText.opacity(0.28))
                        .frame(width: 2, height: breathe ? CGFloat(6 + index * 2) : CGFloat(11 - index))
                }
            }
            .frame(width: 30, height: 12)
        }
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.overlay.opacity(0.08))
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    @ViewBuilder
    private var mascotGlyph: some View {
        switch UserDefaults.standard.string(forKey: "islandPet") ?? "cat" {
        case "dog":
            asciiGlyph("u.u")
        case "robot":
            asciiGlyph("[o]")
        case "spark":
            Image(systemName: "sparkles").font(.system(size: 22, weight: .bold))
        case "music":
            Image(systemName: "music.note").font(.system(size: 22, weight: .bold))
        case "dotOnly":
            Circle().fill(theme.doneColor).frame(width: 15, height: 15)
        case "ghost":
            asciiGlyph("boo")
        case "alien":
            asciiGlyph("<o>")
        case "frog":
            asciiGlyph("@_@")
        case "panda":
            asciiGlyph("(o)")
        default:
            asciiGlyph("=^=")
        }
    }

    private func asciiGlyph(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .bold, design: .monospaced))
            .foregroundColor(theme.primaryText)
            .minimumScaleFactor(0.75)
            .frame(width: 44, height: 28)
    }
}

private final class ArtworkImageCache {
    static let shared = NSCache<NSString, NSImage>()
}

private struct AlbumArtworkView: View {
    let info: NowPlayingInfo
    @State private var loadedImage: NSImage?
    @State private var loadedURL: String?
    private var theme: ThemeResolver { menuTheme() }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [theme.overlay.opacity(0.38), theme.overlay.opacity(0.13)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let loadedImage {
                Image(nsImage: loadedImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if info.appName == "YouTube" || info.appName == "YouTube Music" {
                youtubeFallback
            } else {
                Image(systemName: info.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(theme.primaryText.opacity(0.9))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { loadArtworkIfNeeded() }
        .onChange(of: info.artworkURL) { _, _ in loadArtworkIfNeeded() }
    }

    private var youtubeFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
            Circle()
                .fill(Color.red.opacity(0.9))
                .frame(width: 36, height: 36)
            Image(systemName: info.appName == "YouTube Music" ? "music.note" : "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private func loadArtworkIfNeeded() {
        guard let urlString = info.artworkURL,
              loadedURL != urlString,
              let url = URL(string: urlString) else {
            if info.artworkURL == nil {
                loadedImage = nil
                loadedURL = nil
            }
            return
        }

        loadedURL = urlString
        if let cached = ArtworkImageCache.shared.object(forKey: urlString as NSString) {
            loadedImage = cached
            return
        }
        Task.detached {
            guard let data = try? Data(contentsOf: url),
                  let image = NSImage(data: data) else { return }
            await MainActor.run {
                ArtworkImageCache.shared.setObject(image, forKey: urlString as NSString)
                loadedImage = image
            }
        }
    }
}

// MARK: - Version Row

struct VersionRow: View {
    private var theme: ThemeResolver { menuTheme() }
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundColor(theme.secondaryText)
                .frame(width: 16)

            Text(L10n.version)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.secondaryText)

            Spacer()

            Text(appVersion)
                .font(.system(size: 11))
                .foregroundColor(theme.mutedText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Accessibility Permission Row

struct AccessibilityRow: View {
    let isEnabled: Bool

    @State private var isHovered = false
    @State private var refreshTrigger = false
    private var theme: ThemeResolver { menuTheme() }

    private var currentlyEnabled: Bool {
        // Re-check on each render when refreshTrigger changes
        _ = refreshTrigger
        return isEnabled
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised")
                .font(.system(size: 12))
                .foregroundColor(textColor)
                .frame(width: 16)

            Text(L10n.accessibility)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textColor)

            Spacer()

            if isEnabled {
                Circle()
                    .fill(theme.doneColor)
                    .frame(width: 6, height: 6)

                Text(L10n.enabled)
                    .font(.system(size: 11))
                    .foregroundColor(theme.mutedText)
            } else {
                Button(action: openAccessibilitySettings) {
                    Text(L10n.enable)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(theme.inverseText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(theme.doneColor)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? theme.overlay.opacity(0.22) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshTrigger.toggle()
        }
    }

    private var textColor: Color {
        isHovered ? theme.primaryText : theme.secondaryText
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct MenuRow: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    private var theme: ThemeResolver { menuTheme() }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? theme.overlay.opacity(0.22) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var textColor: Color {
        if isDestructive {
            return theme.errorColor
        }
        return isHovered ? theme.primaryText : theme.secondaryText
    }
}

struct MenuToggleRow: View {
    let icon: String
    let label: String
    let isOn: Bool
    let action: () -> Void

    @State private var isHovered = false
    private var theme: ThemeResolver { menuTheme() }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)

                Spacer()

                Circle()
                    .fill(isOn ? theme.doneColor : theme.mutedText.opacity(0.7))
                    .frame(width: 6, height: 6)

                Text(isOn ? L10n.on : L10n.off)
                    .font(.system(size: 11))
                    .foregroundColor(theme.mutedText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? theme.overlay.opacity(0.22) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var textColor: Color {
        isHovered ? theme.primaryText : theme.secondaryText
    }
}

// MARK: - Threshold Picker Row

struct ThresholdPickerRow: View {
    @Binding var threshold: Int
    @State private var isHovered = false
    private var theme: ThemeResolver { menuTheme() }

    private let options: [(value: Int, label: String)] = [
        (70, "70%"),
        (80, "80%"),
        (90, "90%"),
        (0, "Off"),
    ]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 12))
                .foregroundColor(textColor)
                .frame(width: 16)

            Text(L10n.alertThreshold)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textColor)

            Spacer()

            HStack(spacing: 3) {
                ForEach(options, id: \.value) { option in
                    Button {
                        threshold = option.value
                    } label: {
                        Text(option.label)
                            .font(.system(size: 10, weight: threshold == option.value ? .bold : .regular))
                            .foregroundColor(threshold == option.value ? theme.primaryText : theme.mutedText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(threshold == option.value ? theme.overlay.opacity(0.28) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? theme.overlay.opacity(0.22) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }

    private var textColor: Color {
        isHovered ? theme.primaryText : theme.secondaryText
    }
}
