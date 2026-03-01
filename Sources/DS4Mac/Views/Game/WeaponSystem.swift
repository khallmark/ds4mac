// WeaponSystem.swift — Laser and missile firing logic with cooldown management.
// Called each frame by GameSceneController to handle weapon input and projectile lifecycle.

import SceneKit

final class WeaponSystem {

    // MARK: - Configuration

    let laserCooldown: Float = 0.15       // Seconds between laser shots (continuous fire)
    let missileCooldown: Float = 1.0      // Seconds between missile launches

    let missileSpeed: Float = 50.0        // Units per second

    // MARK: - State

    var laserCooldownTimer: Float = 0
    var missileCooldownTimer: Float = 0

    private var nextMissileWing: Bool = false  // Alternates left/right wing

    // MARK: - Update

    /// Tick cooldown timers. Call once per frame.
    func update(deltaTime: Float) {
        laserCooldownTimer = max(0, laserCooldownTimer - deltaTime)
        missileCooldownTimer = max(0, missileCooldownTimer - deltaTime)
    }

    /// Normalized cooldown for HUD display (0 = ready, 1 = full cooldown).
    var laserCooldownPercent: Float { laserCooldownTimer / laserCooldown }
    var missileCooldownPercent: Float { missileCooldownTimer / missileCooldown }

    // MARK: - Fire Laser

    /// Attempt to fire a laser beam. Returns the beam node if cooldown allows, nil otherwise.
    func fireLaser(from shipNode: SCNNode, into container: SCNNode) -> SCNNode? {
        guard laserCooldownTimer <= 0 else { return nil }
        laserCooldownTimer = laserCooldown

        let beam = ProjectileBuilder.buildLaserBeam()

        // Position at laser origin (nose of ship) in world space
        let laserOrigin = shipNode.childNode(withName: "laserOrigin", recursively: true)
        let worldPos = laserOrigin?.worldPosition ?? shipNode.worldPosition
        beam.position = worldPos

        // Orient beam along ship's forward direction
        beam.simdOrientation = shipNode.simdWorldOrientation

        container.addChildNode(beam)
        return beam
    }

    // MARK: - Fire Missile

    /// Attempt to fire a missile. Returns the missile node if cooldown allows, nil otherwise.
    func fireMissile(from shipNode: SCNNode, into container: SCNNode) -> SCNNode? {
        guard missileCooldownTimer <= 0 else { return nil }
        missileCooldownTimer = missileCooldown

        let missile = ProjectileBuilder.buildMissile(velocity: missileSpeed)

        // Alternate between left and right wing spawn points
        let originName = nextMissileWing ? "missileOriginRight" : "missileOriginLeft"
        nextMissileWing.toggle()

        let origin = shipNode.childNode(withName: originName, recursively: true)
        let worldPos = origin?.worldPosition ?? shipNode.worldPosition
        missile.position = worldPos

        // Orient missile along ship forward and set velocity
        missile.simdOrientation = shipNode.simdWorldOrientation
        let forward = shipNode.simdWorldFront
        missile.physicsBody?.velocity = SCNVector3(forward * missileSpeed)

        container.addChildNode(missile)
        return missile
    }
}

// MARK: - SCNNode World Position Helper

extension SCNNode {
    /// World position derived from the world transform matrix.
    var worldPosition: SCNVector3 {
        SCNVector3(simdWorldPosition)
    }
}
