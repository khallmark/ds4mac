// DS4OverlayViews.swift — Interactive glow overlays positioned on top of the DS4 controller photo.
// Each overlay is invisible when idle and shows a translucent glow when active.
// The photo already renders the physical buttons — overlays only provide press feedback.
// When `debug` is true, overlays render as solid high-contrast markers for calibration.

import SwiftUI
import DS4Protocol

// MARK: - StickOverlay

/// Analog stick position dot with glow on press. No background drawn — the photo shows the stick well.
struct StickOverlay: View {
    let stick: DS4StickState
    let pressed: Bool
    var debug = false

    private var nx: CGFloat { (CGFloat(stick.x) - 128) / 128 }
    private var ny: CGFloat { (CGFloat(stick.y) - 128) / 128 }

    var body: some View {
        ZStack {
            if pressed {
                Circle()
                    .fill(Color.accentColor.opacity(debug ? 0.6 : 0.3))
                    .frame(width: DS4Layout.stickWellRadius * 2,
                           height: DS4Layout.stickWellRadius * 2)
                    .blur(radius: debug ? 0 : 8)
            }

            Circle()
                .fill(Color.accentColor)
                .frame(width: DS4Layout.stickDotRadius * 2,
                       height: DS4Layout.stickDotRadius * 2)
                .shadow(color: debug ? .clear : Color.accentColor.opacity(0.6), radius: 4)
                .offset(x: nx * DS4Layout.stickDotTravel,
                        y: ny * DS4Layout.stickDotTravel)
        }
        .frame(width: DS4Layout.stickWellRadius * 2,
               height: DS4Layout.stickWellRadius * 2)
    }
}

// MARK: - DPadOverlay

/// D-pad glow highlights. Shows all 4 arms in debug mode, only active direction otherwise.
struct DPadOverlay: View {
    let direction: DS4DPadDirection
    var debug = false

    private var upActive: Bool {
        debug || [.north, .northEast, .northWest].contains(direction)
    }
    private var downActive: Bool {
        debug || [.south, .southEast, .southWest].contains(direction)
    }
    private var leftActive: Bool {
        debug || [.west, .northWest, .southWest].contains(direction)
    }
    private var rightActive: Bool {
        debug || [.east, .northEast, .southEast].contains(direction)
    }

    private let arm = DS4Layout.dpadArmSize
    private let gap = DS4Layout.dpadGap

    var body: some View {
        ZStack {
            // Center dot in debug mode for precise positioning
            if debug {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: 4)
            }

            if upActive {
                glowPill()
                    .offset(y: -(arm + gap))
            }
            if downActive {
                glowPill()
                    .offset(y: arm + gap)
            }
            if leftActive {
                glowPill()
                    .offset(x: -(arm + gap))
            }
            if rightActive {
                glowPill()
                    .offset(x: arm + gap)
            }
        }
    }

    private func glowPill() -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.accentColor.opacity(debug ? 0.8 : 0.45))
            .frame(width: arm, height: arm)
            .blur(radius: debug ? 0 : 4)
    }
}

// MARK: - FaceButtonOverlay

/// Face button glow dots. Each button shows its signature color when pressed.
struct FaceButtonOverlay: View {
    let buttons: DS4Buttons
    var debug = false

    private let spacing = DS4Layout.faceButtonSpacing
    private let diameter = DS4Layout.faceButtonRadius * 2

    var body: some View {
        ZStack {
            if buttons.triangle {
                glowDot(color: .green)
                    .offset(y: -spacing)
            }
            if buttons.circle {
                glowDot(color: .red)
                    .offset(x: spacing)
            }
            if buttons.cross {
                glowDot(color: .blue)
                    .offset(y: spacing)
            }
            if buttons.square {
                glowDot(color: .pink)
                    .offset(x: -spacing)
            }
        }
    }

    private func glowDot(color: Color) -> some View {
        Circle()
            .fill(color.opacity(debug ? 0.9 : 0.5))
            .frame(width: diameter, height: diameter)
            .blur(radius: debug ? 0 : 6)
            .shadow(color: debug ? .clear : color.opacity(0.4), radius: 8)
    }
}

// MARK: - ShoulderOverlay

/// L1/R1 shoulder button glow. Only visible when pressed.
struct ShoulderOverlay: View {
    let active: Bool
    var debug = false

