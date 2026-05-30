//
//  RateLimitMonitor.swift
//  OmiIsland
//
//  Monitors Claude Code rate limit status by parsing JSONL or querying CLI.
//

import Combine
import Foundation
import SwiftUI
import UserNotifications

/// Parsed rate limit display info
struct RateLimitDisplayInfo: Equatable {
    let fiveHourPercent: Int?
    let sevenDayPercent: Int?
    let fiveHourResetAt: Date?
    let sevenDayResetAt: Date?
    let planName: String?

    var displayText: String {
        var parts: [String] = []

        // 5h: just percentage + reset time, no label
        if let pct = fiveHourPercent {
            let resetStr = formatRemaining(fiveHourResetAt)
            parts.append("\(pct)%\(resetStr.isEmpty ? "" : " \(resetStr)")")
        }

        // 7d: show when >= 5%
        if let pct = sevenDayPercent, pct >= 5 {
            let resetStr = formatRemaining(sevenDayResetAt)
            parts.append("\(pct)%\(resetStr.isEmpty ? "" : " \(resetStr)")")
        }

        return parts.isEmpty ? "--" : parts.joined(separator: "|\(parts.count > 1 ? "" : "")")
    }

    var color: Color {
        let maxPct = max(fiveHourPercent ?? 0, sevenDayPercent ?? 0)
        if maxPct >= 90 {
            return Color(red: 0.94, green: 0.27, blue: 0.27)  // red
        }
        if maxPct >= 70 {
            return Color(red: 1.0, green: 0.6, blue: 0.2)  // orange
        }
        return Color(red: 0.29, green: 0.87, blue: 0.5)  // green
    }

    private func formatRemaining(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 { return "" }
        if remaining < 3600 {
            return "\(Int(remaining / 60))m"
        } else if remaining < 86400 {
            let h = Int(remaining / 3600)
            let m = Int(remaining.truncatingRemainder(dividingBy: 3600) / 60)
            return m > 0 ? "\(h)h\(m)m" : "\(h)h"
        }
        return "\(Int(remaining / 86400))d"
    }
}

@MainActor
class RateLimitMonitor: ObservableObject {
    static let shared = RateLimitMonitor()

    @Published private(set) var rateLimitInfo: RateLimitDisplayInfo?
    @Published private(set) var isLoading = false
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var lastRefreshError: String?

    /// Tracks whether we already fired a notification for the current high-usage period.
    /// Resets when usage drops below the threshold.
    private var hasNotifiedFiveHour = false
    private var hasNotifiedSevenDay = false
    private var usageWarningThreshold: Int {
        UserDefaults.standard.integer(forKey: "usageWarningThreshold")
    }

    private var refreshTimer: Timer?

    /// Whether the poll loop is currently running. Used to make start()
    /// idempotent so the timer doesn't get recreated on every toggle.
    private(set) var isRunning = false

    /// When the API returns 429 we stop hitting it until this time. Prevents
    /// the rate-limit endpoint itself from being rate-limited into a retry
    /// storm. Cleared on the next successful refresh.
    private var backoffUntil: Date?
    private let backoffDuration: TimeInterval = 300  // 5 minutes
    /// Minimum spacing between non-forced refreshes. The 60s timer is always
    /// well above this; it only throttles the extra refreshes triggered when
    /// the panel re-opens or start() is called again while already running.
    private let minRefreshInterval: TimeInterval = 30

    /// Private init — does NOT start polling. Call `start()` explicitly
    /// when the Usage Bar is enabled. Previously init would unconditionally
    /// fire a request and kick off a 300s timer, which meant users who
    /// disabled the Usage Bar in settings were still silently hitting
    /// api.anthropic.com every 5 minutes (see issue #50).
    private init() {}

    /// Begin polling the Anthropic usage API on a 1-minute interval and
    /// fire an immediate refresh. Idempotent — repeated calls are no-ops.
    func start() {
        // Already polling — true no-op. Repeated start() calls (panel re-open,
        // multiple views' onAppear, defaults churn) must NOT each force an
        // immediate API hit; refreshes happen only on the 60s timer below.
        if isRunning { return }
        isRunning = true
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    /// Stop polling and clear cached state. Called when the user toggles
    /// the Usage Bar off. Clearing `rateLimitInfo` ensures stale data
    /// doesn't flash back if the bar is re-enabled before the next poll.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        hasNotifiedFiveHour = false
        hasNotifiedSevenDay = false
        backoffUntil = nil
    }

    private enum FetchResult {
        case success(RateLimitDisplayInfo)
        case rateLimited
        case unavailable
    }

    /// `force` bypasses the soft min-interval throttle (not the 429 backoff).
    /// The 60s timer and initial start call with the default; explicit user
    /// actions never need to force because data this fresh is fine.
    func refresh(force: Bool = false) async {
        guard !isLoading else { return }

        // Respect 429 backoff window — never poke the API while backing off.
        if let until = backoffUntil, Date() < until { return }

        if !force, let last = lastRefreshAt,
           Date().timeIntervalSince(last) < minRefreshInterval {
            return
        }

        isLoading = true
        defer { isLoading = false }

        switch await fetchFromAPI() {
        case .success(let info):
            // Cache last-known reset times: if this refresh omitted a reset
            // timestamp but we previously had one, keep showing the old one
            // instead of dropping to "reset unknown" (issue: reset disappears).
            let merged = RateLimitDisplayInfo(
                fiveHourPercent: info.fiveHourPercent,
                sevenDayPercent: info.sevenDayPercent,
                fiveHourResetAt: info.fiveHourResetAt ?? rateLimitInfo?.fiveHourResetAt,
                sevenDayResetAt: info.sevenDayResetAt ?? rateLimitInfo?.sevenDayResetAt,
                planName: info.planName ?? rateLimitInfo?.planName
            )
            rateLimitInfo = merged
            lastRefreshAt = Date()
            lastRefreshError = nil
            backoffUntil = nil
            SoundEffectsService.shared.updateUsageLimit(
                kind: .claude,
                isLimitReached: max(merged.fiveHourPercent ?? 0, merged.sevenDayPercent ?? 0) >= 100
            )
            DebugLogger.log("RateLimit", "refresh ok")
        case .rateLimited:
            let until = Date().addingTimeInterval(backoffDuration)
            backoffUntil = until
            lastRefreshAt = Date()
            lastRefreshError = "Usage temporarily unavailable (using last known)"
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm:ss"
            DebugLogger.log("RateLimit", "refresh failed: 429, backing off until \(fmt.string(from: until))")
        case .unavailable:
            lastRefreshError = "Claude usage unavailable"
            DebugLogger.log("RateLimit", "refresh failed: unavailable; keeping lastKnown=\(rateLimitInfo?.displayText ?? "nil")")
        }
    }

