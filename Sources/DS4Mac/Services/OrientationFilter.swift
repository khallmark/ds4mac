// OrientationFilter.swift — Complementary filter sensor fusion for DS4 IMU
//
// Converts raw DS4IMUState (gyro + accelerometer) into a stable orientation
// quaternion suitable for driving SceneKit node transforms.
//
// Algorithm: 98% gyroscope integration (fast, accurate short-term) blended
// with 2% accelerometer gravity reference (slow, drift-free pitch/roll).
// Yaw is gyro-only — no magnetometer on DS4, so yaw drifts slowly (~1°/min).
//
// Runtime noise reduction (docs/08-Gyroscope-IMU-Feature.md Sections 3.4, 6.1):
// - Continuous gyro bias estimation: detects stationary state, averages gyro
//   samples over ~2s, subtracts residual thermal bias drift.
// - Gyro dead zone: below 0.5 deg/s, treat as zero rotation (eliminates jitter).
// - Accelerometer EMA smoothing: low-pass filter on accel before tilt computation.

import Foundation
import Observation
import simd
import DS4Protocol

@MainActor
@Observable
final class OrientationFilter {

    // MARK: - Observable Output

    /// Current orientation as a unit quaternion (raw, before reference offset).
    private(set) var orientation: simd_quatf = .identity

    /// Orientation with reference offset applied. Use this for display/SceneKit.
    var displayOrientation: simd_quatf {
        (referenceOrientation * orientation).normalized
    }

    // MARK: - Configuration

    /// Gyro trust factor (0.0–1.0). Higher = more responsive, lower = less drift.
    var alpha: Float = 0.98

    /// Per-controller calibration data. When set, uses calibrated deg/s and g-force
    /// instead of hardcoded BMI055 nominal constants. Significantly reduces gyro drift.
    var calibrationData: DS4CalibrationData?

    // MARK: - Private Constants

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

    // MARK: - Runtime Bias Estimation (docs Section 3.4)

    /// Accumulated gyro samples during stationary periods (deg/s).
    private var gyroBiasAccumulator: SIMD3<Float> = .zero

    /// Number of samples accumulated in current stationary window.
    private var gyroBiasSampleCount: Int = 0

    /// Estimated residual gyro bias from continuous calibration (deg/s).
    /// Subtracted from gyro readings before integration.
    private var estimatedGyroBias: SIMD3<Float> = .zero

    /// Samples needed before accepting a bias estimate (~2 seconds at 30 Hz).
    private let biasSettlingSamples: Int = 60

    /// Accelerometer magnitude threshold for stationary detection.
    /// Controller is "still" when accel magnitude is within ±0.05g of 1g.
    private let stationaryThreshold: Float = 0.05

    // MARK: - Gyro Dead Zone (docs Section 6.1)

    /// Below this threshold (deg/s), gyro is treated as zero. Eliminates jitter at rest.
    private let gyroDeadZone: Float = 0.5

    // MARK: - Accelerometer Smoothing

    /// Exponential moving average of accelerometer (g-force). Reduces noise in
    /// the gravity reference used for pitch/roll correction.
    private var smoothedAccel: SIMD3<Float> = SIMD3(0, 1, 0)  // Default: gravity along +Y

    /// EMA factor for accelerometer. Lower = smoother but more latent.
    private let accelSmoothingFactor: Float = 0.15

    // MARK: - Reference Orientation

    /// Reference quaternion for "set level." Applied as inverse offset so the
    /// current physical orientation maps to identity (level ship).
    private var referenceOrientation: simd_quatf = .identity

    // MARK: - Update

