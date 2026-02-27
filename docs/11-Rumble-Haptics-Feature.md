# DS4 Rumble / Haptic Feedback Feature Reference

> Comprehensive documentation of the DualShock 4 vibration motor hardware, protocol integration, haptic effect design, and macOS implementation guidance.
> Cross-references: [04-DS4-USB-Protocol](./04-DS4-USB-Protocol.md) | [05-DS4-Bluetooth-Protocol](./05-DS4-Bluetooth-Protocol.md) | [06-Light-Bar-Feature](./06-Light-Bar-Feature.md)

---

## Table of Contents

1. [Hardware Description](#1-hardware-description)
2. [Output Report Byte Offsets](#2-output-report-byte-offsets)
3. [Motor Characteristics](#3-motor-characteristics)
4. [Feature Flags and Activation](#4-feature-flags-and-activation)
5. [Rumble Boost and Scaling](#5-rumble-boost-and-scaling)
6. [Haptic Patterns and Effects](#6-haptic-patterns-and-effects)
7. [Rumble-Light Bar Integration](#7-rumble-light-bar-integration)
8. [Autostop and Safety](#8-autostop-and-safety)
9. [macOS Implementation Guide](#9-macos-implementation-guide)
10. [macOS Core Haptics Integration](#10-macos-core-haptics-integration)
11. [Code Examples](#11-code-examples)
12. [Cross-Reference Summary](#12-cross-reference-summary)

---

## 1. Hardware Description

### 1.1 Motor Overview

The DualShock 4 contains two **Eccentric Rotating Mass (ERM)** vibration motors with an intentionally asymmetric design. The two motors differ in size, mass, and operating characteristics to produce a wide range of tactile feedback when used in combination.

| Property | Left Motor (Heavy/Slow) | Right Motor (Light/Fast) |
|---|---|---|
| **Common Names** | Heavy, Strong, Slow, Big, Low-frequency | Light, Weak, Fast, Small, High-frequency |
| **Motor Type** | ERM (Eccentric Rotating Mass) | ERM (Eccentric Rotating Mass) |
| **Location** | Left grip (handle) | Right grip (handle) |
| **Eccentric Mass** | Larger, heavier weight | Smaller, lighter weight |
| **Frequency Range** | Lower frequency (~60-120 Hz) | Higher frequency (~150-300 Hz) |
| **Perceived Effect** | Deep, bass-like rumble | Sharp, buzzy vibration |
| **Control Range** | 0x00 - 0xFF (0-255) | 0x00 - 0xFF (0-255) |
| **Output Report Name** | `RumbleMotorStrengthLeftHeavySlow` | `RumbleMotorStrengthRightLightFast` |

### 1.2 Asymmetric Design Rationale

The asymmetric motor design serves several purposes:

1. **Broader frequency spectrum**: Combining two motors with different natural frequencies allows the controller to reproduce a wider range of tactile sensations than a single motor could achieve.

2. **Directional feedback**: Because the motors are physically separated into left and right grips, the controller can create a subtle sense of directionality in the player's hands.

3. **Layered effects**: Game developers can layer a low-frequency "thud" (left/heavy motor) with a high-frequency "buzz" (right/light motor) to create complex composite sensations such as an explosion (heavy bass + high-frequency shrapnel debris).

4. **Power efficiency**: For light feedback (UI confirmations, subtle environmental cues), only the small motor needs to activate, consuming less power than spinning up the large motor.

### 1.3 ERM Motor Physics

ERM motors produce vibration by spinning an off-center (eccentric) mass on a small DC motor shaft. The vibration characteristics are determined by:

```
Vibration amplitude = f(eccentric_mass, angular_velocity)
Vibration frequency = f(angular_velocity)
Angular velocity    = f(applied_voltage / PWM_duty_cycle)
```

Key physical behaviors:

- **Frequency and amplitude are coupled**: Unlike Linear Resonant Actuators (LRAs), ERM motors cannot independently control frequency and amplitude. Increasing the drive signal increases both the speed (frequency) and the centrifugal force (amplitude) simultaneously.
- **Spin-up latency**: ERM motors have a mechanical inertia that creates a noticeable delay (~20-50 ms) between the drive signal changing and the motor reaching the target speed. This is especially pronounced when going from 0 to a high value.
- **Spin-down latency**: Similarly, when the drive signal drops to zero, the motor takes time to decelerate and stop, creating a brief "tail" of residual vibration.
- **Minimum activation threshold**: Below a certain drive level, the motor does not have enough torque to overcome static friction and begin spinning. See Section 3 for measured thresholds.

### 1.4 Physical Placement

```
                    +---------------------------+
                    |        TOUCHPAD           |
                    |                           |
              +-----+                           +-----+
              |     |                           |     |
              | [L] |      (face buttons)       | [R] |
              |     |                           |     |
              |Heavy|                           |Light|
              |Motor|                           |Motor|
              |     |                           |     |
              +-----+                           +-----+
                Left Grip                  Right Grip

  L = Left Motor (Heavy/Slow, lower frequency, larger eccentric mass)
  R = Right Motor (Light/Fast, higher frequency, smaller eccentric mass)
```

---

## 2. Output Report Byte Offsets

### 2.1 USB Output Report (Report ID 0x05)

The rumble motor values are written as part of the standard 32-byte USB output report.

| Byte | Field | Range | Description |
|---|---|---|---|
| 0 | Report ID | `0x05` | Fixed USB output report identifier |
| 1 | Feature Flags | `0x07` | Bit 0 must be set to enable rumble updates |
| 2 | Feature Flags 2 | `0x04` | Typically `0x04` |
| 3 | Reserved | `0x00` | Padding |
| **4** | **Right Motor (Light/Fast)** | **0x00-0xFF** | **High-frequency rumble intensity** |
| **5** | **Left Motor (Heavy/Slow)** | **0x00-0xFF** | **Low-frequency rumble intensity** |
| 6 | LED Red | 0x00-0xFF | Light bar red channel |
| 7 | LED Green | 0x00-0xFF | Light bar green channel |
| 8 | LED Blue | 0x00-0xFF | Light bar blue channel |
| 9 | Flash On | 0x00-0xFF | Light bar flash on duration |
| 10 | Flash Off | 0x00-0xFF | Light bar flash off duration |
| 11-31 | Reserved | 0x00 | Padding |

**Reference:** [04-DS4-USB-Protocol, Section 3.1](./04-DS4-USB-Protocol.md)

### 2.2 Bluetooth Output Report (Report ID 0x11)

Over Bluetooth, the rumble values shift by +2 bytes due to the BT-specific header fields.

| Byte | Field | Range | Description |
|---|---|---|---|
| 0 | Report ID | `0x11` | Bluetooth output report identifier |
| 1 | BT Flags 1 | `0xC0` | EnableHID + EnableCRC + poll rate |
| 2 | BT Flags 2 | `0x00` | Microphone enable flags |
| 3 | Feature Flags | `0x07` | Bit 0 must be set to enable rumble updates |
| 4 | Feature Flags 2 | `0x04` | Typically `0x04` |
| 5 | Reserved | `0x00` | Padding |
| **6** | **Right Motor (Light/Fast)** | **0x00-0xFF** | **High-frequency rumble intensity** |
| **7** | **Left Motor (Heavy/Slow)** | **0x00-0xFF** | **Low-frequency rumble intensity** |
| 8 | LED Red | 0x00-0xFF | Light bar red channel |
| 9 | LED Green | 0x00-0xFF | Light bar green channel |
| 10 | LED Blue | 0x00-0xFF | Light bar blue channel |
| 11 | Flash On | 0x00-0xFF | Flash on duration |
| 12 | Flash Off | 0x00-0xFF | Flash off duration |
| 13-73 | Reserved/Audio | 0x00 | Padding / audio config |
| 74-77 | CRC-32 | 4 bytes | Required checksum (little-endian) |

**Reference:** [05-DS4-Bluetooth-Protocol, Section 6.2](./05-DS4-Bluetooth-Protocol.md)

### 2.3 Offset Comparison Table

| Field | USB Byte | BT Byte | Offset Shift |
|---|---|---|---|
| Right Motor (Light/Fast) | 4 | 6 | +2 |
| Left Motor (Heavy/Slow) | 5 | 7 | +2 |

**Important naming convention:** The output report bytes are ordered Right-then-Left (small motor first, large motor second), which is the opposite of what some developers might expect. DS4Windows uses the names `RumbleMotorStrengthRightLightFast` and `RumbleMotorStrengthLeftHeavySlow` to make this unambiguous.

From DS4Windows `DS4Device.cs`:
```csharp
outReportBuffer[4] = currentHap.rumbleState.RumbleMotorStrengthRightLightFast; // fast motor (USB byte 4)
outReportBuffer[5] = currentHap.rumbleState.RumbleMotorStrengthLeftHeavySlow;  // slow motor (USB byte 5)
```

From ds4drv `device.py`:
```python
pkt[offset+3] = min(small_rumble, 255)  # Right/weak motor
pkt[offset+4] = min(big_rumble, 255)    # Left/strong motor
```

---

## 3. Motor Characteristics

### 3.1 Minimum Activation Values

ERM motors require a minimum drive signal to overcome static friction and begin spinning. Below this threshold the motor is electrically energized but does not produce perceptible vibration. The exact threshold varies between individual controllers due to manufacturing tolerances and wear, but typical observed values are:

| Motor | Approximate Minimum | Notes |
|---|---|---|
| Left (Heavy/Slow) | ~0x10 - 0x20 (16-32) | Larger mass requires more torque to start |
| Right (Light/Fast) | ~0x08 - 0x14 (8-20) | Smaller mass starts more easily |

**Recommendation:** For reliable activation across all controller units, use a minimum value of at least `0x20` (32) for the heavy motor and `0x14` (20) for the light motor. Values below these thresholds should be clamped to zero to avoid a "buzzing but not vibrating" state where the motor coil is energized but the shaft is not spinning.

```c
// Clamp values below activation threshold to zero
uint8_t clampMotorValue(uint8_t value, uint8_t threshold) {
    return (value >= threshold) ? value : 0;
}

// Example thresholds
#define HEAVY_MOTOR_MIN  0x20  // ~32
#define LIGHT_MOTOR_MIN  0x14  // ~20
```

### 3.2 Frequency Response

Because ERM motors couple frequency and amplitude, the vibration frequency increases with the drive level:

| Drive Level | Left Motor (approx.) | Right Motor (approx.) |
|---|---|---|
| Low (~0x20-0x40) | ~60-80 Hz | ~150-180 Hz |
| Medium (~0x40-0xA0) | ~80-100 Hz | ~180-240 Hz |
| High (~0xA0-0xFF) | ~100-120 Hz | ~240-300 Hz |

These are approximate ranges. The actual frequencies depend on the specific motor, controller revision, and battery voltage (Bluetooth operation at lower battery levels may reduce motor voltage).

### 3.3 Response Time

| Transition | Approximate Latency |
|---|---|
| 0 to max (spin-up) | ~30-50 ms |
| Max to 0 (spin-down) | ~40-80 ms |
| Mid to mid (speed change) | ~10-30 ms |
| Report transmission (USB) | ~4 ms per report |
| Report transmission (BT) | ~1.25 ms per report (single controller) |

The spin-up latency means that very short pulses (under ~30 ms) will not reach full intensity before the motor is commanded to stop. For crisp haptic "clicks," the minimum pulse duration should be at least 40-60 ms.

### 3.4 Power Consumption

Rumble motors are the largest power consumers on the DS4 after the radio and light bar at maximum brightness. Continuous high-intensity rumble on both motors can noticeably reduce battery life during Bluetooth operation.

| State | Approximate Current Draw (combined) |
|---|---|
| Both motors off | ~0 mA (negligible) |
| Light motor only, medium | ~40-80 mA |
| Heavy motor only, medium | ~80-150 mA |
| Both motors, full intensity | ~200-350 mA |

For battery-conscious applications, prefer using only the light motor for subtle effects and limit heavy motor usage to impactful moments.

---

## 4. Feature Flags and Activation

### 4.1 Enabling Rumble in Output Reports

The rumble motors are only updated when the Feature Flags byte has bit 0 set (`0x01`). Without this flag, the motor values in the report are ignored by the controller firmware.

| Bit | Mask | Feature |
|---|---|---|
| 0 | `0x01` | **Enable rumble motor update** |
| 1 | `0x02` | Enable light bar color update |
| 2 | `0x04` | Enable light bar flash update |

**Common combinations:**

| Value | Meaning |
|---|---|
| `0x01` | Rumble only (no light bar changes) |
| `0x03` | Rumble + light bar color |
| `0x07` | Rumble + light bar color + flash (standard default) |

From DS4Windows `DS4OutDevice.cs`:
```csharp
internal const byte RUMBLE_FEATURE_FLAG = 0x01;
```

### 4.2 Stopping Rumble

To stop both rumble motors, set both motor values to `0x00` and send the output report with the rumble feature flag enabled:

```c
// USB: Stop rumble
buf[1] = 0x07;  // Feature flags (rumble enabled)
buf[4] = 0x00;  // Right motor = off
buf[5] = 0x00;  // Left motor = off
```

**Important:** Simply omitting the rumble feature flag (`0x00` in the feature byte) does **not** stop the motors. It tells the controller to ignore the motor fields, leaving whatever rumble was previously set still running.

### 4.3 Rumble and Light Bar Simultaneity

Rumble and light bar values are transmitted in the same output report. This means:

1. Every time you update the light bar, you must also include the desired rumble values (or vice versa).
2. If you send a light-bar-only update with the rumble bytes set to zero and the rumble flag enabled, it will stop any active rumble effect.
3. DS4Windows and ds4drv both maintain a combined haptic state (`DS4HapticState`) that merges rumble and light bar settings into each output report.

---

## 5. Rumble Boost and Scaling

### 5.1 Rumble Boost (DS4Windows)

DS4Windows provides a user-configurable **Rumble Boost** setting (0-255, default 100) that scales all rumble values as a percentage. This allows users to amplify or attenuate the rumble intensity globally for each controller profile.

**Boost formula:**

```
boosted_value = (raw_value * boost_percentage) / 100
if boosted_value > 255:
    boosted_value = 255
```

From DS4Windows `ControlService.cs`:
```csharp
byte boost = getRumbleBoost(deviceNum);
uint lightBoosted = ((uint)lightMotor * (uint)boost) / 100;
if (lightBoosted > 255)
    lightBoosted = 255;
uint heavyBoosted = ((uint)heavyMotor * (uint)boost) / 100;
if (heavyBoosted > 255)
    heavyBoosted = 255;
```

| Boost Value | Effect |
|---|---|
| 0 | Rumble completely disabled |
| 50 | Rumble at 50% of requested intensity |
| 100 | Rumble at exactly requested intensity (default) |
| 150 | Rumble at 150% (clamped to 255 max) |
| 255 | Rumble at 255% of requested (extreme amplification, clamped) |

### 5.2 Motor Inversion (DS4Windows)

DS4Windows supports swapping the heavy and light motor assignments via the `InverseRumbleMotors` option. This is useful for controllers with non-standard motor wiring or for users who prefer the physical sensation reversed.

From DS4Windows `Mapping.cs`:
```csharp
if (Global.InverseRumbleMotors[device])
    d.setRumble(heavy, light);
else
    d.setRumble(light, heavy);
```

### 5.3 Implementing Rumble Scaling for macOS

A recommended approach for a macOS driver:

```swift
struct RumbleConfiguration {
    /// Boost percentage (0-255). Default 100 = 1:1 mapping.
    var boostPercent: UInt8 = 100

    /// Swap heavy and light motor assignments.
    var inverseMotors: Bool = false

    /// Minimum activation threshold for heavy motor.
    var heavyMotorMinThreshold: UInt8 = 0x20

    /// Minimum activation threshold for light motor.
    var lightMotorMinThreshold: UInt8 = 0x14

    func apply(heavy: UInt8, light: UInt8) -> (heavy: UInt8, light: UInt8) {
        // Apply boost scaling
        var h = min(UInt16(heavy) * UInt16(boostPercent) / 100, 255)
        var l = min(UInt16(light) * UInt16(boostPercent) / 100, 255)

        // Apply minimum activation thresholds
        if h > 0 && h < UInt16(heavyMotorMinThreshold) { h = 0 }
        if l > 0 && l < UInt16(lightMotorMinThreshold) { l = 0 }

        // Apply motor inversion if configured
        if inverseMotors {
            return (heavy: UInt8(l), light: UInt8(h))
        }
        return (heavy: UInt8(h), light: UInt8(l))
    }
}
```

---

## 6. Haptic Patterns and Effects

### 6.1 Basic Rumble Patterns

The following table catalogs common haptic patterns used in game development, expressed as motor intensity values and timing.

| Pattern Name | Heavy Motor | Light Motor | Duration | Description |
|---|---|---|---|---|
| **Gentle tap** | 0 | 80 | 60 ms | Subtle UI confirmation |
| **Button click** | 0 | 160 | 40 ms | Crisp button-press feedback |
| **Soft thud** | 100 | 0 | 100 ms | Soft impact (landing, footstep) |
| **Hard impact** | 255 | 128 | 150 ms | Heavy hit (punch, collision) |
| **Explosion** | 255 | 255 | 300 ms | Maximum intensity on both motors |
| **Rumble strip** | 0 | 200 | Repeating 30 ms on / 30 ms off | Racing game road edge |
| **Engine idle** | 40 | 20 | Continuous | Low persistent vibration |
| **Engine rev** | 80-200 | 40-100 | Continuous, variable | Proportional to RPM |
| **Heartbeat** | 180 | 0 | 80 ms on, 100 ms off, 80 ms on, 600 ms off | Double-pulse pattern |
| **Damage taken** | 200 | 255 | 200 ms | Both motors, sharp onset |
| **Low health pulse** | 120 | 0 | 200 ms on, 800 ms off | Slow rhythmic warning |
| **Gun recoil (pistol)** | 200 | 100 | 80 ms | Sharp single pulse |
| **Gun recoil (auto)** | 160 | 80 | Repeating 50 ms on / 30 ms off | Rapid fire pattern |
| **Shield break** | 255 | 255 | 100 ms decay to 0 | Maximum then fade |

### 6.2 DS4Windows Extras-Based Rumble

DS4Windows supports mapping button actions to rumble effects via the "extras" system. When a button with extras is held, the rumble activates; when released, it stops.

**Extras array format:**
```
extras[0] = heavy motor value (0-255)
extras[1] = light motor value (0-255)
extras[2] = light bar override enable (0 or 1)
extras[3] = LED red
extras[4] = LED green
extras[5] = LED blue
extras[6] = LED flash
extras[7] = mouse sensitivity override enable (0 or 1)
extras[8] = mouse sensitivity value
```

From DS4Windows `Mapping.cs`:
```csharp
if (!(extras[0] == extras[1] && extras[1] == 0))
{
    ctrl.setRumble((byte)extras[0], (byte)extras[1], device);
    extrasRumbleActive[device] = true;
}
```

When the button is released:
```csharp
if (extrasRumbleActive[device])
{
    ctrl.setRumble(0, 0, device);
    extrasRumbleActive[device] = false;
}
```

### 6.3 DS4Windows Macro Rumble Events

DS4Windows macros can embed rumble events using a special encoding. Macro codes >= 1,000,000 are interpreted as rumble commands:

**Macro rumble encoding:**
```
Code format: 1HHHLLLL (7 digits)
  HHH = heavy motor value (3-digit decimal: 000-255)
  LLL = light motor value (3-digit decimal: 000-255)

Example: 1128064 -> heavy=128, light=064
Example: 1255000 -> heavy=255, light=000 (heavy motor only)
Example: 1000200 -> heavy=000, light=200 (light motor only)
Example: 1000000 -> heavy=000, light=000 (stop rumble)
```

From DS4Windows `Mapping.cs`:
```csharp
// Rumble event (macroCodeValue >= 1000000)
string r = macroCodeValue.ToString().Substring(1);
byte heavy = (byte)(int.Parse(r[0].ToString()) * 100 +
                    int.Parse(r[1].ToString()) * 10 +
                    int.Parse(r[2].ToString()));
byte light = (byte)(int.Parse(r[3].ToString()) * 100 +
                    int.Parse(r[4].ToString()) * 10 +
                    int.Parse(r[5].ToString()));
```

A macro sequence to create a "damage taken" effect:
```
1255255    // Start: both motors at max
  300200   // Wait 200ms (delay codes are 300+ms offset)
1000000    // Stop: both motors off
```

### 6.4 DS4Windows Haptic State Architecture

DS4Windows uses a layered haptic state system with a clear separation between force feedback (rumble) and lightbar state:

```csharp
// Force feedback state (rumble motors only)
public struct DS4ForceFeedbackState {
    public byte RumbleMotorStrengthLeftHeavySlow;
    public byte RumbleMotorStrengthRightLightFast;
    public bool RumbleMotorsExplicitlyOff;
}

// Combined haptic state (rumble + lightbar)
public struct DS4HapticState {
    public DS4LightbarState lightbarState;
    public DS4ForceFeedbackState rumbleState;
    public bool dirty;
}
```

The `RumbleMotorsExplicitlyOff` flag distinguishes between "no rumble requested" and "rumble explicitly set to zero," which is important for state change detection and output report optimization.

---

## 7. Rumble-Light Bar Integration

### 7.1 Synchronized Feedback

Because rumble and light bar values share the same output report, they can be synchronized to create multi-sensory feedback effects. For example:

| Game Event | Rumble Effect | Light Bar Effect |
|---|---|---|
| Damage taken | Heavy=200, Light=255, 200 ms | Flash red, 200 ms |
| Health critical | Heavy=120, Light=0, pulsing | Red, slow flash |
| Shield active | Light=60, continuous | Cyan glow |
| Explosion | Heavy=255, Light=255, 300 ms | Orange flash to red fade |
| Power-up collected | Light=100, 80 ms | Gold pulse |
| Stealth mode | None | Dim purple |

### 7.2 Distance Profile (DS4Windows)

DS4Windows implements a "Distance" profile where the light bar color dynamically responds to rumble intensity. When the heavy motor exceeds certain thresholds, the light bar transitions from the base color toward red and begins flashing:

From DS4Windows `DS4LightBar.cs`:
```csharp
// When heavy rumble > 100: transition lightbar toward red
if (device.getLeftHeavySlowRumble() > 100)
{
    DS4Color maxCol = new DS4Color(max, max, 0);
    DS4Color redCol = new DS4Color(255, 0, 0);
    color = getTransitionedColor(ref maxCol, ref redCol, rumble);
}

// When heavy rumble > 155: flash the lightbar in sync
if (distanceprofile && device.getLeftHeavySlowRumble() > 155)
{
    lightState.LightBarFlashDurationOff =
        lightState.LightBarFlashDurationOn =
            (byte)((-device.getLeftHeavySlowRumble() + 265));
}
```

This creates a dynamic link where stronger vibration causes more aggressive light bar feedback, enhancing immersion.

---

## 8. Autostop and Safety

### 8.1 Rumble Autostop Timer

DS4Windows implements a safety timer that automatically stops rumble motors after a configurable timeout. This prevents motors from running indefinitely if the game or application fails to send a stop command (for example, due to a crash or a lost ViGEm notification).

From DS4Windows `DS4Device.cs`:
```csharp
private readonly Stopwatch rumbleAutostopTimer = new Stopwatch();

// In the output report loop:
if (rumbleAutostopTimer.IsRunning)
{
    if (rumbleAutostopTimer.ElapsedMilliseconds >= rumbleAutostopTime)
        setRumble(0, 0);
}
```

**Configuration:**
- `rumbleAutostopTime` = 0: Timer disabled (rumble runs until explicitly stopped)
- `rumbleAutostopTime` > 0: Rumble stops after this many milliseconds of no new rumble events

**Recommended default:** 5000 ms (5 seconds). This provides a safety net without interfering with long game-driven effects.

### 8.2 Implementing Autostop for macOS

```swift
class RumbleAutostopTimer {
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.ds4mac.rumble-autostop")
    private var timeoutMs: Int = 0
    private var stopHandler: (() -> Void)?

    func configure(timeoutMs: Int, stopHandler: @escaping () -> Void) {
        self.timeoutMs = timeoutMs
        self.stopHandler = stopHandler
    }

    /// Call whenever a new rumble event is received.
    func restart() {
        cancel()
        guard timeoutMs > 0 else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(timeoutMs))
        timer.setEventHandler { [weak self] in
            self?.stopHandler?()
        }
        timer.resume()
        self.timer = timer
    }

    /// Call when rumble is explicitly set to zero.
    func cancel() {
        timer?.cancel()
        timer = nil
    }
}
```

---

## 9. macOS Implementation Guide

### 9.1 Setting Rumble via USB (IOKit)

```objc
#import <IOKit/hid/IOHIDManager.h>

void ds4_set_rumble_usb(IOHIDDeviceRef device,
                         uint8_t rightLightFast,
                         uint8_t leftHeavySlow,
                         uint8_t ledRed,
                         uint8_t ledGreen,
                         uint8_t ledBlue) {
    uint8_t report[32] = {0};

    report[0]  = 0x05;           // Report ID
    report[1]  = 0x07;           // Features: rumble + lightbar + flash
    report[2]  = 0x04;
    report[3]  = 0x00;
    report[4]  = rightLightFast; // Right motor (light/fast)
    report[5]  = leftHeavySlow;  // Left motor (heavy/slow)
    report[6]  = ledRed;
    report[7]  = ledGreen;
    report[8]  = ledBlue;
    report[9]  = 0x00;           // Flash on (0 = no flash)
    report[10] = 0x00;           // Flash off (0 = no flash)

    IOHIDDeviceSetReport(device,
                         kIOHIDReportTypeOutput,
                         0x05,
                         report + 1,  // Skip report ID for IOKit
                         31);
}
```

### 9.2 Setting Rumble via Bluetooth (IOKit + CRC-32)

```objc
#import <IOKit/hid/IOHIDManager.h>
#import <zlib.h>

void ds4_set_rumble_bt(IOHIDDeviceRef device,
                        uint8_t rightLightFast,
                        uint8_t leftHeavySlow,
                        uint8_t ledRed,
                        uint8_t ledGreen,
                        uint8_t ledBlue) {
    uint8_t report[78] = {0};

    report[0]  = 0x11;           // Report ID
    report[1]  = 0xC0;           // BT flags: EnableHID + EnableCRC
    report[2]  = 0x00;           // BT flags 2
    report[3]  = 0x07;           // Features: rumble + lightbar + flash
    report[4]  = 0x04;
    report[5]  = 0x00;
    report[6]  = rightLightFast; // Right motor (light/fast)
    report[7]  = leftHeavySlow;  // Left motor (heavy/slow)
    report[8]  = ledRed;
    report[9]  = ledGreen;
    report[10] = ledBlue;
    report[11] = 0x00;           // Flash on
    report[12] = 0x00;           // Flash off

    // CRC-32: seed with 0xA2, then hash report bytes [0..73]
    uint8_t seed = 0xA2;
    uint32_t crc = (uint32_t)crc32(0L, Z_NULL, 0);
    crc = (uint32_t)crc32(crc, &seed, 1);
    crc = (uint32_t)crc32(crc, report, 74);

    report[74] = (uint8_t)(crc & 0xFF);
    report[75] = (uint8_t)((crc >> 8) & 0xFF);
    report[76] = (uint8_t)((crc >> 16) & 0xFF);
    report[77] = (uint8_t)((crc >> 24) & 0xFF);

    IOHIDDeviceSetReport(device,
                         kIOHIDReportTypeOutput,
                         0x11,
                         report + 1,
                         77);
}
```

### 9.3 Transport-Agnostic Rumble Function

```objc
typedef enum {
    DS4TransportUSB,
    DS4TransportBluetooth
} DS4Transport;

void ds4_set_rumble(IOHIDDeviceRef device,
                     DS4Transport transport,
                     uint8_t rightLightFast,
                     uint8_t leftHeavySlow,
                     uint8_t ledRed,
                     uint8_t ledGreen,
                     uint8_t ledBlue) {
    if (transport == DS4TransportUSB) {
        ds4_set_rumble_usb(device, rightLightFast, leftHeavySlow,
                           ledRed, ledGreen, ledBlue);
    } else {
        ds4_set_rumble_bt(device, rightLightFast, leftHeavySlow,
                          ledRed, ledGreen, ledBlue);
    }
}
```

---

## 10. macOS Core Haptics Integration

### 10.1 Overview

Apple's **Core Haptics** framework (available since macOS 10.15 Catalina) provides a high-level API for designing haptic experiences. While Core Haptics is primarily designed for the Taptic Engine in MacBooks and iPhones, its pattern-design concepts can be adapted for DS4 rumble motor control.

The general approach is to define haptic patterns using Core Haptics' event model, then translate those patterns into DS4 motor commands through a custom player/renderer.

### 10.2 Core Haptics Concepts Mapped to DS4

| Core Haptics Concept | DS4 Mapping |
|---|---|
| `CHHapticEvent` (transient) | Short rumble pulse (40-150 ms) |
| `CHHapticEvent` (continuous) | Sustained rumble at specified intensity |
| `CHHapticEventParameter` (intensity) | Motor value (0.0-1.0 mapped to 0x00-0xFF) |
| `CHHapticEventParameter` (sharpness) | Motor selection (0.0 = heavy only, 1.0 = light only) |
| `CHHapticPattern` | Sequence of timed rumble commands |
| `CHHapticDynamicParameter` | Real-time intensity/sharpness modification |

### 10.3 Sharpness-to-Motor Mapping

The Core Haptics "sharpness" parameter naturally maps to the DS4's dual motor system:

```
sharpness = 0.0  ->  100% heavy motor, 0% light motor (deep rumble)
sharpness = 0.5  ->  50% heavy motor, 50% light motor (balanced)
sharpness = 1.0  ->  0% heavy motor, 100% light motor (sharp buzz)
```

**Implementation:**

```swift
func mapHapticToMotors(intensity: Float, sharpness: Float) -> (heavy: UInt8, light: UInt8) {
    let clampedIntensity = max(0.0, min(1.0, intensity))
    let clampedSharpness = max(0.0, min(1.0, sharpness))

    let heavyRatio = 1.0 - clampedSharpness
    let lightRatio = clampedSharpness

    let heavy = UInt8(clampedIntensity * heavyRatio * 255.0)
    let light = UInt8(clampedIntensity * lightRatio * 255.0)

    return (heavy: heavy, light: light)
}
```

### 10.4 AHAP-Inspired Pattern Engine

Apple Haptic and Audio Pattern (AHAP) files describe haptic sequences as JSON. The following shows a DS4 rumble pattern engine inspired by this format:

```swift
struct DS4HapticEvent {
    enum EventType {
        case transient   // Short pulse
        case continuous  // Sustained rumble
    }

    let type: EventType
    let time: TimeInterval        // Start time (seconds from pattern start)
    let duration: TimeInterval    // Duration (only for continuous)
    let intensity: Float          // 0.0 - 1.0
    let sharpness: Float          // 0.0 (heavy) - 1.0 (light)
}

struct DS4HapticPattern {
    let events: [DS4HapticEvent]

    /// Default transient pulse duration
    static let transientDuration: TimeInterval = 0.06  // 60ms
}

class DS4HapticPlayer {
    private let device: IOHIDDevice
    private let transport: DS4Transport
    private var playbackTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.ds4mac.haptics")

    init(device: IOHIDDevice, transport: DS4Transport) {
        self.device = device
        self.transport = transport
    }

    func play(pattern: DS4HapticPattern) {
        // Sort events by time
        let sorted = pattern.events.sorted { $0.time < $1.time }

        // Build timeline of motor state changes
        var timeline: [(time: TimeInterval, heavy: UInt8, light: UInt8)] = []

        for event in sorted {
            let motors = mapHapticToMotors(intensity: event.intensity,
                                           sharpness: event.sharpness)
            timeline.append((time: event.time,
                           heavy: motors.heavy,
                           light: motors.light))

            // Schedule the stop event
            let endTime: TimeInterval
            switch event.type {
            case .transient:
                endTime = event.time + DS4HapticPattern.transientDuration
            case .continuous:
                endTime = event.time + event.duration
            }
            timeline.append((time: endTime, heavy: 0, light: 0))
        }

        // Sort by time and execute
        timeline.sort { $0.time < $1.time }
        executeTimeline(timeline)
    }

    private func executeTimeline(_ timeline: [(time: TimeInterval, heavy: UInt8, light: UInt8)]) {
        let startTime = DispatchTime.now()
        for entry in timeline {
            queue.asyncAfter(deadline: startTime + entry.time) { [weak self] in
                guard let self = self else { return }
                ds4_set_rumble(self.device, self.transport,
                              entry.light, entry.heavy,
                              0, 0, 0)  // Preserve current LED state in real impl
            }
        }
    }
}
```

### 10.5 Predefined AHAP-Style Patterns

```swift
extension DS4HapticPattern {
    /// Single sharp tap (UI button press)
    static let tap = DS4HapticPattern(events: [
        DS4HapticEvent(type: .transient, time: 0, duration: 0,
                       intensity: 0.6, sharpness: 0.8)
    ])

    /// Double tap (notification)
    static let doubleTap = DS4HapticPattern(events: [
        DS4HapticEvent(type: .transient, time: 0, duration: 0,
                       intensity: 0.5, sharpness: 0.7),
        DS4HapticEvent(type: .transient, time: 0.12, duration: 0,
                       intensity: 0.5, sharpness: 0.7)
    ])

    /// Heavy impact (collision, punch)
    static let heavyImpact = DS4HapticPattern(events: [
        DS4HapticEvent(type: .continuous, time: 0, duration: 0.15,
                       intensity: 1.0, sharpness: 0.2)
    ])

    /// Explosion (layered: initial burst + lingering rumble)
    static let explosion = DS4HapticPattern(events: [
        DS4HapticEvent(type: .continuous, time: 0, duration: 0.08,
                       intensity: 1.0, sharpness: 0.3),
        DS4HapticEvent(type: .continuous, time: 0.08, duration: 0.25,
                       intensity: 0.6, sharpness: 0.1),
        DS4HapticEvent(type: .continuous, time: 0.33, duration: 0.15,
                       intensity: 0.2, sharpness: 0.0)
    ])

    /// Heartbeat (double-pulse)
    static let heartbeat = DS4HapticPattern(events: [
        DS4HapticEvent(type: .continuous, time: 0, duration: 0.08,
                       intensity: 0.7, sharpness: 0.1),
        DS4HapticEvent(type: .continuous, time: 0.18, duration: 0.08,
                       intensity: 0.7, sharpness: 0.1)
        // Repeat after ~0.86 seconds for continuous heartbeat
    ])

    /// Gun recoil (single shot)
    static let gunshot = DS4HapticPattern(events: [
        DS4HapticEvent(type: .continuous, time: 0, duration: 0.04,
                       intensity: 1.0, sharpness: 0.4),
        DS4HapticEvent(type: .continuous, time: 0.04, duration: 0.06,
                       intensity: 0.4, sharpness: 0.2)
    ])

    /// Engine idle (continuous low rumble)
    static let engineIdle = DS4HapticPattern(events: [
        DS4HapticEvent(type: .continuous, time: 0, duration: 10.0,
                       intensity: 0.15, sharpness: 0.2)
    ])
}
```

### 10.6 GCController Haptics (Game Controller Framework)

On macOS 11+, Apple's **Game Controller** framework (`GCController`) provides native haptic support. If the DS4 is recognized as a `GCController`, rumble may be accessible through `GCController.haptics`:

```swift
import GameController

func playRumbleViaGameController(controller: GCController) {
    guard let haptics = controller.haptics else {
        print("Controller does not support haptics via GameController framework")
        return
    }

    // Create engine for the left handle (heavy motor)
    if let leftEngine = haptics.createEngine(withLocality: .leftHandle) {
        do {
            let pattern = try CHHapticPattern(events: [
                CHHapticEvent(eventType: .hapticContinuous,
                             parameters: [
                                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.0)
                             ],
                             relativeTime: 0,
                             duration: 0.2)
            ], parameters: [])

            let player = try leftEngine.makePlayer(with: pattern)
            try leftEngine.start()
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Haptic error: \(error)")
        }
    }

    // Create engine for the right handle (light motor)
    if let rightEngine = haptics.createEngine(withLocality: .rightHandle) {
        // Similar pattern setup for the right/light motor
    }
}
```

**Important caveats:**
- macOS may not expose the DS4 as a `GCController` in all configurations, particularly over raw HID access.
- The `GCController` haptics API abstracts away the individual motor control. For precise dual-motor control, direct HID output reports via IOKit are recommended.
- `GCController` haptics locality `.leftHandle` and `.rightHandle` map to the heavy and light motors respectively.

---

## 11. Code Examples

### 11.1 Complete Swift Rumble Controller

```swift
import IOKit.hid

// MARK: - Rumble Data Types

struct DS4RumbleState: Equatable {
    var rightLightFast: UInt8 = 0
    var leftHeavySlow: UInt8 = 0
    var explicitlyOff: Bool = false

    static let off = DS4RumbleState(rightLightFast: 0, leftHeavySlow: 0, explicitlyOff: true)

    var isActive: Bool {
        return rightLightFast > 0 || leftHeavySlow > 0
    }
}

struct DS4OutputState {
    var rumble: DS4RumbleState = .off
    var ledRed: UInt8 = 0
    var ledGreen: UInt8 = 0
    var ledBlue: UInt8 = 64
    var flashOn: UInt8 = 0
    var flashOff: UInt8 = 0
}

enum DS4Connection {
    case usb
    case bluetooth
}

// MARK: - Output Report Builder

class DS4RumbleController {
    let device: IOHIDDevice
    let connection: DS4Connection
    var config = RumbleConfiguration()
    private var currentState = DS4OutputState()

    init(device: IOHIDDevice, connection: DS4Connection) {
        self.device = device
        self.connection = connection
    }

    // MARK: High-Level API

    /// Set rumble with raw motor values.
    func setRumble(heavy: UInt8, light: UInt8) {
        let scaled = config.apply(heavy: heavy, light: light)
        currentState.rumble.leftHeavySlow = scaled.heavy
        currentState.rumble.rightLightFast = scaled.light
        currentState.rumble.explicitlyOff = (scaled.heavy == 0 && scaled.light == 0)
        sendOutputReport()
    }

    /// Set rumble using intensity (0.0-1.0) and sharpness (0.0=heavy, 1.0=light).
    func setRumble(intensity: Float, sharpness: Float) {
        let motors = mapHapticToMotors(intensity: intensity, sharpness: sharpness)
        setRumble(heavy: motors.heavy, light: motors.light)
    }

    /// Stop all rumble immediately.
    func stopRumble() {
        setRumble(heavy: 0, light: 0)
    }

    /// Set LED color (preserves current rumble state).
    func setLED(red: UInt8, green: UInt8, blue: UInt8) {
        currentState.ledRed = red
        currentState.ledGreen = green
        currentState.ledBlue = blue
        sendOutputReport()
    }

    // MARK: Output Report

    private func sendOutputReport() {
        switch connection {
        case .usb:
            sendUSBReport()
        case .bluetooth:
            sendBluetoothReport()
        }
    }

    private func sendUSBReport() {
        var report = [UInt8](repeating: 0, count: 32)
        report[0]  = 0x05
        report[1]  = 0x07  // rumble + lightbar + flash
        report[2]  = 0x04
        report[4]  = currentState.rumble.rightLightFast
        report[5]  = currentState.rumble.leftHeavySlow
        report[6]  = currentState.ledRed
        report[7]  = currentState.ledGreen
        report[8]  = currentState.ledBlue
        report[9]  = currentState.flashOn
        report[10] = currentState.flashOff

        report.withUnsafeBufferPointer { buf in
            let ptr = buf.baseAddress!.advanced(by: 1)
            IOHIDDeviceSetReport(device,
                                 kIOHIDReportType(kIOHIDReportTypeOutput),
                                 0x05, ptr, 31)
        }
    }

    private func sendBluetoothReport() {
        var report = [UInt8](repeating: 0, count: 78)
        report[0]  = 0x11
        report[1]  = 0xC0
        report[2]  = 0x00
        report[3]  = 0x07
        report[4]  = 0x04
        report[6]  = currentState.rumble.rightLightFast
        report[7]  = currentState.rumble.leftHeavySlow
        report[8]  = currentState.ledRed
        report[9]  = currentState.ledGreen
        report[10] = currentState.ledBlue
        report[11] = currentState.flashOn
        report[12] = currentState.flashOff

        // CRC-32
        var crcData = Data([0xA2])
        crcData.append(Data(report[0..<74]))
        let crc = crc32Compute(crcData)
        report[74] = UInt8(crc & 0xFF)
        report[75] = UInt8((crc >> 8) & 0xFF)
        report[76] = UInt8((crc >> 16) & 0xFF)
        report[77] = UInt8((crc >> 24) & 0xFF)

        report.withUnsafeBufferPointer { buf in
            let ptr = buf.baseAddress!.advanced(by: 1)
            IOHIDDeviceSetReport(device,
                                 kIOHIDReportType(kIOHIDReportTypeOutput),
                                 0x11, ptr, 77)
        }
    }
}
```

### 11.2 Timed Rumble Effects (Swift)

```swift
extension DS4RumbleController {

    /// Play a short rumble pulse.
    func pulse(heavy: UInt8, light: UInt8, durationMs: Int) {
        setRumble(heavy: heavy, light: light)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(durationMs)) { [weak self] in
            self?.stopRumble()
        }
    }

    /// Play a repeating rumble pattern.
    func repeatPattern(heavy: UInt8, light: UInt8,
                       onMs: Int, offMs: Int, repeatCount: Int) {
        var iteration = 0
        func playNext() {
            guard iteration < repeatCount else {
                stopRumble()
                return
            }
            setRumble(heavy: heavy, light: light)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(onMs)) { [weak self] in
                self?.stopRumble()
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(offMs)) {
                    iteration += 1
                    playNext()
                }
            }
        }
        playNext()
    }

    /// Play a decaying rumble (e.g., for an explosion aftershock).
    func decayingRumble(initialHeavy: UInt8, initialLight: UInt8,
                         durationMs: Int, steps: Int = 10) {
        let stepMs = durationMs / steps
        for i in 0..<steps {
            let factor = Float(steps - i) / Float(steps)
            let h = UInt8(Float(initialHeavy) * factor)
            let l = UInt8(Float(initialLight) * factor)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(i * stepMs)) { [weak self] in
                self?.setRumble(heavy: h, light: l)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(durationMs)) { [weak self] in
            self?.stopRumble()
        }
    }
}
```

### 11.3 Game-Driven Rumble Examples

```swift
// UI button press feedback
controller.pulse(heavy: 0, light: 128, durationMs: 50)

// Footstep (subtle)
controller.pulse(heavy: 60, light: 0, durationMs: 80)

// Gunshot recoil
controller.pulse(heavy: 220, light: 140, durationMs: 100)

// Automatic weapon fire (5 rounds)
controller.repeatPattern(heavy: 180, light: 100,
                          onMs: 50, offMs: 30, repeatCount: 5)

// Explosion with decay
controller.decayingRumble(initialHeavy: 255, initialLight: 255,
                           durationMs: 400, steps: 8)

// Engine idle (continuous)
controller.setRumble(heavy: 35, light: 15)

// Engine proportional to speed (0.0 - 1.0)
func updateEngineRumble(speed: Float) {
    let heavy = UInt8(min(Float(40) + speed * 180.0, 255.0))
    let light = UInt8(min(Float(15) + speed * 80.0, 255.0))
    controller.setRumble(heavy: heavy, light: light)
}

// Heartbeat (low health warning)
func playHeartbeat() {
    controller.pulse(heavy: 180, light: 0, durationMs: 80)
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180)) {
        controller.pulse(heavy: 180, light: 0, durationMs: 80)
    }
    // Repeat after ~860 ms total for continuous heartbeat
}

// Racing game rumble strip
controller.repeatPattern(heavy: 0, light: 200,
                          onMs: 30, offMs: 30, repeatCount: 10)

// Damage taken with synchronized red flash
func onDamageTaken() {
    var state = DS4OutputState()
    state.rumble = DS4RumbleState(rightLightFast: 255, leftHeavySlow: 200)
    state.ledRed = 255
    state.ledGreen = 0
    state.ledBlue = 0
    // Send combined rumble + LED in single output report
    // ... (send output report with these values)

    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
        controller.stopRumble()
        controller.setLED(red: 0, green: 0, blue: 64) // Restore player color
    }
}
```

### 11.4 ds4drv Rumble API (Python Reference)

The ds4drv reference implementation from chrippa provides a simple rumble API:

```python
# ds4drv/device.py

def rumble(self, small=0, big=0):
    """Sets the intensity of the rumble motors. Valid range is 0-255.

    Args:
        small: Right/light/fast motor intensity (0-255)
        big:   Left/heavy/slow motor intensity (0-255)
    """
    self._control(small_rumble=small, big_rumble=big)

def control(self, big_rumble=0, small_rumble=0,
            led_red=0, led_green=0, led_blue=0,
            flash_led1=0, flash_led2=0):
    if self.type == "bluetooth":
        pkt = bytearray(77)
        pkt[0] = 128        # 0x80 -- EnableHID flag
        pkt[2] = 255        # 0xFF -- Feature enable all
        offset = 2
        report_id = 0x11
    elif self.type == "usb":
        pkt = bytearray(31)
        pkt[0] = 255        # 0xFF -- Feature enable all
        offset = 0
        report_id = 0x05

    # Rumble motor values
    pkt[offset+3] = min(small_rumble, 255)   # Right/weak motor
    pkt[offset+4] = min(big_rumble, 255)     # Left/strong motor

    # LED color
    pkt[offset+5] = min(led_red, 255)
    pkt[offset+6] = min(led_green, 255)
    pkt[offset+7] = min(led_blue, 255)

    # Flash timing
    pkt[offset+8] = min(flash_led1, 255)
    pkt[offset+9] = min(flash_led2, 255)

    self.write_report(report_id, pkt)
```

---

## 12. Cross-Reference Summary

### Protocol Documents

| Topic | Document | Section |
|---|---|---|
| USB output report byte map | [04-DS4-USB-Protocol](./04-DS4-USB-Protocol.md) | Section 3 (Output Report 0x05) |
| USB rumble motor bytes | [04-DS4-USB-Protocol](./04-DS4-USB-Protocol.md) | Section 3.3 (Rumble Motors) |
| USB feature flags | [04-DS4-USB-Protocol](./04-DS4-USB-Protocol.md) | Section 3.2 (Feature Flags) |
| USB output report code example | [04-DS4-USB-Protocol](./04-DS4-USB-Protocol.md) | Section 9.2 (Constructing Output Report) |
| BT output report byte map | [05-DS4-Bluetooth-Protocol](./05-DS4-Bluetooth-Protocol.md) | Section 6 (Output Report 0x11) |
| BT rumble byte offsets | [05-DS4-Bluetooth-Protocol](./05-DS4-Bluetooth-Protocol.md) | Section 6.5 (Offset Difference) |
| BT CRC-32 for output reports | [05-DS4-Bluetooth-Protocol](./05-DS4-Bluetooth-Protocol.md) | Section 8 (CRC-32 Calculation) |
| BT output code example | [05-DS4-Bluetooth-Protocol](./05-DS4-Bluetooth-Protocol.md) | Section 13.2 (Constructing BT Output) |
| Light bar + rumble integration | [06-Light-Bar-Feature](./06-Light-Bar-Feature.md) | Section 2 (Output Report Fields) |
| Light bar features byte | [06-Light-Bar-Feature](./06-Light-Bar-Feature.md) | Section 2 (Features Byte) |

### Reference Implementations

| Feature | DS4Windows Source | ds4drv Source |
|---|---|---|
| Motor state struct | `DS4Library/DS4Device.cs` (DS4ForceFeedbackState) | -- |
| Haptic state (combined) | `DS4Library/DS4Device.cs` (DS4HapticState) | -- |
| setRumble API | `DS4Library/DS4Device.cs:1875` | `ds4drv/device.py:91` |
| Output report construction | `DS4Library/DS4Device.cs:1560` | `ds4drv/device.py:117` |
| Rumble boost scaling | `DS4Control/ControlService.cs:3207` | -- |
| Motor inversion | `DS4Control/Mapping.cs:4950` | -- |
| Extras-based rumble | `DS4Control/Mapping.cs:3500` | -- |
| Macro rumble encoding | `DS4Control/Mapping.cs:4943` | -- |
| Rumble autostop timer | `DS4Library/DS4Device.cs:958` | -- |
| Rumble-lightbar sync | `DS4Control/DS4LightBar.cs:303` | -- |
| Rumble feature flag | `DS4Control/DS4OutDevice.cs:32` | -- |

---

## Sources

- [Sony DualShock 4 -- Game Controller Collective Wiki](https://controllers.fandom.com/wiki/Sony_DualShock_4)
- [Sony DualShock 4/Data Structures -- Game Controller Collective Wiki](https://controllers.fandom.com/wiki/Sony_DualShock_4/Data_Structures)
- [DS4-USB -- PS4 Developer Wiki](https://www.psdevwiki.com/ps4/DS4-USB)
- [DS4-BT -- PS4 Developer Wiki](https://www.psdevwiki.com/ps4/DS4-BT)
- [DualShock 4 -- GIMX Wiki](https://gimx.fr/wiki/index.php?title=DualShock_4)
- [DS4Windows Source Code (Ryochan7)](https://github.com/Ryochan7/DS4Windows) -- `DS4Device.cs`, `ControlService.cs`, `DS4LightBar.cs`, `Mapping.cs`, `MacroParser.cs`, `DS4OutDevice.cs`, `ScpUtil.cs`
- [ds4drv (chrippa)](https://github.com/chrippa/ds4drv) -- `ds4drv/device.py`
- [Apple Core Haptics Documentation](https://developer.apple.com/documentation/corehaptics)
- [Apple Game Controller Framework -- GCController.haptics](https://developer.apple.com/documentation/gamecontroller/gccontroller/haptics)
- Linux kernel `hid-sony.c` driver
