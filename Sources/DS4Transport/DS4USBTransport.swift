// DS4USBTransport.swift — USB transport via IOKit IOHIDManager
// Handles device discovery, hot-plug, input report polling, and output report sending.
// Reference: docs/04-DS4-USB-Protocol.md, docs/10-macOS-Driver-Architecture.md Section 2.3

import Foundation
import IOKit
import IOKit.hid
import DS4Protocol

/// USB transport implementation for DualShock 4 controllers.
///
/// Uses IOKit `IOHIDManager` for device discovery and HID communication.
/// Supports hot-plug: device matching and removal callbacks fire automatically
/// when a controller is connected or disconnected while the transport is active.
///
/// Threading: IOKit callbacks fire on the RunLoop where the transport is scheduled
/// (the RunLoop active when `connect()` is called). Callers must ensure that RunLoop
/// is running for callbacks to be delivered.
public final class DS4USBTransport: DS4TransportProtocol {

    // MARK: - DS4TransportProtocol Conformance

    public var transportName: String { "USB" }
    public private(set) var deviceInfo: DS4DeviceInfo?
    public private(set) var isConnected: Bool = false
    public var onEvent: ((DS4TransportEvent) -> Void)?

    // MARK: - IOKit State

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?

    /// Persistent buffer for IOKit to write input reports into.
    /// Allocated once per polling session and kept alive until unregistered.
    /// Must use UnsafeMutablePointer.allocate() — NOT Array.withUnsafeMutableBufferPointer
    /// (that pointer is only valid inside the closure).
    private var reportBufferPtr: UnsafeMutablePointer<UInt8>?
    private var reportBufferSize: Int = 0

    public init() {}

    deinit {
        reportBufferPtr?.deallocate()
    }

    // MARK: - Connect

    /// Discover and connect to the first available DualShock 4 controller.
    ///
    /// Creates an IOHIDManager, sets matching criteria for DS4 V1, V2, and Wireless Adapter,
    /// registers hot-plug callbacks, and attempts to find a connected device.
    ///
    /// - Throws: `DS4TransportError.alreadyConnected` if already connected,
    ///           `.connectionFailed` if the IOHIDManager can't be opened,
    ///           `.deviceNotFound` if no DS4 controller is currently connected.
    public func connect() throws {
        guard !isConnected else { throw DS4TransportError.alreadyConnected }

        // Clean up any leftover manager from a previous session
        cleanupManager()

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr

        // Build matching dictionaries for DS4 V1, V2, and Sony Wireless Adapter
        let matchV1 = createMatchingDict(vendorID: DS4DeviceID.vendorID, productID: DS4DeviceID.ds4V1PID)
        let matchV2 = createMatchingDict(vendorID: DS4DeviceID.vendorID, productID: DS4DeviceID.ds4V2PID)
        let matchDongle = createMatchingDict(vendorID: DS4DeviceID.vendorID, productID: DS4DeviceID.donglePID)

        IOHIDManagerSetDeviceMatchingMultiple(mgr, [matchV1, matchV2, matchDongle] as CFArray)

        // Register hot-plug callbacks for device connect/disconnect while running
        let context = Unmanaged<DS4USBTransport>.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, hidDeviceMatchedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, hidDeviceRemovedCallback, context)

