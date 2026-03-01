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
    var centerButtons = CGPoint(x: 195, y: 100)

    // CenterButtonsOverlay internal offsets (relative to centerButtons position)
    var shareOffset = CGSize(width: -47, height: -24)
    var optionsOffset = CGSize(width: 47, height: -24)
    var psOffset = CGSize(width: 0, height: 40)

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
        centerButtons = CGPoint(x: 195, y: 100)
        shareOffset = CGSize(width: -47, height: -24)
        optionsOffset = CGSize(width: 47, height: -24)
        psOffset = CGSize(width: 0, height: 40)
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
