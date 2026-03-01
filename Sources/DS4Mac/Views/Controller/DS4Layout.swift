// DS4Layout.swift — Coordinate system and element positions for the DS4 controller photo overlay.
// All positions are in a fixed 380×250 design canvas (matching the @2x controller photo at 760×500px).
// The canvas scales uniformly to fit available space via GeometryReader in DS4ControllerView.
//
// Image padding (px): left=50, right=30, top=10, bottom=50
// At @2x (pt):        left=25, right=15, top=5,  bottom=25
// Controller body occupies (25,5)–(365,225) = 340×220pt, centered at (195, 115).

import SwiftUI

// MARK: - Layout Constants

enum DS4Layout {
    // Canvas dimensions (design-time coordinate space, matches @2x image logical size)
    static let canvasWidth: CGFloat = 380
    static let canvasHeight: CGFloat = 250
    static let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)
    static let aspectRatio: CGFloat = canvasWidth / canvasHeight

    // Light bar (blue glow strip at top of touchpad recess)
    static let lightBarCenter = CGPoint(x: 195, y: 29)
    static let lightBarSize = CGSize(width: 80, height: 4)

    // Shoulder buttons (L1/R1)
    static let l1Center = CGPoint(x: 94, y: 15)
    static let r1Center = CGPoint(x: 299, y: 15)
    static let shoulderButtonSize = CGSize(width: 40, height: 12)

    // Trigger indicators (L2/R2)
    static let l2Center = CGPoint(x: 90, y: 0)
    static let r2Center = CGPoint(x: 300, y: 0)
    static let triggerSize = CGSize(width: 35, height: 10)

    // D-Pad
    static let dpadCenter = CGPoint(x: 90, y: 70)
    static let dpadArmSize: CGFloat = 12
    static let dpadSpacing: CGFloat = 18

    // Face buttons (triangle/circle/cross/square)
    static let faceButtonCenter = CGPoint(x: 302, y: 70)
    static let faceButtonRadius: CGFloat = 8
    static let faceButtonSpacing: CGFloat = 26

    // Analog sticks
    static let leftStickCenter = CGPoint(x: 142, y: 117)
    static let rightStickCenter = CGPoint(x: 252, y: 117)
    static let stickWellRadius: CGFloat = 22
    static let stickDotRadius: CGFloat = 5
    static let stickDotTravel: CGFloat = 15 // max pixel offset from center

    // Touchpad area on controller body
    static let touchpadCenter = CGPoint(x: 196, y: 56)
    static let touchpadSize = CGSize(width: 110, height: 50)
    
    // Center buttons
    static let shareCenter = CGPoint(x: 148, y: 76)
    static let optionsCenter = CGPoint(x: 242, y: 76)
    static let psCenter = CGPoint(x: 195, y: 140)

    // Touchpad resolution (hardware)
    static let touchMaxX: CGFloat = 1920
    static let touchMaxY: CGFloat = 943

    // Computed rects from center + size pairs
    static let lightBarRect = CGRect(
        x: lightBarCenter.x - lightBarSize.width / 2,
        y: lightBarCenter.y - lightBarSize.height / 2,
        width: lightBarSize.width,
        height: lightBarSize.height
    )
    static let l2Rect = CGRect(
        x: l2Center.x - triggerSize.width / 2,
        y: l2Center.y - triggerSize.height / 2,
        width: triggerSize.width,
        height: triggerSize.height
    )
    static let r2Rect = CGRect(
        x: r2Center.x - triggerSize.width / 2,
        y: r2Center.y - triggerSize.height / 2,
        width: triggerSize.width,
        height: triggerSize.height
    )
    static let touchpadRect = CGRect(
        x: touchpadCenter.x - touchpadSize.width / 2,
        y: touchpadCenter.y - touchpadSize.height / 2,
        width: touchpadSize.width,
        height: touchpadSize.height
    )
}

// MARK: - Controller Colors

/// Retained colors used by overlay views. Artwork-specific colors removed (photo replaces drawn artwork).
enum DS4Colors {
    static let labelColor = Color(white: 0.55)
    static let inactiveElement = Color(white: 0.35, opacity: 0.4)
}
