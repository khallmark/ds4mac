// DS4ControllerView.swift — Top-level controller visualization composing photo + interactive overlays.
// Uses a fixed 380×250 design canvas that scales uniformly to fit the available space.

import SwiftUI
import DS4Protocol
import DS4Transport

struct DS4ControllerView: View {
    @Environment(DS4TransportManager.self) var manager
    @Environment(DS4LayoutCalibration.self) var cal

    var body: some View {
        GeometryReader { geo in
            let scale = min(
                geo.size.width / DS4Layout.canvasWidth,
                geo.size.height / DS4Layout.canvasHeight
            )

            ZStack {
                // Layer 1: Controller photo (never redraws on state changes)
                DS4ControllerArtwork()

                // Layer 2: Interactive overlays
                controllerOverlays
            }
            .frame(width: DS4Layout.canvasWidth, height: DS4Layout.canvasHeight)
            .scaleEffect(scale, anchor: .center)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(DS4Layout.aspectRatio, contentMode: .fit)
        .opacity(cal.showAll || manager.connectionState == .connected ? 1.0 : 0.3)
        .animation(.easeInOut(duration: 0.3), value: manager.connectionState == .connected)
        .animation(.easeInOut(duration: 0.2), value: cal.showAll)
    }

    // MARK: - Overlay Composition

    @ViewBuilder
    private var controllerOverlays: some View {
        let dbg = cal.showAll
        let state = dbg ? Self.previewState : manager.inputState
        let output = manager.outputState

        // Light bar — use real output color, or blue when in calibration mode
        LightBarOverlay(
            red: dbg ? 0 : output.ledRed,
            green: dbg ? 0 : output.ledGreen,
            blue: dbg ? 255 : output.ledBlue,
            debug: dbg
        )
        .position(cal.lightBar)

        // Shoulder buttons
        ShoulderOverlay(active: state.buttons.l1, debug: dbg)
            .position(cal.l1)
        ShoulderOverlay(active: state.buttons.r1, debug: dbg)
            .position(cal.r1)

        // Triggers
        TriggerOverlay(value: state.l2Trigger, debug: dbg)
            .position(cal.l2)
        TriggerOverlay(value: state.r2Trigger, debug: dbg)
            .position(cal.r2)

        // D-Pad
        DPadOverlay(direction: state.dpad, spacing: cal.dpadSpacing, debug: dbg)
            .position(cal.dpad)

        // Face buttons
        FaceButtonOverlay(buttons: state.buttons, spacing: cal.faceButtonSpacing, debug: dbg)
            .position(cal.faceButtons)

        // Analog sticks
        StickOverlay(stick: state.leftStick, pressed: state.buttons.l3, debug: dbg)
            .position(cal.leftStick)
        StickOverlay(stick: state.rightStick, pressed: state.buttons.r3, debug: dbg)
            .position(cal.rightStick)

        // Center buttons (Share, PS, Options)
        CenterButtonsOverlay(buttons: state.buttons, calibration: cal, debug: dbg)
            .position(cal.centerButtons)

        // Touchpad dots on controller body
        TouchpadDotsOverlay(
            touch0: state.touchpad.touch0,
            touch1: state.touchpad.touch1,
            padSize: cal.touchpadSize,
            debug: dbg
        )
        .position(cal.touchpad)
    }

    // MARK: - Preview State (all overlays active for calibration)

    private static let previewState = DS4InputState(
        leftStick: DS4StickState(x: 128, y: 128),
        rightStick: DS4StickState(x: 128, y: 128),
        dpad: .north,
        buttons: DS4Buttons(
            square: true, cross: true,
            circle: true, triangle: true,
            l1: true, r1: true,
            l2: true, r2: true,
            share: true, options: true,
            l3: false, r3: false,
            ps: true, touchpadClick: false
        ),
        l2Trigger: 160,
        r2Trigger: 160,
        touchpad: DS4TouchpadState(
            touch0: DS4TouchFinger(active: true, trackingID: 1, x: 480, y: 470),
            touch1: DS4TouchFinger(active: true, trackingID: 2, x: 1440, y: 470)
        )
    )
}
