// DS4HIDManager.swift — IOHIDManager wrapper for DualShock 4 controller discovery and communication
// Handles device matching, input report polling, output report sending, and feature report access.

import Foundation
import IOKit
import IOKit.hid
import DS4Protocol

/// Manages a connection to a DualShock 4 controller via IOKit HID.
///
/// Typical usage:
/// 1. Call `open()` to discover and connect to the first available DS4
/// 2. Optionally read feature reports (e.g., 0x02 to trigger BT extended mode)
/// 3. Start input report polling with a callback
/// 4. Send output reports for LED/rumble control
/// 5. Call `close()` when done
final class DS4HIDManager {

    // MARK: - Properties

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var deviceInfo: DS4DeviceInfo?
    /// Persistent buffer for IOKit to write input reports into.
    /// Allocated once and kept alive for the lifetime of this manager.
    private var reportBufferPtr: UnsafeMutablePointer<UInt8>?
    private var reportBufferSize: Int = 0
    fileprivate var inputCallback: (([UInt8]) -> Void)?
    private var isOpen = false

    deinit {
        reportBufferPtr?.deallocate()
    }

    // MARK: - Open / Discovery

    /// Discover and open the first connected DualShock 4 controller.
    ///
    /// Creates an IOHIDManager, sets matching criteria for Sony DS4 V1, V2, and Wireless Adapter,
    /// then attempts to copy the set of matched devices.
    ///
    /// - Returns: A `DS4DeviceInfo` describing the connected device, or `nil` if no DS4 found.
    func open() -> DS4DeviceInfo? {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr

        // Build matching dictionaries for DS4 V1, V2, and Sony Wireless Adapter
        let matchV1 = createMatchingDict(vendorID: DS4DeviceID.vendorID, productID: DS4DeviceID.ds4V1PID)
        let matchV2 = createMatchingDict(vendorID: DS4DeviceID.vendorID, productID: DS4DeviceID.ds4V2PID)
        let matchDongle = createMatchingDict(vendorID: DS4DeviceID.vendorID, productID: DS4DeviceID.donglePID)

        IOHIDManagerSetDeviceMatchingMultiple(mgr, [matchV1, matchV2, matchDongle] as CFArray)

        // Schedule with the current run loop so device matching works
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        // Open the manager
        let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            fputs("Error: IOHIDManagerOpen failed with code \(openResult)\n", stderr)
            return nil
        }

        // Copy the set of matched devices — use safe CF bridging
        guard let deviceSetRef = IOHIDManagerCopyDevices(mgr) else {
            fputs("Error: No HID devices matched\n", stderr)
            return nil
        }

        // Bridge CFSet to Swift array — CF types always succeed in downcast
        let deviceArray: [IOHIDDevice]
        if let deviceSet = deviceSetRef as? Set<IOHIDDevice> {
            deviceArray = Array(deviceSet)
        } else {
            // Fallback: bridge through NSSet
            let nsSet = deviceSetRef as NSSet
            deviceArray = nsSet.allObjects.map { $0 as! IOHIDDevice }
        }
        guard let firstDevice = deviceArray.first else {
            fputs("Error: Matched device set was empty\n", stderr)
            return nil
        }

        device = firstDevice
        isOpen = true

        // Open the device itself for exclusive access
        let devOpenResult = IOHIDDeviceOpen(firstDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        if devOpenResult != kIOReturnSuccess {
            fputs("Warning: IOHIDDeviceOpen returned \(devOpenResult) — may still work\n", stderr)
        }

        // Extract device properties
        let info = extractDeviceInfo(from: firstDevice)
        deviceInfo = info
        return info
    }

    // MARK: - Input Report Polling

