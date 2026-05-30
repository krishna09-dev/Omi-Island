//
//  SystemSettingsView.swift
//  OmiIsland
//
//  Floating "System Settings" window — the single home for every
//  configuration surface for the Version 1 app.
//
//  Theme: solid brand lime (#CAFF00) surface with near-black text,
//  matching the Pair phone QR popup.
//

import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

private func settingsTheme() -> ThemeResolver {
    ThemeResolver(theme: NotchCustomizationStore.shared.customization.theme)
}

// MARK: - Notch menu entry row

struct SystemSettingsRow: View {
    @State private var isHovered = false

    var body: some View {
        Button {
            SystemSettingsWindow.shared.show()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .opacity(isHovered ? 1 : 0.6)
                    .frame(width: 16)

                Text(L10n.openSettings)
                    .font(.system(size: 13, weight: .medium))
                    .opacity(isHovered ? 1 : 0.7)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Theme.sidebarActiveFill : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Floating Window

/// Borderless NSWindows return `false` from `canBecomeKey` by default,
/// which blocks SwiftUI TextFields inside them from receiving keyboard
/// focus. Overriding this lets text inputs (e.g. the Anthropic API Proxy
/// field) accept typing. Mirrors the pattern in PairPhoneView.swift.
private final class KeyableSettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Called to close the window (e.g. by Cmd+W via main-menu File→Close).
    /// Borderless windows don't get this for free, and Omi-Island is an
    /// accessory app with no main menu anyway, so we also intercept Cmd+W
    /// in keyDown below. Both paths funnel through here.
    override func performClose(_ sender: Any?) {
        close()
    }

    /// Intercept Cmd+W at the window level. In a normal app Cmd+W routes
    /// through File→Close Window in the main menu, but Omi-Island runs
    /// as an accessory (no main menu), so the shortcut otherwise beeps.
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
final class SystemSettingsWindow {
    static let shared = SystemSettingsWindow()

    private var window: NSWindow?

    func show(initialTab: SettingsTab = .general) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SystemSettingsContentView(
            initialTab: initialTab,
            onClose: { self.close() },
            onHide: { self.hide() }
        )
        let hostingView = NSHostingView(rootView: contentView)
        let w = KeyableSettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = true
        w.isMovableByWindowBackground = true
        w.contentView = hostingView
        w.contentView?.wantsLayer = true
        w.contentView?.layer?.cornerRadius = 16
        w.contentView?.layer?.masksToBounds = true

        if let screen = NSScreen.main {
            let f = screen.frame
            w.setFrameOrigin(NSPoint(x: f.midX - 480, y: f.midY - 360))
        }

        // Keep at normal window level: the settings pane is a regular
        // workspace, not a HUD. Users want it to sit below other apps when
        // they focus elsewhere, not to float on top of everything. The
        // previous `.maximumWindow` level made it shadow the entire OS.
        w.level = .normal
        NSApplication.shared.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.isReleasedWhenClosed = false
        self.window = w
    }

    func close() {
        window?.close()
        window = nil
    }

    /// Hide the window without destroying it — next `show()` re-foregrounds the
    /// same instance (state preserved). Used by the titlebar minimize button;
    /// borderless windows can't `miniaturize` to the Dock, so we `orderOut`.
    func hide() {
        window?.orderOut(nil)
    }
}

// MARK: - Tab enum

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case media
    case about

    var id: String { rawValue }

    static var visibleV1Tabs: [SettingsTab] {
        SettingsTab.allCases
    }

    var icon: String {
        switch self {
        case .general:        return "gearshape.fill"
        case .media:          return "music.note"
        case .about:          return "info.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .general:        return L10n.tabGeneral
        case .media:          return "Media"
        case .about:          return L10n.tabAbout
        }
    }

    /// English subtitle shown next to the Chinese H1 on each detail pane —
    /// mirrors the reference mock's "General preferences" pattern.
    /// When the UI is already English, we skip it to avoid duplicating the title.
    var englishSubtitle: String {
        guard L10n.isChinese else { return "" }
        switch self {
        case .general:        return "General preferences"
        case .media:          return "Media"
        case .about:          return "About"
        }
    }
}

// MARK: - Shared theming constants

/// Graphite two-surface theme: sidebar is a warm charcoal (`#201f27`),
/// detail area is a slightly darker graphite (`#1c1c1e`). Lime survives
/// only as an accent on toggles, active sidebar icons, and focus rings.
/// Palette is lifted from the Anthropic-style reference design — see
/// `~/Desktop/1_files/UI.jsx` and the System Settings HTML mock.
enum Theme {
    private static var resolver: ThemeResolver { settingsTheme() }

