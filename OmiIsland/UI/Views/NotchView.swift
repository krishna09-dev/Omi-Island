//
//  NotchView.swift
//  OmiIsland
//
//  The main dynamic island SwiftUI view with accurate notch shape
//

import AppKit
import Combine
import CoreGraphics
import SwiftUI

// Corner radius constants
private let cornerRadiusInsets = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6), bottom: CGFloat(14))
)

struct NotchView: View {
    @ObservedObject var viewModel: NotchViewModel
    @StateObject private var activityCoordinator = NotchActivityCoordinator.shared
    @State private var isVisible: Bool = true
    @State private var isHovering: Bool = false
    @State private var isBouncing: Bool = false
    @State private var autoCollapseTimer: DispatchWorkItem? = nil

    @AppStorage("smartSuppression") private var smartSuppression: Bool = true
    @AppStorage("autoCollapseOnMouseLeave") private var autoCollapseOnMouseLeave: Bool = true
    @AppStorage("compactCollapsed") private var compactCollapsed: Bool = false
    @AppStorage("showMediaVisualizer") private var showMediaVisualizer: Bool = true
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared
    @ObservedObject private var media = MediaSystemController.shared
    private var theme: ThemeResolver { ThemeResolver(theme: notchStore.customization.theme) }

    @Namespace private var activityNamespace

    /// Whether any Claude session is currently processing or compacting
    private var isAnyProcessing: Bool {
        false
    }

    /// Whether any Claude session has a pending permission request
    private var hasPendingPermission: Bool {
        false
    }

    /// Whether any Claude session is waiting for user input (done/ready state) within the display window
    private var hasWaitingForInput: Bool {
        false
    }

    /// Whether any Claude session is waiting for a question answer
    private var hasWaitingForQuestion: Bool {
        false
    }

    /// Whether there are any active (non-ended) sessions
    private var hasActiveSessions: Bool {
        false
    }

    private var hasMediaStatus: Bool {
        showMediaVisualizer && media.mediaVisible && media.nowPlaying.hasMetadata && media.nowPlaying.isPlaying
    }

    private var hasConnectedOutputDevice: Bool {
        false
    }

    private var hasSystemActivity: Bool {
        activityCoordinator.expandingActivity.show && activityCoordinator.expandingActivity.type != .claude
    }

    /// The most urgent animation state across all active sessions.
    /// Priority: needsYou > error > working > thinking > done > idle
    private var mostUrgentAnimationState: AnimationState {
        .idle
    }

    /// Priority ordering for animation states (higher = more urgent)
    private func animationPriority(_ state: AnimationState) -> Int {
        switch state {
        case .idle: return 0
        case .done: return 1
        case .thinking: return 2
        case .working: return 3
        case .error: return 4
        case .needsYou: return 5
        }
    }

    /// The highest-priority session: urgent states first, then most recently active
    private var highestPrioritySession: SessionState? {
        nil
    }

    /// Split text into project name and status for separate styling
    private var activityTextParts: (project: String, status: String)? {
        nil
    }

    // MARK: - Sizing

    private var closedNotchSize: CGSize {
        // Always honor the user's notchHeight — even on hardware-
        // notched MacBooks. The software Omi-Island can be taller or
        // shorter than the physical camera cutout; previously this
        // branch pinned to viewModel.deviceNotchRect.height, which
        // was captured at launch and never updated, so the live edit
        // height buttons appeared to do nothing on MacBook.
        let geo = notchStore.customization.geometry(for: viewModel.screenID)
        let height = NotchHardwareDetector.clampedHeight(geo.notchHeight)
        return CGSize(
            width: viewModel.deviceNotchRect.width,
            height: height
        )
    }