    /// Begin receiving input reports from the connected device.
    ///
    /// Allocates a persistent report buffer sized appropriately for the connection type
    /// (78 bytes for BT, 64 bytes for USB) and registers an IOHIDDevice input report callback.
    ///
    /// - Parameter callback: Closure invoked with each raw report byte array on the run loop thread.
    func startInputReportPolling(callback: @escaping ([UInt8]) -> Void) {
        guard let dev = device, let info = deviceInfo else {
            fputs("Error: No device open for input report polling\n", stderr)
            return
        }

        inputCallback = callback

        // Allocate a persistent buffer that outlives withUnsafeMutableBufferPointer closures.
        // IOKit writes into this buffer asynchronously, so it must remain valid until we
        // unregister the callback.
        let bufferSize = (info.connectionType == .bluetooth)
            ? DS4ReportSize.btInput
            : DS4ReportSize.usbInput

        // Deallocate any previous buffer
        reportBufferPtr?.deallocate()
        reportBufferPtr = .allocate(capacity: bufferSize)
        reportBufferPtr?.initialize(repeating: 0, count: bufferSize)
        reportBufferSize = bufferSize

        // Pass self as context via Unmanaged pointer
        let context = Unmanaged<DS4HIDManager>.passUnretained(self).toOpaque()

        IOHIDDeviceRegisterInputReportCallback(
            dev,
            reportBufferPtr!,
            reportBufferSize,
            hidInputReportCallback,
            context
        )
    }

    // MARK: - Output Reports

    /// Send an output report to the connected device.
    ///
    /// - Parameter data: The complete report bytes including report ID at index 0.
    /// - Returns: `true` if the report was sent successfully.
    @discardableResult
    func sendOutputReport(_ data: [UInt8]) -> Bool {
        guard let dev = device, !data.isEmpty else {
            fputs("Error: No device open or empty report data\n", stderr)
            return false
        }

        let reportID = CFIndex(data[0])
        let result = data.withUnsafeBufferPointer { bufPtr -> IOReturn in
            guard let base = bufPtr.baseAddress else { return kIOReturnError }
            return IOHIDDeviceSetReport(
                dev,
                kIOHIDReportTypeOutput,
                reportID,
                base,
                data.count
            )
        }

        if result != kIOReturnSuccess {
            fputs("Error: IOHIDDeviceSetReport failed with code \(result)\n", stderr)
            return false
        }
        return true
    }

    // MARK: - Feature Reports

    /// Read a feature report from the connected device.
    ///
    /// This is needed for operations like reading calibration data (report 0x02) which also
    /// triggers the Bluetooth mode switch from reduced to extended input reports.
    ///
    /// - Parameters:
    ///   - reportID: The HID feature report ID to read.
    ///   - length: The expected report length in bytes.
    /// - Returns: The raw report bytes, or `nil` on failure.
    func readFeatureReport(reportID: UInt8, length: Int) -> [UInt8]? {
        guard let dev = device else {
            fputs("Error: No device open for feature report read\n", stderr)
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: length)
        var reportLength = CFIndex(length)

        let result = buffer.withUnsafeMutableBufferPointer { bufPtr -> IOReturn in
            guard let base = bufPtr.baseAddress else { return kIOReturnError }
            return IOHIDDeviceGetReport(
                dev,
                kIOHIDReportTypeFeature,
                CFIndex(reportID),
                base,
                &reportLength
            )
        }

        if result != kIOReturnSuccess {
            fputs("Error: IOHIDDeviceGetReport (feature 0x\(String(reportID, radix: 16))) failed with code \(result)\n", stderr)
            return nil
        }

        // Trim to actual returned length
        return Array(buffer.prefix(reportLength))
    }

    // MARK: - Close

