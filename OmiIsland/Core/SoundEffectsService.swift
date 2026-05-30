//
//  SoundEffectsService.swift
//  OmiIsland
//
//  Small optional Version 1 sound effects. Disabled by default.
//

import AppKit
import Foundation

@MainActor
final class SoundEffectsService {
    static let shared = SoundEffectsService()

    enum UsageKind: String {
        case claude
        case codex
    }

    private enum Keys {
        static let enabled = "soundEffects.enabled"
        static let usageLimitSounds = "soundEffects.usageLimits"
        static let deviceConnectionSounds = "soundEffects.deviceConnections"
    }

    private enum Effect: String {
        case claudeLimit
        case codexLimit
        case headphonesConnected
        case headphonesDisconnected
    }

    private var lastKnownLimitState: [UsageKind: Bool] = [:]
    private var lastPlayedAt: [Effect: Date] = [:]

    private init() {}

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.enabled: false,
            Keys.usageLimitSounds: true,
            Keys.deviceConnectionSounds: true
        ])
    }

    func updateUsageLimit(kind: UsageKind, isLimitReached: Bool) {
        let previous = lastKnownLimitState[kind]
        lastKnownLimitState[kind] = isLimitReached

        guard previous == false, isLimitReached else { return }
        guard UserDefaults.standard.bool(forKey: Keys.enabled),
              UserDefaults.standard.bool(forKey: Keys.usageLimitSounds) else { return }

        let effect: Effect = kind == .claude ? .claudeLimit : .codexLimit
        play(effect, cooldown: 600)
    }

    func playHeadphoneConnection(isConnected: Bool) {
        guard UserDefaults.standard.bool(forKey: Keys.enabled),
              UserDefaults.standard.bool(forKey: Keys.deviceConnectionSounds) else { return }
        play(isConnected ? .headphonesConnected : .headphonesDisconnected, cooldown: 2)
    }

    private func play(_ effect: Effect, cooldown: TimeInterval) {
        let now = Date()
        if let last = lastPlayedAt[effect], now.timeIntervalSince(last) < cooldown {
            return
        }
        lastPlayedAt[effect] = now

        guard let sound = NSSound(named: soundName(for: effect)) ?? NSSound(named: "Pop") else {
            DebugLogger.log("SoundEffects", "system sound unavailable for \(effect.rawValue)")
            return
        }
        sound.volume = volume(for: effect)
        sound.play()
        DebugLogger.log("SoundEffects", "played \(effect.rawValue)")
    }

    private func soundName(for effect: Effect) -> NSSound.Name {
        switch effect {
        case .claudeLimit, .codexLimit:
            return "Submarine"
        case .headphonesConnected:
            return "Glass"
        case .headphonesDisconnected:
            return "Pop"
        }
    }

    private func volume(for effect: Effect) -> Float {
        switch effect {
        case .claudeLimit, .codexLimit:
            return 0.28
        case .headphonesConnected, .headphonesDisconnected:
            return 0.22
        }
    }
}
