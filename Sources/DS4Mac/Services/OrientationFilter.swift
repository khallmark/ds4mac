// OrientationFilter.swift — Complementary filter sensor fusion for DS4 IMU
//
// Converts raw DS4IMUState (gyro + accelerometer) into a stable orientation
// quaternion suitable for driving SceneKit node transforms.
//
// Algorithm: 98% gyroscope integration (fast, accurate short-term) blended
// with 2% accelerometer gravity reference (slow, drift-free pitch/roll).
// Yaw is gyro-only — no magnetometer on DS4, so yaw drifts slowly (~1°/min).
// Use reset() to re-center.

import Foundation
import Observation
import simd
import DS4Protocol

@MainActor
@Observable
final class OrientationFilter {

    // MARK: - Observable Output

    /// Current orientation as a unit quaternion. Apply directly to SCNNode.simdOrientation.
    private(set) var orientation: simd_quatf = .identity

    // MARK: - Configuration

    /// Gyro trust factor (0.0–1.0). Higher = more responsive, lower = less drift.
    var alpha: Float = 0.98

    /// Per-controller calibration data. When set, uses calibrated deg/s and g-force
    /// instead of hardcoded BMI055 nominal constants. Significantly reduces gyro drift.
    var calibrationData: DS4CalibrationData?

    // MARK: - Private

    /// Fixed timestep matching DS4TransportManager's 30 Hz display throttle.
    /// The manager merges multiple raw reports (~250 Hz) into single state updates,
    /// so using the raw DS4 timestamp delta is not meaningful here.
    private let dt: Float = 1.0 / 30.0

    /// BMI055 gyroscope sensitivity: 16.4 LSB/(deg/s) at ±2000 deg/s range.
    /// Fallback when calibrationData is nil.
    /// (docs/08-Gyroscope-IMU-Feature.md Section 4.1)
    private let gyroScale: Float = 1.0 / 16.4

    /// DS4 accelerometer scale: ~8192 LSB/g.
    /// Fallback when calibrationData is nil.
    /// (docs/08-Gyroscope-IMU-Feature.md Section 4.2)
    private let accelScale: Float = 1.0 / 8192.0

    // MARK: - Update