    // Sidebar / detail surfaces now derive from the global semantic theme.
    static var sidebarFill: Color { resolver.overlay.opacity(resolver.isRetroArcade ? 0.92 : 0.94) }
    static var sidebarText: Color { resolver.primaryText }
    static var sidebarActiveFill: Color { resolver.primaryText.opacity(resolver.isRetroArcade ? 0.12 : 0.08) }
    static var sidebarHoverFill: Color { resolver.primaryText.opacity(resolver.isRetroArcade ? 0.08 : 0.04) }
    static var sidebarBorder: Color { resolver.border.opacity(resolver.isRetroArcade ? 0.3 : 0.16) }

    static var detailFill: Color { resolver.background }
    static var detailText: Color { resolver.primaryText }
    static var border: Color { resolver.border }

    static var cardFill: Color { resolver.overlay.opacity(resolver.isRetroArcade ? 0.18 : 0.32) }
    static var cardBorder: Color { resolver.border.opacity(resolver.isRetroArcade ? 0.32 : 0.22) }
    static var rowDivider: Color { resolver.border.opacity(resolver.isRetroArcade ? 0.22 : 0.16) }
    static var subtle: Color { resolver.mutedText }
    static var subtleStrong: Color { resolver.secondaryText }

    // Accent now follows semantic working/done emphasis instead of a fixed lime.
    static var accent: Color { resolver.doneColor }
    static var controlFill: Color { resolver.overlay.opacity(resolver.isRetroArcade ? 0.14 : 0.18) }
    static var controlBorder: Color { resolver.border.opacity(resolver.isRetroArcade ? 0.28 : 0.22) }
    static var iconTileFill: Color { resolver.overlay.opacity(resolver.isRetroArcade ? 0.16 : 0.18) }
    static var iconTileBorder: Color { resolver.border.opacity(resolver.isRetroArcade ? 0.28 : 0.22) }
    static var fieldFill: Color { resolver.overlay.opacity(resolver.isRetroArcade ? 0.22 : 0.44) }
    static var fieldBorder: Color { resolver.border.opacity(resolver.isRetroArcade ? 0.34 : 0.28) }
    static var placeholder: Color { resolver.mutedText.opacity(0.9) }
    static var shadow: Color { Color.black.opacity(resolver.isRetroArcade ? 0.22 : 0.5) }
    static var destructiveText: Color { resolver.errorColor }
    static var destructiveFill: Color { resolver.errorColor.opacity(0.1) }
    static var destructiveBorder: Color { resolver.errorColor.opacity(0.18) }
    static var success: Color { resolver.doneColor }
    static var warning: Color { resolver.needsYouColor }
    static var error: Color { resolver.errorColor }
    static var neutralDot: Color { resolver.mutedText.opacity(0.5) }
    static var backgroundInk: Color { resolver.inverseText }
    static var titlebarGlyph: Color { resolver.inverseText.opacity(0.6) }
    static var knobShadow: Color { Color.black.opacity(resolver.isRetroArcade ? 0.18 : 0.35) }
    static var toggleActiveBorder: Color { resolver.inverseText.opacity(0.25) }

    // Real macOS traffic-light colors.
    static let tlRed = Color(red: 1.00, green: 0.373, blue: 0.341)
    static let tlYellow = Color(red: 0.996, green: 0.737, blue: 0.180)
    static let tlGreen = Color(red: 0.157, green: 0.784, blue: 0.251)
    static let tlStroke = Color.black.opacity(0.25)
}

// MARK: - Content root

private struct SystemSettingsContentView: View {
    let initialTab: SettingsTab
    let onClose: () -> Void
    let onHide: () -> Void
    @State private var tab: SettingsTab
    @State private var isHoveringTitleBar = false
    /// Observe the theme store so swapping themes re-renders the whole
    /// settings tree. Without this subscription the body only references
    /// `Theme.*` (a static enum that reads from the store each call),
    /// so SwiftUI has no dependency edge and skips invalidation — users
    /// had to click a sidebar tab to force a re-render.
    @ObservedObject private var notchStore = NotchCustomizationStore.shared

