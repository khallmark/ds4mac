// GameSceneController.swift — Core game loop and scene management for space combat.
//
// Responsibilities:
// - Scene graph construction (ship, cameras, lights, starfield, alien/projectile containers)
// - SCNSceneRendererDelegate: per-frame ship movement, camera follow, weapon/alien updates
// - SCNPhysicsContactDelegate: hit detection between projectiles and aliens
// - Haptic feedback via DS4 rumble motors

import SceneKit
import simd
import DS4Protocol
import DS4Transport

final class GameSceneController: NSObject, SCNSceneRendererDelegate, SCNPhysicsContactDelegate {

    // MARK: - Scene Graph

    let scene: SCNScene
    let shipNode: SCNNode

    // Camera rig — follows ship position (lerped), NOT rotation
    private let cameraRig: SCNNode
    let thirdPersonCamera: SCNNode
    let firstPersonCamera: SCNNode

    // Container nodes for dynamic entities
    private let aliensContainer: SCNNode
    private let projectilesContainer: SCNNode
    private let explosionsContainer: SCNNode

    // MARK: - Systems

    let gameState: GameState
    let weaponSystem: WeaponSystem
    private var engineFlame: SCNParticleSystem?

    // MARK: - Alien Tracking

    private var aliens: [AlienState] = []
    private let alienCount = 7

    // MARK: - Ship Physics

    private var shipVelocity: SIMD3<Float> = .zero
    private let maxSpeed: Float = 40.0
    private let thrustForce: Float = 30.0
    private let strafeForce: Float = 15.0
    private let dragFactor: Float = 0.98  // Per-frame velocity decay

    // MARK: - Camera State

    private var cameraAzimuth: Float = 0        // Horizontal orbit angle (radians)
    private var cameraElevation: Float = 0.2    // Vertical orbit angle (radians)
    private let cameraDistance: Float = 12.0
    private let cameraFollowSpeed: Float = 4.0  // Lerp speed
    private let cameraOrbitSpeed: Float = 2.5   // Right stick sensitivity
    private let cameraReturnSpeed: Float = 1.5  // Return-to-center speed

    // MARK: - Input

    var currentInput = GameInputState()
    var isFirstPerson = false

    // MARK: - Frame Timing

    private var lastUpdateTime: TimeInterval = 0

    // MARK: - Haptic Output

    var rumbleOutput: ((UInt8, UInt8) -> Void)?  // (weak/right, strong/left)

    // MARK: - Init

    init(gameState: GameState) {
        self.gameState = gameState
        self.weaponSystem = WeaponSystem()

        // Create scene
        scene = SCNScene()
        scene.background.contents = NSColor.black

        // Build ship (reuse geometry from SpaceshipSceneController pattern)
        shipNode = Self.buildPlayerShip()

        // Camera rig
        cameraRig = SCNNode()
        cameraRig.name = "cameraRig"
        thirdPersonCamera = Self.buildThirdPersonCamera()
        firstPersonCamera = Self.buildFirstPersonCamera()
        cameraRig.addChildNode(thirdPersonCamera)
        shipNode.addChildNode(firstPersonCamera)

        // Containers
        aliensContainer = SCNNode()
        aliensContainer.name = "aliens"
        projectilesContainer = SCNNode()
        projectilesContainer.name = "projectiles"
        explosionsContainer = SCNNode()
        explosionsContainer.name = "explosions"

        super.init()

        // Assemble scene graph
        scene.rootNode.addChildNode(shipNode)
        scene.rootNode.addChildNode(cameraRig)
        scene.rootNode.addChildNode(aliensContainer)
        scene.rootNode.addChildNode(projectilesContainer)
        scene.rootNode.addChildNode(explosionsContainer)

        // Engine flame
        let flame = EngineFlameBuilder.buildFlameSystem()
        if let engineGlow = shipNode.childNode(withName: "engineGlow", recursively: true) {
            engineGlow.addParticleSystem(flame)
        }
        engineFlame = flame

        // Lighting + starfield
        Self.addLighting(to: scene)
        Self.addStarfield(to: scene)

        // Physics world
        scene.physicsWorld.contactDelegate = self

        // Spawn aliens
        spawnInitialAliens()
    }

    // MARK: - SCNSceneRendererDelegate (Game Loop)

    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt: Float
        if lastUpdateTime == 0 {
            dt = 1.0 / 60.0
        } else {
            dt = min(Float(time - lastUpdateTime), 0.1)  // Clamp to avoid spiral of death
        }
        lastUpdateTime = time

