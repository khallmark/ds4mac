// DS4Types.swift — Data model types for DualShock 4 controller state
// All types are Codable (JSON output) and Equatable (test assertions).

/// D-pad direction values (low nibble of button byte 0).
/// Values 0-7 map to 8 compass directions; 8 = neutral/released.
public enum DS4DPadDirection: UInt8, Codable, Sendable {
    case north     = 0
    case northEast = 1
    case east      = 2
    case southEast = 3
    case south     = 4
    case southWest = 5
    case west      = 6
    case northWest = 7
    case neutral   = 8
}

/// Analog stick state. X: 0=left, 128=center, 255=right. Y: 0=up, 128=center, 255=down.
public struct DS4StickState: Codable, Equatable, Sendable {
    public var x: UInt8
    public var y: UInt8

    public init(x: UInt8 = 128, y: UInt8 = 128) {
        self.x = x
        self.y = y
    }
}

/// All 14 digital button states.
public struct DS4Buttons: Codable, Equatable, Sendable {
    public var square: Bool
    public var cross: Bool
    public var circle: Bool
    public var triangle: Bool
    public var l1: Bool
    public var r1: Bool
    public var l2: Bool      // digital trigger button
    public var r2: Bool      // digital trigger button
    public var share: Bool
    public var options: Bool
    public var l3: Bool      // left stick click
    public var r3: Bool      // right stick click
    public var ps: Bool      // PlayStation button
    public var touchpadClick: Bool

    public init(
        square: Bool = false, cross: Bool = false,
        circle: Bool = false, triangle: Bool = false,
        l1: Bool = false, r1: Bool = false,
        l2: Bool = false, r2: Bool = false,
        share: Bool = false, options: Bool = false,
        l3: Bool = false, r3: Bool = false,
        ps: Bool = false, touchpadClick: Bool = false
    ) {
        self.square = square; self.cross = cross
        self.circle = circle; self.triangle = triangle
        self.l1 = l1; self.r1 = r1
        self.l2 = l2; self.r2 = r2
        self.share = share; self.options = options
        self.l3 = l3; self.r3 = r3
        self.ps = ps; self.touchpadClick = touchpadClick
    }
}

/// Single touch finger on the capacitive touchpad.
/// Active bit is inverted in the raw report: bit 7 = 0 means touching.
/// Coordinates: X 0-1919 (12-bit), Y 0-942 (12-bit).
public struct DS4TouchFinger: Codable, Equatable, Sendable {
    public var active: Bool
    public var trackingID: UInt8    // 7-bit ID (0-127), increments per new touch
    public var x: UInt16            // 0-1919
    public var y: UInt16            // 0-942

    public init(active: Bool = false, trackingID: UInt8 = 0, x: UInt16 = 0, y: UInt16 = 0) {
        self.active = active
        self.trackingID = trackingID
        self.x = x
        self.y = y
    }
}

/// Touchpad state: up to 2 simultaneous touch points.
public struct DS4TouchpadState: Codable, Equatable, Sendable {
    public var touch0: DS4TouchFinger
    public var touch1: DS4TouchFinger
    public var packetCounter: UInt8

    public init(
        touch0: DS4TouchFinger = DS4TouchFinger(),
        touch1: DS4TouchFinger = DS4TouchFinger(),
        packetCounter: UInt8 = 0
    ) {
        self.touch0 = touch0
        self.touch1 = touch1
        self.packetCounter = packetCounter
    }
}

/// 6-axis IMU state (raw signed 16-bit values, uncalibrated).
/// Gyroscope: degrees/second (needs calibration for accuracy).
/// Accelerometer: at rest, Y ≈ +8192 (1g from gravity).
public struct DS4IMUState: Codable, Equatable, Sendable {
    public var gyroPitch: Int16     // X-axis rotation
    public var gyroYaw: Int16       // Y-axis rotation
    public var gyroRoll: Int16      // Z-axis rotation
    public var accelX: Int16
    public var accelY: Int16
    public var accelZ: Int16

    public init(
        gyroPitch: Int16 = 0, gyroYaw: Int16 = 0, gyroRoll: Int16 = 0,
        accelX: Int16 = 0, accelY: Int16 = 0, accelZ: Int16 = 0
    ) {
        self.gyroPitch = gyroPitch; self.gyroYaw = gyroYaw; self.gyroRoll = gyroRoll
        self.accelX = accelX; self.accelY = accelY; self.accelZ = accelZ
    }
}

/// Battery and peripheral status.
public struct DS4BatteryState: Codable, Equatable, Sendable {
    public var level: UInt8             // 0-8 (wireless), 0-11 (wired/charging)
    public var cableConnected: Bool     // USB cable attached
    public var headphones: Bool         // headphones plugged in
    public var microphone: Bool         // mic plugged in

