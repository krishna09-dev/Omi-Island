//
//  TCCPermissionFixer.swift
//  OmiIsland
//
//  An ad-hoc-signed app's CDHash changes on every upgrade. macOS TCC keys
//  authorizations by (Bundle ID + Designated Requirement), so an old grant
//  doesn't apply to the new CDHash. Normally the user would have to remove +
//  re-add the app in System Settings; this one-clicks that flow.
//
//  `tccutil reset` does not require an admin password on Sequoia 15.x
//  (verified locally).
//
//  All heavy work (Process, NSAppleScript) runs on a background queue
//  so the UI doesn't stall ~600ms when the user taps "Repair".
//

import AppKit
import ApplicationServices
import Foundation
import os.log

enum TCCService: String {
    case accessibility = "Accessibility"
    case appleEvents = "AppleEvents"
}

enum TCCPermissionFixer {
    private static let logger = Logger(subsystem: "dev.krishna09.omiisland", category: "TCC")
    private static let bundleID = Bundle.main.bundleIdentifier ?? "dev.krishna09.omiisland"

    /// Reset the given TCC service, then trigger the native permission prompt.
    /// Returns whether tccutil exited 0; the actual grant is asynchronous, so
    /// callers should re-query state shortly after.
    @discardableResult
    static func resetAndRequest(_ service: TCCService) async -> Bool {
        let didReset = await runTccutilReset(service)
        switch service {
        case .accessibility:
            await MainActor.run {
                let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(opts)
            }
        case .appleEvents:
            await triggerAutomationPrompt()
        }
        return didReset
    }

    private static func runTccutilReset(_ service: TCCService) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                process.arguments = ["reset", service.rawValue, bundleID]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    logger.info("tccutil reset \(service.rawValue, privacy: .public) exit=\(process.terminationStatus)")
                    cont.resume(returning: process.terminationStatus == 0)
                } catch {
                    logger.error("tccutil reset failed: \(error.localizedDescription, privacy: .public)")
                    cont.resume(returning: false)
                }
            }
        }
    }

    /// Trigger the Automation permission prompt by sending a side-effect-free
    /// AppleEvent to System Events. NSAppleScript blocks synchronously, so this
    /// runs on a background thread to avoid a ~500ms main-thread stall.
    private static func triggerAutomationPrompt() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let script = NSAppleScript(source: #"tell application "System Events" to count processes"#)
                var err: NSDictionary?
                _ = script?.executeAndReturnError(&err)
                cont.resume()
            }
        }
    }
}
