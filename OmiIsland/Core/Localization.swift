//
//  Localization.swift
//  OmiIsland
//
//  Omi-Island ships English-only. `tr` simply returns its argument; it exists
//  so call sites read as localized lookups and a future i18n layer can slot in.
//

import Foundation

enum L10n {
    /// English-only build.
    static var isChinese: Bool { false }

    static func tr(_ en: String) -> String { en }

    // MARK: - Rate-limit notification (RateLimitMonitor)

    static var rateLimitNotificationTitle: String { tr("Claude Code Usage Warning") }
    static func rateLimitNotificationBody(window: String, percent: Int) -> String {
        tr("\(window) window usage has reached \(percent)%.")
    }
    static func rateLimitNotificationBodyWithReset(window: String, percent: Int, resetHint: String) -> String {
        tr("\(window) window usage has reached \(percent)%. Resets in \(resetHint).")
    }

    // MARK: - Short duration formatting ("resets in X" hints)

    static var durationLessThanOneMinute: String { tr("<1min") }
    static func durationMinutes(_ m: Int) -> String { tr("\(m)min") }
    static func durationHoursMinutes(_ h: Int, _ m: Int) -> String { tr("\(h)h\(m)m") }
    static func durationHours(_ h: Int) -> String { tr("\(h)h") }
    static func durationDays(_ d: Int) -> String { tr("\(d)d") }

    // MARK: - Settings & menu

    static var alertThreshold: String { tr("Alert") }
    static var anthropicApiProxyPlaceholder: String { "http://127.0.0.1:7890" }
    static var accessibility: String { tr("Accessibility") }
    static var version: String { tr("Version") }
    static var checkForUpdates: String { tr("Check for Updates") }
    static var on: String { tr("On") }
    static var off: String { tr("Off") }
    static var enable: String { tr("Enable") }
    static var enabled: String { tr("On") }
    static var systemSettings: String { tr("System Settings") }
    static var openSettings: String { tr("Settings") }
    static var tabGeneral: String { tr("General") }
    static var tabAbout: String { tr("About") }
    static var openAccessibilitySettings: String { tr("Open Accessibility settings") }
    static var repairPermission: String { tr("Repair") }
    static var repairing: String { tr("Repairing…") }
    static var feedback: String { tr("Feedback") }
    static var starOnGitHub: String { tr("Star on GitHub") }
    static var quitApp: String { tr("Quit Omi-Island") }

    // MARK: - Sound / audio device

    static var notificationSound: String { tr("Notification Sound") }
    static var screen: String { tr("Screen") }
    static var automatic: String { tr("Automatic") }
    static var auto_: String { tr("Auto") }
    static var builtIn: String { tr("Built-in") }
    static var main_: String { tr("Main") }
    static var builtInOrMain: String { tr("Built-in or Main") }

    /// Display names for sound events (used by SoundManager).
    static func soundEventName(_ event: String) -> String {
        switch event {
        case "session_start": return "Session Start"
        case "processing_begins": return "Processing"
        case "needs_approval": return "Needs Approval"
        case "approval_granted": return "Approval Granted"
        case "approval_denied": return "Approval Denied"
        case "session_complete": return "Session Complete"
        case "error": return "Error"
        case "compacting": return "Compacting"
        case "rate_limit_warning": return "Rate Limit Warning"
        default: return event
        }
    }

    // MARK: - Notch live-edit overlay

    static var notchEditSave: String { tr("Save") }
    static var notchEditCancel: String { tr("Cancel") }
    static var notchEditNotchPreset: String { tr("Notch Preset") }
    static var notchEditDragMode: String { tr("Drag Mode") }
    static var notchEditReset: String { tr("Reset") }
    static var notchEditPresetDisabledTooltip: String { tr("Your device doesn't have a hardware notch") }
}