        // Schedule on the current run loop — callbacks fire here
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        // Open the manager
        let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            cleanupManager()
            throw DS4TransportError.connectionFailed("IOHIDManagerOpen failed with code \(openResult)")
        }

        // Copy the set of matched devices — use safe CF bridging
        guard let deviceSetRef = IOHIDManagerCopyDevices(mgr) else {
            cleanupManager()
            throw DS4TransportError.deviceNotFound
        }

        // Bridge CFSet → Swift array. Direct Set<IOHIDDevice> cast can crash;
        // fall back to NSSet bridge if needed.
        let deviceArray: [IOHIDDevice]
        if let deviceSet = deviceSetRef as? Set<IOHIDDevice> {
            deviceArray = Array(deviceSet)
        } else {
            let nsSet = deviceSetRef as NSSet
            deviceArray = nsSet.allObjects.map { $0 as! IOHIDDevice }
        }

        guard let firstDevice = deviceArray.first else {
            cleanupManager()
            throw DS4TransportError.deviceNotFound
        }

        try connectDevice(firstDevice)
    }

    // MARK: - Disconnect

    /// Disconnect from the current controller and release all IOKit resources.
    ///
    /// Safe to call even if not connected. Fires `.disconnected` event if
    /// a device was connected at the time of the call.
    public func disconnect() {
        let wasConnected = isConnected
        cleanupDevice()
        cleanupManager()
        if wasConnected {
            onEvent?(.disconnected)
        }
    }

    // MARK: - Input Report Polling

    /// Begin receiving input reports from the connected device.
    ///
    /// Allocates a persistent report buffer sized for the connection type
    /// (78 bytes for Bluetooth, 64 bytes for USB) and registers an IOKit
    /// input report callback. Reports are delivered via `onEvent(.inputReport)`.
    ///
    /// No-op if no device is connected.
    public func startInputReportPolling() {
        guard let dev = device, let info = deviceInfo else { return }

        let bufferSize = (info.connectionType == .bluetooth)
            ? DS4ReportSize.btInput
            : DS4ReportSize.usbInput

        // Deallocate any previous buffer before allocating a new one
        reportBufferPtr?.deallocate()
        reportBufferPtr = .allocate(capacity: bufferSize)
        reportBufferPtr?.initialize(repeating: 0, count: bufferSize)
        reportBufferSize = bufferSize

        let context = Unmanaged<DS4USBTransport>.passUnretained(self).toOpaque()

        IOHIDDeviceRegisterInputReportCallback(
            dev,
            reportBufferPtr!,
            reportBufferSize,
            hidUSBInputReportCallback,
            context
        )
    }

    // MARK: - Output Reports

    /// Send an output report to the connected device.
    ///
    /// - Parameter data: Complete report bytes including report ID at index 0.
    /// - Returns: `true` if the report was sent successfully.
    /// - Throws: `DS4TransportError.notConnected` if no device is connected,
    ///           `.reportSendFailed` if the IOKit call fails.
    @discardableResult
    public func sendOutputReport(_ data: [UInt8]) throws -> Bool {
        guard let dev = device, isConnected else {
            throw DS4TransportError.notConnected
        }
        guard !data.isEmpty else {
            throw DS4TransportError.reportSendFailed("Empty report data")
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

        guard result == kIOReturnSuccess else {
            throw DS4TransportError.reportSendFailed("IOHIDDeviceSetReport failed with code \(result)")
        }
        return true
    }

    // MARK: - Feature Reports

    /// Read a feature report from the connected device.
    ///
    /// Used for operations like reading calibration data (report 0x02) which also
    /// triggers the Bluetooth mode switch from reduced to extended input reports.
    ///
    /// - Parameters:
    ///   - reportID: The HID feature report ID to read.
    ///   - length: The expected report length in bytes.
    /// - Returns: The raw report bytes, or `nil` if no device is connected or on failure.
    public func readFeatureReport(reportID: UInt8, length: Int) -> [UInt8]? {
        guard let dev = device else { return nil }

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

        guard result == kIOReturnSuccess else { return nil }
        return Array(buffer.prefix(reportLength))
    }

    // MARK: - Hot-Plug Handlers

    /// Called by the IOKit matching callback when a DS4 device is connected.
    fileprivate func handleDeviceMatched(_ matchedDevice: IOHIDDevice) {
        // Ignore if we already have a connected device
        guard !isConnected else { return }
        try? connectDevice(matchedDevice)
    }

    /// Called by the IOKit removal callback when a DS4 device is disconnected.
    fileprivate func handleDeviceRemoved(_ removedDevice: IOHIDDevice) {
        // Only handle if this is our connected device
        guard removedDevice === device else { return }

        // Unregister input report callback before deallocating buffer
        if let buf = reportBufferPtr, reportBufferSize > 0 {
            IOHIDDeviceRegisterInputReportCallback(
                removedDevice, buf, reportBufferSize, nil, nil
            )
        }

        // Clean up device-level state (keep manager alive for reconnection)
        device = nil
        deviceInfo = nil
        reportBufferPtr?.deallocate()
        reportBufferPtr = nil
        reportBufferSize = 0
        isConnected = false

        onEvent?(.disconnected)
    }

    // MARK: - Private Helpers

    /// Open and configure a specific IOHIDDevice.
    private func connectDevice(_ dev: IOHIDDevice) throws {
        let devOpenResult = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        if devOpenResult != kIOReturnSuccess {
            // Non-fatal warning — some devices still work after a failed open
        }

        device = dev
        let info = extractDeviceInfo(from: dev)
        deviceInfo = info
        isConnected = true
        onEvent?(.connected(info))
    }

    /// Clean up device-level resources (callback, buffer, device handle).
    private func cleanupDevice() {
        if let dev = device, let buf = reportBufferPtr, reportBufferSize > 0 {
            IOHIDDeviceRegisterInputReportCallback(dev, buf, reportBufferSize, nil, nil)
        }
        if let dev = device {
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil
        deviceInfo = nil
        reportBufferPtr?.deallocate()
        reportBufferPtr = nil
        reportBufferSize = 0
        isConnected = false
    }

    /// Clean up manager-level resources (callbacks, scheduling, handle).
    private func cleanupManager() {
        guard let mgr = manager else { return }
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, nil, nil)
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        manager = nil
    }

    /// Create an IOKit matching dictionary for a specific vendor/product ID pair.
    private func createMatchingDict(vendorID: UInt16, productID: UInt16) -> [String: Any] {
        [
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

        let connectionType: DS4ConnectionType
        if let t = transport?.lowercased() {
            connectionType = t.contains("bluetooth") ? .bluetooth : .usb
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

    /// Read an integer property from an IOHIDDevice using CFGetTypeID for safe bridging.
    private func getIntProperty(_ device: IOHIDDevice, key: String) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }
        guard CFGetTypeID(value) == CFNumberGetTypeID() else { return nil }
        var intVal: Int = 0
        if CFNumberGetValue((value as! CFNumber), .intType, &intVal) {
            return intVal
        }
        return nil
    }

    /// Read a string property from an IOHIDDevice using CFGetTypeID for safe bridging.
    private func getStringProperty(_ device: IOHIDDevice, key: String) -> String? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }
        guard CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return (value as! CFString) as String
    }
}