    /// Feed a new IMU sample from DS4TransportManager.inputState.imu.
    /// Call this from `.onChange(of: manager.inputState.imu)` at ~30 Hz.
    func update(from imu: DS4IMUState) {
        // Step 1: Convert gyro to radians/sec
        let gyroPitchDPS: Float
        let gyroYawDPS: Float
        let gyroRollDPS: Float
        let ax: Float
        let ay: Float
        let az: Float

        if let cal = calibrationData {
            // Calibrated: returns deg/s directly (bias-corrected, per-axis sensitivity)
            gyroPitchDPS = Float(cal.calibrateGyro(axis: .pitch, rawValue: imu.gyroPitch))
            gyroYawDPS   = Float(cal.calibrateGyro(axis: .yaw, rawValue: imu.gyroYaw))
            gyroRollDPS  = Float(cal.calibrateGyro(axis: .roll, rawValue: imu.gyroRoll))
            // Calibrated: returns g-force directly
            ax = Float(cal.calibrateAccel(axis: .pitch, rawValue: imu.accelX))
            ay = Float(cal.calibrateAccel(axis: .yaw, rawValue: imu.accelY))
            az = Float(cal.calibrateAccel(axis: .roll, rawValue: imu.accelZ))
        } else {
            // Fallback: nominal BMI055 constants (no bias correction)
            gyroPitchDPS = Float(imu.gyroPitch) * gyroScale
            gyroYawDPS   = Float(imu.gyroYaw)   * gyroScale
            gyroRollDPS  = Float(imu.gyroRoll)  * gyroScale
            ax = Float(imu.accelX) * accelScale
            ay = Float(imu.accelY) * accelScale
            az = Float(imu.accelZ) * accelScale
        }

        let gyroPitch = gyroPitchDPS * (.pi / 180.0)
        let gyroYaw   = gyroYawDPS   * (.pi / 180.0)
        // Z-axis inverted: DS4 +Z (toward player) → SceneKit -Z (into screen)
        let gyroRoll  = -gyroRollDPS  * (.pi / 180.0)

        // Step 2: Integrate gyro as incremental rotation quaternion
        // Each axis contributes a small rotation: angle = rate * dt
        let qDeltaX = simd_quatf(angle: gyroPitch * dt, axis: SIMD3<Float>(1, 0, 0))
        let qDeltaY = simd_quatf(angle: gyroYaw * dt,   axis: SIMD3<Float>(0, 1, 0))
        let qDeltaZ = simd_quatf(angle: gyroRoll * dt,  axis: SIMD3<Float>(0, 0, 1))

        let qDelta = qDeltaX * qDeltaY * qDeltaZ
        let qGyro = (orientation * qDelta).normalized

        // Step 3: Derive pitch and roll from accelerometer gravity vector (already in g-force)
        // DS4 coordinate system: X=right, Y=up, Z=toward player.
        // At rest, gravity is along +Y (~1g). Standard tilt formulas adapted for Y-up:
        //   pitch (nose up/down) = f(Z component), roll (side tilt) = f(X component)
        let accelPitch = atan2(-az, sqrt(ax * ax + ay * ay))
        let accelRoll  = atan2(ax, sqrt(ay * ay + az * az))

        // Step 4: Build accelerometer quaternion, preserving gyro's yaw
        // (Accelerometer cannot determine yaw — no magnetometer on DS4)
        let gyroEuler = qGyro.eulerAnglesZYX
        let qAccel = simd_quatf(
            pitch: accelPitch,
            yaw: gyroEuler.y,
            roll: accelRoll
        )

        // Step 5: Complementary blend via spherical interpolation
        // alpha=0.98 → 98% gyro (responsive), 2% accel (drift correction)
        orientation = simd_slerp(qAccel, qGyro, alpha)
    }

    /// Reset to identity (neutral orientation). Use when yaw drifts too far.
    func reset() {
        orientation = .identity
    }
}

// MARK: - simd_quatf Helpers

extension simd_quatf {

    /// Identity quaternion (no rotation).
    static let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    /// Extract Euler angles (pitch, yaw, roll) in ZYX convention.
    /// Returns (x: pitch, y: yaw, z: roll) in radians.
    var eulerAnglesZYX: SIMD3<Float> {
        // Roll (Z-axis rotation)
        let sinRcosP = 2.0 * (real * imag.x + imag.y * imag.z)
        let cosRcosP = 1.0 - 2.0 * (imag.x * imag.x + imag.y * imag.y)
        let roll = atan2(sinRcosP, cosRcosP)

        // Pitch (X-axis rotation) — clamped to avoid NaN at poles
        let sinP = 2.0 * (real * imag.y - imag.z * imag.x)
        let pitch: Float
        if abs(sinP) >= 1 {
            pitch = copysign(.pi / 2, sinP)
        } else {
            pitch = asin(sinP)
        }

        // Yaw (Y-axis rotation)
        let sinYcosP = 2.0 * (real * imag.z + imag.x * imag.y)
        let cosYcosP = 1.0 - 2.0 * (imag.y * imag.y + imag.z * imag.z)
        let yaw = atan2(sinYcosP, cosYcosP)

        return SIMD3<Float>(pitch, yaw, roll)
    }

    /// Create quaternion from Euler angles in ZYX convention.
    init(pitch: Float, yaw: Float, roll: Float) {
        let qX = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        let qY = simd_quatf(angle: yaw,   axis: SIMD3<Float>(0, 1, 0))
        let qZ = simd_quatf(angle: roll,  axis: SIMD3<Float>(0, 0, 1))
        self = (qY * qX * qZ).normalized
    }

    /// Normalized quaternion (unit length).
    var normalized: simd_quatf {
        let len = length
        guard len > 0 else { return .identity }
        return simd_quatf(ix: imag.x / len, iy: imag.y / len, iz: imag.z / len, r: real / len)
    }
}
