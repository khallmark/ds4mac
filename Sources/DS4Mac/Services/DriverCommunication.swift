// DriverCommunication.swift — IOUserClient wrapper for DS4Mac ↔ DS4Driver dext IPC
// Uses IOKit user client API (IOServiceOpen/IOConnectCallMethod) to call
// external methods exposed by DS4UserClient in the DriverKit extension.
//
// Selector IDs must match DS4UserClient.cpp's dispatch table:
//   0 = setLightBar(r, g, b)
//   1 = setRumble(heavy, light)
//   2 = getInputState()
//   3 = getBatteryState()
//
// Reference: docs/10-macOS-Driver-Architecture.md Section 3

import Foundation
import IOKit
import Observation

/// Communicates with the DS4Driver dext via IOUserClient external methods.
@Observable
final class DriverCommunication {

    // MARK: - Selector IDs (must match DS4UserClient.cpp)

    private enum Selector {
        static let setLightBar: UInt32        = 0
        static let setRumble: UInt32          = 1
        static let getInputState: UInt32      = 2
        static let getBatteryState: UInt32    = 3
        static let getCalibrationData: UInt32 = 4
        static let getCalibratedIMU: UInt32   = 5
    }

    /// The IOUserClient connection to the dext.
    private var connection: io_connect_t = IO_OBJECT_NULL

    /// Whether we have an active connection to the dext.
    var isConnected: Bool { connection != IO_OBJECT_NULL }

    // MARK: - Connection Lifecycle

    /// Open a connection to the DS4Driver dext's IOUserClient.
    /// The dext must be loaded and the DS4 device matched for this to succeed.
    func connect() throws {
        // Find the DS4HIDDevice service in the I/O Registry
        let matchingDict = IOServiceMatching("DS4HIDDevice")
        var service: io_service_t = IO_OBJECT_NULL
        var iterator: io_iterator_t = 0

        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matchingDict,
            &iterator
        )
        guard result == KERN_SUCCESS else {
            throw DriverError.serviceNotFound
        }

        service = IOIteratorNext(iterator)
        IOObjectRelease(iterator)

        guard service != IO_OBJECT_NULL else {
            throw DriverError.serviceNotFound
        }

        defer { IOObjectRelease(service) }