    /// Feed a new IMU sample from DS4TransportManager.inputState.imu.
    /// Call this from `.onChange(of: manager.inputState.imu)` at ~30 Hz.
    func update(from imu: DS4IMUState) {
        // Step 1: Convert to physical units (deg/s for gyro, g-force for accel)
        let gyroPitchDPS: Float
        let gyroYawDPS: Float
        let gyroRollDPS: Float
        let ax: Float
        let ay: Float
        let az: Float

        if let cal = calibrationData {
            gyroPitchDPS = Float(cal.calibrateGyro(axis: .pitch, rawValue: imu.gyroPitch))
            gyroYawDPS   = Float(cal.calibrateGyro(axis: .yaw, rawValue: imu.gyroYaw))
            gyroRollDPS  = Float(cal.calibrateGyro(axis: .roll, rawValue: imu.gyroRoll))
            ax = Float(cal.calibrateAccel(axis: .pitch, rawValue: imu.accelX))
            ay = Float(cal.calibrateAccel(axis: .yaw, rawValue: imu.accelY))
            az = Float(cal.calibrateAccel(axis: .roll, rawValue: imu.accelZ))
        } else {
            gyroPitchDPS = Float(imu.gyroPitch) * gyroScale
            gyroYawDPS   = Float(imu.gyroYaw)   * gyroScale
            gyroRollDPS  = Float(imu.gyroRoll)  * gyroScale
            ax = Float(imu.accelX) * accelScale
            ay = Float(imu.accelY) * accelScale
            az = Float(imu.accelZ) * accelScale
        }

        // Step 2: Continuous gyro bias estimation (docs Section 3.4)
        // Detect stationary state via accelerometer magnitude ≈ 1g
        let accelMag = sqrt(ax * ax + ay * ay + az * az)
        let isStationary = abs(accelMag - 1.0) < stationaryThreshold

        if isStationary {
            gyroBiasAccumulator += SIMD3(gyroPitchDPS, gyroYawDPS, gyroRollDPS)
            gyroBiasSampleCount += 1
            if gyroBiasSampleCount >= biasSettlingSamples {
                estimatedGyroBias = gyroBiasAccumulator / Float(gyroBiasSampleCount)
                gyroBiasAccumulator = .zero
                gyroBiasSampleCount = 0
            }
        } else {
            gyroBiasAccumulator = .zero
            gyroBiasSampleCount = 0
        }

        // Step 3: Apply runtime bias correction + dead zone
        let correctedPitch = applyDeadZone(gyroPitchDPS - estimatedGyroBias.x)
        let correctedYaw   = applyDeadZone(gyroYawDPS   - estimatedGyroBias.y)
        let correctedRoll  = applyDeadZone(gyroRollDPS  - estimatedGyroBias.z)

        // Step 4: Convert to radians/sec for quaternion integration
        let gyroPitch = correctedPitch * (.pi / 180.0)
        let gyroYaw   = correctedYaw   * (.pi / 180.0)
        // Z-axis inverted: DS4 +Z (toward player) → SceneKit -Z (into screen)
        let gyroRoll  = -correctedRoll  * (.pi / 180.0)

        // Step 5: Integrate gyro as incremental rotation quaternion
        let qDeltaX = simd_quatf(angle: gyroPitch * dt, axis: SIMD3<Float>(1, 0, 0))
        let qDeltaY = simd_quatf(angle: gyroYaw * dt,   axis: SIMD3<Float>(0, 1, 0))
        let qDeltaZ = simd_quatf(angle: gyroRoll * dt,  axis: SIMD3<Float>(0, 0, 1))

        let qDelta = qDeltaX * qDeltaY * qDeltaZ
        let qGyro = (orientation * qDelta).normalized

        // Step 6: Smooth accelerometer via EMA before tilt computation
        let rawAccel = SIMD3<Float>(ax, ay, az)
        smoothedAccel = accelSmoothingFactor * rawAccel + (1 - accelSmoothingFactor) * smoothedAccel

        // Step 7: Derive pitch and roll from smoothed gravity vector
        // DS4 coordinate system: X=right, Y=up, Z=toward player.
        // At rest, gravity is along +Y (~1g). Standard tilt formulas adapted for Y-up:
        let accelPitch = atan2(-smoothedAccel.z,
                               sqrt(smoothedAccel.x * smoothedAccel.x + smoothedAccel.y * smoothedAccel.y))
        let accelRoll  = atan2(smoothedAccel.x,
                               sqrt(smoothedAccel.y * smoothedAccel.y + smoothedAccel.z * smoothedAccel.z))

        // Step 8: Build accelerometer quaternion, preserving gyro's yaw
        // (Accelerometer cannot determine yaw — no magnetometer on DS4)
        let gyroEuler = qGyro.eulerAnglesZYX
        let qAccel = simd_quatf(
            pitch: accelPitch,
            yaw: gyroEuler.y,
            roll: accelRoll
        )

        // Step 9: Complementary blend via spherical interpolation
        // alpha=0.98 → 98% gyro (responsive), 2% accel (drift correction)
        orientation = simd_slerp(qAccel, qGyro, alpha)
    }

    // MARK: - Actions

    /// Set current physical orientation as "level." The spaceship will appear
    /// horizontal regardless of how the controller sits on the desk.
    func setLevel() {
        referenceOrientation = orientation.conjugate
    }

    /// Full reset: identity orientation, clear reference offset and bias estimate.
    func reset() {
        orientation = .identity
        referenceOrientation = .identity
        estimatedGyroBias = .zero
        gyroBiasAccumulator = .zero
        gyroBiasSampleCount = 0
        smoothedAccel = SIMD3(0, 1, 0)
    }

    // MARK: - Private Helpers

    private func applyDeadZone(_ value: Float) -> Float {
        abs(value) < gyroDeadZone ? 0 : value
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
