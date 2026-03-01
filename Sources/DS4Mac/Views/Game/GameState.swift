// GameState.swift — Observable game state driving the HUD overlay.
// Updated by GameSceneController each frame, observed by HUDOverlay via SwiftUI.

import Observation

@Observable
final class GameState {
    var score: Int = 0
    var aliensDestroyed: Int = 0

    // HUD display values (updated each frame by game loop)
    var throttlePercent: Float = 0         // 0.0-1.0
    var speedDisplay: Float = 0            // current speed in units/s
    var laserCooldownPercent: Float = 0    // 0=ready, 1=full cooldown
    var missileCooldownPercent: Float = 0  // 0=ready, 1=full cooldown
    var isPlaying: Bool = true

    func addScore(points: Int) {
        score += points
        aliensDestroyed += 1
    }

    func reset() {
        score = 0
        aliensDestroyed = 0
        throttlePercent = 0
        speedDisplay = 0
        laserCooldownPercent = 0
        missileCooldownPercent = 0
        isPlaying = true
    }
}
