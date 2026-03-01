// DS4TrackpadManager.swift — Gesture engine that turns the DS4 touchpad into a macOS trackpad
// Posts CGEvent synthetic input for cursor movement, clicks, scroll, and pinch-to-zoom.
// Receives raw input at ~250 Hz via DS4TransportManager.onRawInputState for low-latency tracking.

import Foundation
import CoreGraphics
import ApplicationServices
import Observation
import DS4Protocol
import DS4Transport

@MainActor
@Observable
final class DS4TrackpadManager {

    // MARK: - Observable State (for UI)

    /// Whether trackpad emulation is active.
    private(set) var isEnabled: Bool = false

    /// Whether the app has Accessibility permission (required for CGEvent posting).
    private(set) var hasAccessibilityPermission: Bool = false

    /// Current detected gesture for status display.
    private(set) var currentGesture: GestureKind = .idle

    /// Number of fingers currently touching the pad.
    private(set) var activeTouchCount: Int = 0

    // MARK: - Settings

    var cursorSensitivity: Double = 1.0
    var scrollSensitivity: Double = 1.0
    var pinchSensitivity: Double = 1.0
    var naturalScrolling: Bool = true

    // MARK: - Types

    enum GestureKind: String {
        case idle = "Idle"
        case cursor = "Cursor"
        case scroll = "Scroll"
        case pinch = "Pinch"
    }

    private enum GestureState {
        case idle

        /// One finger down, waiting to see if it moves (cursor) or another finger arrives.
        case oneFingerPending(startX: Double, startY: Double)

        /// Actively moving cursor.
        case cursorTracking

        /// Two fingers down, haven't disambiguated scroll vs pinch yet.
        case twoFingerPending(startCenter: CGPoint, startDistance: Double, sampleCount: Int)

        /// Actively scrolling with two fingers.
        case scrolling

        /// Actively pinching/spreading with two fingers.
        case pinching(lastDistance: Double)
    }

    // MARK: - Private State

    private var gestureState: GestureState = .idle

    // Previous frame touch data for delta computation
    private var previousTouch0: DS4TouchFinger?
    private var previousTouch1: DS4TouchFinger?
    private var previousTrackingID0: UInt8?
    private var previousTrackingID1: UInt8?

    // Click tracking
    private var previousTouchpadClick: Bool = false
    private var clickedButton: CGMouseButton?

    // Sub-pixel accumulation for precise cursor movement
    private var accumulatedDX: Double = 0
    private var accumulatedDY: Double = 0

    // Scroll accumulation for smooth scrolling
    private var scrollAccumDX: Double = 0
    private var scrollAccumDY: Double = 0

    // Pinch accumulation (same pattern — prevent Int32 truncation of small deltas)
    private var pinchAccum: Double = 0

    // Weak reference to the transport manager
    @ObservationIgnored
    private weak var transportManager: DS4TransportManager?

    // CGEvent source
    @ObservationIgnored
    private let eventSource: CGEventSource?

    // Accessibility permission polling timer
    @ObservationIgnored
    private var permissionTimer: Timer?

    // MARK: - Constants

    /// Base cursor speed: screen points per touchpad pixel at sensitivity 1.0.
    /// DS4 touchpad is ~47mm wide at 1920 px → ~40.8 px/mm.
    /// A good default: ~0.5 screen pt per touchpad px.
    private let baseCursorScale: Double = 0.5

    /// Base scroll speed: scroll pixels per touchpad pixel delta.
    private let baseScrollScale: Double = 0.15

    /// Movement threshold (touchpad pixels) to commit from pending to cursor tracking.
    private let cursorCommitThreshold: Double = 3.0

    /// Center-of-mass movement threshold to commit to scroll gesture.
    private let scrollCommitThreshold: Double = 8.0

    /// Inter-finger distance change threshold to commit to pinch gesture.
    private let pinchCommitThreshold: Double = 15.0

    // MARK: - Init

    init() {
        eventSource = CGEventSource(stateID: .hidSystemState)
    }

    // MARK: - Public API

    /// Wire up to a transport manager's raw input callback.
    func attach(to manager: DS4TransportManager) {
        transportManager = manager
        manager.onRawInputState = { [weak self] state in
            self?.processInput(state)
        }
        checkAccessibilityPermission()
    }