    /// Send a macOS notification + play sound when usage first crosses the threshold.
    /// Resets when usage drops back below the threshold so it can fire again next time.
    private func checkAndNotify(_ info: RateLimitDisplayInfo) async {
        // Threshold disabled (Off)
        guard usageWarningThreshold > 0 else {
            hasNotifiedFiveHour = false
            hasNotifiedSevenDay = false
            return
        }

        // 5-hour window
        if let pct = info.fiveHourPercent {
            if pct >= usageWarningThreshold && !hasNotifiedFiveHour {
                let resetStr = info.fiveHourResetAt.map { formatNotificationReset($0) } ?? ""
                let success = await sendUsageNotification(window: "5h", percent: pct, resetHint: resetStr)
                if success { hasNotifiedFiveHour = true }
            } else if pct < usageWarningThreshold {
                hasNotifiedFiveHour = false
            }
        } else {
            hasNotifiedFiveHour = false
        }

        // 7-day window
        if let pct = info.sevenDayPercent {
            if pct >= usageWarningThreshold && !hasNotifiedSevenDay {
                let resetStr = info.sevenDayResetAt.map { formatNotificationReset($0) } ?? ""
                let success = await sendUsageNotification(window: "7d", percent: pct, resetHint: resetStr)
                if success { hasNotifiedSevenDay = true }
            } else if pct < usageWarningThreshold {
                hasNotifiedSevenDay = false
            }
        } else {
            hasNotifiedSevenDay = false
        }
    }

    private func sendUsageNotification(window: String, percent: Int, resetHint: String) async -> Bool {
        // Play warning sound via SoundManager (respects globalMute and per-event toggle)
        SoundManager.shared.play(.rateLimitWarning)

        // Send macOS notification (no system sound — SoundManager handles audio)
        let content = UNMutableNotificationContent()
        content.title = L10n.rateLimitNotificationTitle
        let body: String
        if resetHint.isEmpty {
            body = L10n.rateLimitNotificationBody(window: window, percent: percent)
        } else {
            body = L10n.rateLimitNotificationBodyWithReset(
                window: window, percent: percent, resetHint: resetHint
            )
        }
        content.body = body
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "omiisland.ratelimit.\(window)",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            DebugLogger.log("RateLimit", "Notification error: \(error.localizedDescription)")
            return false
        }
    }

    private func formatNotificationReset(_ date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return "" }
        if remaining < 60 {
            return L10n.durationLessThanOneMinute
        }
        if remaining < 3600 {
            let m = Int(ceil(remaining / 60))
            return L10n.durationMinutes(m)
        } else if remaining < 86400 {
            let h = Int(remaining / 3600)
            let m = Int(ceil(remaining.truncatingRemainder(dividingBy: 3600) / 60))
            return m > 0
                ? L10n.durationHoursMinutes(h, m)
                : L10n.durationHours(h)
        }
        return L10n.durationDays(Int(remaining / 86400))
    }

    /// Read OAuth token from macOS Keychain and call Anthropic usage API
    private func fetchFromAPI() async -> FetchResult {
        // Read token from Keychain
        guard let token = readOAuthToken() else {
            DebugLogger.log("RateLimit", "No OAuth token found")
            return .unavailable
        }

        // Call https://api.anthropic.com/api/oauth/usage
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return .unavailable }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 10

        do {
            let session = AppSettings.makeAnthropicSession()
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 429 { return .rateLimited }
            guard status == 200 else { return .unavailable }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unavailable }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let fiveHour = json["five_hour"] as? [String: Any]
            let sevenDay = json["seven_day"] as? [String: Any]

            let fiveHourPct = (fiveHour?["utilization"] as? Double).map { Int($0) }
            let sevenDayPct = (sevenDay?["utilization"] as? Double).map { Int($0) }
            let fiveHourReset = (fiveHour?["resets_at"] as? String).flatMap { formatter.date(from: $0) }
            let sevenDayReset = (sevenDay?["resets_at"] as? String).flatMap { formatter.date(from: $0) }

            return .success(RateLimitDisplayInfo(
                fiveHourPercent: fiveHourPct,
                sevenDayPercent: sevenDayPct,
                fiveHourResetAt: fiveHourReset,
                sevenDayResetAt: sevenDayReset,
                planName: nil
            ))
        } catch {
            DebugLogger.log("RateLimit", "Fetch error: \(error.localizedDescription)")
            return .unavailable
        }
    }

    /// Read OAuth access token from macOS Keychain
    private func readOAuthToken() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let json = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
                  let oauth = json["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String else { return nil }
            return token
        } catch {
            return nil
        }
    }
}