        // Open user client connection
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard openResult == KERN_SUCCESS else {
            throw DriverError.connectionFailed(openResult)
        }
    }

    /// Close the connection to the dext.
    func disconnect() {
        if connection != IO_OBJECT_NULL {
            IOServiceClose(connection)
            connection = IO_OBJECT_NULL
        }
    }

    deinit {
        disconnect()
    }

    // MARK: - External Methods

    /// Set the light bar color on the DS4 controller.
    func setLightBar(red: UInt8, green: UInt8, blue: UInt8) throws {
        guard isConnected else { throw DriverError.notConnected }

        var input: [UInt64] = [UInt64(red), UInt64(green), UInt64(blue)]
        let result = IOConnectCallScalarMethod(
            connection,
            Selector.setLightBar,
            &input,
            3,
            nil,
            nil
        )
        guard result == KERN_SUCCESS else {
            throw DriverError.methodFailed(Selector.setLightBar, result)
        }
    }

    /// Set the rumble motor intensity on the DS4 controller.
    func setRumble(heavy: UInt8, light: UInt8) throws {
        guard isConnected else { throw DriverError.notConnected }

        var input: [UInt64] = [UInt64(heavy), UInt64(light)]
        let result = IOConnectCallScalarMethod(
            connection,
            Selector.setRumble,
            &input,
            2,
            nil,
            nil
        )
        guard result == KERN_SUCCESS else {
            throw DriverError.methodFailed(Selector.setRumble, result)
        }
    }

    /// Read the current battery state from the DS4 controller.
    func getBatteryState() throws -> (level: UInt8, cable: Bool, headphones: Bool, mic: Bool) {
        guard isConnected else { throw DriverError.notConnected }

        var output = [UInt64](repeating: 0, count: 4)
        var outputCount: UInt32 = 4
        let result = IOConnectCallScalarMethod(
            connection,
            Selector.getBatteryState,
            nil,
            0,
            &output,
            &outputCount
        )
        guard result == KERN_SUCCESS else {
            throw DriverError.methodFailed(Selector.getBatteryState, result)
        }

        return (
            level: UInt8(output[0] & 0xFF),
            cable: output[1] != 0,
            headphones: output[2] != 0,
            mic: output[3] != 0
        )
    }

    /// Read the current parsed input state from the DS4 controller via the dext.
    /// Returns the raw bytes of the C++ DS4InputState struct.
    func getInputState() throws -> [UInt8] {
        guard isConnected else { throw DriverError.notConnected }

        // Buffer must be large enough for the C++ DS4InputState struct.
        // The struct is ~80 bytes on arm64; use 256 as a safe upper bound.
        var outputSize = 256
        var outputBuffer = [UInt8](repeating: 0, count: outputSize)

        let result = outputBuffer.withUnsafeMutableBytes { ptr -> kern_return_t in
            IOConnectCallStructMethod(
                connection,
                Selector.getInputState,
                nil,
                0,
                ptr.baseAddress,
                &outputSize
            )
        }
        guard result == KERN_SUCCESS else {
            throw DriverError.methodFailed(Selector.getInputState, result)
        }

        return Array(outputBuffer.prefix(outputSize))
    }

    /// Read the IMU calibration data from the dext.
    /// Returns raw bytes of the C++ DS4CalibrationData struct.
    func getCalibrationData() throws -> [UInt8] {
        guard isConnected else { throw DriverError.notConnected }

        // DS4CalibrationData is ~39 bytes (17 × int16 + bool + padding); use 64 as safe bound.
        var outputSize = 64
        var outputBuffer = [UInt8](repeating: 0, count: outputSize)

        let result = outputBuffer.withUnsafeMutableBytes { ptr -> kern_return_t in
            IOConnectCallStructMethod(
                connection,
                Selector.getCalibrationData,
                nil,
                0,
                ptr.baseAddress,
                &outputSize
            )
        }
        guard result == KERN_SUCCESS else {
            throw DriverError.methodFailed(Selector.getCalibrationData, result)
        }

        return Array(outputBuffer.prefix(outputSize))
    }

    /// Read the current calibrated IMU values (degrees/sec + g-force) from the dext.
    /// Returns raw bytes of the C++ DS4CalibratedIMU struct (6 doubles = 48 bytes).
    func getCalibratedIMU() throws -> [UInt8] {
        guard isConnected else { throw DriverError.notConnected }

        // DS4CalibratedIMU is 6 × double = 48 bytes; use 64 as safe bound.
        var outputSize = 64
        var outputBuffer = [UInt8](repeating: 0, count: outputSize)

        let result = outputBuffer.withUnsafeMutableBytes { ptr -> kern_return_t in
            IOConnectCallStructMethod(
                connection,
                Selector.getCalibratedIMU,
                nil,
                0,
                ptr.baseAddress,
                &outputSize
            )
        }
        guard result == KERN_SUCCESS else {
            throw DriverError.methodFailed(Selector.getCalibratedIMU, result)
        }

        return Array(outputBuffer.prefix(outputSize))
    }

    // MARK: - Errors

    enum DriverError: Error, LocalizedError {
        case serviceNotFound
        case connectionFailed(kern_return_t)
        case notConnected
        case methodFailed(UInt32, kern_return_t)

        var errorDescription: String? {
            switch self {
            case .serviceNotFound:
                return "DS4Driver service not found in I/O Registry. Is the extension loaded?"
            case .connectionFailed(let kr):
                return "Failed to open IOUserClient connection: 0x\(String(kr, radix: 16))"
            case .notConnected:
                return "Not connected to DS4Driver"
            case .methodFailed(let selector, let kr):
                return "External method \(selector) failed: 0x\(String(kr, radix: 16))"
            }
        }
    }
}
