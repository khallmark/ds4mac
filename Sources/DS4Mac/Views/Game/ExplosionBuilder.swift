// ExplosionBuilder.swift — Burst particle effect for alien destruction.
// Spawns at the hit location and auto-removes after the burst completes.

import SceneKit

enum ExplosionBuilder {

    /// Spawn an explosion at the given world position and add it to the container node.
    static func spawnExplosion(at position: SCNVector3, in container: SCNNode) {
        let node = SCNNode()
        node.name = "explosion"
        node.position = position

        let system = buildExplosionSystem()
        node.addParticleSystem(system)
        container.addChildNode(node)

        // Auto-remove after particles die out
        node.runAction(.sequence([
            .wait(duration: 1.2),
            .removeFromParentNode(),
        ]))
    }

    private static func buildExplosionSystem() -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.birthRate = 500
        system.emissionDuration = 0.15  // Short burst
        system.loops = false

        system.particleLifeSpan = 0.8
        system.particleLifeSpanVariation = 0.3
        system.particleVelocity = 15.0
        system.particleVelocityVariation = 5.0
        system.spreadingAngle = 180  // Spherical burst

        system.particleSize = 0.25
        system.particleSizeVariation = 0.1

        system.particleColor = NSColor(red: 1.0, green: 0.6, blue: 0.1, alpha: 1.0)
        system.particleColorVariation = SCNVector4(0.1, 0.3, 0.1, 0)

        system.blendMode = .additive
        system.isLightingEnabled = false
        system.isAffectedByGravity = false

        // Color animation: bright orange → deep red → fade
        let colorController = SCNParticlePropertyController(
            animation: {
                let anim = CAKeyframeAnimation()
                anim.values = [
                    NSColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1.0),
                    NSColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 0.9),
                    NSColor(red: 0.6, green: 0.1, blue: 0.0, alpha: 0.0),
                ]
                anim.keyTimes = [0, 0.3, 1.0]
                anim.duration = 1.0
                return anim
            }()
        )
        system.propertyControllers = [.color: colorController]

        // Particles shrink as they die
        let sizeController = SCNParticlePropertyController(
            animation: {
                let anim = CAKeyframeAnimation()
                anim.values = [NSNumber(value: 1.0), NSNumber(value: 0.3), NSNumber(value: 0.0)]
                anim.keyTimes = [0, 0.5, 1.0]
                anim.duration = 1.0
                return anim
            }()
        )
        system.propertyControllers?[.size] = sizeController

        return system
    }
}