    init(
        initialTab: SettingsTab = .general,
        onClose: @escaping () -> Void,
        onHide: @escaping () -> Void
    ) {
        self.initialTab = initialTab
        self.onClose = onClose
        self.onHide = onHide
        self._tab = State(initialValue: initialTab)
    }

    var body: some View {
        // IMPORTANT: clipShape BEFORE overlay so the rounded corners actually
        // cut the sidebar's opaque lime fill and the detail's dark fill,
        // then the overlay border is stroked on the clipped edge on top.
        // Putting shadow OUTSIDE the clip so it isn't cut off.
        VStack(spacing: 0) {
            titleBar
            HStack(spacing: 0) {
                sidebar
                detail
            }
        }
        .frame(width: 960, height: 720)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
        )
        .shadow(color: Theme.shadow, radius: 30, y: 12)
        .onHover { isHoveringTitleBar = $0 }
    }

    // MARK: Title bar

    /// Real macOS-style chrome: red/yellow/green dots on the left, centered
    /// title. Borderless windows have no OS chrome, so we synthesize it.
    private var titleBar: some View {
        ZStack {
            HStack(spacing: 8) {
                trafficLight(fill: Theme.tlRed, glyph: "xmark", action: onClose)
                trafficLight(fill: Theme.tlYellow, glyph: "minus", action: onHide)
                // Green is decorative (no fullscreen for a utility window).
                Circle()
                    .fill(Theme.tlGreen)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Theme.tlStroke, lineWidth: 0.5))
                Spacer()
            }
            .padding(.horizontal, 14)

            Text(L10n.systemSettings)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.detailText.opacity(0.85))
        }
        .frame(height: 38)
        .background(Theme.sidebarFill)
        .overlay(
            Rectangle()
                .fill(Theme.border)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private func trafficLight(fill: Color, glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(fill)
                .frame(width: 12, height: 12)
                .overlay(
                    Image(systemName: glyph)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(Theme.titlebarGlyph.opacity(isHoveringTitleBar ? 1 : 0))
                )
                .overlay(Circle().strokeBorder(Theme.tlStroke, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 10)
            ForEach(SettingsTab.visibleV1Tabs) { t in
                tabRow(t)
            }

            Spacer()

            Rectangle()
                .fill(Theme.rowDivider)
                .frame(height: 0.5)
                .padding(.horizontal, 10)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.subtle)
                        .frame(width: 18)
                    Text("Quit")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.subtleStrong)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 196)
        .background(Theme.sidebarFill)
        .overlay(
            Rectangle()
                .fill(Theme.sidebarBorder)
                .frame(width: 0.5),
            alignment: .trailing
        )
    }

    @ViewBuilder
    private func tabRow(_ t: SettingsTab) -> some View {
        let isSelected = tab == t
        SidebarPillRow(
            icon: t.icon,
            label: t.label,
            isSelected: isSelected,
            action: {
                withAnimation(.easeOut(duration: 0.15)) { tab = t }
            }
        )
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Large H1 + English subtitle, mirroring the reference mock.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(tab.label)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(Theme.detailText)
                        .tracking(-0.4)
                    Text(tab.englishSubtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.subtle)
                }
                .padding(.top, 22)
                .padding(.bottom, 4)

                switch tab {
                case .general:        GeneralTab()
                case .media:          MediaTab()
                case .about:          AboutTab()
                }
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.detailFill)
    }
}

// MARK: - Reusable tab-level primitives

/// Sidebar pill: hover = subtle fill, active = slightly stronger fill + lime
/// icon. Hoisted out of the content view so we can hold per-row hover state.
private struct SidebarPillRow: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? Theme.accent : Theme.subtle)
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Theme.detailText : Theme.subtleStrong)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? Theme.sidebarActiveFill
                          : (isHovered ? Theme.sidebarHoverFill : Color.clear))
            )
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Card container. Reference design uses `rgba(255,255,255,0.03)` fill +
/// `rgba(255,255,255,0.08)` border at radius 12. The optional uppercase
/// "section label" now renders *above* the card, not inside it.
struct SettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundColor(Theme.subtle)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
            }
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
                    )
            )
        }
    }
}

