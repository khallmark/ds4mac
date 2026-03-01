// ProjectileBuilder.swift — Laser beam and missile geometry for weapons.
// Lasers are thin bright cylinders that fade quickly.
// Missiles are small cones with exhaust trail particle systems.

import SceneKit

enum ProjectileBuilder {

    // MARK: - Laser Beam

    /// Create a laser beam node. Oriented along -Z (ship forward) by default.
    /// The beam is a thin cylinder with emissive cyan material.
    static func buildLaserBeam() -> SCNNode {
        let length: CGFloat = 80.0
        let geo = SCNCylinder(radius: 0.04, height: length)
        geo.radialSegmentCount = 6

        let mat = SCNMaterial()
        mat.emission.contents = NSColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0)
        mat.diffuse.contents = NSColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 0.8)
        mat.lightingModel = .constant
        geo.firstMaterial = mat

        let node = SCNNode(geometry: geo)
        // SCNCylinder is along Y by default; rotate to face -Z
        node.eulerAngles.x = .pi / 2
        // Offset so the beam starts at origin and extends forward
        node.position = SCNVector3(0, 0, -length / 2)

        // Wrap in container so the spawn point is at the base
        let container = SCNNode()
        container.name = "laser"
        container.addChildNode(node)

        // Physics body for collision detection
        let shape = SCNPhysicsShape(geometry: SCNBox(width: 0.1, height: 0.1, length: length, chamferRadius: 0), options: nil)
        container.physicsBody = SCNPhysicsBody(type: .kinematic, shape: shape)
        container.physicsBody?.categoryBitMask = PhysicsCategory.laser
        container.physicsBody?.contactTestBitMask = PhysicsCategory.alien
        container.physicsBody?.collisionBitMask = 0  // No physical collision response

        // Auto-remove after brief display
        container.runAction(.sequence([
            .wait(duration: 0.12),
            .fadeOut(duration: 0.05),
            .removeFromParentNode(),
        ]))

        return container
    }

    // MARK: - Missile

    /// Create a missile node with exhaust trail. Flies straight at given velocity.
    static func buildMissile(velocity: Float = 50.0) -> SCNNode {
        let bodyGeo = SCNCone(topRadius: 0, bottomRadius: 0.08, height: 0.35)
        bodyGeo.radialSegmentCount = 8

        let mat = SCNMaterial()
        mat.emission.contents = NSColor(red: 1.0, green: 0.5, blue: 0.1, alpha: 1.0)
        mat.diffuse.contents = NSColor(red: 0.8, green: 0.3, blue: 0.0, alpha: 1.0)
        mat.lightingModel = .constant
        bodyGeo.firstMaterial = mat

        let body = SCNNode(geometry: bodyGeo)
        body.eulerAngles.x = -.pi / 2  // Point cone tip forward (-Z)

        let container = SCNNode()
        container.name = "missile"
        container.addChildNode(body)

        // Exhaust trail particle system
        let trail = buildMissileTrail()
        container.addParticleSystem(trail)

        // Dynamic physics body — flies forward
        let shape = SCNPhysicsShape(geometry: SCNSphere(radius: 0.15), options: nil)
        container.physicsBody = SCNPhysicsBody(type: .dynamic, shape: shape)
        container.physicsBody?.categoryBitMask = PhysicsCategory.missile
        container.physicsBody?.contactTestBitMask = PhysicsCategory.alien
        container.physicsBody?.collisionBitMask = 0
        container.physicsBody?.isAffectedByGravity = false
        container.physicsBody?.damping = 0  // No air resistance in space

        // Auto-remove after lifetime expires
        container.runAction(.sequence([
            .wait(duration: 5.0),
            .removeFromParentNode(),
        ]))

        return container
    }

    // MARK: - Missile Trail

    private static func buildMissileTrail() -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.birthRate = 80
        system.emissionDuration = .infinity
        system.loops = true

        system.particleLifeSpan = 0.4
        system.particleLifeSpanVariation = 0.1
        system.particleVelocity = 2.0
        system.spreadingAngle = 20
        system.emittingDirection = SCNVector3(0, 0, 1)  // Trail goes backward

        system.particleSize = 0.06
        system.particleSizeVariation = 0.02
        system.particleColor = NSColor(red: 1.0, green: 0.6, blue: 0.1, alpha: 0.8)
        system.blendMode = .additive
        system.isLightingEnabled = false
        system.isAffectedByGravity = false

        return system
    }
}