    /// Extra width for expanding activities (like Dynamic Island).
    ///
    /// Reads from the per-screen `ScreenGeometry.maxWidth` so the live edit
    /// "resize" arrow buttons visibly grow / shrink the notch as the
    /// user drives the slider. The user's `maxWidth` is the total
    /// closed-with-content width — subtracting the hardware notch
    /// width yields the wing expansion.
    ///
    /// Compact mode caps at 100pt regardless of the user's max so the
    /// dot+icon+count layout never overflows the visible notch ring.
    /// Full mode honors the user's max directly. Idle state (no
    /// active sessions) is always 0 — the notch shrinks tight around
    /// the hardware shape.
    private var expansionWidth: CGFloat {
        let geo = notchStore.customization.geometry(for: viewModel.screenID)
        let userMax = geo.maxWidth
        let userExpansion = max(0, userMax - closedNotchSize.width)
        let needsExpansion = notchStore.isEditing
            || hasSystemActivity
            || hasMediaStatus
            || hasActiveSessions
            || isProcessing
            || hasPendingPermission
            || hasWaitingForQuestion
            || hasWaitingForInput

        if !needsExpansion {
            let idleTarget = min(max(closedNotchSize.width + 118, 330), 365)
            return max(userExpansion, idleTarget - closedNotchSize.width)
        }

        if hasSystemActivity {
            let target = min(max(viewModel.screenRect.width * 0.32, 380), 480)
            return max(userExpansion, target - closedNotchSize.width)
        }

        if hasMediaStatus {
            let target = min(max(viewModel.screenRect.width * 0.34, 380), 460)
            return max(userExpansion, target - closedNotchSize.width)
        }

        if compactCollapsed {
            return min(100, userExpansion)
        }
        return userExpansion
    }

    private var notchSize: CGSize {
        switch viewModel.status {
        case .closed, .popping:
            return closedNotchSize
        case .opened:
            return viewModel.openedSize
        }
    }

    /// Width of the closed content (notch + any expansion)
    private var closedContentWidth: CGFloat {
        closedNotchSize.width + expansionWidth
    }

    // MARK: - Corner Radii

