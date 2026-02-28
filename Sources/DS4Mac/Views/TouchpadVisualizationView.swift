// TouchpadVisualizationView.swift — Scaled touchpad with live touch point visualization
// Shows the DS4 capacitive touchpad area (1920x943) with up to 2 touch dots.

import SwiftUI
import DS4Protocol
import DS4Transport

struct TouchpadVisualizationView: View {
    @EnvironmentObject var manager: DS4TransportManager

    // DS4 touchpad resolution
    private let touchMaxX: CGFloat = 1920
    private let touchMaxY: CGFloat = 943

    var body: some View {
        ScrollView {
            if manager.connectionState != .connected {
                ContentUnavailableView(
                    "No Controller Connected",
                    systemImage: "hand.point.up",
                    description: Text("Connect a DualShock 4 to see touchpad input.")
                )
            } else {
                VStack(spacing: 20) {
                    touchpadCanvas
                    touchDetails
                }
                .padding()
            }
        }
        .navigationTitle("Touchpad")
    }

    // MARK: - Touchpad Canvas

    @ViewBuilder
    private var touchpadCanvas: some View {
        let tp = manager.inputState.touchpad

        GroupBox("Touchpad Surface") {
            GeometryReader { geo in
                let padWidth = geo.size.width
                let padHeight = padWidth * (touchMaxY / touchMaxX)

                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.textBackgroundColor).opacity(0.5))
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)

                    // Grid lines
                    gridOverlay(width: padWidth, height: padHeight)

                    // Touch 0
                    if tp.touch0.active {
                        touchDot(
                            finger: tp.touch0,
                            color: .accentColor,
                            padWidth: padWidth,
                            padHeight: padHeight
                        )
                    }

                    // Touch 1
                    if tp.touch1.active {
                        touchDot(
                            finger: tp.touch1,
                            color: .orange,
                            padWidth: padWidth,
                            padHeight: padHeight
                        )
                    }

                    // "No touch" indicator
                    if !tp.touch0.active && !tp.touch1.active {
                        Text("No touch detected")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: padWidth, height: padHeight)
            }
            .aspectRatio(touchMaxX / touchMaxY, contentMode: .fit)
            .frame(maxWidth: 500)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Grid Overlay

    private func gridOverlay(width: CGFloat, height: CGFloat) -> some View {
        Canvas { ctx, size in
            let lineColor = Color.secondary.opacity(0.1)
            let cols = 8
            let rows = 4

            for i in 1..<cols {
                let x = CGFloat(i) / CGFloat(cols) * size.width
                ctx.stroke(
                    Path { p in p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: size.height)) },
                    with: .color(lineColor), lineWidth: 0.5
                )
            }
            for i in 1..<rows {
                let y = CGFloat(i) / CGFloat(rows) * size.height
                ctx.stroke(
                    Path { p in p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: size.width, y: y)) },
                    with: .color(lineColor), lineWidth: 0.5
                )
            }

            // Center crosshair
            let cx = size.width / 2
            let cy = size.height / 2
            ctx.stroke(
                Path { p in p.move(to: .init(x: cx - 8, y: cy)); p.addLine(to: .init(x: cx + 8, y: cy)) },
                with: .color(Color.secondary.opacity(0.3)), lineWidth: 1
            )
            ctx.stroke(
                Path { p in p.move(to: .init(x: cx, y: cy - 8)); p.addLine(to: .init(x: cx, y: cy + 8)) },
                with: .color(Color.secondary.opacity(0.3)), lineWidth: 1
            )
        }
    }

    // MARK: - Touch Dot

    private func touchDot(finger: DS4TouchFinger, color: Color, padWidth: CGFloat, padHeight: CGFloat) -> some View {
        let x = CGFloat(finger.x) / touchMaxX * padWidth
        let y = CGFloat(finger.y) / touchMaxY * padHeight

        return ZStack {
            // Outer glow
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 32, height: 32)

            // Inner dot
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
                .shadow(color: color.opacity(0.5), radius: 4)

            // ID label
            Text("\(finger.trackingID)")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .position(x: x, y: y)
    }

    // MARK: - Touch Details

    @ViewBuilder
    private var touchDetails: some View {
        let tp = manager.inputState.touchpad

        GroupBox("Touch Data") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                    Text("Touch 0")
                        .fontWeight(.medium)
                    if tp.touch0.active {
                        Text("ID \(tp.touch0.trackingID)")
                            .foregroundStyle(.secondary)
                        Text("(\(tp.touch0.x), \(tp.touch0.y))")
                            .monospacedDigit()
                    } else {
                        Text("Inactive")
                            .foregroundStyle(.secondary)
                        Text("")
                    }
                }
                GridRow {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                    Text("Touch 1")
                        .fontWeight(.medium)
                    if tp.touch1.active {
                        Text("ID \(tp.touch1.trackingID)")
                            .foregroundStyle(.secondary)
                        Text("(\(tp.touch1.x), \(tp.touch1.y))")
                            .monospacedDigit()
                    } else {
                        Text("Inactive")
                            .foregroundStyle(.secondary)
                        Text("")
                    }
                }
                GridRow {
                    Color.clear.frame(width: 8, height: 8)
                    Text("Packet")
                        .fontWeight(.medium)
                    Text("\(tp.packetCounter)")
                        .monospacedDigit()
                    Text("")
                }
            }
            .font(.system(.caption))
            .padding(.vertical, 4)
        }
    }
}