    public init(level: UInt8 = 0, cableConnected: Bool = false,
                headphones: Bool = false, microphone: Bool = false) {
        self.level = level
        self.cableConnected = cableConnected
        self.headphones = headphones
        self.microphone = microphone
    }

    /// Battery percentage estimate.
    public var percentage: Int {
        let maxVal = cableConnected ? 11 : 8
        return min(Int(level) * 100 / max(maxVal, 1), 100)
    }
}

/// Connection type.
public enum DS4ConnectionType: String, Codable, Sendable {
    case usb
    case bluetooth
}

/// Complete parsed controller input state from a single HID report.
public struct DS4InputState: Codable, Equatable, Sendable {
    public var leftStick: DS4StickState
    public var rightStick: DS4StickState
    public var dpad: DS4DPadDirection
    public var buttons: DS4Buttons
    public var l2Trigger: UInt8         // analog trigger 0-255
    public var r2Trigger: UInt8         // analog trigger 0-255
    public var touchpad: DS4TouchpadState
    public var imu: DS4IMUState
    public var battery: DS4BatteryState
    public var timestamp: UInt16
    public var frameCounter: UInt8

    public init(
        leftStick: DS4StickState = DS4StickState(),
        rightStick: DS4StickState = DS4StickState(),
        dpad: DS4DPadDirection = .neutral,
        buttons: DS4Buttons = DS4Buttons(),
        l2Trigger: UInt8 = 0,
        r2Trigger: UInt8 = 0,
        touchpad: DS4TouchpadState = DS4TouchpadState(),
        imu: DS4IMUState = DS4IMUState(),
        battery: DS4BatteryState = DS4BatteryState(),
        timestamp: UInt16 = 0,
        frameCounter: UInt8 = 0
    ) {
        self.leftStick = leftStick; self.rightStick = rightStick
        self.dpad = dpad; self.buttons = buttons
        self.l2Trigger = l2Trigger; self.r2Trigger = r2Trigger
        self.touchpad = touchpad; self.imu = imu
        self.battery = battery; self.timestamp = timestamp
        self.frameCounter = frameCounter
    }
}

/// Device information extracted from IOHIDDevice properties.
public struct DS4DeviceInfo: Codable, Equatable, Sendable {
    public var vendorID: UInt16
    public var productID: UInt16
    public var versionNumber: Int
    public var manufacturer: String?
    public var product: String?
    public var serialNumber: String?
    public var connectionType: DS4ConnectionType
    public var transport: String?

    public init(
        vendorID: UInt16 = DS4DeviceID.vendorID,
        productID: UInt16 = DS4DeviceID.ds4V1PID,
        versionNumber: Int = 0,
        manufacturer: String? = nil,
        product: String? = nil,
        serialNumber: String? = nil,
        connectionType: DS4ConnectionType = .usb,
        transport: String? = nil
    ) {
        self.vendorID = vendorID; self.productID = productID
        self.versionNumber = versionNumber; self.manufacturer = manufacturer
        self.product = product; self.serialNumber = serialNumber
        self.connectionType = connectionType; self.transport = transport
    }

    /// Human-readable model name.
    public var modelName: String {
        switch productID {
        case DS4DeviceID.ds4V1PID: return "DualShock 4 V1"
        case DS4DeviceID.ds4V2PID: return "DualShock 4 V2"
        case DS4DeviceID.donglePID: return "Sony Wireless Adapter"
        default: return "Unknown DS4 (0x\(String(productID, radix: 16, uppercase: true)))"
        }
    }
}

/// Output state for rumble motors, light bar LED, and flash timing.
public struct DS4OutputState: Codable, Equatable, Sendable {
    public var rumbleHeavy: UInt8 = 0   // left/strong motor (0-255)
    public var rumbleLight: UInt8 = 0   // right/weak motor (0-255)
    public var ledRed: UInt8 = 0
    public var ledGreen: UInt8 = 0
    public var ledBlue: UInt8 = 0
    public var flashOn: UInt8 = 0       // ~10ms units
    public var flashOff: UInt8 = 0      // ~10ms units

    public init(
        rumbleHeavy: UInt8 = 0, rumbleLight: UInt8 = 0,
        ledRed: UInt8 = 0, ledGreen: UInt8 = 0, ledBlue: UInt8 = 0,
        flashOn: UInt8 = 0, flashOff: UInt8 = 0
    ) {
        self.rumbleHeavy = rumbleHeavy; self.rumbleLight = rumbleLight
        self.ledRed = ledRed; self.ledGreen = ledGreen; self.ledBlue = ledBlue
        self.flashOn = flashOn; self.flashOff = flashOff
    }
}