    private var topCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.bottom
            : cornerRadiusInsets.closed.bottom
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
    }

    // Animation springs
    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    /// While in Live Edit, the closed notch is pinned to the exact
    /// configured width/height so the ◀▶/▲▼ arrows produce visible,
    /// WYSIWYG feedback even when there is no active session content
    /// to fill the expansion wings. Outside edit mode, the notch keeps
    /// its content-hugging behavior — no always-on black bar. (Issue #30)
    private var forceClosedPreviewSize: Bool {
        notchStore.isEditing && viewModel.status != .opened
    }

    /// User-customized horizontal offset of the notch, clamped at
    /// render time so an off-screen stored value on a smaller
    /// secondary display never bleeds past the edge. Spec 5.5.
    private var clampedHorizontalOffset: CGFloat {
        let geo = notchStore.customization.geometry(for: viewModel.screenID)
        return NotchHardwareDetector.clampedHorizontalOffset(
            storedOffset: geo.horizontalOffset,
            runtimeWidth: viewModel.status == .opened ? notchSize.width : closedContentWidth,
            screenWidth: viewModel.screenRect.width
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Outer container does NOT receive hits - only the notch content does
            VStack(spacing: 0) {
                notchLayout
                    .notchPalette()
                    .frame(
                        minWidth: forceClosedPreviewSize ? closedContentWidth : nil,
                        maxWidth: viewModel.status == .opened ? notchSize.width : closedContentWidth,
                        minHeight: forceClosedPreviewSize ? closedNotchSize.height : nil,
                        alignment: .top
                    )
                    .padding(
                        .horizontal,
                        viewModel.status == .opened
                            ? cornerRadiusInsets.opened.top
                            : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], viewModel.status == .opened ? 12 : 0)
                    .background(NotchPalette.for(notchStore.customization.theme).bg)
                    .animation(.easeInOut(duration: 0.3), value: notchStore.customization.theme)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(NotchPalette.for(notchStore.customization.theme).bg)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                            .animation(.easeInOut(duration: 0.3), value: notchStore.customization.theme)
                    }
                    .shadow(color: notchShadowColor, radius: notchShadowRadius)
                    .frame(
                        minWidth: forceClosedPreviewSize ? closedContentWidth : nil,
                        maxWidth: viewModel.status == .opened ? notchSize.width : closedContentWidth,
                        minHeight: forceClosedPreviewSize ? closedNotchSize.height : nil,
                        maxHeight: viewModel.status == .opened
                            ? notchSize.height
                            : (forceClosedPreviewSize ? closedNotchSize.height : nil),
                        alignment: .top
                    )
                    .animation(viewModel.status == .opened ? openAnimation : closeAnimation, value: viewModel.status)
                    .animation(openAnimation, value: notchSize) // Animate container size changes between content types
                    .animation(.smooth, value: activityCoordinator.expandingActivity)
                    .animation(.smooth, value: hasActiveSessions)
                    .animation(.spring(response: 0.34, dampingFraction: 0.84), value: hasMediaStatus)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isBouncing)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                            isHovering = hovering
                        }

                        // Auto-collapse on mouse leave (Task 2)
                        if hovering {
                            // Mouse re-entered: cancel pending auto-collapse
                            autoCollapseTimer?.cancel()
                            autoCollapseTimer = nil
                            if viewModel.status == .closed || viewModel.status == .popping {
                                let workItem = DispatchWorkItem {
                                    guard isHovering,
                                          !NotchCustomizationStore.shared.isEditing,
                                          viewModel.status != .opened else { return }
                                    viewModel.contentType = .menu
                                    viewModel.notchOpen(reason: .hover)
                                }
                                autoCollapseTimer = workItem
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: workItem)
                            }
                        } else if autoCollapseOnMouseLeave && viewModel.status == .opened {
                            let workItem = DispatchWorkItem { [self] in
                                if !isHovering && viewModel.status == .opened && viewModel.openReason == .hover {
                                    viewModel.notchClose()
                                }
                            }
                            autoCollapseTimer = workItem
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: workItem)
                        }
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            if viewModel.status != .opened {
                                viewModel.contentType = .menu
                                viewModel.notchOpen(reason: .click)
                            }
                        }
                    )
                    .offset(x: clampedHorizontalOffset)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                media.start()
            }
            // Always show notch (standby state shows even with no sessions)
            isVisible = true
        }
        .onChange(of: viewModel.status) { oldStatus, newStatus in
            handleStatusChange(from: oldStatus, to: newStatus)
        }
        .onChange(of: expansionWidth) { _, newWidth in
            viewModel.currentExpansionWidth = newWidth
        }
        .task {
            // Sync the initial expansion width into the view model on
            // first appearance so the hit-test region matches the
            // visible notch from the very first frame.
            viewModel.currentExpansionWidth = expansionWidth
        }
    }

    // MARK: - Notch Layout

    private var isProcessing: Bool {
        false
    }

    /// Whether to show the expanded closed state (any active sessions)
    private var showClosedActivity: Bool {
        false
    }

    @ViewBuilder
    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row - hidden when opened, full when closed
            headerRow
                .frame(height: viewModel.status == .opened ? 4 : max(24, closedNotchSize.height))

            // Main content only when opened
            if viewModel.status == .opened {
                contentView
                    .frame(width: notchSize.width - 24, alignment: .top) // Fixed width to prevent reflow
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.smooth(duration: 0.35)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))
                        )
                    )
            }
        }
    }

    // MARK: - Header Row (persists across states)

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 0) {
            if viewModel.status == .opened {
                // Opened state: invisible spacer only — no icon
                Color.clear
                    .matchedGeometryEffect(id: "crab", in: activityNamespace, isSource: viewModel.status == .opened)
                    .frame(width: 1, height: 1)
            } else if hasSystemActivity {
                SystemActivityContent(
                    activity: activityCoordinator.expandingActivity,
                    notchHeight: closedNotchSize.height,
                    notchSafeWidth: closedNotchSize.width
                )
            } else if hasMediaStatus {
                MediaCompactIslandView(
                    nowPlaying: media.nowPlaying,
                    notchHeight: closedNotchSize.height,
                    notchSafeWidth: closedNotchSize.width,
                    showsConnectedDevice: hasConnectedOutputDevice
                )
            } else {
                standbyContent
            }
        }
        .frame(height: closedNotchSize.height)
        .clipped()
    }

    // MARK: - Shadow helpers

    private var notchShadowColor: Color {
        (viewModel.status == .opened || isHovering) ? .black.opacity(0.7) : .clear
    }

    private var notchShadowRadius: CGFloat { 6 }

    // MARK: - Standby Content

    /// Mirrors the left wing of CollapsedNotchContent (compact style):
    /// idle dot + buddy icon, left-aligned, full active-state width.
    private var standbyContent: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle()
                    .fill(theme.doneColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: theme.doneColor.opacity(0.5), radius: 4)
                if notchStore.customization.showBuddy {
                    IslandPetGlyphView(state: .idle, size: 22, scale: 0.36)
                }
            }
            .padding(.leading, 8)
            .frame(width: 82, alignment: .leading)

            Spacer(minLength: max(130, closedNotchSize.width * 0.62))

            if hasConnectedOutputDevice {
                ConnectedDeviceIndicatorView()
                    .padding(.trailing, 10)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Opened Header Content

    @ViewBuilder
    private var openedHeaderContent: some View {
        HStack(spacing: 12) {
            Spacer()

            // Menu toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.toggleMenu()
                }
            } label: {
                Image(systemName: viewModel.contentType == .menu ? "xmark" : "line.3.horizontal")
                    .notchFont(11, weight: .medium)
                    .notchSecondaryForeground()
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content View (Opened State)

    @ViewBuilder
    private var contentView: some View {
        NotchMenuView(viewModel: viewModel)
        .frame(width: notchSize.width - 24) // Fixed width to prevent text reflow
        // Removed .id() - was causing view recreation and performance issues
    }

    // MARK: - Event Handlers

    private func handleProcessingChange() {
        activityCoordinator.hideActivity()
        isVisible = true
    }

    private func handleStatusChange(from oldStatus: NotchStatus, to newStatus: NotchStatus) {
        switch newStatus {
        case .opened, .popping:
            isVisible = true
        case .closed:
            // Always remain visible — standby content shows even with no sessions
            break
        }
    }
}

private struct SystemActivityContent: View {
    let activity: ExpandingActivity
    let notchHeight: CGFloat
    let notchSafeWidth: CGFloat
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared
    @State private var pulse = false
    private var theme: ThemeResolver { ThemeResolver(theme: notchStore.customization.theme) }

    private var icon: String {
        switch activity.type {
        case .volume: return activity.label == "Mute" ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        // Left side is always the plain headphone glyph — the connect/disconnect
        // state lives only on the right side (issue: no second headphone icon).
        case .audioDevice: return "headphones"
        case .claude, .none: return "circle.fill"
        }
    }

    private var progress: CGFloat {
        max(0, min(1, activity.value))
    }

    var body: some View {
        GeometryReader { geo in
            let safeGap = min(max(notchSafeWidth + 18, 150), 190)
            let sideWidth = max(96, (geo.size.width - safeGap - 28) / 2)

            HStack(spacing: 0) {
                leftContent
                    .frame(width: sideWidth, alignment: .leading)

                Spacer(minLength: safeGap)
                    .frame(width: safeGap)

                rightContent
                    .frame(width: sideWidth, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .frame(width: geo.size.width, height: max(24, notchHeight), alignment: .center)
        }
        .frame(height: max(24, notchHeight))
        .transition(.asymmetric(
            insertion: .scale(scale: 0.88, anchor: .center).combined(with: .opacity),
            removal: .opacity
        ))
        .onAppear {
            pulse = false
            withAnimation(.spring(response: 0.28, dampingFraction: 0.46).repeatCount(2, autoreverses: true)) {
                pulse = true
            }
        }
        .onChange(of: activity.value) { _, _ in
            pulse = false
            withAnimation(.spring(response: 0.24, dampingFraction: 0.45).repeatCount(2, autoreverses: true)) {
                pulse = true
            }
        }
    }

    /// Left side: just the icon. For volume/brightness this is the speaker/sun
    /// glyph (no "Volume"/"Brightness" word — keeps it notch-safe and compact).
    /// For headphone events this is the plain headphone glyph only.
    private var leftContent: some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(theme.primaryText)
            .frame(width: 26, height: 26)
            .background(Circle().fill(theme.overlay.opacity(0.22)))
            .scaleEffect(pulse ? 1.04 : 0.98)
    }

    private var rightContent: some View {
        Group {
            if activity.type == .volume || activity.type == .brightness {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.overlay.opacity(0.25))
                        Capsule()
                            .fill(theme.primaryText.opacity(activity.label == "Mute" ? 0.45 : 0.86))
                            .frame(width: activity.label == "Mute" ? 8 : max(8, geo.size.width * progress))
                        Circle()
                            .fill(theme.primaryText.opacity(0.92))
                            .frame(width: 5, height: 5)
                            .opacity(activity.label == "Mute" ? 0.18 : (pulse ? 0.7 : 0.22))
                            .offset(x: activity.label == "Mute" ? 0 : max(0, min(geo.size.width - 5, progress * geo.size.width - 2.5)))
                    }
                    .animation(.spring(response: 0.24, dampingFraction: 0.82), value: progress)
                }
                .frame(width: 124, height: 3)
            } else if activity.type == .audioDevice {
                // State icon only — green check for connected, red slash for
                // disconnected. No second headphone glyph here.
                AudioDeviceStateIcon(
                    isConnected: activity.value > 0,
                    pulse: pulse,
                    batteryLabel: activity.value > 0 && !activity.label.isEmpty ? activity.label : nil
                )
            } else if !activity.label.isEmpty {
                Text(activity.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.secondaryText)
                    .lineLimit(1)
            }
        }
    }
}