/// iOS-style pill toggle matching the reference mock: neon-lime gradient
/// when on, inset charcoal when off, with a radial-highlight knob that
/// animates between ends.
private struct IOSToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? AnyShapeStyle(LinearGradient(
                        colors: [Theme.accent, Theme.accent.opacity(0.87)],
                        startPoint: .top, endPoint: .bottom
                    )) : AnyShapeStyle(Theme.controlFill))
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isOn ? Theme.toggleActiveBorder : Theme.controlBorder,
                                lineWidth: 0.5
                            )
                    )
                    .shadow(
                        color: isOn ? Theme.accent.opacity(0.3) : .clear,
                        radius: 6, y: 2
                    )

                Circle()
                    .fill(RadialGradient(
                        colors: [Color.white, Color(white: 0.95), Color(white: 0.88)],
                        center: UnitPoint(x: 0.4, y: 0.35),
                        startRadius: 0, endRadius: 14
                    ))
                    .frame(width: 19, height: 19)
                    .shadow(color: Theme.knobShadow, radius: 1.5, y: 1)
                    .padding(2)
            }
            .frame(width: 38, height: 23)
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

/// Toggle cell — icon tile + label + iOS slider. Adopts the reference
/// "setting row" pattern (icon square, main label, optional sublabel).
private struct TabToggle: View {
    let icon: String
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Theme.iconTileFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Theme.iconTileBorder, lineWidth: 0.5)
                    )
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isOn ? Theme.accent : Theme.subtleStrong)
            }
            .frame(width: 28, height: 28)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.detailText.opacity(0.92))

            Spacer(minLength: 0)

            IOSToggle(isOn: isOn, action: action)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Reference-style list-of-rows primitives

/// Section label above a card: uppercase, tracked, muted.
/// Usage: `SectionLabel(L10n.someSection)` then `SettingsListCard { ... }`.
private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundColor(Theme.subtle)
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }
}

/// Card sized for a vertical list of SettingRow. Uses tight vertical padding
/// so rows' own 12pt vertical padding drives the row height — matches the
/// reference mock's `padding: '4px 16px'` row card.
private struct SettingsListCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
                )
        )
    }
}

/// A single list row: optional icon tile, label, optional sublabel, control.
/// `isLast` suppresses the bottom divider so the final row sits flush with the
/// card's bottom padding.
private struct SettingRow<Control: View>: View {
    let icon: String?
    let label: String
    let sublabel: String?
    let isLast: Bool
    @ViewBuilder let control: () -> Control

    init(
        icon: String? = nil,
        label: String,
        sublabel: String? = nil,
        isLast: Bool = false,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.icon = icon
        self.label = label
        self.sublabel = sublabel
        self.isLast = isLast
        self.control = control
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.iconTileFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Theme.iconTileBorder, lineWidth: 0.5)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.subtleStrong)
                }
                .frame(width: 28, height: 28)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.detailText.opacity(0.92))
                if let sublabel, !sublabel.isEmpty {
                    Text(sublabel)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.subtle)
                }
            }

            Spacer(minLength: 8)

            control()
        }
        .padding(.vertical, 12)
        .overlay(
            Rectangle()
                .fill(Theme.rowDivider)
                .frame(height: 0.5)
                .opacity(isLast ? 0 : 1),
            alignment: .bottom
        )
    }
}

/// Colored dot + title + body, used in the proxy explanation card.
/// `variant` controls dot color + glyph:
///   - .pos  → accent-filled, "✓"
///   - .neg  → muted outline, "✕"
///   - .hint → muted outline, "i"
private struct InfoRow: View {
    enum Variant { case pos, neg, hint }
    let variant: Variant
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            dot
            (Text(title + "：")
                .foregroundColor(Theme.detailText.opacity(0.9))
                .font(.system(size: 12, weight: .medium))
             + Text(message)
                .foregroundColor(Theme.subtleStrong)
                .font(.system(size: 12)))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var dot: some View {
        let isPos = variant == .pos
        ZStack {
            Circle()
                .fill(isPos ? Theme.accent : Theme.controlFill)
                .overlay(
                    Circle().strokeBorder(
                        isPos ? Color.clear : Theme.controlBorder,
                        lineWidth: 0.5
                    )
                )
            Text(glyph)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(isPos ? Theme.backgroundInk : Theme.subtleStrong)
        }
        .frame(width: 16, height: 16)
        .padding(.top, 1)
    }