    /// Close the device and HID manager, releasing all resources.
    func close() {
        // Unregister input report callback if it was registered
        if let dev = device, let buf = reportBufferPtr, reportBufferSize > 0 {
            IOHIDDeviceRegisterInputReportCallback(
                dev,
                buf,
                reportBufferSize,
                nil,
                nil
            )
        }

        if let dev = device {
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        if let mgr = manager {
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }

        device = nil
        manager = nil
        deviceInfo = nil
        inputCallback = nil
        reportBufferPtr?.deallocate()
        reportBufferPtr = nil
        reportBufferSize = 0
        isOpen = false
    }

    /// The currently connected device info, if any.
    var currentDeviceInfo: DS4DeviceInfo? {
        return deviceInfo
    }

    // MARK: - Private Helpers

    /// Create an IOKit matching dictionary for a specific vendor/product ID pair.
    private func createMatchingDict(vendorID: UInt16, productID: UInt16) -> [String: Any] {
        return [
            kIOHIDVendorIDKey: Int(vendorID),
            kIOHIDProductIDKey: Int(productID),
        ]
    }

    /// Extract DS4DeviceInfo from an IOHIDDevice's properties.
    private func extractDeviceInfo(from device: IOHIDDevice) -> DS4DeviceInfo {
        let vendorID = getIntProperty(device, key: kIOHIDVendorIDKey).map { UInt16($0) } ?? 0
        let productID = getIntProperty(device, key: kIOHIDProductIDKey).map { UInt16($0) } ?? 0
        let versionNumber = getIntProperty(device, key: kIOHIDVersionNumberKey) ?? 0
        let manufacturer = getStringProperty(device, key: kIOHIDManufacturerKey)
        let product = getStringProperty(device, key: kIOHIDProductKey)
        let serialNumber = getStringProperty(device, key: kIOHIDSerialNumberKey)
        let transport = getStringProperty(device, key: kIOHIDTransportKey)

        // Determine connection type from transport string
        let connectionType: DS4ConnectionType
        if let t = transport?.lowercased() {
            if t.contains("bluetooth") {
                connectionType = .bluetooth
            } else {
                connectionType = .usb
            }
        } else {
            connectionType = .usb
        }

        return DS4DeviceInfo(
            vendorID: vendorID,
            productID: productID,
            versionNumber: versionNumber,
            manufacturer: manufacturer,
            product: product,
            serialNumber: serialNumber,
            connectionType: connectionType,
            transport: transport
        )
    }

    /// Read an integer property from an IOHIDDevice.
    private func getIntProperty(_ device: IOHIDDevice, key: String) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }
        guard CFGetTypeID(value) == CFNumberGetTypeID() else { return nil }
        var intVal: Int = 0
        if CFNumberGetValue((value as! CFNumber), .intType, &intVal) {
            return intVal
        }
        return nil
    }

    /// Read a string property from an IOHIDDevice.
    private func getStringProperty(_ device: IOHIDDevice, key: String) -> String? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }
        guard CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return (value as! CFString) as String
    }
}

// MARK: - C Callback

/// C-compatible input report callback for IOHIDDeviceRegisterInputReportCallback.
///
/// Parameters (per IOKit API):
/// - context: Opaque pointer to the DS4HIDManager instance
/// - result: IOReturn status code
/// - sender: The IOHIDDevice that sent the report
/// - type: The HID report type
/// - reportID: The report ID
/// - report: Pointer to the report data buffer
/// - reportLength: Length of the report data
private func hidInputReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context = context else { return }
    guard result == kIOReturnSuccess else { return }
    guard reportLength > 0 else { return }

    let manager = Unmanaged<DS4HIDManager>.fromOpaque(context).takeUnretainedValue()

    // IOKit behavior varies: the buffer may or may not include the report ID byte.
    // Detect by checking if the first byte matches the report ID AND the length
    // matches a known full-report size. If so, the buffer already has the ID.
    let rid = UInt8(reportID)
    let bufferIncludesID: Bool
    if report[0] == rid {
        // Check if length matches a known full-report size
        switch (rid, reportLength) {
        case (DS4ReportID.usbInput, DS4ReportSize.usbInput),
             (DS4ReportID.btInput, DS4ReportSize.btInput):
            bufferIncludesID = true
        default:
            bufferIncludesID = false
        }
    } else {
        bufferIncludesID = false
    }

    let fullReport: [UInt8]
    if bufferIncludesID {
        // Buffer already has the report ID — use as-is
        fullReport = Array(UnsafeBufferPointer(start: report, count: reportLength))
    } else {
        // Buffer doesn't include the report ID — prepend it
        var buf = [UInt8](repeating: 0, count: reportLength + 1)
        buf[0] = rid
        for i in 0..<reportLength {
            buf[i + 1] = report[i]
        }
        fullReport = buf
    }

    manager.inputCallback?(fullReport)
}
