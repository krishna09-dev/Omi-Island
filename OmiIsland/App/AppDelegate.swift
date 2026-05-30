import AppKit
import SwiftUI
import UserNotifications

@MainActor class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var windowManager: WindowManager?
    private var screenObserver: ScreenObserver?

    static var shared: AppDelegate?

    var windowController: NotchWindowController? {
        windowManager?.windowController
    }

    override init() {
        super.init()
        AppDelegate.shared = self
        SoundEffectsService.registerDefaults()
        UserDefaults.standard.register(defaults: [
            "usageWarningThreshold": 90,
            "islandPet": "cat",
            "showMediaVisualizer": true,
            "showSystemLevelIsland": true,
            "showUsageInfo": false,
            "replaceSystemHUD": false
        ])

        // Apply the user's Anthropic API Proxy setting to the process
        // environment as early as possible, BEFORE any plugin is loaded
        // or any subprocess is spawned. All Foundation.Process children
        // (stats' claude CLI, future plugins' shell-outs) will inherit
        // HTTPS_PROXY / HTTP_PROXY / ALL_PROXY without per-plugin opt-in.
        AppSettings.applyProxyToProcessEnvironment()

        // Re-apply whenever any UserDefaults value changes — cheap, idempotent.
        // The notification fires on every defaults write (including unrelated
        // keys), but applyProxyToProcessEnvironment() is a small setenv loop
        // so the redundant calls are harmless.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            AppSettings.applyProxyToProcessEnvironment()
            Task { @MainActor in Self.updateUsageInfoMonitoring() }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.updateUsageInfoMonitoring()
        if !ensureSingleInstance() {
            NSApplication.shared.terminate(nil)
            return
        }

        NSApplication.shared.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self

        windowManager = WindowManager()
        _ = windowManager?.setupNotchWindow()

        screenObserver = ScreenObserver { [weak self] in
            self?.handleScreenChange()
        }

        // No auto-update: the open-source build has no Sparkle/appcast. The
        // About page links to GitHub Releases instead.

        ThemeRegistry.shared.loadAll()
    }

    private static var lastUsageInfoApplied: Bool?

    private static func updateUsageInfoMonitoring() {
        let enabled = UserDefaults.standard.object(forKey: "showUsageInfo") as? Bool ?? false
        guard enabled != lastUsageInfoApplied else { return }
        lastUsageInfoApplied = enabled
        if enabled {
            RateLimitMonitor.shared.start()
            CodexUsageMonitor.shared.start()
        } else {
            RateLimitMonitor.shared.stop()
            CodexUsageMonitor.shared.stop()
        }
    }

    private func handleScreenChange() {
        _ = windowManager?.setupNotchWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        screenObserver = nil
    }

    // Allow notifications to show even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    private func ensureSingleInstance() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.krishna09.omiisland"
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID
        }

        if runningApps.count > 1 {
            if let existingApp = runningApps.first(where: { $0.processIdentifier != getpid() }) {
                existingApp.activate()
            }
            return false
        }

        return true
    }
}
