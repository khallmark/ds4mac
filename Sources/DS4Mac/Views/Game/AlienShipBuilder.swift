// AlienShipBuilder.swift — Procedural alien ship geometry (3 types).
// Each builder returns an SCNNode with physics body attached.

import SceneKit

enum AlienType: CaseIterable {
    case saucer   // Red torus + dome
    case dart     // Green pyramid + fins
    case cruiser  // Purple box + engine pods

    var maxHealth: Int {
        switch self {
        case .saucer: return 1
        case .dart: return 1
        case .cruiser: return 2
        }
    }

    var points: Int {
        switch self {
        case .saucer: return 100
        case .dart: return 150
        case .cruiser: return 250
        }
    }
}

enum AlienShipBuilder {

    static func build(type: AlienType) -> SCNNode {
        switch type {
        case .saucer: return buildSaucer()
        case .dart: return buildDart()
        case .cruiser: return buildCruiser()
        }
    }

    // MARK: - Saucer (Red)

    private static func buildSaucer() -> SCNNode {
        let ship = SCNNode()
        ship.name = "alien_saucer"

        // Main body: torus
        let torusGeo = SCNTorus(ringRadius: 1.0, pipeRadius: 0.25)
        torusGeo.ringSegmentCount = 24
        torusGeo.pipeSegmentCount = 12
        torusGeo.firstMaterial = metalMaterial(
            diffuse: NSColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 1),
            metalness: 0.7,
            roughness: 0.4
        )
        let torus = SCNNode(geometry: torusGeo)
        ship.addChildNode(torus)

        // Central dome: emissive red glow
        let domeGeo = SCNSphere(radius: 0.5)
        domeGeo.segmentCount = 12
        let domeMat = SCNMaterial()
        domeMat.emission.contents = NSColor(red: 1.0, green: 0.2, blue: 0.1, alpha: 1.0)
        domeMat.diffuse.contents = NSColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 0.8)
        domeMat.lightingModel = .constant
        domeGeo.firstMaterial = domeMat
        let dome = SCNNode(geometry: domeGeo)
        dome.position = SCNVector3(0, 0.2, 0)
        ship.addChildNode(dome)

        // Physics
        ship.physicsBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: SCNSphere(radius: 1.2), options: nil))
        ship.physicsBody?.categoryBitMask = PhysicsCategory.alien
        ship.physicsBody?.contactTestBitMask = PhysicsCategory.laser | PhysicsCategory.missile
        ship.physicsBody?.collisionBitMask = 0

        return ship
    }

    // MARK: - Dart (Green)

    private static func buildDart() -> SCNNode {
        let ship = SCNNode()
        ship.name = "alien_dart"

        // Main body: elongated pyramid
        let pyramidGeo = SCNPyramid(width: 0.8, height: 2.0, length: 0.8)
        pyramidGeo.firstMaterial = metalMaterial(
            diffuse: NSColor(red: 0.1, green: 0.5, blue: 0.15, alpha: 1),
            metalness: 0.8,
            roughness: 0.3
        )
        let pyramid = SCNNode(geometry: pyramidGeo)
        pyramid.eulerAngles.x = -.pi / 2  // Point tip forward (-Z)
        pyramid.position = SCNVector3(0, 0, 0)
        ship.addChildNode(pyramid)

        // Fins
        let finGeo = SCNBox(width: 0.05, height: 0.6, length: 0.4, chamferRadius: 0.01)
        finGeo.firstMaterial = metalMaterial(
            diffuse: NSColor(red: 0.08, green: 0.4, blue: 0.12, alpha: 1),
            metalness: 0.7,
            roughness: 0.35
        )
        let leftFin = SCNNode(geometry: finGeo)
        leftFin.position = SCNVector3(-0.4, 0, 0.3)
        leftFin.eulerAngles.z = .pi * 0.15
        ship.addChildNode(leftFin)

        let rightFin = SCNNode(geometry: finGeo)
        rightFin.position = SCNVector3(0.4, 0, 0.3)
        rightFin.eulerAngles.z = -.pi * 0.15
        ship.addChildNode(rightFin)

        // Engine glow
        let engineGeo = SCNSphere(radius: 0.15)
        engineGeo.segmentCount = 8
        let engineMat = SCNMaterial()
        engineMat.emission.contents = NSColor(red: 0.1, green: 1.0, blue: 0.2, alpha: 1.0)
        engineMat.lightingModel = .constant
        engineGeo.firstMaterial = engineMat
        let engine = SCNNode(geometry: engineGeo)
        engine.position = SCNVector3(0, 0, 0.8)
        ship.addChildNode(engine)

        // Physics
        ship.physicsBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: SCNSphere(radius: 1.0), options: nil))
        ship.physicsBody?.categoryBitMask = PhysicsCategory.alien
        ship.physicsBody?.contactTestBitMask = PhysicsCategory.laser | PhysicsCategory.missile
        ship.physicsBody?.collisionBitMask = 0

        return ship
    }

    // MARK: - Cruiser (Purple)

    private static func buildCruiser() -> SCNNode {
        let ship = SCNNode()
        ship.name = "alien_cruiser"

        // Main body: elongated box
        let bodyGeo = SCNBox(width: 1.2, height: 0.5, length: 2.5, chamferRadius: 0.1)
        bodyGeo.firstMaterial = metalMaterial(
            diffuse: NSColor(red: 0.35, green: 0.1, blue: 0.5, alpha: 1),
            metalness: 0.75,
            roughness: 0.35
        )
        let body = SCNNode(geometry: bodyGeo)
        ship.addChildNode(body)

        // Cannon barrel underneath
        let cannonGeo = SCNCylinder(radius: 0.1, height: 1.5)
        cannonGeo.radialSegmentCount = 8
        cannonGeo.firstMaterial = metalMaterial(
            diffuse: NSColor(red: 0.25, green: 0.08, blue: 0.4, alpha: 1),
            metalness: 0.9,
            roughness: 0.2
        )
        let cannon = SCNNode(geometry: cannonGeo)
        cannon.eulerAngles.x = .pi / 2  // Lay along Z
        cannon.position = SCNVector3(0, -0.3, -0.5)
        ship.addChildNode(cannon)

        // Engine pods (left and right)
        let podGeo = SCNSphere(radius: 0.2)
        podGeo.segmentCount = 10
        let podMat = SCNMaterial()
        podMat.emission.contents = NSColor(red: 0.6, green: 0.1, blue: 1.0, alpha: 1.0)
        podMat.lightingModel = .constant
        podGeo.firstMaterial = podMat

        let leftPod = SCNNode(geometry: podGeo)
        leftPod.position = SCNVector3(-0.7, 0, 1.0)
        ship.addChildNode(leftPod)

        let rightPod = SCNNode(geometry: podGeo)
        rightPod.position = SCNVector3(0.7, 0, 1.0)
        ship.addChildNode(rightPod)

        // Physics
        ship.physicsBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: SCNBox(width: 1.4, height: 0.6, length: 2.7, chamferRadius: 0), options: nil))
        ship.physicsBody?.categoryBitMask = PhysicsCategory.alien
        ship.physicsBody?.contactTestBitMask = PhysicsCategory.laser | PhysicsCategory.missile
        ship.physicsBody?.collisionBitMask = 0

        return ship
    }

    // MARK: - Helpers

    private static func metalMaterial(diffuse: NSColor, metalness: CGFloat, roughness: CGFloat) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = diffuse
        mat.metalness.contents = metalness
        mat.roughness.contents = roughness
        mat.lightingModel = .physicallyBased
        return mat
    }
}
