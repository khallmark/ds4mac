// SpaceCombatWindow.swift — SwiftUI window hosting the space combat mini-game.
//
// Bridges DS4 controller input to GameSceneController:
// - IMU → OrientationFilter → ship orientation
// - Sticks/triggers/buttons → InputMapper → GameInputState snapshot
// - SceneView renders continuously with the game controller as delegate
// - HUDOverlay observes GameState for score, cooldowns, throttle

import SwiftUI
import SceneKit
import DS4Protocol
import DS4Transport

struct SpaceCombatWindow: View {
    @Environment(DS4TransportManager.self) var manager

    @State private var orientationFilter = OrientationFilter()
    @State private var gameState = GameState()
    @State private var gameController: GameSceneController?
    @State private var isFirstPerson = false
    @State private var previousInput: DS4InputState?

    var body: some View {
        ZStack {
            if let gc = gameController {
                // SceneKit 3D view
                SceneView(
                    scene: gc.scene,
                    pointOfView: isFirstPerson ? gc.firstPersonCamera : gc.thirdPersonCamera,
                    options: [.rendersContinuously],
                    delegate: gc
                )
                .ignoresSafeArea()

                // HUD overlay
                HUDOverlay(
                    gameState: gameState,
                    isFirstPerson: $isFirstPerson,
                    onResetGyro: { orientationFilter.setLevel() }
                )
            } else {
                ProgressView("Initializing...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            let gc = GameSceneController(gameState: gameState)
            gc.rumbleOutput = { [weak manager] light, heavy in
                DispatchQueue.main.async {
                    manager?.setRumble(heavy: heavy, light: light)
                }
            }
            gameController = gc
            orientationFilter.calibrationData = manager.calibrationData
        }
        .onChange(of: manager.calibrationData) { _, newCal in
            orientationFilter.calibrationData = newCal
        }
        .onChange(of: manager.inputState) { oldState, newState in
            guard let gc = gameController else { return }

            // Map controller input to game input with edge detection
            let mapped = InputMapper.map(current: newState, previous: previousInput)
            previousInput = newState
            gc.currentInput = mapped

            // Update ship orientation from gyroscope
            orientationFilter.update(from: newState.imu)
            gc.shipNode.simdOrientation = orientationFilter.displayOrientation

            // Handle toggle camera (edge-detected in mapped input)
            if mapped.toggleCamera {
                isFirstPerson.toggle()
                gc.isFirstPerson = isFirstPerson
            }

            // Handle gyro reset
            if mapped.resetOrientation {
                orientationFilter.setLevel()
            }

            // Handle set level
            if mapped.setLevel {
                orientationFilter.setLevel()
            }
        }
    }
}
