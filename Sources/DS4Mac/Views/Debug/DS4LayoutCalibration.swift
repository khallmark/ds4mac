// DS4LayoutCalibration.swift — Runtime-mutable mirror of DS4Layout positions.
// Used by the debug panel to allow live overlay position tweaking.
// Initialized from DS4Layout static values; changes reflect immediately in the controller view.

import SwiftUI
import AppKit

@Observable
final class DS4LayoutCalibration {
    // When true, all overlays render in "active" state for visual calibration
    var showAll = false

    // MARK: - Overlay Positions

    var lightBar = DS4Layout.lightBarCenter
    var l1 = DS4Layout.l1Center
    var r1 = DS4Layout.r1Center
    var l2 = DS4Layout.l2Center
    var r2 = DS4Layout.r2Center
    var dpad = DS4Layout.dpadCenter
    var faceButtons = DS4Layout.faceButtonCenter
    var leftStick = DS4Layout.leftStickCenter
    var rightStick = DS4Layout.rightStickCenter
    var touchpad = DS4Layout.touchpadCenter
    var touchpadSize = DS4Layout.touchpadSize
    var centerButtons = CGPoint(x: 195, y: 100)

    // Button spacing (distance from center to each arm/dot)
    var dpadSpacing = DS4Layout.dpadSpacing
    var faceButtonSpacing = DS4Layout.faceButtonSpacing

    // CenterButtonsOverlay internal offsets (relative to centerButtons position)
    var shareOffset = CGSize(width: -69, height: -64)
    var optionsOffset = CGSize(width: 71, height: -64)
    var psOffset = CGSize(width: 2, height: 20)

    // MARK: - Actions

    func reset() {
        lightBar = DS4Layout.lightBarCenter
        l1 = DS4Layout.l1Center
        r1 = DS4Layout.r1Center
        l2 = DS4Layout.l2Center
        r2 = DS4Layout.r2Center
        dpad = DS4Layout.dpadCenter
        faceButtons = DS4Layout.faceButtonCenter
        leftStick = DS4Layout.leftStickCenter
        rightStick = DS4Layout.rightStickCenter
        touchpad = DS4Layout.touchpadCenter
        touchpadSize = DS4Layout.touchpadSize
        centerButtons = CGPoint(x: 195, y: 100)
        dpadSpacing = DS4Layout.dpadSpacing
        faceButtonSpacing = DS4Layout.faceButtonSpacing
        shareOffset = CGSize(width: -69, height: -64)
        optionsOffset = CGSize(width: 71, height: -64)
        psOffset = CGSize(width: 2, height: 20)
    }

    func swiftCode() -> String {
        """
        // DS4Layout positions (calibrated)
        static let lightBarCenter = CGPoint(x: \(Int(lightBar.x)), y: \(Int(lightBar.y)))
        static let l1Center = CGPoint(x: \(Int(l1.x)), y: \(Int(l1.y)))
        static let r1Center = CGPoint(x: \(Int(r1.x)), y: \(Int(r1.y)))
        static let l2Center = CGPoint(x: \(Int(l2.x)), y: \(Int(l2.y)))
        static let r2Center = CGPoint(x: \(Int(r2.x)), y: \(Int(r2.y)))
        static let dpadCenter = CGPoint(x: \(Int(dpad.x)), y: \(Int(dpad.y)))
        static let faceButtonCenter = CGPoint(x: \(Int(faceButtons.x)), y: \(Int(faceButtons.y)))
        static let leftStickCenter = CGPoint(x: \(Int(leftStick.x)), y: \(Int(leftStick.y)))
        static let rightStickCenter = CGPoint(x: \(Int(rightStick.x)), y: \(Int(rightStick.y)))
        static let touchpadCenter = CGPoint(x: \(Int(touchpad.x)), y: \(Int(touchpad.y)))
        static let touchpadSize = CGSize(width: \(Int(touchpadSize.width)), height: \(Int(touchpadSize.height)))
        static let dpadSpacing: CGFloat = \(Int(dpadSpacing))
        static let faceButtonSpacing: CGFloat = \(Int(faceButtonSpacing))

        // CenterButtonsOverlay anchor
        .position(x: \(Int(centerButtons.x)), y: \(Int(centerButtons.y)))

        // CenterButtonsOverlay offsets
        .offset(x: \(Int(shareOffset.width)), y: \(Int(shareOffset.height)))   // Share
        .offset(x: \(Int(optionsOffset.width)), y: \(Int(optionsOffset.height)))   // Options
        .offset(x: \(Int(psOffset.width)), y: \(Int(psOffset.height)))   // PS
        """
    }

    func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(swiftCode(), forType: .string)
    }
}