/// Right-side connect/disconnect indicator for headphone events.
/// Green check (connected) or red slash (disconnected), with a soft pulse.
private struct AudioDeviceStateIcon: View {
    let isConnected: Bool
    let pulse: Bool
    let batteryLabel: String?
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared
    private var theme: ThemeResolver { ThemeResolver(theme: notchStore.customization.theme) }

    var body: some View {
        let tint = isConnected ? theme.doneColor : Color.red.opacity(0.95)
        HStack(spacing: 6) {
            Image(systemName: isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(tint)
                .scaleEffect(pulse ? 1.12 : 0.94)
                .shadow(color: tint.opacity(pulse ? 0.7 : 0.3), radius: pulse ? 6 : 2)

            if let batteryLabel {
                Text(batteryLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.secondaryText)
                    .lineLimit(1)
            }
        }
    }
}

private struct IslandPetGlyphView: View {
    let state: AnimationState
    let size: CGFloat
    let scale: CGFloat
    @AppStorage("islandPet") private var islandPet: String = "cat"
    private var theme: ThemeResolver { ThemeResolver(theme: NotchCustomizationStore.shared.customization.theme) }

    var body: some View {
        Group {
            switch islandPet {
            case "dog":
                asciiGlyph("u.u", size: size)
            case "robot":
                asciiGlyph("[o]", size: size)
            case "ghost":
                asciiGlyph("boo", size: size)
            case "alien":
                asciiGlyph("<o>", size: size)
            case "frog":
                asciiGlyph("@_@", size: size)
            case "panda":
                asciiGlyph("(o)", size: size)
            case "spark":
                Image(systemName: "sparkles")
                    .font(.system(size: max(10, size * 0.68), weight: .bold))
                    .foregroundColor(theme.primaryText)
                    .frame(width: size, height: size)
            case "music":
                Image(systemName: "music.note")
                    .font(.system(size: max(10, size * 0.72), weight: .bold))
                    .foregroundColor(theme.primaryText)
                    .frame(width: size, height: size)
            case "dotOnly":
                EmptyView()
            default:
                PixelCharacterView(state: state)
                    .scaleEffect(scale)
                    .frame(width: size, height: size)
            }
        }
    }