    private var glyph: String {
        switch variant {
        case .pos: return "✓"
        case .neg: return "✕"
        case .hint: return "i"
        }
    }
}

// MARK: - General tab

private struct GeneralTab: View {
    @AppStorage("islandPet") private var islandPet: String = "cat"
    @AppStorage("showUsageInfo") private var showUsageInfo: Bool = false
    @AppStorage("soundEffects.enabled") private var soundEffectsEnabled: Bool = false
    @AppStorage("soundEffects.usageLimits") private var usageLimitSounds: Bool = true
    @AppStorage("soundEffects.deviceConnections") private var deviceConnectionSounds: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLabel("General")
            SettingsListCard {
                SettingRow(
                    icon: "pawprint.fill",
                    label: "Island Pet",
                    sublabel: "Choose the compact island identity.",
                    isLast: true
                ) {
                    Picker("", selection: $islandPet) {
                        Text("Cat").tag("cat")
                        Text("Dog").tag("dog")
                        Text("Robot").tag("robot")
                        Text("Ghost").tag("ghost")
                        Text("Alien").tag("alien")
                        Text("Frog").tag("frog")
                        Text("Panda").tag("panda")
                        Text("Spark").tag("spark")
                        Text("Dot").tag("dotOnly")
                        Text("Music").tag("music")
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }

            SectionLabel("Usage Info")
            SettingsListCard {
                SettingRow(
                    icon: "gauge.with.dots.needle.33percent",
                    label: "Show Usage Info",
                    sublabel: "Show a tiny Claude/Codex availability status only when cached real usage is available. No sessions or approvals.",
                    isLast: true
                ) {
                    IOSToggle(isOn: showUsageInfo) {
                        showUsageInfo.toggle()
                    }
                }
            }

            SectionLabel("Sound Effects")
            SettingsListCard {
                SettingRow(
                    icon: "speaker.wave.2.fill",
                    label: "Sound Effects",
                    sublabel: "Enable short, soft sounds for usage limits and device connection events.",
                    isLast: false
                ) {
                    IOSToggle(isOn: soundEffectsEnabled) {
                        soundEffectsEnabled.toggle()
                    }
                }

                SettingRow(
                    icon: "gauge.with.dots.needle.67percent",
                    label: "Usage Limit Sounds",
                    sublabel: "Play once when Claude or Codex changes into limit reached. Includes a 10-minute cooldown.",
                    isLast: false
                ) {
                    IOSToggle(isOn: usageLimitSounds) {
                        usageLimitSounds.toggle()
                    }
                    .opacity(soundEffectsEnabled ? 1 : 0.45)
                }

                SettingRow(
                    icon: "headphones",
                    label: "Device Connection Sounds",
                    sublabel: "Play once with the 3-second headphone connect/disconnect animation.",
                    isLast: true
                ) {
                    IOSToggle(isOn: deviceConnectionSounds) {
                        deviceConnectionSounds.toggle()
                    }
                    .opacity(soundEffectsEnabled ? 1 : 0.45)
                }
            }
        }
    }
}

/// Lists user-blacklisted project cwds with per-row unblacklist + clear-all.
private struct HiddenProjectsCard: View {
    @ObservedObject private var hidden: HiddenProjectsStore = .shared

    var body: some View {
        SettingsListCard {
            if hidden.allBlacklisted.isEmpty {
                HStack {
                    Text("No hidden projects. Right-click or hover a group in the list to hide it.")
                        .notchFont(11)
                        .notchSecondaryForeground()
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            } else {
                ForEach(Array(hidden.allBlacklisted.enumerated()), id: \.element) { idx, cwd in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(fileURLWithPath: cwd).lastPathComponent)
                                .notchFont(13, weight: .medium)
                            Text(cwd)
                                .notchFont(11)
                                .notchSecondaryForeground()
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Unhide") {
                            hidden.unblacklist(cwd: cwd)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tint)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    if idx < hidden.allBlacklisted.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
                Divider().opacity(0.4)
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        hidden.clearAll()
                    } label: {
                        Text("Clear All")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }
        }
    }
}

