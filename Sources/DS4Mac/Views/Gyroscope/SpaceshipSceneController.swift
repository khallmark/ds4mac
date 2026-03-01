// SpaceshipSceneController.swift — SceneKit scene graph for the 3D gyroscope visualization
//
// Builds a complete space scene with:
// - Procedural spaceship from SceneKit primitives (no external model files)
// - First-person camera (child of ship, rotates with it)
// - Third-person camera (fixed at root, watches ship rotate at origin)
// - Starfield particle system (~2000 static particles on a sphere)
// - Ambient + directional lighting

import SceneKit

final class SpaceshipSceneController {

    let scene: SCNScene
    let shipNode: SCNNode
    let thirdPersonCamera: SCNNode
    let firstPersonCamera: SCNNode

    init() {
        scene = SCNScene()
        scene.background.contents = NSColor.black

        // Build and add ship
        shipNode = Self.buildShip()
        scene.rootNode.addChildNode(shipNode)

        // Build cameras
        thirdPersonCamera = Self.buildThirdPersonCamera()
        firstPersonCamera = Self.buildFirstPersonCamera()
        scene.rootNode.addChildNode(thirdPersonCamera)
        shipNode.addChildNode(firstPersonCamera)

        // Lighting
        Self.addLighting(to: scene)

        // Starfield
        Self.addStarfield(to: scene)
    }

    // MARK: - Ship Geometry

