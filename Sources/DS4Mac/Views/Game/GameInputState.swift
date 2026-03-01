// GameInputState.swift — Normalized controller input for the space combat game loop.
// Converts raw DS4InputState (0-255 sticks, UInt8 triggers, Bool buttons) into
// game-ready values: normalized floats with dead zones and button edge detection.

import DS4Protocol

/// Snapshot of controller input consumed by GameSceneController each frame.
struct GameInputState {
    // Sticks: -1.0...1.0 with dead zone applied
    var strafeX: Float = 0       // left stick X: -1=left, +1=right
    var strafeY: Float = 0       // left stick Y: -1=down, +1=up (inverted from raw)
    var cameraX: Float = 0       // right stick X: camera orbit horizontal
    var cameraY: Float = 0       // right stick Y: camera orbit vertical

    // Triggers: 0.0...1.0
    var throttle: Float = 0      // R2 forward thrust
    var brake: Float = 0         // L2 reverse/brake

    // Buttons: edge-detected (true only on the frame the button transitions to pressed)
    var fireLaser: Bool = false   // R1 just pressed
    var fireMissile: Bool = false // L1 just pressed
    var laserHeld: Bool = false   // R1 currently held (continuous fire)
    var toggleCamera: Bool = false // triangle just pressed
    var resetOrientation: Bool = false // share just pressed
    var setLevel: Bool = false    // options just pressed
}

/// Converts raw DS4InputState to normalized GameInputState.
enum InputMapper {
    /// Dead zone as fraction of full range. Accounts for DS4 stick drift (~123-130 center).
    static let stickDeadZone: Float = 0.15
    private static let stickCenter: Float = 128.0

    /// Map current input state, using previous state for button edge detection.
    static func map(current: DS4InputState, previous: DS4InputState?) -> GameInputState {
        let prev = previous?.buttons

        return GameInputState(
            strafeX: normalizeStick(current.leftStick.x),
            strafeY: -normalizeStick(current.leftStick.y),  // Invert: raw 0=up, game +1=up
            cameraX: normalizeStick(current.rightStick.x),
            cameraY: -normalizeStick(current.rightStick.y),
            throttle: Float(current.r2Trigger) / 255.0,
            brake: Float(current.l2Trigger) / 255.0,
            fireLaser: current.buttons.r1 && !(prev?.r1 ?? false),
            fireMissile: current.buttons.l1 && !(prev?.l1 ?? false),
            laserHeld: current.buttons.r1,
            toggleCamera: current.buttons.triangle && !(prev?.triangle ?? false),
            resetOrientation: current.buttons.share && !(prev?.share ?? false),
            setLevel: current.buttons.options && !(prev?.options ?? false)
        )
    }

    /// Normalize stick axis from 0-255 to -1.0...1.0 with dead zone.
    static func normalizeStick(_ raw: UInt8) -> Float {
        let normalized = (Float(raw) - stickCenter) / stickCenter
        return abs(normalized) < stickDeadZone ? 0 : normalized
    }
}
