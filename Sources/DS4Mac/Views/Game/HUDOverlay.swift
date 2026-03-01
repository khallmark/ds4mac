// HUDOverlay.swift — SwiftUI overlay for the space combat game.
// Displays score, crosshair, throttle bar, weapon cooldowns, and control buttons.
// Observes GameState (updated each frame by GameSceneController).

import SwiftUI

struct HUDOverlay: View {
    let gameState: GameState
    @Binding var isFirstPerson: Bool
    var onResetGyro: () -> Void

    var body: some View {
        ZStack {
            // Crosshair (center)
            crosshair

            // Top-left: score
            VStack(alignment: .leading, spacing: 4) {
                scoreDisplay
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            // Bottom-left: flight instruments
            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                throttleBar
                speedReadout
                cooldownBars
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            // Top-right: controls
            VStack(alignment: .trailing, spacing: 8) {
                controlButtons
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding()
        }
        .allowsHitTesting(true)
    }

    // MARK: - Crosshair

    @ViewBuilder
    private var crosshair: some View {
        Image(systemName: "plus")
            .font(.system(size: 24, weight: .thin))
            .foregroundStyle(.white.opacity(0.6))
    }

    // MARK: - Score

    @ViewBuilder
    private var scoreDisplay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(gameState.score)")
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Text("\(gameState.aliensDestroyed) destroyed")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(10)
        .background(.black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Throttle Bar

    @ViewBuilder
    private var throttleBar: some View {
        HStack(spacing: 6) {
            Text("THR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 28, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.15))

                    // Fill bar
                    RoundedRectangle(cornerRadius: 3)
                        .fill(throttleColor)
                        .frame(width: geo.size.width * CGFloat(gameState.throttlePercent))
                }
            }
            .frame(width: 100, height: 8)

            Text("\(Int(gameState.throttlePercent * 100))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var throttleColor: Color {
        let t = gameState.throttlePercent
        if t > 0.8 { return .orange }
        if t > 0.5 { return .yellow }
        return .cyan
    }

    // MARK: - Speed

    @ViewBuilder
    private var speedReadout: some View {
        HStack(spacing: 6) {
            Text("SPD")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 28, alignment: .trailing)

            Text(String(format: "%.0f u/s", gameState.speedDisplay))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: - Cooldown Bars

    @ViewBuilder
    private var cooldownBars: some View {
        cooldownBar(label: "LZR", percent: gameState.laserCooldownPercent, color: .cyan)
        cooldownBar(label: "MSL", percent: gameState.missileCooldownPercent, color: .orange)
    }

    @ViewBuilder
    private func cooldownBar(label: String, percent: Float, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 28, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.15))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(percent <= 0 ? color : color.opacity(0.3))
                        .frame(width: geo.size.width * CGFloat(1.0 - percent))
                }
            }
            .frame(width: 100, height: 8)

            Text(percent <= 0 ? "RDY" : String(format: "%.1fs", percent))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(percent <= 0 ? color : .white.opacity(0.5))
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Control Buttons

    @ViewBuilder
    private var controlButtons: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button {
                isFirstPerson.toggle()
            } label: {
                Label(
                    isFirstPerson ? "Third Person" : "First Person",
                    systemImage: isFirstPerson ? "eye" : "airplane"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                onResetGyro()
            } label: {
                Label("Set Level", systemImage: "level")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