/// Proxy input + three info rows (applies / does not apply / leave empty).
/// Replaces the old single-paragraph description with the structured
/// ✓ / ✕ / i rows from the reference mock.
private struct AnthropicProxyRow: View {
    @AppStorage("anthropicProxyURL") private var proxyURL: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // SwiftUI's TextField.prompt repeatedly ignores `foregroundColor`
            // on macOS and falls back to its own secondary-label gray, which
            // reads almost-black on our dark input fill. Roll our own: a
            // manually positioned Text, only visible when empty, in a solid
            // light gray we control.
            ZStack(alignment: .leading) {
                if proxyURL.isEmpty {
                    Text(L10n.anthropicApiProxyPlaceholder)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.placeholder)
                        .padding(.horizontal, 12)
                        .allowsHitTesting(false)
                }
                TextField("", text: $proxyURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.detailText.opacity(0.95))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.fieldBorder, lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 9) {
                InfoRow(
                    variant: .pos,
                    title: "Applies to",
                    message: "Notch usage bar (api.anthropic.com) and every subprocess spawned by Omi-Island. HTTPS_PROXY / HTTP_PROXY / ALL_PROXY are set once at launch and inherited."
                )
                InfoRow(
                    variant: .neg,
                    title: "Does not apply to",
                    message: "In-app sync (always direct) and third-party plugin URLSession calls (use system proxy)."
                )
                InfoRow(
                    variant: .hint,
                    title: "Leave empty to disable",
                    message: "Clear this field when you don't need a proxy."
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
                )
        )
    }
}

/// Settings-tab accessibility row: icon + label + sublabel + status pill
/// (green dot + "Enabled" when granted, "Repair" button when not).
private struct SettingsAccessibilityRow: View {
    let isLast: Bool
    @State private var isGranted = AXIsProcessTrusted()
    @State private var isRepairing = false

    var body: some View {
        SettingRow(
            icon: "hand.raised.fill",
            label: L10n.accessibility,
            sublabel: "Required for keyboard shortcuts and window control",
            isLast: isLast
        ) {
            if isGranted {
                HStack(spacing: 6) {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    Text(L10n.enabled)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.subtle)
                }
            } else {
                HStack(spacing: 6) {
                    // Primary action: one-click repair (for TCC lapses from ad-hoc CDHash changes)
                    Button {
                        repair()
                    } label: {
                        Text(isRepairing ? L10n.repairing : L10n.repairPermission)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.backgroundInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRepairing)

                    // Fallback: open System Settings (legacy behavior)
                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.openAccessibilitySettings)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isGranted = AXIsProcessTrusted()
        }
    }

    private func repair() {
        isRepairing = true
        Task {
            await TCCPermissionFixer.resetAndRequest(.accessibility)
            // Authorization is async; refresh state after a short wait
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                isGranted = AXIsProcessTrusted()
                isRepairing = false
            }
        }
    }
}

// MARK: - Media tab