    /// Procedural spaceship built from SceneKit primitives.
    /// The ship faces along -Z (SceneKit forward convention).
    private static func buildShip() -> SCNNode {
        let ship = SCNNode()
        ship.name = "spaceship"

        // --- Fuselage: elongated cylinder along Z-axis ---
        let fuselageGeo = SCNCylinder(radius: 0.3, height: 3.0)
        fuselageGeo.radialSegmentCount = 24
        fuselageGeo.firstMaterial = metalMaterial(
            diffuse: NSColor(white: 0.7, alpha: 1),
            metalness: 0.8,
            roughness: 0.3
        )
        let fuselage = SCNNode(geometry: fuselageGeo)
        fuselage.name = "fuselage"
        fuselage.eulerAngles.x = .pi / 2  // Lay cylinder along Z-axis
        ship.addChildNode(fuselage)

        // --- Nose cone: points forward (-Z) ---
        let noseGeo = SCNCone(topRadius: 0, bottomRadius: 0.3, height: 0.8)
        noseGeo.radialSegmentCount = 24
        noseGeo.firstMaterial = metalMaterial(
            diffuse: NSColor(white: 0.6, alpha: 1),
            metalness: 0.9,
            roughness: 0.2
        )
        let nose = SCNNode(geometry: noseGeo)
        nose.name = "nose"
        nose.eulerAngles.x = -.pi / 2  // Point cone tip forward
        nose.position = SCNVector3(0, 0, -1.9)
        ship.addChildNode(nose)

        // --- Wings: swept delta shape (thin boxes) ---
        let wingGeo = SCNBox(width: 2.5, height: 0.05, length: 1.2, chamferRadius: 0.02)
        wingGeo.firstMaterial = metalMaterial(
            diffuse: NSColor(white: 0.65, alpha: 1),
            metalness: 0.7,
            roughness: 0.35
        )

        let leftWing = SCNNode(geometry: wingGeo)
        leftWing.name = "leftWing"
        leftWing.position = SCNVector3(-1.2, 0, 0.3)
        leftWing.eulerAngles.z = .pi * 0.02  // Slight dihedral
        ship.addChildNode(leftWing)

        let rightWing = SCNNode(geometry: wingGeo)
        rightWing.name = "rightWing"
        rightWing.position = SCNVector3(1.2, 0, 0.3)
        rightWing.eulerAngles.z = -.pi * 0.02
        ship.addChildNode(rightWing)

        // --- Vertical tail fin ---
        let tailGeo = SCNBox(width: 0.05, height: 0.8, length: 0.6, chamferRadius: 0.02)
        tailGeo.firstMaterial = metalMaterial(
            diffuse: NSColor(white: 0.6, alpha: 1),
            metalness: 0.7,
            roughness: 0.3
        )
        let tail = SCNNode(geometry: tailGeo)
        tail.name = "tailFin"
        tail.position = SCNVector3(0, 0.5, 1.3)
        ship.addChildNode(tail)

        // --- Engine glow: emissive blue sphere at rear ---
        let engineGeo = SCNSphere(radius: 0.22)
        engineGeo.segmentCount = 16
        let engineMat = SCNMaterial()
        engineMat.emission.contents = NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0)
        engineMat.diffuse.contents = NSColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 0.6)
        engineMat.lightingModel = .constant  // Self-illuminated, ignores scene lights
        engineGeo.firstMaterial = engineMat
        let engine = SCNNode(geometry: engineGeo)
        engine.name = "engineGlow"
        engine.position = SCNVector3(0, 0, 1.7)
        ship.addChildNode(engine)

        // --- Cockpit: translucent dome on top ---
        let cockpitGeo = SCNSphere(radius: 0.25)
        cockpitGeo.segmentCount = 16
        let cockpitMat = SCNMaterial()
        cockpitMat.diffuse.contents = NSColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 0.4)
        cockpitMat.transparency = 0.6
        cockpitMat.isDoubleSided = true
        cockpitMat.lightingModel = .physicallyBased
        cockpitGeo.firstMaterial = cockpitMat
        let cockpit = SCNNode(geometry: cockpitGeo)
        cockpit.name = "cockpit"
        cockpit.position = SCNVector3(0, 0.3, -0.8)
        ship.addChildNode(cockpit)

        return ship
    }

    // MARK: - Cameras

    /// Third-person camera: fixed at root, behind and above the ship.
    private static func buildThirdPersonCamera() -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 60
        camera.zNear = 0.1
        camera.zFar = 500

        let node = SCNNode()
        node.name = "thirdPersonCamera"
        node.camera = camera
        node.position = SCNVector3(0, 3, 8)  // Behind and above (ship faces -Z)
        node.look(at: SCNVector3(0, 0, 0))
        return node
    }

    /// First-person camera: child of ship node, inside the cockpit looking forward.
    private static func buildFirstPersonCamera() -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 90
        camera.zNear = 0.1
        camera.zFar = 500

        let node = SCNNode()
        node.name = "firstPersonCamera"
        node.camera = camera
        node.position = SCNVector3(0, 0.3, -1.0)  // Inside cockpit, looking along -Z
        return node
    }

    // MARK: - Lighting

    private static func addLighting(to scene: SCNScene) {
        // Ambient: base visibility so no part of the ship is pure black
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 200
        ambient.color = NSColor(white: 0.3, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.name = "ambientLight"
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Directional: simulates a distant star, gives the ship shape/shadow
        let directional = SCNLight()
        directional.type = .directional
        directional.intensity = 800
        directional.color = NSColor(white: 0.95, alpha: 1)
        directional.castsShadow = false
        let directionalNode = SCNNode()
        directionalNode.name = "directionalLight"
        directionalNode.light = directional
        directionalNode.eulerAngles = SCNVector3(-CGFloat.pi / 4, CGFloat.pi / 4, 0)
        scene.rootNode.addChildNode(directionalNode)
    }

    // MARK: - Starfield

    private static func addStarfield(to scene: SCNScene) {
        // Place individual star nodes on a large sphere.
        // Using geometry instead of particle system for guaranteed static placement.
        let starfieldNode = SCNNode()
        starfieldNode.name = "starfield"

        let starGeo = SCNSphere(radius: 0.15)
        starGeo.segmentCount = 4  // Low-poly for performance
        let starMat = SCNMaterial()
        starMat.diffuse.contents = NSColor.white
        starMat.lightingModel = .constant  // Self-illuminated
        starGeo.firstMaterial = starMat

        let starCount = 1500
        let radius: CGFloat = 150.0

        for i in 0..<starCount {
            let star = SCNNode(geometry: starGeo)
            star.name = "star_\(i)"

            // Uniform distribution on sphere surface using spherical coordinates
            // with cos(theta) uniform for even distribution
            let u = CGFloat.random(in: 0...1)
            let v = CGFloat.random(in: 0...1)
            let theta = 2.0 * CGFloat.pi * u
            let phi = acos(2.0 * v - 1.0)

            star.position = SCNVector3(
                radius * sin(phi) * cos(theta),
                radius * sin(phi) * sin(theta),
                radius * cos(phi)
            )

            // Random brightness variation
            let brightness = CGFloat.random(in: 0.3...1.0)
            let size = CGFloat.random(in: 0.05...0.2)
            star.scale = SCNVector3(size, size, size)
            star.opacity = brightness

            starfieldNode.addChildNode(star)
        }

        // Flatten the starfield node for GPU batching (significant perf improvement)
        let flatStarfield = starfieldNode.flattenedClone()
        flatStarfield.name = "starfield"
        scene.rootNode.addChildNode(flatStarfield)
    }

    // MARK: - Material Helpers

    /// PBR metallic material shorthand.
    private static func metalMaterial(
        diffuse: NSColor,
        metalness: CGFloat,
        roughness: CGFloat
    ) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = diffuse
        mat.metalness.contents = metalness
        mat.roughness.contents = roughness
        mat.lightingModel = .physicallyBased
        return mat
    }
}
