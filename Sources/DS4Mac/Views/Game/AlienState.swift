// AlienState.swift — Per-alien tracking: health, movement phase, respawn timer.
// Each alien drifts along an orbital path; GameSceneController updates positions each frame.

import SceneKit

struct AlienState {
    let node: SCNNode
    let type: AlienType
    var health: Int
    var isAlive: Bool = true

    // Orbital movement parameters
    var orbitRadius: Float        // Distance from origin
    var orbitSpeed: Float         // Radians per second
    var orbitPhase: Float         // Current angle (radians)
    var orbitTilt: Float          // Tilt of orbital plane (radians)
    var verticalBobSpeed: Float   // Vertical oscillation speed
    var verticalBobAmplitude: Float // Vertical oscillation amplitude

    // Respawn
    var respawnTimer: Float = 0   // Counts down from 3.0 after death

    init(node: SCNNode, type: AlienType, orbitRadius: Float) {
        self.node = node
        self.type = type
        self.health = type.maxHealth
        self.orbitRadius = orbitRadius
        self.orbitSpeed = Float.random(in: 0.15...0.4)
        self.orbitPhase = Float.random(in: 0...(2.0 * .pi))
        self.orbitTilt = Float.random(in: -0.3...0.3)
        self.verticalBobSpeed = Float.random(in: 0.3...0.8)
        self.verticalBobAmplitude = Float.random(in: 2.0...6.0)
    }

    /// Update position along orbital path. Called each frame by the game loop.
    mutating func updateMovement(deltaTime: Float) {
        guard isAlive else { return }

        orbitPhase += orbitSpeed * deltaTime

        let x = orbitRadius * cos(orbitPhase)
        let z = orbitRadius * sin(orbitPhase)
        let y = verticalBobAmplitude * sin(orbitPhase * verticalBobSpeed * 2.3) + orbitTilt * orbitRadius * 0.3

        node.position = SCNVector3(x, y, z)

        // Face tangent direction (direction of travel)
        let tx = -orbitRadius * sin(orbitPhase) * orbitSpeed
        let tz = orbitRadius * cos(orbitPhase) * orbitSpeed
        let angle = atan2(tx, tz)
        node.eulerAngles.y = CGFloat(angle)
    }

    /// Apply damage. Returns true if the alien just died.
    mutating func applyDamage(_ amount: Int) -> Bool {
        guard isAlive else { return false }
        health -= amount
        if health <= 0 {
            isAlive = false
            node.isHidden = true
            node.physicsBody?.categoryBitMask = 0  // Stop detecting contacts
            respawnTimer = 3.0
            return true
        }
        return false
    }

    /// Tick respawn timer. Returns true when ready to respawn.
    mutating func updateRespawn(deltaTime: Float) -> Bool {
        guard !isAlive else { return false }
        respawnTimer -= deltaTime
        if respawnTimer <= 0 {
            respawn()
            return true
        }
        return false
    }

    /// Reset alien for a new life at a random orbit position.
    private mutating func respawn() {
        health = type.maxHealth
        isAlive = true
        node.isHidden = false
        node.physicsBody?.categoryBitMask = PhysicsCategory.alien
        node.opacity = 1.0

        // Randomize new orbit parameters
        orbitRadius = Float.random(in: 30...80)
        orbitPhase = Float.random(in: 0...(2.0 * .pi))
        orbitSpeed = Float.random(in: 0.15...0.4)
        orbitTilt = Float.random(in: -0.3...0.3)
    }
}
