// TrackpadView.swift — Settings UI for DS4 touchpad-as-trackpad emulation
// Inspector tab with permission status, enable toggle, sensitivity sliders, and live gesture status.

import SwiftUI
import DS4Transport

struct TrackpadView: View {
    @Environment(DS4TransportManager.self) var manager
    @Environment(DS4TrackpadManager.self) var trackpadManager

    @AppStorage("trackpadEnabled") private var trackpadEnabled = false
    @AppStorage("cursorSensitivity") private var cursorSensitivity = 1.0
    @AppStorage("scrollSensitivity") private var scrollSensitivity = 1.0
    @AppStorage("pinchSensitivity") private var pinchSensitivity = 1.0
    @AppStorage("naturalScrolling") private var naturalScrolling = true

    var body: some View {
        VStack(spacing: 16) {
            if !trackpadManager.hasAccessibilityPermission {
                permissionSection
            }

            enableSection
            sensitivitySection
            scrollSection
            statusSection

            Spacer()
        }
        .padding()
        .onAppear {
            trackpadManager.checkAccessibilityPermission()
            syncSettings()
        }
        .onChange(of: trackpadEnabled) { _, new in
            trackpadManager.setEnabled(new)
        }
        .onChange(of: cursorSensitivity) { _, new in
            trackpadManager.cursorSensitivity = new
        }
        .onChange(of: scrollSensitivity) { _, new in
            trackpadManager.scrollSensitivity = new
        }
        .onChange(of: pinchSensitivity) { _, new in
            trackpadManager.pinchSensitivity = new
        }
        .onChange(of: naturalScrolling) { _, new in
            trackpadManager.naturalScrolling = new
        }
    }

    // MARK: - Permission Section

    private var permissionSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Accessibility Permission Required", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.headline)

                Text("DS4Mac needs Accessibility access to move the cursor and simulate clicks. Grant access in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Grant Access") {
                    trackpadManager.requestAccessibilityPermission()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    // MARK: - Enable Section

    private var enableSection: some View {
        GroupBox {
            Toggle(isOn: $trackpadEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Trackpad")
                        .font(.headline)
                    Text("Use the DS4 touchpad as a macOS trackpad")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!trackpadManager.hasAccessibilityPermission
                      || manager.connectionState != .connected)
            .padding(4)
        }
    }

    // MARK: - Sensitivity Section

    private var sensitivitySection: some View {
        GroupBox("Sensitivity") {
            VStack(spacing: 12) {
                sensitivitySlider(label: "Cursor Speed", value: $cursorSensitivity)
                sensitivitySlider(label: "Scroll Speed", value: $scrollSensitivity)
                sensitivitySlider(label: "Pinch Speed", value: $pinchSensitivity)
            }
            .padding(4)
        }
        .disabled(!trackpadEnabled)
    }

    private func sensitivitySlider(label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.1fx", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0.2...3.0, step: 0.1)
        }
    }

    // MARK: - Scroll Section

    private var scrollSection: some View {
        GroupBox("Scrolling") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Natural Scrolling", isOn: $naturalScrolling)

                Text("When enabled, content moves in the direction your fingers move (like a touchscreen).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
        .disabled(!trackpadEnabled)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        GroupBox("Status") {
            VStack(spacing: 8) {
                HStack {
                    Text("Gesture")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(trackpadManager.currentGesture.rawValue)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(gestureColor)
                }

                HStack {
                    Text("Touches")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(trackpadManager.activeTouchCount)")
                        .font(.body.monospacedDigit())
                }

                HStack {
                    Text("Permission")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: trackpadManager.hasAccessibilityPermission
                          ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(trackpadManager.hasAccessibilityPermission ? .green : .red)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Helpers

    private var gestureColor: Color {
        switch trackpadManager.currentGesture {
        case .idle: return .secondary
        case .cursor: return .blue
        case .scroll: return .green
        case .pinch: return .orange
        }
    }

    private func syncSettings() {
        trackpadManager.cursorSensitivity = cursorSensitivity
        trackpadManager.scrollSensitivity = scrollSensitivity
        trackpadManager.pinchSensitivity = pinchSensitivity
        trackpadManager.naturalScrolling = naturalScrolling
        if trackpadEnabled {
            trackpadManager.setEnabled(true)
        }
    }
}
