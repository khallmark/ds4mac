// DS4Tool — Command-line tool for DualShock 4 controller interaction
// Usage: DS4Tool <command> [options]
// Commands: info, monitor, led, rumble, capture, test-roundtrip
// Flags: --json, --timeout <seconds>, --rate <hz>

import Foundation
import DS4Protocol
import DS4Transport

// MARK: - JSON Encoder (shared — must be initialized before dispatch)

let jsonEncoder: JSONEncoder = {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    return enc
}()

// MARK: - Argument Parsing

let args = Array(CommandLine.arguments.dropFirst())

guard let command = args.first else {
    printUsage()
    exit(0)
}

let jsonMode = args.contains("--json")
let timeout: TimeInterval = {
    if let idx = args.firstIndex(of: "--timeout"), idx + 1 < args.count,
       let val = Double(args[idx + 1]) {
        return val
    }
    return 10.0
}()

// MARK: - Command Dispatch

switch command {
case "info":
    runInfo(json: jsonMode)
case "monitor":
    runMonitor(json: jsonMode, timeout: timeout)
case "led":
    let colorArgs = args.filter { !$0.starts(with: "-") && $0 != "led" }
    guard colorArgs.count >= 3,
          let r = UInt8(colorArgs[0]),
          let g = UInt8(colorArgs[1]),
          let b = UInt8(colorArgs[2]) else {
        fputs("Usage: DS4Tool led <r> <g> <b> [--json]\n", stderr)
        exit(1)
    }
    runLED(r: r, g: g, b: b, json: jsonMode)
case "rumble":
    let motorArgs = args.filter { !$0.starts(with: "-") && $0 != "rumble" }
    guard motorArgs.count >= 2,
          let heavy = UInt8(motorArgs[0]),
          let light = UInt8(motorArgs[1]) else {
        fputs("Usage: DS4Tool rumble <heavy> <light> [--json]\n", stderr)
        exit(1)
    }
    runRumble(heavy: heavy, light: light, json: jsonMode)
case "capture":
    let captureArgs = args.filter { !$0.starts(with: "-") && $0 != "capture" }
    let count = captureArgs.first.flatMap(Int.init) ?? 10
    let outputDir: String = {
        if let idx = args.firstIndex(of: "--output"), idx + 1 < args.count {
            return args[idx + 1]
        }
        return "."
    }()
    runCapture(count: count, outputDir: outputDir, json: jsonMode)
case "test-roundtrip":
    runTestRoundtrip(json: jsonMode, timeout: timeout)
case "--help", "-h", "help":
    printUsage()
default:
    fputs("Unknown command: \(command)\n", stderr)
    printUsage()
    exit(1)
}

// MARK: - Transport Helper