// MARK: - C Callbacks

/// IOKit device matching callback — fires when a new DS4 device is connected.
private func hidDeviceMatchedCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context = context else { return }
    let transport = Unmanaged<DS4USBTransport>.fromOpaque(context).takeUnretainedValue()
    transport.handleDeviceMatched(device)
}

/// IOKit device removal callback — fires when a DS4 device is disconnected.
private func hidDeviceRemovedCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context = context else { return }
    let transport = Unmanaged<DS4USBTransport>.fromOpaque(context).takeUnretainedValue()
    transport.handleDeviceRemoved(device)
}

/// C-compatible input report callback for IOHIDDeviceRegisterInputReportCallback.
///
/// IOKit behavior varies: the buffer may or may not include the report ID byte.
/// We detect this by checking if `buffer[0] == reportID && length == expectedFullSize`.
/// If so, the buffer already has the ID and we use it as-is. Otherwise, we prepend it.
private func hidUSBInputReportCallback(
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

    let transport = Unmanaged<DS4USBTransport>.fromOpaque(context).takeUnretainedValue()

    // Detect whether the buffer already includes the report ID byte
    let rid = UInt8(reportID)
    let bufferIncludesID: Bool
    if report[0] == rid {
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

    transport.onEvent?(.inputReport(fullReport))
}
