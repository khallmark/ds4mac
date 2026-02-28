// ExtensionManager.swift — SystemExtensions framework integration for DS4Driver dext
// Handles activation, deactivation, and lifecycle of the DriverKit system extension.
// Reference: docs/10-macOS-Driver-Architecture.md Section 7.3

import Foundation
import Observation
import SystemExtensions

/// Manages the DS4Driver DriverKit system extension lifecycle.
/// Provides activation/deactivation and tracks the current extension state.
@MainActor
@Observable
final class ExtensionManager: NSObject {

    /// Current state of the system extension.
    enum ExtensionState: String {
        case unknown        = "Unknown"
        case notInstalled   = "Not Installed"
        case activating     = "Activating..."
        case needsApproval  = "Needs Approval"
        case active         = "Active"
        case deactivating   = "Deactivating..."
        case failed         = "Failed"
    }

    /// Bundle identifier of the DriverKit system extension.
    /// Must match the CFBundleIdentifier in DS4Driver/Info.plist.
    static let dextIdentifier = "com.ds4mac.driver.DS4Driver"

    private(set) var state: ExtensionState = .unknown
    private(set) var lastError: String?

    /// Request activation of the DS4Driver system extension.
    /// macOS will prompt the user to approve in System Settings.
    func activateDriver() {
        state = .activating
        lastError = nil

        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: Self.dextIdentifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Request deactivation of the DS4Driver system extension.
    func deactivateDriver() {
        state = .deactivating
        lastError = nil

        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: Self.dextIdentifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
}

// MARK: - OSSystemExtensionRequestDelegate

extension ExtensionManager: OSSystemExtensionRequestDelegate {

    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        Task { @MainActor in
            switch result {
            case .completed:
                state = .active
                lastError = nil
            case .willCompleteAfterReboot:
                state = .needsApproval
                lastError = "Extension will activate after reboot"
            @unknown default:
                state = .unknown
                lastError = "Unknown result: \(result.rawValue)"
            }
        }
    }

    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            state = .failed
            lastError = error.localizedDescription
        }
    }

    nonisolated func requestNeedsUserApproval(
        _ request: OSSystemExtensionRequest
    ) {
        Task { @MainActor in
            state = .needsApproval
            lastError = nil
        }
    }

    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        // Allow replacing an older version with a newer one
        return .replace
    }
}