/// Create a USB transport, connect to the first DS4 controller, and return the transport + device info.
/// Exits on failure.
func openTransport() -> (DS4USBTransport, DS4DeviceInfo) {
    let transport = DS4USBTransport()
    do {
        try transport.connect()
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
    guard let info = transport.deviceInfo else {
        fputs("Error: No device info available after connect\n", stderr)
        exit(1)
    }
    return (transport, info)
}

// MARK: - Info Command

func runInfo(json: Bool) {
    let (transport, info) = openTransport()
    defer { transport.disconnect() }

    if json {
        do {
            let data = try jsonEncoder.encode(info)
            print(String(data: data, encoding: .utf8)!)
        } catch {
            fputs("Error: Failed to encode device info as JSON: \(error)\n", stderr)
            exit(3)
        }
    } else {
        print("DualShock 4 Controller")
        print("  Model:       \(info.modelName)")
        print("  Vendor ID:   0x\(String(info.vendorID, radix: 16, uppercase: true))")
        print("  Product ID:  0x\(String(info.productID, radix: 16, uppercase: true))")
        print("  Version:     \(info.versionNumber)")
        if let mfg = info.manufacturer {
            print("  Manufacturer: \(mfg)")
        }
        if let prod = info.product {
            print("  Product:     \(prod)")
        }
        if let serial = info.serialNumber {
            print("  Serial:      \(serial)")
        }
        print("  Connection:  \(info.connectionType.rawValue.uppercased())")
        if let transport = info.transport {
            print("  Transport:   \(transport)")
        }
    }
    exit(0)
}

// MARK: - Monitor Command

func runMonitor(json: Bool, timeout: TimeInterval) {
    let (transport, info) = openTransport()

    // For Bluetooth connections, read feature report 0x02 to trigger extended report mode
    if info.connectionType == .bluetooth {
        fputs("Bluetooth connection detected, requesting extended reports...\n", stderr)
        let calibrationData = transport.readFeatureReport(
            reportID: DS4ReportID.calibrationUSB,
            length: DS4ReportSize.calibration
        )
        if calibrationData != nil {
            fputs("Extended BT report mode activated\n", stderr)
        } else {
            fputs("Warning: Could not read calibration report, BT reports may be reduced\n", stderr)
        }
    }

    if !json {
        fputs("Monitoring \(info.modelName) via \(info.connectionType.rawValue.uppercased()) for \(Int(timeout))s...\n", stderr)
        fputs("Press Ctrl+C to stop\n\n", stderr)
    }

    // Rate limiting: in human-readable mode, only display every ~25th report (~10 Hz output)
    var reportCount = 0
    let displayInterval = json ? 1 : 25

    transport.onEvent = { event in
        guard case .inputReport(let reportBytes) = event else { return }
        reportCount += 1

        do {
            let state = try DS4InputReportParser.parse(reportBytes)

            if reportCount % displayInterval == 0 {
                if json {
                    if let data = try? jsonEncoder.encode(state) {
                        print(String(data: data, encoding: .utf8)!)
                        fflush(stdout)
                    }
                } else {
                    printHumanReadableState(state, reportNumber: reportCount)
                }
            }
        } catch DS4InputReportParser.ParseError.invalidLength(let expected, let got) {
            // Reduced BT reports (10 bytes) are expected before mode switch completes; skip silently
            if got < 20 { return }
            fputs("Parse error: invalid length (expected \(expected), got \(got))\n", stderr)
        } catch DS4InputReportParser.ParseError.invalidReportID(_, let got) {
            // Report ID 0x01 with small size = reduced BT report, skip
            if got == DS4ReportID.btInputReduced { return }
            fputs("Parse error: unexpected report ID 0x\(String(got, radix: 16))\n", stderr)
        } catch DS4InputReportParser.ParseError.crcMismatch {
            fputs("Parse error: CRC mismatch (corrupted BT report)\n", stderr)
        } catch {
            fputs("Parse error: \(error)\n", stderr)
        }
    }
    transport.startInputReportPolling()

    // Schedule a timer to stop after the timeout
    let timer = Timer(timeInterval: timeout, repeats: false) { _ in
        if !json {
            fputs("\nMonitor timeout (\(Int(timeout))s) reached. Exiting.\n", stderr)
        }
        transport.disconnect()
        exit(0)
    }
    RunLoop.current.add(timer, forMode: .default)

    // Run the run loop to process HID callbacks
    CFRunLoopRun()
}

// MARK: - LED Command

func runLED(r: UInt8, g: UInt8, b: UInt8, json: Bool) {
    let (transport, info) = openTransport()
    defer { transport.disconnect() }

    let outputState = DS4OutputState(
        ledRed: r,
        ledGreen: g,
        ledBlue: b
    )

    let report: [UInt8]
    if info.connectionType == .bluetooth {
        report = DS4OutputReportBuilder.buildBluetooth(outputState)
    } else {
        report = DS4OutputReportBuilder.buildUSB(outputState)
    }

    let success: Bool
    do {
        success = try transport.sendOutputReport(report)
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        success = false
    }

    if json {
        let result: [String: Any] = [
            "command": "led",
            "success": success,
            "red": r,
            "green": g,
            "blue": b,
            "connection": info.connectionType.rawValue,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    } else {
        if success {
            print("LED color set to R=\(r) G=\(g) B=\(b) via \(info.connectionType.rawValue.uppercased())")
        } else {
            fputs("Error: Failed to send LED output report\n", stderr)
            exit(2)
        }
    }

    exit(success ? 0 : 2)
}

// MARK: - Rumble Command

func runRumble(heavy: UInt8, light: UInt8, json: Bool) {
    let (transport, info) = openTransport()

    let outputState = DS4OutputState(
        rumbleHeavy: heavy,
        rumbleLight: light
    )

    let report: [UInt8]
    if info.connectionType == .bluetooth {
        report = DS4OutputReportBuilder.buildBluetooth(outputState)
    } else {
        report = DS4OutputReportBuilder.buildUSB(outputState)
    }

    do {
        try transport.sendOutputReport(report)
    } catch {
        if json {
            print("{\"command\":\"rumble\",\"success\":false}")
        } else {
            fputs("Error: \(error.localizedDescription)\n", stderr)
        }
        transport.disconnect()
        exit(2)
    }

    if !json {
        print("Rumble active: heavy=\(heavy) light=\(light) via \(info.connectionType.rawValue.uppercased())")
        print("Running for 2 seconds...")
    }

    // Keep rumble active for 2 seconds, then send zero-rumble to stop
    let stopTimer = Timer(timeInterval: 2.0, repeats: false) { _ in
        let stopState = DS4OutputState()
        let stopReport: [UInt8]
        if info.connectionType == .bluetooth {
            stopReport = DS4OutputReportBuilder.buildBluetooth(stopState)
        } else {
            stopReport = DS4OutputReportBuilder.buildUSB(stopState)
        }
        _ = try? transport.sendOutputReport(stopReport)

        if json {
            let result: [String: Any] = [
                "command": "rumble",
                "success": true,
                "heavy": heavy,
                "light": light,
                "duration": 2.0,
                "connection": info.connectionType.rawValue,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            print("Rumble stopped.")
        }

        transport.disconnect()
        exit(0)
    }
    RunLoop.current.add(stopTimer, forMode: .default)
    CFRunLoopRun()
}

// MARK: - Capture Command

func runCapture(count: Int, outputDir: String, json: Bool) {
    let (transport, info) = openTransport()

    // For Bluetooth, trigger extended mode
    if info.connectionType == .bluetooth {
        _ = transport.readFeatureReport(reportID: DS4ReportID.calibrationUSB, length: DS4ReportSize.calibration)
    }

    // Ensure output directory exists
    let fm = FileManager.default
    if !fm.fileExists(atPath: outputDir) {
        do {
            try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        } catch {
            fputs("Error: Could not create output directory '\(outputDir)': \(error)\n", stderr)
            exit(2)
        }
    }

    if !json {
        fputs("Capturing \(count) reports from \(info.modelName) via \(info.connectionType.rawValue.uppercased())...\n", stderr)
    }

    var captured = 0
    var filenames: [String] = []

    transport.onEvent = { event in
        guard case .inputReport(let reportBytes) = event else { return }

        // Skip reduced BT reports
        if reportBytes.count < 20 { return }

        captured += 1

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let filename = "ds4_report_\(String(format: "%04d", captured))_\(timestamp).bin"
        let filePath = (outputDir as NSString).appendingPathComponent(filename)

        let data = Data(reportBytes)
        do {
            try data.write(to: URL(fileURLWithPath: filePath))
            filenames.append(filePath)

            if !json {
                print("[\(captured)/\(count)] Saved \(reportBytes.count) bytes -> \(filename)")
            }
        } catch {
            fputs("Error writing report \(captured): \(error)\n", stderr)
        }

        if captured >= count {
            if json {
                let result: [String: Any] = [
                    "command": "capture",
                    "count": captured,
                    "connection": info.connectionType.rawValue,
                    "files": filenames,
                    "reportSize": reportBytes.count,
                ]
                if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                print("Capture complete: \(captured) reports saved to '\(outputDir)'")
            }
            transport.disconnect()
            exit(0)
        }
    }
    transport.startInputReportPolling()

    // Safety timeout: 30 seconds max for capture
    let safetyTimeout = Timer(timeInterval: 30.0, repeats: false) { _ in
        fputs("Warning: Capture timed out after 30 seconds (\(captured)/\(count) reports captured)\n", stderr)
        transport.disconnect()
        exit(captured > 0 ? 0 : 1)
    }
    RunLoop.current.add(safetyTimeout, forMode: .default)
    CFRunLoopRun()
}

// MARK: - Test Roundtrip (stub for future increment)

func runTestRoundtrip(json: Bool, timeout: TimeInterval) {
    fputs("DS4Tool test-roundtrip: Not yet implemented (Increment 10)\n", stderr)
    exit(1)
}

// MARK: - Human-Readable Display Helpers

func printHumanReadableState(_ state: DS4InputState, reportNumber: Int) {
    // Build a compact single-screen display using ANSI escape codes
    // Move cursor to top-left and clear screen for a "live" display
    print("\u{1B}[H\u{1B}[J", terminator: "")

    print("=== DualShock 4 Input Report #\(reportNumber) ===\n")

    // Sticks
    print("Left Stick:  X=\(String(format: "%3d", state.leftStick.x))  Y=\(String(format: "%3d", state.leftStick.y))    " +
          "Right Stick: X=\(String(format: "%3d", state.rightStick.x))  Y=\(String(format: "%3d", state.rightStick.y))")

    // Triggers
    print("L2 Trigger:  \(String(format: "%3d", state.l2Trigger))            " +
          "R2 Trigger:  \(String(format: "%3d", state.r2Trigger))")

    // D-Pad
    print("D-Pad:       \(dpadString(state.dpad))")

    // Buttons (compact, only show pressed)
    var pressed: [String] = []
    if state.buttons.cross     { pressed.append("X") }
    if state.buttons.circle    { pressed.append("O") }
    if state.buttons.square    { pressed.append("[]") }
    if state.buttons.triangle  { pressed.append("/\\") }
    if state.buttons.l1        { pressed.append("L1") }
    if state.buttons.r1        { pressed.append("R1") }
    if state.buttons.l2        { pressed.append("L2") }
    if state.buttons.r2        { pressed.append("R2") }
    if state.buttons.l3        { pressed.append("L3") }
    if state.buttons.r3        { pressed.append("R3") }
    if state.buttons.share     { pressed.append("Share") }
    if state.buttons.options   { pressed.append("Options") }
    if state.buttons.ps        { pressed.append("PS") }
    if state.buttons.touchpadClick { pressed.append("Touch") }
    print("Buttons:     \(pressed.isEmpty ? "(none)" : pressed.joined(separator: " "))")

    // IMU
    print("Gyro:        pitch=\(String(format: "%6d", state.imu.gyroPitch))  " +
          "yaw=\(String(format: "%6d", state.imu.gyroYaw))  " +
          "roll=\(String(format: "%6d", state.imu.gyroRoll))")
    print("Accel:       X=\(String(format: "%6d", state.imu.accelX))  " +
          "Y=\(String(format: "%6d", state.imu.accelY))  " +
          "Z=\(String(format: "%6d", state.imu.accelZ))")

    // Touchpad
    let t0 = state.touchpad.touch0
    let t1 = state.touchpad.touch1
    let touch0Str = t0.active ? "id=\(t0.trackingID) x=\(t0.x) y=\(t0.y)" : "(inactive)"
    let touch1Str = t1.active ? "id=\(t1.trackingID) x=\(t1.x) y=\(t1.y)" : "(inactive)"
    print("Touch 0:     \(touch0Str)")
    print("Touch 1:     \(touch1Str)")

    // Battery
    let batteryPct = state.battery.percentage
    let cableStr = state.battery.cableConnected ? " [USB]" : " [Wireless]"
    print("Battery:     \(batteryPct)%\(cableStr)")

    // Timestamp and frame
    print("Timestamp:   \(state.timestamp)  Frame: \(state.frameCounter)")

    fflush(stdout)
}

func dpadString(_ dpad: DS4DPadDirection) -> String {
    switch dpad {
    case .north:     return "Up"
    case .northEast: return "Up-Right"
    case .east:      return "Right"
    case .southEast: return "Down-Right"
    case .south:     return "Down"
    case .southWest: return "Down-Left"
    case .west:      return "Left"
    case .northWest: return "Up-Left"
    case .neutral:   return "(center)"
    }
}

func printUsage() {
    print("""
    DS4Tool — DualShock 4 Controller Utility

    USAGE: DS4Tool <command> [options]

    COMMANDS:
      info                    Show connected DS4 device info
      monitor                 Stream parsed input reports
      led <r> <g> <b>         Set light bar color (0-255 each)
      rumble <heavy> <light>  Activate rumble motors (0-255 each)
      capture <count>         Save raw HID reports as binary fixtures
      test-roundtrip          Send output, verify input still flows

    OPTIONS:
      --json                  Output in JSON format
      --timeout <seconds>     Duration for monitor/test (default: 10)
      --output <dir>          Output directory for capture (default: .)
      --help                  Show this help message

    EXIT CODES:
      0  Success
      1  No controller found
      2  Connection error
      3  Parse error
    """)
}
