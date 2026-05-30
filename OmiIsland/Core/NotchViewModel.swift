//
//  NotchViewModel.swift
//  OmiIsland
//
//  State management for the dynamic island
//

import AppKit
import Combine
import SwiftUI

enum NotchStatus: Equatable {
    case closed
    case opened
    case popping
}

enum NotchOpenReason {
    case click
    case hover
    case notification
    case boot
    case unknown
}

enum NotchContentType: Equatable {
    case instances
    case menu

    var id: String {
        switch self {
        case .instances: return "instances"
        case .menu: return "menu"
        }
    }
}

@MainActor
class NotchViewModel: ObservableObject {
    // MARK: - Published State

    @Published var status: NotchStatus = .closed
    @Published var openReason: NotchOpenReason = .unknown
    @Published var contentType: NotchContentType = .instances
    @Published var isHovering: Bool = false

    /// Session counts for dynamic panel sizing
    @Published var sessionCount: Int = 0
    @Published var activeSessionCount: Int = 0
    @Published var isInstancesExpanded: Bool = false

    // MARK: - Dependencies

    private let screenSelector = ScreenSelector.shared
    private let soundSelector = SoundSelector.shared

    // MARK: - Geometry

    let geometry: NotchGeometry
    let spacing: CGFloat = 12
    let hasPhysicalNotch: Bool
    let screenID: String

    /// Current expansion width from NotchView (synced for hit testing)
    @Published var currentExpansionWidth: CGFloat = 240

    var deviceNotchRect: CGRect { geometry.deviceNotchRect }
    var screenRect: CGRect { geometry.screenRect }
    var windowHeight: CGFloat { geometry.windowHeight }

    /// Height contributed by inline report content inside the notch menu.
    /// Now always `.hidden` since stats moved to an external plugin.
    @Published var dailyReportState: DailyReportState = .hidden

    /// Discrete height buckets for the daily report card. Hard-coded
    /// instead of measured via GeometryReader / PreferenceKey to avoid
    /// feedback loops between content size and window size.
    enum DailyReportState: Equatable {
        case hidden       // Card is not shown (no activity or not loaded)
        case loading      // First-launch scan, shows the neon cat
        case collapsed    // Hero line + context line only
        case expandedDay  // Hero + day details (pills + breakdowns)
        case expandedWeek // Hero + week details (sparkline + highlights + ...)

        var height: CGFloat {
            switch self {
            case .hidden:       return 0
            case .loading:      return 80
            case .collapsed:    return 118
            case .expandedDay:  return 230
            case .expandedWeek: return 400
            }
        }
    }

    /// Dynamic opened size for the Version 1 hover panel.
    var openedSize: CGSize {
        switch contentType {
        case .menu:
            // Compact Dynamic-Island feel: keep the hover panel short so it
            // hugs the music row + pet/usage strip with no empty bottom space.
            let width = min(screenRect.width * 0.48, 480)
            let height: CGFloat = 150
            return CGSize(
                width: width,
                height: min(height, screenRect.height * 0.7)
            )
        case .instances:
            return CGSize(width: min(screenRect.width * 0.48, 480), height: 150)
        }
    }

    // MARK: - Animation

