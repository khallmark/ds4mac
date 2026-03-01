// EngineFlameBuilder.swift — Engine thrust particle system for the player ship.
// Emits particles backward (+Z) from the engine, with intensity scaled by throttle.

import SceneKit

enum EngineFlameBuilder {

    /// Create the engine flame particle system. Attach to the engine glow node.
    static func buildFlameSystem() -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.birthRate = 0  // Starts off; updated each frame by throttle
        system.emissionDuration = .infinity
        system.loops = true

        system.particleLifeSpan = 0.3
        system.particleLifeSpanVariation = 0.1
        system.particleVelocity = 8.0
        system.particleVelocityVariation = 2.0
        system.spreadingAngle = 15
        system.emittingDirection = SCNVector3(0, 0, 1)  // Backward (+Z = rear of ship)
        system.emitterShape = SCNSphere(radius: 0.12)

        system.particleSize = 0.1
        system.particleSizeVariation = 0.05

        // Blue core → orange → transparent
        system.particleColor = NSColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 1.0)
        system.particleColorVariation = SCNVector4(0.3, 0.2, 0.1, 0)

        system.blendMode = .additive
        system.isLightingEnabled = false
        system.isAffectedByGravity = false
        system.isAffectedByPhysicsFields = false

        // Color animation over particle life: blue → orange → fade
        let colorController = SCNParticlePropertyController(
            animation: {
                let anim = CAKeyframeAnimation()
                anim.values = [
                    NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0),
                    NSColor(red: 1.0, green: 0.6, blue: 0.1, alpha: 0.8),
                    NSColor(red: 1.0, green: 0.3, blue: 0.0, alpha: 0.0),
                ]
                anim.keyTimes = [0, 0.4, 1.0]
                anim.duration = 1.0  // Normalized to particle lifetime
                return anim
            }()
        )
        system.propertyControllers = [.color: colorController]

        return system
    }

    /// Update flame intensity based on throttle (0.0-1.0).
    static func updateIntensity(_ system: SCNParticleSystem, throttle: Float) {
        system.birthRate = CGFloat(throttle * 300.0)
        system.particleSize = CGFloat(0.05 + throttle * 0.15)
        system.particleVelocity = CGFloat(4.0 + throttle * 8.0)
    }
}