    var body: some View {
        if active {
            Capsule()
                .fill(Color.accentColor.opacity(debug ? 0.8 : 0.5))
                .frame(width: DS4Layout.shoulderButtonSize.width,
                       height: DS4Layout.shoulderButtonSize.height)
                .blur(radius: debug ? 0 : 5)
        }
    }
}

// MARK: - TriggerOverlay

/// L2/R2 analog trigger glow. Fill width and opacity scale with pressure.
struct TriggerOverlay: View {
    let value: UInt8
    var debug = false

    private var fraction: CGFloat { CGFloat(value) / 255 }

    var body: some View {
        if value > 0 {
            Capsule()
                .fill(Color.accentColor.opacity(debug ? 0.8 : Double(fraction) * 0.6))
                .frame(width: debug ? DS4Layout.triggerSize.width : max(4, fraction * DS4Layout.triggerSize.width),
                       height: DS4Layout.triggerSize.height)
                .blur(radius: debug ? 0 : 3)
        }
    }
}

// MARK: - CenterButtonsOverlay

/// Share, Options, and PS button glow group.
struct CenterButtonsOverlay: View {
    let buttons: DS4Buttons
    var calibration: DS4LayoutCalibration?
    var debug = false

    var body: some View {
        let share = calibration?.shareOffset ?? CGSize(width: -47, height: -24)
        let options = calibration?.optionsOffset ?? CGSize(width: 47, height: -24)
        let ps = calibration?.psOffset ?? CGSize(width: 0, height: 40)

        ZStack {
            // Center anchor dot in debug mode
            if debug {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 4, height: 4)
            }

            if buttons.share {
                Capsule()
                    .fill(Color.accentColor.opacity(debug ? 0.8 : 0.45))
                    .frame(width: 26, height: 9)
                    .blur(radius: debug ? 0 : 3)
                    .offset(share)
            }

            if buttons.options {
                Capsule()
                    .fill(Color.accentColor.opacity(debug ? 0.8 : 0.45))
                    .frame(width: 26, height: 9)
                    .blur(radius: debug ? 0 : 3)
                    .offset(options)
            }

            if buttons.ps {
                Circle()
                    .fill(Color.accentColor.opacity(debug ? 0.8 : 0.45))
                    .frame(width: 12, height: 12)
                    .blur(radius: debug ? 0 : 4)
                    .offset(ps)
            }
        }
    }
}

// MARK: - LightBarOverlay

/// LED light bar glow with bloom effect.
struct LightBarOverlay: View {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    var debug = false

    private var isLit: Bool {
        red > 0 || green > 0 || blue > 0
    }

    private var ledColor: Color {
        Color(red: Double(red) / 255,
              green: Double(green) / 255,
              blue: Double(blue) / 255)
    }

    var body: some View {
        if isLit {
            Capsule()
                .fill(ledColor)
                .frame(width: DS4Layout.lightBarSize.width,
                       height: DS4Layout.lightBarSize.height)
                .shadow(color: debug ? .clear : ledColor.opacity(0.8), radius: 15)
                .blur(radius: debug ? 0 : 2)
        }
    }
}

// MARK: - TouchpadDotsOverlay

/// Touch finger position dots mapped onto the controller touchpad area.
struct TouchpadDotsOverlay: View {
    let touch0: DS4TouchFinger
    let touch1: DS4TouchFinger
    var debug = false

    private let padWidth = DS4Layout.touchpadSize.width
    private let padHeight = DS4Layout.touchpadSize.height

    var body: some View {
        ZStack {
            // Touchpad boundary in debug mode
            if debug {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                    .frame(width: padWidth, height: padHeight)
            }

            if touch0.active {
                touchDot(finger: touch0, color: .accentColor)
            }
            if touch1.active {
                touchDot(finger: touch1, color: .orange)
            }
        }
        .frame(width: padWidth, height: padHeight)
        .clipped()
    }

    @ViewBuilder
    private func touchDot(finger: DS4TouchFinger, color: Color) -> some View {
        let px = CGFloat(finger.x) / DS4Layout.touchMaxX * padWidth
        let py = CGFloat(finger.y) / DS4Layout.touchMaxY * padHeight

        ZStack {
            Circle()
                .fill(color.opacity(debug ? 0.5 : 0.25))
                .frame(width: 20, height: 20)

            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(radius: debug ? 0 : 2)
        }
        .position(x: px, y: py)
    }
}