        updateShipMovement(dt: dt)
        updateEngineFlame()
        updateCamera(dt: dt)
        updateWeapons(dt: dt)
        updateAliens(dt: dt)
        updateGameState()
        updateHaptics()
    }

    // MARK: - Ship Movement

    private func updateShipMovement(dt: Float) {
        let input = currentInput

        // Forward thrust along ship's facing direction
        let shipForward = shipNode.simdWorldFront  // -Z in local space
        let thrust = shipForward * input.throttle * thrustForce

        // Strafe relative to ship orientation
        let shipRight = shipNode.simdWorldRight
        let shipUp = shipNode.simdWorldUp
        let strafe = (shipRight * input.strafeX + shipUp * input.strafeY) * strafeForce

        // Brake: apply opposing force
        let brakeForce = shipVelocity * (-input.brake * 5.0)

        // Integrate velocity
        shipVelocity += (thrust + strafe + brakeForce) * dt
        shipVelocity *= dragFactor  // Aerodynamic drag (space drag for gameplay)

        // Clamp speed
        let speed = simd_length(shipVelocity)
        if speed > maxSpeed {
            shipVelocity = simd_normalize(shipVelocity) * maxSpeed
        }

        // Update position
        shipNode.simdPosition += shipVelocity * dt
    }

    // MARK: - Engine Flame

    private func updateEngineFlame() {
        guard let flame = engineFlame else { return }
        EngineFlameBuilder.updateIntensity(flame, throttle: currentInput.throttle)
    }

    // MARK: - Camera

    private func updateCamera(dt: Float) {
        let input = currentInput

        // Right stick orbits camera
        if abs(input.cameraX) > 0.05 || abs(input.cameraY) > 0.05 {
            cameraAzimuth += input.cameraX * cameraOrbitSpeed * dt
            cameraElevation += input.cameraY * cameraOrbitSpeed * dt
            cameraElevation = max(-0.8, min(1.2, cameraElevation))  // Clamp vertical
        } else {
            // Return to behind-ship when stick released
            cameraAzimuth *= (1.0 - cameraReturnSpeed * dt)
            cameraElevation += (0.2 - cameraElevation) * cameraReturnSpeed * dt
        }

        // Camera rig follows ship position (lerped for smooth chase)
        let targetPos = shipNode.simdPosition
        let currentPos = cameraRig.simdPosition
        cameraRig.simdPosition = simd_mix(currentPos, targetPos, SIMD3<Float>(repeating: cameraFollowSpeed * dt))

        // Position camera on sphere around rig using spherical coords
        let x = cameraDistance * cos(cameraElevation) * sin(cameraAzimuth)
        let y = cameraDistance * sin(cameraElevation)
        let z = cameraDistance * cos(cameraElevation) * cos(cameraAzimuth)
        thirdPersonCamera.simdPosition = SIMD3<Float>(x, y, z)

        // Look at the ship (slightly ahead of rig center)
        thirdPersonCamera.look(at: SCNVector3(shipNode.simdPosition))
    }

    // MARK: - Weapons

    private func updateWeapons(dt: Float) {
        weaponSystem.update(deltaTime: dt)

        let input = currentInput

        // Continuous laser fire while held
        if input.laserHeld {
            _ = weaponSystem.fireLaser(from: shipNode, into: projectilesContainer)
        }

        // Edge-detected missile fire
        if input.fireMissile {
            _ = weaponSystem.fireMissile(from: shipNode, into: projectilesContainer)
        }
    }

    // MARK: - Aliens

    private func updateAliens(dt: Float) {
        for i in aliens.indices {
            if aliens[i].isAlive {
                aliens[i].updateMovement(deltaTime: dt)
            } else {
                if aliens[i].updateRespawn(deltaTime: dt) {
                    // Just respawned — update node position
                    aliens[i].updateMovement(deltaTime: 0)
                }
            }
        }
    }

    // MARK: - Game State (HUD updates)

    private func updateGameState() {
        let speed = simd_length(shipVelocity)
        gameState.throttlePercent = currentInput.throttle
        gameState.speedDisplay = speed
        gameState.laserCooldownPercent = weaponSystem.laserCooldownPercent
        gameState.missileCooldownPercent = weaponSystem.missileCooldownPercent
    }

    // MARK: - Haptics

    private func updateHaptics() {
        // Engine rumble proportional to throttle (weak motor only)
        let engineRumble = UInt8(min(255, currentInput.throttle * 80))
        rumbleOutput?(engineRumble, 0)
    }

    // MARK: - SCNPhysicsContactDelegate

    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        handleContact(contact)
    }

    private func handleContact(_ contact: SCNPhysicsContact) {
        let nodeA = contact.nodeA
        let nodeB = contact.nodeB
        let catA = nodeA.physicsBody?.categoryBitMask ?? 0
        let catB = nodeB.physicsBody?.categoryBitMask ?? 0

        // Determine which is the projectile and which is the alien
        let alienNode: SCNNode
        let projectileNode: SCNNode
        let damage: Int

        if catA == PhysicsCategory.alien && (catB == PhysicsCategory.laser || catB == PhysicsCategory.missile) {
            alienNode = nodeA
            projectileNode = nodeB
            damage = catB == PhysicsCategory.missile ? 2 : 1
        } else if catB == PhysicsCategory.alien && (catA == PhysicsCategory.laser || catA == PhysicsCategory.missile) {
            alienNode = nodeB
            projectileNode = nodeA
            damage = catA == PhysicsCategory.missile ? 2 : 1
        } else {
            return
        }

        // Remove projectile
        projectileNode.removeFromParentNode()

        // Find and damage the alien
        guard let index = aliens.firstIndex(where: { $0.node === alienNode }) else { return }
        let killed = aliens[index].applyDamage(damage)

        if killed {
            // Spawn explosion at alien's position
            ExplosionBuilder.spawnExplosion(at: alienNode.worldPosition, in: explosionsContainer)

            // Update score
            gameState.addScore(points: aliens[index].type.points)

            // Haptic pulse on kill
            rumbleOutput?(200, 150)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.rumbleOutput?(0, 0)
            }
        } else {
            // Hit flash — brief opacity dip
            alienNode.runAction(.sequence([
                .fadeOpacity(to: 0.3, duration: 0.05),
                .fadeOpacity(to: 1.0, duration: 0.1),
            ]))

            // Small haptic bump on hit
            rumbleOutput?(100, 60)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.rumbleOutput?(0, 0)
            }
        }
    }

    // MARK: - Alien Spawning

    private func spawnInitialAliens() {
        let types = AlienType.allCases
        for i in 0..<alienCount {
            let type = types[i % types.count]
            let node = AlienShipBuilder.build(type: type)
            let radius = Float.random(in: 30...80)

            var state = AlienState(node: node, type: type, orbitRadius: radius)
            state.updateMovement(deltaTime: 0)  // Set initial position
            aliensContainer.addChildNode(node)
            aliens.append(state)
        }
    }

    // MARK: - Player Ship Builder

    private static func buildPlayerShip() -> SCNNode {
        let ship = SCNNode()
        ship.name = "playerShip"

        // Fuselage
        let fuselageGeo = SCNCylinder(radius: 0.3, height: 3.0)
        fuselageGeo.radialSegmentCount = 24
        fuselageGeo.firstMaterial = metalMaterial(
            diffuse: NSColor(white: 0.7, alpha: 1),
            metalness: 0.8, roughness: 0.3
        )
        let fuselage = SCNNode(geometry: fuselageGeo)
        fuselage.name = "fuselage"
        fuselage.eulerAngles.x = .pi / 2
        ship.addChildNode(fuselage)

        // Nose cone
        let noseGeo = SCNCone(topRadius: 0, bottomRadius: 0.3, height: 0.8)
        noseGeo.radialSegmentCount = 24
        noseGeo.firstMaterial = metalMaterial(
            diffuse: NSColor(white: 0.6, alpha: 1),
            metalness: 0.9, roughness: 0.2
        )
        let nose = SCNNode(geometry: noseGeo)
        nose.name = "nose"
        nose.eulerAngles.x = -.pi / 2
        nose.position = SCNVector3(0, 0, -1.9)
        ship.addChildNode(nose)

        // Wings
        let wingGeo = SCNBox(width: 2.5, height: 0.05, length: 1.2, chamferRadius: 0.02)
        wingGeo.firstMaterial = metalMaterial(
            diffuse: NSColor(white: 0.65, alpha: 1),
            metalness: 0.7, roughness: 0.35
        )

        let leftWing = SCNNode(geometry: wingGeo)
        leftWing.name = "leftWing"
        leftWing.position = SCNVector3(-1.2, 0, 0.3)
        leftWing.eulerAngles.z = .pi * 0.02
        ship.addChildNode(leftWing)

        let rightWing = SCNNode(geometry: wingGeo)
        rightWing.name = "rightWing"
        rightWing.position = SCNVector3(1.2, 0, 0.3)
        rightWing.eulerAngles.z = -.pi * 0.02
        ship.addChildNode(rightWing)

        // Tail fin
        let tailGeo = SCNBox(width: 0.05, height: 0.8, length: 0.6, chamferRadius: 0.02)
        tailGeo.firstMaterial = metalMaterial(
            diffuse: NSColor(white: 0.6, alpha: 1),
            metalness: 0.7, roughness: 0.3
        )
        let tail = SCNNode(geometry: tailGeo)
        tail.name = "tailFin"
        tail.position = SCNVector3(0, 0.5, 1.3)
        ship.addChildNode(tail)

        // Engine glow
        let engineGeo = SCNSphere(radius: 0.22)
        engineGeo.segmentCount = 16
        let engineMat = SCNMaterial()
        engineMat.emission.contents = NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0)
        engineMat.diffuse.contents = NSColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 0.6)
        engineMat.lightingModel = .constant
        engineGeo.firstMaterial = engineMat
        let engine = SCNNode(geometry: engineGeo)
        engine.name = "engineGlow"
        engine.position = SCNVector3(0, 0, 1.7)
        ship.addChildNode(engine)

        // Cockpit
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

        // Weapon spawn points (empty nodes marking positions)
        let laserOrigin = SCNNode()
        laserOrigin.name = "laserOrigin"
        laserOrigin.position = SCNVector3(0, 0, -2.3)  // Nose tip
        ship.addChildNode(laserOrigin)

        let missileLeft = SCNNode()
        missileLeft.name = "missileOriginLeft"
        missileLeft.position = SCNVector3(-1.0, -0.1, 0)  // Under left wing
        ship.addChildNode(missileLeft)

        let missileRight = SCNNode()
        missileRight.name = "missileOriginRight"
        missileRight.position = SCNVector3(1.0, -0.1, 0)  // Under right wing
        ship.addChildNode(missileRight)

        // Player physics body (kinematic — we control position directly)
        ship.physicsBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: SCNSphere(radius: 1.5), options: nil))
        ship.physicsBody?.categoryBitMask = PhysicsCategory.player
        ship.physicsBody?.contactTestBitMask = 0
        ship.physicsBody?.collisionBitMask = 0

        return ship
    }

    // MARK: - Cameras

    private static func buildThirdPersonCamera() -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 60
        camera.zNear = 0.1
        camera.zFar = 500

        let node = SCNNode()
        node.name = "thirdPersonCamera"
        node.camera = camera
        node.position = SCNVector3(0, 3, 12)
        return node
    }

    private static func buildFirstPersonCamera() -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 90
        camera.zNear = 0.1
        camera.zFar = 500

        let node = SCNNode()
        node.name = "firstPersonCamera"
        node.camera = camera
        node.position = SCNVector3(0, 0.3, -1.0)
        return node
    }

    // MARK: - Lighting

    private static func addLighting(to scene: SCNScene) {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 200
        ambient.color = NSColor(white: 0.3, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.name = "ambientLight"
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

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
        let starfieldNode = SCNNode()
        starfieldNode.name = "starfield"

        let starGeo = SCNSphere(radius: 0.15)
        starGeo.segmentCount = 4
        let starMat = SCNMaterial()
        starMat.diffuse.contents = NSColor.white
        starMat.lightingModel = .constant
        starGeo.firstMaterial = starMat

        let starCount = 1500
        let radius: CGFloat = 200.0  // Larger radius since ship moves around

        for i in 0..<starCount {
            let star = SCNNode(geometry: starGeo)
            star.name = "star_\(i)"

            let u = CGFloat.random(in: 0...1)
            let v = CGFloat.random(in: 0...1)
            let theta = 2.0 * CGFloat.pi * u
            let phi = acos(2.0 * v - 1.0)

            star.position = SCNVector3(
                radius * sin(phi) * cos(theta),
                radius * sin(phi) * sin(theta),
                radius * cos(phi)
            )

            let brightness = CGFloat.random(in: 0.3...1.0)
            let size = CGFloat.random(in: 0.05...0.2)
            star.scale = SCNVector3(size, size, size)
            star.opacity = brightness

            starfieldNode.addChildNode(star)
        }

        let flatStarfield = starfieldNode.flattenedClone()
        flatStarfield.name = "starfield"
        scene.rootNode.addChildNode(flatStarfield)
    }

    // MARK: - Material Helper

    private static func metalMaterial(diffuse: NSColor, metalness: CGFloat, roughness: CGFloat) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = diffuse
        mat.metalness.contents = metalness
        mat.roughness.contents = roughness
        mat.lightingModel = .physicallyBased
        return mat
    }
}