    var animation: Animation {
        .easeOut(duration: 0.25)
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private let events = EventMonitors.shared
    private var hoverTimer: DispatchWorkItem?

    // MARK: - Initialization

    init(deviceNotchRect: CGRect, screenRect: CGRect, windowHeight: CGFloat, hasPhysicalNotch: Bool, screenID: String) {
        self.screenID = screenID
        self.geometry = NotchGeometry(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenRect,
            windowHeight: windowHeight
        )
        self.hasPhysicalNotch = hasPhysicalNotch
        setupEventHandlers()
        observeSelectors()
    }

    private func observeSelectors() {
        screenSelector.$isPickerExpanded
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        soundSelector.$isPickerExpanded
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Event Handling

    private func setupEventHandlers() {
        events.mouseLocation
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] location in
                self?.handleMouseMove(location)
            }
            .store(in: &cancellables)

        events.mouseDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleMouseDown()
            }
            .store(in: &cancellables)
    }

    /// Pull the user's saved horizontal offset, clamped against the
    /// current screen + visible notch width so a value persisted on
    /// a wider external display doesn't push hit-testing off-screen
    /// when the smaller built-in is the active one. Mirrors the same
    /// clamp NotchView applies for `.offset(x:)` rendering.
    private var currentHorizontalOffset: CGFloat {
        let geo = NotchCustomizationStore.shared.customization.geometry(for: screenID)
        let runtime: CGFloat = status == .opened ? openedSize.width : (geometry.deviceNotchRect.width + currentExpansionWidth)
        return NotchHardwareDetector.clampedHorizontalOffset(
            storedOffset: geo.horizontalOffset,
            runtimeWidth: runtime,
            screenWidth: geometry.screenRect.width
        )
    }

    private func handleMouseMove(_ location: CGPoint) {
        // While the user is in live edit mode, the notch is locked
        // closed and may not auto-open from hover. The live edit
        // overlay panel handles its own clicks; the notch itself
        // should be inert so opening the chat panel doesn't blow
        // away the alignment of the dashed editing frame.
        if NotchCustomizationStore.shared.isEditing {
            isHovering = false
            hoverTimer?.cancel()
            hoverTimer = nil
            return
        }
        let offset = currentHorizontalOffset
        let inNotch = geometry.isPointInNotch(
            location,
            expansionWidth: currentExpansionWidth,
            horizontalOffset: offset
        )
        let inOpened = status == .opened && geometry.isPointInOpenedPanel(
            location,
            size: openedSize,
            horizontalOffset: offset
        )

        let newHovering = inNotch || inOpened

        // Only update if changed to prevent unnecessary re-renders
        guard newHovering != isHovering else { return }

        isHovering = newHovering

        // Cancel any pending hover timer
        hoverTimer?.cancel()
        hoverTimer = nil

        if isHovering {
            if status == .closed || status == .popping {
                let delay = min(NotchCustomizationStore.shared.customization.hoverSpeed.delay, 0.18)
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self, self.isHovering else { return }
                    self.contentType = .menu
                    self.notchOpen(reason: .hover)
                }
                hoverTimer = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
        } else if status == .opened, openReason == .hover {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, !self.isHovering, self.openReason == .hover else { return }
                self.notchClose()
            }
            hoverTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: workItem)
        }
    }

    private func handleMouseDown() {
        // Same lock-out as mouseMove — clicks on the notch (or anywhere
        // else) should not open the panel while live edit is active.
        // The live edit panel has its own click routing.
        if NotchCustomizationStore.shared.isEditing {
            return
        }
        let location = NSEvent.mouseLocation

        let offset = currentHorizontalOffset
        switch status {
        case .opened:
            // Close if click is outside the panel content area
            if geometry.isPointOutsidePanel(location, size: openedSize, horizontalOffset: offset) {
                notchClose()
                repostClickAt(location)
            }
        case .closed, .popping:
            if geometry.isPointInNotch(location, expansionWidth: currentExpansionWidth, horizontalOffset: offset) {
                contentType = .menu
                notchOpen(reason: .click)
            }
        }
    }

    /// Re-posts a mouse click at the given screen location so it reaches windows behind us
    private func repostClickAt(_ location: CGPoint) {
        // Small delay to let the window's ignoresMouseEvents update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Convert to CGEvent coordinate system (screen coordinates with Y from top-left)
            guard let screen = NSScreen.main else { return }
            let screenHeight = screen.frame.height
            let cgPoint = CGPoint(x: location.x, y: screenHeight - location.y)

            // Save cursor position — CGEvent.post(tap: .cghidEventTap)
            // physically warps the cursor to mouseCursorPosition.
            let savedCursorPos = CGEvent(source: nil)?.location

            // Create and post mouse down event
            if let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseDown.post(tap: .cghidEventTap)
            }

            // Create and post mouse up event
            if let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseUp.post(tap: .cghidEventTap)
            }

            // Restore cursor position to prevent unintended cursor jump
            if let savedCursorPos {
                CGWarpMouseCursorPosition(savedCursorPos)
                CGAssociateMouseAndMouseCursorPosition(1)
            }
        }
    }

    // MARK: - Actions

    /// Whether the current open was triggered by user action (should steal focus)
    var shouldActivateOnOpen: Bool = false

    func notchOpen(reason: NotchOpenReason = .unknown) {
        openReason = reason
        // Only steal focus when user explicitly clicked
        shouldActivateOnOpen = (reason == .click)
        status = .opened
    }

    func notchClose() {
        status = .closed
        contentType = .instances
    }

    func notchPop() {
        guard status == .closed else { return }
        status = .popping
    }

    func notchUnpop() {
        guard status == .popping else { return }
        status = .closed
    }

    func toggleMenu() {
        contentType = contentType == .menu ? .instances : .menu
    }

    /// Perform boot animation: expand briefly then collapse
    func performBootAnimation() {
        notchOpen(reason: .boot)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.openReason == .boot else { return }
            self.notchClose()
        }
    }
}