    /// Enable or disable trackpad emulation.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            resetAllState()
        }
    }

    /// Check if Accessibility permission is currently granted.
    func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    /// Prompt the user for Accessibility permission and poll for changes.
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // Poll until granted
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { timer.invalidate(); return }
                self.hasAccessibilityPermission = AXIsProcessTrusted()
                if self.hasAccessibilityPermission {
                    timer.invalidate()
                    self.permissionTimer = nil
                }
            }
        }
    }

    // MARK: - Input Processing

    private func processInput(_ state: DS4InputState) {
        guard isEnabled, hasAccessibilityPermission else { return }

        let touch0 = state.touchpad.touch0
        let touch1 = state.touchpad.touch1
        let click = state.buttons.touchpadClick

        let activeCount = (touch0.active ? 1 : 0) + (touch1.active ? 1 : 0)
        activeTouchCount = activeCount

        // Process gesture state machine
        switch gestureState {
        case .idle:
            handleIdle(touch0, touch1, activeCount)
        case .oneFingerPending:
            handleOneFingerPending(touch0, touch1, activeCount)
        case .cursorTracking:
            handleCursorTracking(touch0, touch1, activeCount)
        case .twoFingerPending:
            handleTwoFingerPending(touch0, touch1, activeCount)
        case .scrolling:
            handleScrolling(touch0, touch1, activeCount)
        case .pinching:
            handlePinching(touch0, touch1, activeCount)
        }

        // Handle click events (edge-detected)
        handleClick(click: click, activeCount: activeCount)

        // Update previous frame state
        previousTouch0 = touch0.active ? touch0 : nil
        previousTouch1 = touch1.active ? touch1 : nil
        previousTrackingID0 = touch0.active ? touch0.trackingID : nil
        previousTrackingID1 = touch1.active ? touch1.trackingID : nil
        previousTouchpadClick = click
    }

    // MARK: - Gesture State Handlers

    private func handleIdle(_ t0: DS4TouchFinger, _ t1: DS4TouchFinger, _ count: Int) {
        if count == 2 {
            enterTwoFingerPending(t0, t1)
        } else if count == 1 && t0.active {
            gestureState = .oneFingerPending(startX: Double(t0.x), startY: Double(t0.y))
            currentGesture = .idle
        }
    }

    private func handleOneFingerPending(_ t0: DS4TouchFinger, _ t1: DS4TouchFinger, _ count: Int) {
        if count == 0 {
            transitionToIdle()
            return
        }
        if count == 2 {
            enterTwoFingerPending(t0, t1)
            return
        }

        guard case .oneFingerPending(let startX, let startY) = gestureState else { return }

        let dx = Double(t0.x) - startX
        let dy = Double(t0.y) - startY
        let dist = hypot(dx, dy)

        if dist > cursorCommitThreshold {
            gestureState = .cursorTracking
            currentGesture = .cursor
        }
    }

    private func handleCursorTracking(_ t0: DS4TouchFinger, _ t1: DS4TouchFinger, _ count: Int) {
        if count == 0 {
            transitionToIdle()
            return
        }
        if count == 2 {
            enterTwoFingerPending(t0, t1)
            return
        }

        // Compute delta from previous frame
        guard let delta = computeDelta(current: t0, previousFinger: previousTouch0,
                                        previousID: previousTrackingID0) else { return }

        let scaled = scaledCursorDelta(delta)
        postCursorMove(dx: scaled.x, dy: scaled.y)
    }

    private func handleTwoFingerPending(_ t0: DS4TouchFinger, _ t1: DS4TouchFinger, _ count: Int) {
        if count == 0 {
            transitionToIdle()
            return
        }
        if count == 1 {
            gestureState = .cursorTracking
            currentGesture = .cursor
            return
        }

        guard case .twoFingerPending(let startCenter, let startDist, let sampleCount) = gestureState else { return }

        let center = fingerCenter(t0, t1)
        let dist = fingerDistance(t0, t1)

        let centerDelta = hypot(center.x - startCenter.x, center.y - startCenter.y)
        let distDelta = abs(dist - startDist)

        // Check if we can disambiguate
        if distDelta > pinchCommitThreshold && distDelta > centerDelta * 0.7 {
            gestureState = .pinching(lastDistance: dist)
            currentGesture = .pinch
        } else if centerDelta > scrollCommitThreshold {
            gestureState = .scrolling
            currentGesture = .scroll
            scrollAccumDX = 0
            scrollAccumDY = 0
        } else if sampleCount > 10 && centerDelta > 3.0 {
            // After enough samples, default to scroll if there's any movement
            gestureState = .scrolling
            currentGesture = .scroll
            scrollAccumDX = 0
            scrollAccumDY = 0
        } else {
            // Keep collecting samples
            gestureState = .twoFingerPending(startCenter: startCenter, startDistance: startDist,
                                              sampleCount: sampleCount + 1)
        }
    }

    private func handleScrolling(_ t0: DS4TouchFinger, _ t1: DS4TouchFinger, _ count: Int) {
        if count == 0 {
            transitionToIdle()
            return
        }
        if count == 1 {
            gestureState = .cursorTracking
            currentGesture = .cursor
            return
        }

        // Compute center-of-mass delta for scroll direction
        let prevCenter = previousTwoFingerCenter()
        let curCenter = fingerCenter(t0, t1)

        if let prev = prevCenter {
            let dx = curCenter.x - prev.x
            let dy = curCenter.y - prev.y

            // Check if this is actually a pinch (fingers diverging)
            if let prevT0 = previousTouch0, let prevT1 = previousTouch1 {
                let prevDist = fingerDistance(prevT0, prevT1)
                let curDist = fingerDistance(t0, t1)
                let distChange = abs(curDist - prevDist)
                let centerMove = hypot(dx, dy)

                if distChange > centerMove * 1.5 && distChange > 15.0 {
                    gestureState = .pinching(lastDistance: curDist)
                    currentGesture = .pinch
                    return
                }
            }

            postScroll(dx: dx, dy: dy)
        }
    }

    private func handlePinching(_ t0: DS4TouchFinger, _ t1: DS4TouchFinger, _ count: Int) {
        if count == 0 {
            transitionToIdle()
            return
        }
        if count == 1 {
            gestureState = .cursorTracking
            currentGesture = .cursor
            return
        }

        guard case .pinching(let lastDist) = gestureState else { return }

        let curDist = fingerDistance(t0, t1)
        let distDelta = curDist - lastDist

        // Check if this switched to scroll (parallel movement)
        if let prevT0 = previousTouch0, let prevT1 = previousTouch1 {
            let prevCenter = fingerCenter(prevT0, prevT1)
            let curCenter = fingerCenter(t0, t1)
            let centerMove = hypot(curCenter.x - prevCenter.x, curCenter.y - prevCenter.y)
            let distChange = abs(distDelta)

            if centerMove > distChange * 1.5 && centerMove > 10.0 {
                gestureState = .scrolling
                currentGesture = .scroll
                scrollAccumDX = 0
                scrollAccumDY = 0
                return
            }
        }

        postPinchZoom(scaleDelta: distDelta)
        gestureState = .pinching(lastDistance: curDist)
    }

    // MARK: - Click Handling

    private func handleClick(click: Bool, activeCount: Int) {
        let clickDown = click && !previousTouchpadClick
        let clickUp = !click && previousTouchpadClick

        if clickDown {
            let button: CGMouseButton = activeCount >= 2 ? .right : .left
            clickedButton = button
            postClick(button: button, isDown: true)
        }

        if clickUp {
            // Release whichever button was pressed on click-down
            if let button = clickedButton {
                postClick(button: button, isDown: false)
                clickedButton = nil
            }
        }
    }

    // MARK: - CGEvent Posting

    private func postCursorMove(dx: Double, dy: Double) {
        accumulatedDX += dx
        accumulatedDY += dy

        let intDX = Int32(accumulatedDX)
        let intDY = Int32(accumulatedDY)

        guard intDX != 0 || intDY != 0 else { return }

        accumulatedDX -= Double(intDX)
        accumulatedDY -= Double(intDY)

        // CGEvent.mouseMoved moves cursor to the ABSOLUTE mouseCursorPosition.
        // Delta fields are just metadata for apps — they don't drive movement.
        // We must compute the new position ourselves.
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        let newPos = CGPoint(x: currentPos.x + Double(intDX),
                             y: currentPos.y + Double(intDY))

        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .mouseMoved,
            mouseCursorPosition: newPos,
            mouseButton: .left
        ) else { return }

        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(intDX))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(intDY))
        event.post(tap: CGEventTapLocation.cghidEventTap)
    }

    private func postClick(button: CGMouseButton, isDown: Bool) {
        let currentPos = CGEvent(source: nil)?.location ?? .zero

        let eventType: CGEventType
        switch (button, isDown) {
        case (.left, true): eventType = .leftMouseDown
        case (.left, false): eventType = .leftMouseUp
        case (.right, true): eventType = .rightMouseDown
        case (.right, false): eventType = .rightMouseUp
        default: return
        }

        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: eventType,
            mouseCursorPosition: currentPos,
            mouseButton: button
        ) else { return }

        event.post(tap: CGEventTapLocation.cghidEventTap)
    }

    private func postScroll(dx: Double, dy: Double) {
        let direction: Double = naturalScrolling ? 1.0 : -1.0
        let scaledX = dx * baseScrollScale * scrollSensitivity * direction
        let scaledY = dy * baseScrollScale * scrollSensitivity * direction

        scrollAccumDX += scaledX
        scrollAccumDY += scaledY

        let intX = Int32(scrollAccumDX)
        let intY = Int32(scrollAccumDY)

        guard intX != 0 || intY != 0 else { return }

        scrollAccumDX -= Double(intX)
        scrollAccumDY -= Double(intY)

        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: -intY,  // vertical: negate because touchpad Y is down-positive
            wheel2: intX,   // horizontal
            wheel3: 0
        ) else { return }

        // Mark as continuous (trackpad-style smooth scroll)
        event.setIntegerValueField(CGEventField(rawValue: 137)!, value: 1)
        event.post(tap: CGEventTapLocation.cghidEventTap)
    }

    private func postPinchZoom(scaleDelta: Double) {
        // Positive delta = fingers apart = zoom in = scroll up
        // Scale: touchpad pixels → scroll pixels. Accumulate to avoid Int32 truncation.
        pinchAccum += scaleDelta * pinchSensitivity * 0.5

        let zoomAmount = Int32(pinchAccum)
        guard zoomAmount != 0 else { return }

        pinchAccum -= Double(zoomAmount)

        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 1,
            wheel1: zoomAmount,
            wheel2: 0,
            wheel3: 0
        ) else { return }

        // Cmd+scroll = zoom in most macOS apps
        event.flags = CGEventFlags.maskCommand
        event.setIntegerValueField(CGEventField(rawValue: 137)!, value: 1)
        event.post(tap: CGEventTapLocation.cghidEventTap)
    }

    // MARK: - Helpers

    private func computeDelta(current: DS4TouchFinger, previousFinger: DS4TouchFinger?,
                               previousID: UInt8?) -> CGPoint? {
        guard let prev = previousFinger, let prevID = previousID else { return nil }
        // CRITICAL: tracking ID must match — different ID = new touch, not movement
        guard current.trackingID == prevID else { return nil }
        guard current.active && prev.active else { return nil }

        let dx = Double(current.x) - Double(prev.x)
        let dy = Double(current.y) - Double(prev.y)
        return CGPoint(x: dx, y: dy)
    }

    private func scaledCursorDelta(_ raw: CGPoint) -> CGPoint {
        CGPoint(
            x: raw.x * baseCursorScale * cursorSensitivity,
            y: raw.y * baseCursorScale * cursorSensitivity
        )
    }

    private func fingerCenter(_ t0: DS4TouchFinger, _ t1: DS4TouchFinger) -> CGPoint {
        CGPoint(
            x: (Double(t0.x) + Double(t1.x)) / 2.0,
            y: (Double(t0.y) + Double(t1.y)) / 2.0
        )
    }

    private func fingerDistance(_ t0: DS4TouchFinger, _ t1: DS4TouchFinger) -> Double {
        let dx = Double(t0.x) - Double(t1.x)
        let dy = Double(t0.y) - Double(t1.y)
        return hypot(dx, dy)
    }

    private func previousTwoFingerCenter() -> CGPoint? {
        guard let p0 = previousTouch0, let p1 = previousTouch1 else { return nil }
        guard p0.active && p1.active else { return nil }
        return fingerCenter(p0, p1)
    }

    private func enterTwoFingerPending(_ t0: DS4TouchFinger, _ t1: DS4TouchFinger) {
        let center = fingerCenter(t0, t1)
        let dist = fingerDistance(t0, t1)
        gestureState = .twoFingerPending(startCenter: center, startDistance: dist, sampleCount: 0)
        currentGesture = .idle
        accumulatedDX = 0
        accumulatedDY = 0
    }

    private func transitionToIdle() {
        gestureState = .idle
        currentGesture = .idle
        accumulatedDX = 0
        accumulatedDY = 0
        scrollAccumDX = 0
        scrollAccumDY = 0
        pinchAccum = 0
    }

    private func resetAllState() {
        gestureState = .idle
        currentGesture = .idle
        activeTouchCount = 0
        previousTouch0 = nil
        previousTouch1 = nil
        previousTrackingID0 = nil
        previousTrackingID1 = nil
        previousTouchpadClick = false
        clickedButton = nil
        accumulatedDX = 0
        accumulatedDY = 0
        scrollAccumDX = 0
        scrollAccumDY = 0
        pinchAccum = 0
    }
}