    private func asciiGlyph(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: max(9, size * 0.42), weight: .bold, design: .monospaced))
            .foregroundColor(theme.primaryText)
            .minimumScaleFactor(0.7)
            .frame(width: size + 8, height: size)
    }
}

private struct MediaCompactIslandView: View {
    let nowPlaying: NowPlayingInfo
    let notchHeight: CGFloat
    let notchSafeWidth: CGFloat
    let showsConnectedDevice: Bool
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared
    @State private var pulse = false
    private var theme: ThemeResolver { ThemeResolver(theme: notchStore.customization.theme) }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle()
                    .fill(theme.doneColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: theme.doneColor.opacity(0.55), radius: 4)
                    .opacity(pulse ? 1 : 0.62)

                if notchStore.customization.showBuddy {
                    IslandPetGlyphView(state: .idle, size: 22, scale: 0.36)
                }
            }
            .padding(.leading, 8)
            .frame(width: 82, alignment: .leading)

            Spacer(minLength: max(130, notchSafeWidth * 0.62))

            if nowPlaying.isPlaying {
                MusicVisualizerView(isAnimating: true)
                    .frame(width: 54, height: 16)
                    .padding(.trailing, 10)
            }
        }
        .frame(height: max(24, notchHeight))
        .transition(.asymmetric(
            insertion: .scale(scale: 0.88, anchor: .center).combined(with: .opacity),
            removal: .opacity
        ))
        .onAppear {
            pulse = false
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onChange(of: nowPlaying.isPlaying) { _, _ in
            pulse = false
            withAnimation(.spring(response: 0.26, dampingFraction: 0.55).repeatCount(2, autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct ConnectedDeviceIndicatorView: View {
    var isConnected: Bool = true
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared
    @State private var pulse = false
    private var theme: ThemeResolver { ThemeResolver(theme: notchStore.customization.theme) }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isConnected ? "headphones" : "headphones.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.primaryText.opacity(0.92))
            Circle()
                .fill(isConnected ? theme.doneColor : Color.orange.opacity(0.95))
                .frame(width: 7, height: 7)
                .scaleEffect(pulse ? 1.16 : 0.9)
                .shadow(
                    color: (isConnected ? theme.doneColor : Color.orange).opacity(pulse ? 0.7 : 0.35),
                    radius: pulse ? 5 : 2
                )
            MusicVisualizerView(isAnimating: true)
                .frame(width: 22, height: 11)
                .opacity(0.7)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct MusicVisualizerView: View {
    let isAnimating: Bool
    @State private var phase = false
    private let heights: [CGFloat] = [0.34, 0.72, 0.5, 0.86, 0.42]

    var body: some View {
        HStack(alignment: .center, spacing: 4.5) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(isAnimating ? 0.82 : 0.22))
                    .frame(width: 2, height: 14 * barScale(for: index))
                    .animation(
                        isAnimating
                            ? .easeInOut(duration: 0.68 + Double(index) * 0.06).repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.18),
                        value: phase
                    )
            }
        }
        .onAppear {
            guard isAnimating else { return }
            phase = true
        }
        .onChange(of: isAnimating) { _, playing in
            phase = playing
        }
    }

    private func barScale(for index: Int) -> CGFloat {
        guard isAnimating else { return 0.28 }
        return phase ? heights[index] : max(0.28, 1.1 - heights[index])
    }
}