private struct MediaTab: View {
    @AppStorage("showMediaVisualizer") private var showMediaVisualizer: Bool = true
    @AppStorage("showSystemLevelIsland") private var showSystemLevelIsland: Bool = true
    @AppStorage("replaceSystemHUD") private var replaceSystemHUD: Bool = false
    @ObservedObject private var media = MediaSystemController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "Media") {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Theme.iconTileFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(Theme.iconTileBorder, lineWidth: 0.5)
                                )
                            Image(systemName: "waveform")
                                .font(.system(size: 12))
                                .foregroundColor(showMediaVisualizer ? Theme.accent : Theme.subtleStrong)
                        }
                        .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Show Media Visualizer")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.detailText.opacity(0.92))
                            Text("Animate the right side of the island when media or browser audio is playing.")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(Theme.subtle)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)

                        IOSToggle(isOn: showMediaVisualizer) {
                            showMediaVisualizer.toggle()
                        }
                    }
                    .padding(.vertical, 2)

                    Divider().overlay(Theme.rowDivider)
                        .padding(.vertical, 10)

                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Theme.iconTileFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(Theme.iconTileBorder, lineWidth: 0.5)
                                )
                            Image(systemName: "slider.horizontal.below.sun.max")
                                .font(.system(size: 12))
                                .foregroundColor(showSystemLevelIsland ? Theme.accent : Theme.subtleStrong)
                        }
                        .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Show Volume/Brightness Island")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.detailText.opacity(0.92))
                            Text("Omi-Island shows its own volume/brightness island. macOS may also show the system HUD.")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(Theme.subtle)
                                .lineLimit(3)
                        }

                        Spacer(minLength: 0)

                        IOSToggle(isOn: showSystemLevelIsland) {
                            showSystemLevelIsland.toggle()
                        }
                    }
                    .padding(.vertical, 2)

                    Divider().overlay(Theme.rowDivider)
                        .padding(.vertical, 10)

                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Theme.iconTileFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(Theme.iconTileBorder, lineWidth: 0.5)
                                )
                            Image(systemName: "rectangle.on.rectangle.slash")
                                .font(.system(size: 12))
                                .foregroundColor(replaceSystemHUD ? Theme.accent : Theme.subtleStrong)
                        }
                        .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Replace macOS Volume/Brightness HUD")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.detailText.opacity(0.92))
                            Text("Attempts to hide the macOS HUD and use Omi-Island instead. Volume/mute can usually be replaced. Brightness depends on macOS and display support.")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(Theme.subtle)
                                .lineLimit(3)
                        }

                        Spacer(minLength: 0)

                        IOSToggle(isOn: replaceSystemHUD) {
                            replaceSystemHUD.toggle()
                            if replaceSystemHUD {
                                media.requestHUDReplacementPermissions()
                            }
                        }
                    }
                    .padding(.vertical, 2)

                    Divider().overlay(Theme.rowDivider)
                        .padding(.vertical, 10)

                    VStack(alignment: .leading, spacing: 5) {
                        statusLine(
                            label: "Accessibility",
                            value: media.accessibilityTrusted ? "Granted" : "Missing",
                            isActive: media.accessibilityTrusted
                        )
                        statusLine(
                            label: "Event tap",
                            value: media.hudEventTapActive ? "Active" : "Inactive",
                            isActive: media.hudEventTapActive
                        )
                        statusLine(
                            label: "Volume/mute",
                            value: media.volumeReplacementActive ? "Active" : "Inactive",
                            isActive: replaceSystemHUD && media.volumeReplacementActive
                        )
                        statusLine(
                            label: "Brightness",
                            value: media.brightnessReplacementActive ? "Active" : "Best effort",
                            isActive: replaceSystemHUD && media.brightnessReplacementActive
                        )
                        statusLine(
                            label: "Status",
                            value: media.hudReplacementStatus,
                            isActive: replaceSystemHUD && media.hudEventTapActive
                        )

                        Button {
                            media.refreshHUDStatus()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Refresh status")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(Theme.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 3)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func statusLine(label: String, value: String, isActive: Bool) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isActive ? Theme.accent : Theme.subtle.opacity(0.55))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.detailText.opacity(0.84))
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Theme.subtle)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - About tab

private struct AboutTab: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0-test"
    }

    private let githubURL = "https://github.com/krishna09-dev/Omi-Island"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Omi-Island")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Theme.detailText.opacity(0.95))
                    Text("A free open-source macOS notch companion app.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.detailText.opacity(0.75))
                    Text("Music, usage status, headphones, sounds, and system islands in your Mac notch.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.detailText.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsCard {
                HStack {
                    Text(L10n.version)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.detailText.opacity(0.9))
                    Spacer()
                    Text(version)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.detailText.opacity(0.6))
                }
            }

            SettingsCard {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            NSWorkspace.shared.open(URL(string: githubURL)!)
                        } label: {
                            aboutLinkButton(icon: "star.fill", label: L10n.starOnGitHub)
                        }
                        .buttonStyle(.plain)

                        Button {
                            NSWorkspace.shared.open(URL(string: "\(githubURL)/issues")!)
                        } label: {
                            aboutLinkButton(icon: "bubble.left", label: L10n.feedback)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        NSWorkspace.shared.open(URL(string: "\(githubURL)/releases")!)
                    } label: {
                        aboutLinkButton(icon: "arrow.down.circle", label: L10n.checkForUpdates)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 11))
                    Text(L10n.quitApp)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Theme.destructiveText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.destructiveFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.destructiveBorder, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private func aboutLinkButton(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(label)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(Theme.backgroundInk)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.accent)
        )
    }
}

