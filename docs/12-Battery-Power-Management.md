# DS4 Battery and Power Management

> Comprehensive technical reference for battery monitoring, charging detection,
> power-state management, and energy-saving strategies for the Sony DualShock 4
> controller on macOS.
>
> **Cross-references:**
> - [01-DS4-Controller-Overview.md](./01-DS4-Controller-Overview.md) -- Hardware specs, battery cell details
> - [04-DS4-USB-Protocol.md](./04-DS4-USB-Protocol.md) -- USB input report byte 30 definition
> - [05-DS4-Bluetooth-Protocol.md](./05-DS4-Bluetooth-Protocol.md) -- BT input report byte 32 definition
> - [06-Light-Bar-Feature.md](./06-Light-Bar-Feature.md) -- Battery-level LED indication
> - [10-macOS-Driver-Architecture.md](./10-macOS-Driver-Architecture.md) -- IOKit power management hooks

---

## Table of Contents

1. [Battery Hardware](#1-battery-hardware)
2. [Input Report Battery Fields](#2-input-report-battery-fields)
3. [Battery Level Mapping](#3-battery-level-mapping)
4. [Charging Detection and Status](#4-charging-detection-and-status)
5. [Cable and Wireless Detection](#5-cable-and-wireless-detection)
6. [Power Saving Features](#6-power-saving-features)
7. [macOS IOPowerManagement Integration](#7-macos-iopowermanagement-integration)
8. [Code Examples](#8-code-examples)
9. [Cross-Reference Summary](#9-cross-reference-summary)

---

## 1. Battery Hardware

### 1.1 Cell Specifications

Both the DS4 v1 (CUH-ZCT1x) and DS4 v2 (CUH-ZCT2x) use the same lithium-ion
polymer cell, model **LIP1522**, manufactured by Sony Energy Devices Corporation.

| Parameter | Value |
|---|---|
| **Cell model** | LIP1522 |
| **Chemistry** | Lithium-ion polymer (Li-Po) |
| **Nominal voltage** | 3.65 V DC |
| **Capacity** | 1000 mAh (3.65 Wh) |
| **Charge voltage** | 4.2 V (typical Li-Po upper cutoff) |
| **Discharge cutoff** | ~3.0 V (estimated, firmware-enforced) |
| **Cycle life** | ~500 full charge cycles to 80% capacity |

### 1.2 Connector Differences Between Revisions

The battery connects to the main board via a JST-type connector. The two hardware
revisions use different connector sizes, which means the batteries are **not
physically interchangeable** without an adapter.

| Revision | Connector | Notes |
|---|---|---|
| DS4 v1 (CUH-ZCT1x) | Large (wide) JST-type plug | Original design |
| DS4 v2 (CUH-ZCT2x) | Small (narrow) JST-type plug | Revised for compact assembly |

> **Source:** [01-DS4-Controller-Overview.md](./01-DS4-Controller-Overview.md),
> Section 2.2 (Detailed Differences table, "Battery connector" row).

### 1.3 Charging via USB

The DS4 charges through the Micro-USB (Micro-B) port. The controller's charging
circuit draws up to **800 mA at 5 V** from the USB bus, achieving a full charge
in approximately **2 hours**.

| Charging Parameter | Value |
|---|---|
| **Input voltage** | 5 V (USB bus power) |
| **Maximum charge current** | 800 mA |
| **Full charge time** | ~2 hours (from empty) |
| **Charge-and-play** | Yes (USB data + power simultaneously on PC/Mac) |

**Important platform caveat:** On a PS4 console, the DS4 v1 only charges via USB
and does not send HID data over the wired connection. On PC and Mac, both charging
and data transfer occur simultaneously over USB. The DS4 v2 supports charge-and-play
on all platforms.

### 1.4 Estimated Battery Life

Battery life depends heavily on which controller features are active:

| Usage Profile | Estimated Runtime |
|---|---|
| Gamepad only (no vibration, dim LED) | ~8 hours |
| Gamepad + moderate rumble + LED | ~5-6 hours |
| Gamepad + heavy rumble + bright LED + audio | ~4 hours |
| Idle (connected, no input, LED on) | ~7-10 hours |

The light bar, rumble motors, and internal speaker are the primary power consumers
beyond the base wireless radio and MCU draw. Reducing light bar brightness and
minimizing rumble are the most effective strategies for extending battery life.

### 1.5 EXT Port Charging

The DS4 includes a proprietary EXT (extension) port on its bottom edge that
supports charging via accessories such as charging docks and extended battery
packs. The EXT port uses an I2C data bus and can deliver power alongside accessory
data. This port is not used by PC/Mac drivers as no public protocol documentation
exists.

---

## 2. Input Report Battery Fields

### 2.1 Status Byte Location

Battery level and connection status are encoded in a single byte of the input
report. The byte offset differs between USB and Bluetooth due to the BT header
bytes.

| Connection | Report ID | Status Byte Offset | Report Total Size |
|---|---|---|---|
| **USB** | `0x01` | **Byte 30** | 64 bytes |
| **Bluetooth (hidraw)** | `0x11` | **Byte 32** | 78 bytes |
| **Bluetooth (raw L2CAP)** | `0x11` | **Byte 33** | 79 bytes (incl. `0xA1` header) |
| **Sony Wireless Adapter** | `0x01` | **Byte 30** | 64 bytes |

The +2 byte offset on Bluetooth is a consequence of the two BT-specific flag
bytes inserted at positions [1] and [2] of the BT report. See
[05-DS4-Bluetooth-Protocol.md](./05-DS4-Bluetooth-Protocol.md), Section 5.3
for the full offset mapping.

### 2.2 Bit-Field Layout

The status byte packs multiple fields into a single 8-bit value:

```
Bit:  7          6         5            4            3    2    1    0
    +----------+---------+-----------+------------+----+----+----+----+
    | Extension| Mic     | Headphone | USB Cable  |    Battery Level  |
    +----------+---------+-----------+------------+-------------------+
```

| Bits | Mask | Field | Description |
|---|---|---|---|
| 3:0 | `0x0F` | Battery Level | Raw battery value (see Section 3) |
| 4 | `0x10` | Cable State | 1 = USB data cable connected |
| 5 | `0x20` | Headphones | 1 = 3.5 mm headphones detected |
| 6 | `0x40` | Microphone | 1 = microphone detected (headset) |
| 7 | `0x80` | Extension | 1 = EXT port device connected |

### 2.3 Reading the Status Byte -- Raw C

```c
// USB mode: status byte is at offset 30 from the start of the report buffer
uint8_t status_byte = input_report[30];

// Bluetooth mode (hidraw): status byte is at offset 32
// uint8_t status_byte = bt_report[32];

uint8_t battery_raw    = status_byte & 0x0F;
bool    cable_connected = (status_byte & 0x10) != 0;
bool    headphones      = (status_byte & 0x20) != 0;
bool    microphone      = (status_byte & 0x40) != 0;
bool    extension       = (status_byte & 0x80) != 0;
```

> **Source (ds4drv):** In `device.py`, the parse_report() method reads the
> battery as `buf[30] % 16` (equivalent to `buf[30] & 0x0F`) and the USB cable
> flag as `(buf[30] & 16) != 0`. This works for both USB and Bluetooth after
> the BT header bytes have been stripped.

### 2.4 Secondary Status Byte (Byte 31 USB / Byte 33 BT)

The byte immediately following the power/status byte carries secondary connection
state information:

| Value | Meaning |
|---|---|
| `0x00` | Controller synced and operational |
| Non-zero | Connection issue, pairing state, or dongle sync pending |

This byte is primarily used by the Sony Wireless Adapter to indicate controller
sync status. For standard USB and Bluetooth connections it is typically `0x00`.

---

## 3. Battery Level Mapping

### 3.1 Raw Value Ranges

The 4-bit battery level field (bits 3:0) uses **different value ranges** depending
on whether the USB cable is connected. This dual-range encoding is the single most
important detail for correct battery percentage calculation.

| Condition | Raw Value Range | Maximum Value Constant | Meaning of Maximum |
|---|---|---|---|
| **On battery** (cable not connected) | 0 -- 8 | `BATTERY_MAX = 8` | Fully charged, discharging |
| **Cable connected** (charging) | 0 -- 11 | `BATTERY_MAX_USB = 11` | Fully charged + cable power |

> **Source (DS4Windows):** `DS4Device.cs` defines:
> ```csharp
> internal const int BATTERY_MAX = 8;
> internal const int BATTERY_MAX_USB = 11;
> ```

> **Source (ds4drv):** `actions/status.py` defines:
> ```python
> BATTERY_MAX          = 8
> BATTERY_MAX_CHARGING = 11
> ```

### 3.2 Value-to-Percentage Conversion

The percentage is computed by scaling the raw value against the appropriate
maximum, then clamping to 100%.

**General formula:**

```
max_value = cable_connected ? 11 : 8
battery_percent = min(raw_value * 100 / max_value, 100)
```

### 3.3 Detailed Mapping Tables

#### On Battery (cable NOT connected, max = 8)

| Raw Value | Percentage | Human Label |
|---|---|---|
| 0 | 0% | Empty / Critical |
| 1 | 12% | Very Low |
| 2 | 25% | Low |
| 3 | 37% | Below Half |
| 4 | 50% | Half |
| 5 | 62% | Above Half |
| 6 | 75% | Good |
| 7 | 87% | High |
| 8 | 100% | Full |

#### Cable Connected (charging, max = 11)

| Raw Value | Percentage | Human Label |
|---|---|---|
| 0 | 0% | Empty, charging |
| 1 | 9% | Very Low, charging |
| 2 | 18% | Low, charging |
| 3 | 27% | Below Quarter, charging |
| 4 | 36% | Quarter, charging |
| 5 | 45% | Below Half, charging |
| 6 | 54% | Half, charging |
| 7 | 63% | Above Half, charging |
| 8 | 72% | Good, charging |
| 9 | 81% | High, charging |
| 10 | 90% | Nearly Full, charging |
| 11 | 100% | Full, on USB power |

### 3.4 Quirks and Edge Cases

1. **Value 0 on battery:** The controller is about to shut itself off. The
   firmware enforces a minimum operating voltage and will power down shortly
   after reporting zero. Drivers should issue a low-battery warning well before
   this point (ds4drv uses a threshold of raw value 2, approximately 25%).

2. **Values above the expected maximum:** On some third-party controllers that
   clone the DS4 protocol, the battery nibble may report values outside the
   0--8 or 0--11 range. Clamping the result to 100% handles this gracefully.
   DS4Windows applies `Math.Min(tempBattery, 100)`.

3. **No battery reading:** Certain third-party controllers do not implement the
   battery field at all. DS4Windows detects this via a feature-set flag
   (`VidPidFeatureSet.NoBatteryReading`) and substitutes a dummy value of 99%
   to suppress spurious low-battery warnings.

4. **Transition during cable plug/unplug:** When a USB cable is connected or
   disconnected, the raw value range changes between 0--11 and 0--8. The
   percentage calculation must use the correct maximum for the current cable
   state. If the cable state and battery nibble are read from the same byte
   atomically (which they are, since they share byte 30), no race condition
   exists.

---

## 4. Charging Detection and Status

### 4.1 Determining Charging State

The DS4 does not have a dedicated "is charging" bit. Instead, the charging state
is inferred from the **Cable State** flag (bit 4 of the status byte):

```
cable_connected = (status_byte & 0x10) != 0
```

When `cable_connected` is true:
- The controller is receiving USB power and is charging (or fully charged).
- The battery raw value uses the 0--11 range.
- If `raw_value >= 11`, the battery is fully charged while on USB power.

When `cable_connected` is false:
- The controller is running on battery only (Bluetooth).
- The battery raw value uses the 0--8 range.

### 4.2 Charging State Transitions

```
State Machine:

  +--------------------+    USB plugged    +-----------------------+
  |                    | ----------------> |                       |
  |  On Battery (BT)  |                   |  Charging (USB)       |
  |  cable_connected=0 |                   |  cable_connected=1    |
  |  range: 0-8        | <---------------- |  range: 0-11          |
  |                    |    USB removed    |                       |
  +--------------------+                   +-----------------------+
         |                                         |
         | raw=0, power down                       | raw=11, full
         v                                         v
  +--------------------+                   +-----------------------+
  | Controller Off     |                   | Fully Charged on USB  |
  +--------------------+                   | (trickle / maintain)  |
                                           +-----------------------+
```

### 4.3 Detecting Charging State Changes

DS4Windows fires events when the charging state transitions, enabling UI updates
and action triggers:

```csharp
// From DS4Device.cs
tempCharging = (tempByte & 0x10) != 0;
if (tempCharging != charging)
{
    charging = tempCharging;
    ChargingChanged?.Invoke(this, EventArgs.Empty);
}
```

A well-designed driver should:

1. Track the previous charging state.
2. Detect transitions (plugged in / unplugged).
3. Notify observers (UI, power management subsystem, light bar controller).
4. Recalculate the battery percentage using the correct range for the new state.

### 4.4 Fully-Charged Detection

There is no explicit "charge complete" flag. A controller is considered fully
charged when:

```
cable_connected == true  AND  battery_raw >= 11
```

At this point, the controller has finished charging and is being powered directly
from USB. The percentage calculation yields 100%.

### 4.5 Quick-Charge Disconnect

DS4Windows supports a "quick charge disconnect" feature where the controller is
automatically disconnected from Bluetooth once the battery reaches full charge
while on USB power. This is useful when the user plugs in the controller only to
charge it rather than to use it wired:

```csharp
// DS4Device.cs -- simplified
protected bool readyQuickChargeDisconnect;

// If charging and battery is full, set flag
if (charging && battery >= 100)
    readyQuickChargeDisconnect = true;
```

---

## 5. Cable and Wireless Detection

### 5.1 Connection Type Determination

From the driver's perspective, the connection type is known at enumeration time:

| Detection Method | Connection Type |
|---|---|
| Matched via `IOUSBDevice` with DS4 VID/PID | USB wired |
| Matched via `IOBluetoothHIDDriver` | Bluetooth wireless |
| Matched via USB with SONYWA PID (`0x0BA0`) | Wireless via dongle |

### 5.2 Runtime Cable State via Input Report

Even when the high-level connection type is known, the cable state bit in the
input report provides real-time USB cable detection. This is relevant in scenarios
such as:

- A Bluetooth-connected controller that is also plugged in for charging.
- Monitoring whether the user has plugged in or removed the USB cable.

```c
bool cable_present = (input_report[30] & 0x10) != 0;
```

### 5.3 Peripheral Detection Bits

The remaining bits in the status byte detect attached peripherals:

| Bit | Mask | Peripheral | Notes |
|---|---|---|---|
| 5 | `0x20` | Headphones | 3.5 mm TRRS stereo headphone detected |
| 6 | `0x40` | Microphone | 3.5 mm TRRS mic ring detected |
| 7 | `0x80` | Extension | EXT port accessory connected |

When both headphones and microphone bits are set simultaneously, a full headset
is connected. ds4drv logs this as follows:

```python
# From ds4drv actions/status.py
if report.plug_audio and report.plug_mic:
    plug_audio = "Headset"
elif report.plug_audio:
    plug_audio = "Headphones"
elif report.plug_mic:
    plug_audio = "Mic"
else:
    plug_audio = "Speaker"
```

---

## 6. Power Saving Features

### 6.1 Firmware Idle Timeout (Controller-Side)

The DS4 controller firmware implements a hardware-level idle timeout. If no button
is pressed and no input activity is detected for approximately **10 minutes**,
the controller will:

1. Gradually dim the light bar over the final ~30 seconds.
2. Disconnect from the host.
3. Power off.

This timeout is hard-coded in the controller's firmware and cannot be changed by
the host driver. It occurs on Bluetooth only; USB-connected controllers do not
auto-disconnect (they draw power from the bus).

### 6.2 Software Idle Timeout (Driver-Side)

Driver software can implement its own idle disconnect timeout that is shorter
than the firmware's 10-minute default. DS4Windows provides a per-profile
configurable idle timeout:

```csharp
// From ScpUtil.cs
public int[] idleDisconnectTimeout = new int[9] { 0, 0, 0, 0, 0, 0, 0, 0, 0 };
// Value is in seconds. 0 = disabled.
```

The idle detection logic checks whether any input has changed:

```csharp
// From DS4Device.cs -- simplified
if (!isRemoved && idleTimeout > 0)
{
    idleInput = isDS4Idle();
    if (idleInput)
    {
        DateTime timeout = lastActive + TimeSpan.FromSeconds(idleTimeout);
        if (!charging)
            shouldDisconnect = utcNow >= timeout;
    }
    else
    {
        lastActive = utcNow;
    }
}
```

**Key behavior:** The idle disconnect is **suppressed while the USB cable is
connected** (`!charging`). This prevents the driver from disconnecting a
controller that is deliberately plugged in for charging.

### 6.3 Keep-Alive Output Reports

The DS4 firmware's idle timer is reset whenever the controller receives an
output report (rumble/LED command) from the host. DS4Windows exploits this to
implement a keep-alive mechanism that sends periodic output reports even when
there is no actual change to the rumble or LED state:

```csharp
// DS4Device.cs -- standby watchdog
bool haptime = force || standbySw.ElapsedMilliseconds >= 4000L;
```

This sends an output report every ~4 seconds if the host has not sent one
recently, preventing the controller from entering its firmware idle timeout.

### 6.4 Light Bar Dimming

Reducing the light bar brightness is the most user-visible power saving strategy.
The light bar LED draws measurable current, and dimming it directly extends
battery life.

**PS4 system behavior:** The PS4 uses relatively dim LED values (intensity ~64
out of 255) as the default player colors, specifically to conserve battery.

**Idle-based dimming (DS4Windows):** When the `ledAsBattery` option is enabled
and an idle disconnect timeout is configured, DS4Windows progressively dims the
light bar as the idle period approaches the timeout threshold:

```csharp
// DS4LightBar.cs -- idle-based dimming
int idleDisconnectTimeout = getIdleDisconnectTimeout(deviceNum);
if (idleDisconnectTimeout > 0 && lightModeInfo.ledAsBattery &&
    (!device.isCharging() || device.getBattery() >= 100))
{
    TimeSpan timeratio = new TimeSpan(DateTime.UtcNow.Ticks - device.lastActive.Ticks);
    double botratio = timeratio.TotalMilliseconds;
    double topratio = TimeSpan.FromSeconds(idleDisconnectTimeout).TotalMilliseconds;
    double ratio = 100.0 * (botratio / topratio);
    if (ratio >= 50.0 && ratio < 100.0)
    {
        // Quadratic fade from full brightness to off over the second half
        // of the idle period
        DS4Color emptyCol = new DS4Color(0, 0, 0);
        double elapsed = 0.02 * (ratio - 50.0);
        color = getTransitionedColor(ref color, ref emptyCol,
            (uint)(-100.0 * elapsed * (elapsed - 2.0)));
    }
    else if (ratio >= 100.0)
    {
        // Fully dimmed at timeout
        color = new DS4Color(0, 0, 0);
    }
}
```

The dimming curve is quadratic, starting at 50% of the idle period and reaching
full darkness at the timeout point. This provides a visual cue to the user that
the controller is about to disconnect.

### 6.5 Battery-Aware LED Flash Patterns

When the battery drops below a configurable threshold, the light bar switches
from solid to flashing. The flash duty cycle directly reflects the remaining
charge level, serving as both a warning and a power-saving measure (the LED is
off for a portion of each cycle).

| Battery Level | On Duration | Off Duration | Duty Cycle |
|---|---|---|---|
| 0-9% | 28 | 252 | ~10% |
| 10-19% | 28 | 252 | ~10% |
| 20-29% | 56 | 224 | ~20% |
| 30-39% | 84 | 196 | ~30% |
| 40-49% | 112 | 168 | ~40% |
| 50-59% | 140 | 140 | ~50% |
| 60-69% | 168 | 112 | ~60% |
| 70-79% | 196 | 84 | ~70% |
| 80-89% | 224 | 56 | ~80% |
| 90-99% | 252 | 28 | ~90% |
| 100% | 0 | 0 | 100% (solid) |

Duration values are in controller units where 255 corresponds to approximately
2.5 seconds. See [06-Light-Bar-Feature.md](./06-Light-Bar-Feature.md), Section 7
for the complete battery indication reference.

### 6.6 Charging Light Bar Indication

DS4Windows supports multiple visual styles while the controller is charging:

| Charging Type | Behavior |
|---|---|
| **Type 0** | Standard -- same battery-tier flash pattern |
| **Type 1** | Pulse/breathe -- smooth fade in and out cycle |
| **Type 2** | Rainbow -- slow hue spectrum cycle |
| **Type 3** | Custom color -- user-defined static color |

The pulse animation uses a 4-second cycle (`PULSE_CHARGING_DURATION = 4000`),
compared to the 2-second cycle used for low-battery flash
(`PULSE_FLASH_DURATION = 2000`).

---

## 7. macOS IOPowerManagement Integration

### 7.1 Overview

macOS provides the `IOPMPowerSource` and `IOPowerManagement` frameworks for
drivers and user-space applications to participate in system power management.
A DS4 driver should integrate with these frameworks to:

1. Report the controller's battery level to the system.
2. Respond to system sleep/wake transitions.
3. Optionally prevent system sleep while the controller is in active use.

### 7.2 Registering as a Power Source

A kernel extension or DriverKit extension can register the DS4 controller as a
power source so that the battery level appears in the macOS battery menu and
system-level power APIs.

**IOKit KEXT approach:**

```cpp
#include <IOKit/pwr_mgt/RootDomain.h>
#include <IOKit/pwr_mgt/IOPMPowerSource.h>

// In your IOService subclass (e.g., DS4Driver):

bool DS4Driver::start(IOService *provider)
{
    if (!super::start(provider))
        return false;

    // Register with power management
    PMinit();
    provider->joinPMtree(this);

    // Create a power source dictionary to report battery state
    OSDictionary *batteryProps = OSDictionary::withCapacity(8);

    OSString *name = OSString::withCString("DualShock 4");
    batteryProps->setObject(kIOPMPSNameKey, name);
    name->release();

    // Report as external (not the main laptop battery)
    OSBoolean *isExternal = kOSBooleanTrue;
    batteryProps->setObject(kIOPMPSExternalConnectedKey, isExternal);

    // Set transport type
    OSString *transport = OSString::withCString("Bluetooth");
    batteryProps->setObject(kIOPMPSTransportTypeKey, transport);
    transport->release();

    updateBatteryProperties(batteryProps, 100, false);

    // Publish as IOPMPowerSource
    setProperty("IOPMPowerSource", batteryProps);
    batteryProps->release();

    return true;
}

void DS4Driver::updateBatteryProperties(OSDictionary *props,
                                        int percent,
                                        bool charging)
{
    OSNumber *level = OSNumber::withNumber(percent, 32);
    props->setObject(kIOPMPSCurrentCapacityKey, level);
    level->release();

    OSNumber *max = OSNumber::withNumber(100, 32);
    props->setObject(kIOPMPSMaxCapacityKey, max);
    max->release();

    OSBoolean *isCharging = charging ? kOSBooleanTrue : kOSBooleanFalse;
    props->setObject(kIOPMPSIsChargingKey, isCharging);
}
```

### 7.3 Responding to System Sleep/Wake

When the Mac enters sleep, the driver should:

1. **Save the current LED/rumble state** so it can be restored after wake.
2. **Turn off the light bar and rumble** to prevent power drain during sleep.
3. **Release USB resources** if the controller is connected via USB.

On wake:

1. **Re-enumerate the device** (USB devices may be re-enumerated by the stack).
2. **Re-read the calibration report** if on Bluetooth, to re-trigger extended
   report mode (the controller reverts to basic `0x01` reports after a
   reconnection).
3. **Restore the LED state** to the pre-sleep configuration.

```cpp
// IOService power state table
static IOPMPowerState powerStates[] = {
    // version, capabilityFlags, outputPowerCharacter, inputPowerRequirement
    { 1, 0,                  0,                 0                },  // Off
    { 1, kIOPMDeviceUsable,  kIOPMPowerOn,      kIOPMPowerOn    },  // On
};

IOReturn DS4Driver::setPowerState(unsigned long newState,
                                   IOService *whatDevice)
{
    if (newState == 0) {
        // System is going to sleep
        saveLEDState();
        sendOutputReport(/* rumble=0, led=off */);
    } else {
        // System woke up
        restoreLEDState();
        // BT controllers may need re-initialization
        if (connectionType == kBluetooth) {
            readCalibrationReport();  // Re-trigger extended reports
        }
    }
    return kIOPMAckImplied;
}
```

### 7.4 DriverKit (DEXT) Power Management

For modern macOS (11.0+), DriverKit extensions use a slightly different API.
The `IOUserHIDDevice` subclass can override the `SetPowerState` method:

```cpp
// DriverKit approach
kern_return_t DS4DriverExtension::SetPowerState(uint32_t powerStateOrdinal)
{
    if (powerStateOrdinal == 0) {
        // Entering sleep
        SaveState();
        SendBlankOutput();
    } else {
        // Waking
        RestoreState();
    }
    return kIOReturnSuccess;
}
```

### 7.5 User-Space Power Monitoring (IOPSCopyPowerSourcesInfo)

A user-space application (such as a DS4 configuration tool) can publish battery
information through the `IOPSCreatePowerSource` API so that the controller's
battery appears in the macOS menu bar:

```c
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/ps/IOPSKeys.h>

CFTypeRef powerSourceRef = NULL;

void ds4_register_power_source(void)
{
    powerSourceRef = IOPSCreatePowerSource(CFSTR("DualShock 4"));
    if (!powerSourceRef) return;

    ds4_update_power_source(100, false);
}

void ds4_update_power_source(int percent, bool charging)
{
    if (!powerSourceRef) return;

    CFMutableDictionaryRef desc = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);

    // Name
    CFDictionarySetValue(desc, CFSTR(kIOPSNameKey),
                         CFSTR("DualShock 4"));
    // Type
    CFDictionarySetValue(desc, CFSTR(kIOPSTypeKey),
                         CFSTR(kIOPSInternalBatteryType));
    // Transport
    CFDictionarySetValue(desc, CFSTR(kIOPSTransportTypeKey),
                         CFSTR("Bluetooth"));
    // Current capacity
    CFNumberRef cap = CFNumberCreate(kCFAllocatorDefault,
                                     kCFNumberIntType, &percent);
    CFDictionarySetValue(desc, CFSTR(kIOPSCurrentCapacityKey), cap);
    CFRelease(cap);

    // Max capacity
    int maxCap = 100;
    CFNumberRef maxCapRef = CFNumberCreate(kCFAllocatorDefault,
                                           kCFNumberIntType, &maxCap);
    CFDictionarySetValue(desc, CFSTR(kIOPSMaxCapacityKey), maxCapRef);
    CFRelease(maxCapRef);

    // Charging state
    CFDictionarySetValue(desc, CFSTR(kIOPSIsChargingKey),
                         charging ? kCFBooleanTrue : kCFBooleanFalse);

    // Power source state
    CFDictionarySetValue(desc, CFSTR(kIOPSPowerSourceStateKey),
                         charging
                             ? CFSTR(kIOPSACPowerValue)
                             : CFSTR(kIOPSBatteryPowerValue));

    IOPSSetPowerSourceDetails(powerSourceRef, desc);
    CFRelease(desc);
}

void ds4_unregister_power_source(void)
{
    if (powerSourceRef) {
        IOPSReleasePowerSource(powerSourceRef);
        powerSourceRef = NULL;
    }
}
```

---

## 8. Code Examples

### 8.1 Complete Battery Monitor (C -- macOS IOKit)

This example demonstrates reading the DS4 input report over USB, extracting the
battery level and charging state, computing the percentage, and printing it.

```c
#include <IOKit/hid/IOHIDManager.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

#define DS4_VID             0x054C
#define DS4_PID_V1          0x05C4
#define DS4_PID_V2          0x09CC
#define BATTERY_MAX         8
#define BATTERY_MAX_USB     11
#define STATUS_BYTE_USB     30
#define STATUS_BYTE_BT      32
#define LOW_BATTERY_THRESH  25  // percent

typedef struct {
    int      percent;         // 0-100
    uint8_t  raw;             // 0-8 or 0-11
    bool     cable_connected;
    bool     headphones;
    bool     microphone;
    bool     extension;
    bool     charging;        // Alias for cable_connected
    bool     fully_charged;
} DS4BatteryState;

DS4BatteryState ds4_parse_battery(const uint8_t *report,
                                  bool is_bluetooth)
{
    DS4BatteryState state = {0};
    int offset = is_bluetooth ? STATUS_BYTE_BT : STATUS_BYTE_USB;
    uint8_t status = report[offset];

    state.raw             = status & 0x0F;
    state.cable_connected = (status & 0x10) != 0;
    state.headphones      = (status & 0x20) != 0;
    state.microphone      = (status & 0x40) != 0;
    state.extension       = (status & 0x80) != 0;
    state.charging        = state.cable_connected;

    int max_value = state.cable_connected ? BATTERY_MAX_USB : BATTERY_MAX;
    state.percent = state.raw * 100 / max_value;
    if (state.percent > 100) state.percent = 100;

    state.fully_charged = state.cable_connected && (state.raw >= BATTERY_MAX_USB);

    return state;
}

const char *ds4_battery_description(const DS4BatteryState *state)
{
    static char buf[64];
    if (state->fully_charged)
        snprintf(buf, sizeof(buf), "Fully charged (USB)");
    else if (state->charging)
        snprintf(buf, sizeof(buf), "%d%% (Charging)", state->percent);
    else
        snprintf(buf, sizeof(buf), "%d%%", state->percent);
    return buf;
}

// IOHIDManager input report callback
void ds4_input_callback(void *context, IOReturn result,
                        void *sender, IOHIDReportType type,
                        uint32_t reportID, uint8_t *report,
                        CFIndex reportLength)
{
    if (reportID != 0x01 || reportLength < 64) return;

    static DS4BatteryState prev = {0};
    DS4BatteryState curr = ds4_parse_battery(report, /* is_bluetooth */ false);

    // Notify on change
    if (curr.percent != prev.percent || curr.charging != prev.charging) {
        printf("Battery: %s\n", ds4_battery_description(&curr));

        if (!curr.charging && curr.percent <= LOW_BATTERY_THRESH) {
            printf("WARNING: Low battery!\n");
        }

        prev = curr;
    }
}
```

### 8.2 Battery Monitor (Swift -- macOS IOKit)

```swift
import IOKit.hid
import Foundation

struct DS4BatteryState {
    let raw: UInt8            // 0-8 or 0-11
    let percent: Int          // 0-100
    let cableConnected: Bool
    let headphones: Bool
    let microphone: Bool
    let extension_: Bool
    let fullyCharged: Bool

    var isCharging: Bool { cableConnected }

    var description: String {
        if fullyCharged {
            return "Fully charged (USB)"
        } else if cableConnected {
            return "\(percent)% (Charging)"
        } else {
            return "\(percent)%"
        }
    }

    var isLow: Bool { !cableConnected && percent <= 25 }
}

func parseBattery(report: Data, isBluetooth: Bool) -> DS4BatteryState {
    let offset = isBluetooth ? 32 : 30
    guard report.count > offset else {
        return DS4BatteryState(raw: 0, percent: 0,
                               cableConnected: false,
                               headphones: false,
                               microphone: false,
                               extension_: false,
                               fullyCharged: false)
    }

    let status = report[offset]
    let raw = status & 0x0F
    let cable = (status & 0x10) != 0
    let maxValue = cable ? 11 : 8
    let percent = min(Int(raw) * 100 / maxValue, 100)

    return DS4BatteryState(
        raw: raw,
        percent: percent,
        cableConnected: cable,
        headphones: (status & 0x20) != 0,
        microphone: (status & 0x40) != 0,
        extension_: (status & 0x80) != 0,
        fullyCharged: cable && raw >= 11
    )
}
```

### 8.3 Battery-Aware Light Bar Update (C)

This example combines battery monitoring with light bar control, implementing the
color-fade and flash-duty-cycle approach used by DS4Windows.

```c
#include <IOKit/hid/IOHIDManager.h>
#include <stdint.h>
#include <math.h>

// Flash durations indexed by battery_percent / 10
static const uint8_t kFlashOn[11]  = {28,28,56,84,112,140,168,196,224,252,0};
static const uint8_t kFlashOff[11] = {252,252,224,196,168,140,112,84,56,28,0};

typedef struct {
    uint8_t r, g, b;
} DS4Color;

// Linearly interpolate between two colors based on t (0.0 = from, 1.0 = to)
static DS4Color lerp_color(DS4Color from, DS4Color to, float t) {
    t = fminf(fmaxf(t, 0.0f), 1.0f);
    return (DS4Color){
        .r = (uint8_t)(from.r + t * (to.r - from.r)),
        .g = (uint8_t)(from.g + t * (to.g - from.g)),
        .b = (uint8_t)(from.b + t * (to.b - from.b))
    };
}

void ds4_update_battery_lightbar(IOHIDDeviceRef device,
                                  int battery_percent,
                                  bool charging)
{
    int tier = battery_percent / 10;
    if (tier > 10) tier = 10;

    uint8_t report[32] = {0};
    report[0] = 0x05;  // Report ID
    report[1] = 0x07;  // Enable rumble + lightbar + flash
    report[2] = 0x04;

    if (charging && battery_percent < 100) {
        // Amber/orange pulse while charging
        report[6] = 255;  // Red
        report[7] = 128;  // Green
        report[8] = 0;    // Blue
        report[9] = 64;   // Slow pulse on
        report[10] = 64;  // Slow pulse off
    } else if (battery_percent <= 20 && !charging) {
        // Low battery: red with tiered flash rate
        report[6] = 255;
        report[7] = 0;
        report[8] = 0;
        report[9]  = kFlashOn[tier];
        report[10] = kFlashOff[tier];
    } else {
        // Normal: green-to-red gradient based on battery level
        DS4Color full = {0, 255, 0};    // Green at 100%
        DS4Color empty = {255, 0, 0};   // Red at 0%
        float t = battery_percent / 100.0f;
        DS4Color color = lerp_color(empty, full, t);
        report[6] = color.r;
        report[7] = color.g;
        report[8] = color.b;
        report[9]  = 0;  // No flash
        report[10] = 0;
    }

    IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput,
                         0x05, report, sizeof(report));
}
```

### 8.4 Low-Battery Flash Warning (Python -- ds4drv style)

This example mirrors the approach in ds4drv's `actions/battery.py`, where the
light bar flashes for 5 seconds every 60 seconds when the battery is low:

```python
import time
import threading

BATTERY_MAX = 8
BATTERY_MAX_CHARGING = 11
BATTERY_WARNING_RAW = 2  # ~25%

class DS4BatteryMonitor:
    """Monitors DS4 battery and triggers low-battery LED flash."""

    def __init__(self, device):
        self.device = device
        self._check_interval = 60   # seconds between checks
        self._flash_duration = 5    # seconds to flash
        self._running = False

    def start(self):
        self._running = True
        self._thread = threading.Thread(target=self._monitor_loop,
                                        daemon=True)
        self._thread.start()

    def stop(self):
        self._running = False

    def _monitor_loop(self):
        while self._running:
            time.sleep(self._check_interval)
            report = self.device.read_report()
            if report is None:
                continue

            battery_raw = report.battery
            cable = report.plug_usb

            if battery_raw < BATTERY_WARNING_RAW and not cable:
                # Flash the LED for 5 seconds
                self.device.start_led_flash(on=30, off=30)
                time.sleep(self._flash_duration)
                self.device.stop_led_flash()

    @staticmethod
    def compute_percent(raw_value, cable_connected):
        max_val = BATTERY_MAX_CHARGING if cable_connected else BATTERY_MAX
        return min(raw_value * 100 // max_val, 100)
```

### 8.5 Periodic Battery Polling with IOHIDManager (C)

For drivers that need to poll the battery state at a regular cadence rather than
on every input report (to reduce processing overhead):

```c
#include <IOKit/hid/IOHIDManager.h>
#include <dispatch/dispatch.h>

static dispatch_source_t batteryTimer = NULL;
static IOHIDDeviceRef ds4Device = NULL;

void startBatteryPolling(IOHIDDeviceRef device, double intervalSeconds)
{
    ds4Device = device;
    batteryTimer = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));

    uint64_t interval_ns = (uint64_t)(intervalSeconds * NSEC_PER_SEC);
    dispatch_source_set_timer(batteryTimer,
                              dispatch_time(DISPATCH_TIME_NOW, 0),
                              interval_ns, interval_ns / 10);

    dispatch_source_set_event_handler(batteryTimer, ^{
        // Request a synchronous read of the current input report
        uint8_t report[64] = {0};
        CFIndex length = sizeof(report);
        IOReturn ret = IOHIDDeviceGetReport(ds4Device,
                                             kIOHIDReportTypeInput,
                                             0x01, report, &length);
        if (ret == kIOReturnSuccess && length >= 31) {
            DS4BatteryState state = ds4_parse_battery(report, false);
            printf("[Battery Poll] %s\n",
                   ds4_battery_description(&state));
        }
    });

    dispatch_resume(batteryTimer);
}

void stopBatteryPolling(void)
{
    if (batteryTimer) {
        dispatch_source_cancel(batteryTimer);
        batteryTimer = NULL;
    }
}
```

---

## 9. Cross-Reference Summary

| Topic | Document | Section |
|---|---|---|
| Battery cell specs (LIP1522, voltage, capacity) | [01-DS4-Controller-Overview.md](./01-DS4-Controller-Overview.md) | 7.2 Battery |
| Battery connector v1 vs v2 | [01-DS4-Controller-Overview.md](./01-DS4-Controller-Overview.md) | 2.2 Detailed Differences |
| USB input report byte 30 layout | [04-DS4-USB-Protocol.md](./04-DS4-USB-Protocol.md) | 2.8 Battery Level and Status |
| BT input report byte 32 layout | [05-DS4-Bluetooth-Protocol.md](./05-DS4-Bluetooth-Protocol.md) | 5.6 Power/Status Byte |
| Light bar battery flash patterns | [06-Light-Bar-Feature.md](./06-Light-Bar-Feature.md) | 7. Battery Level Indication |
| Light bar charging animation styles | [06-Light-Bar-Feature.md](./06-Light-Bar-Feature.md) | 7 (DS4Windows charging types) |
| Light bar battery color gradient | [06-Light-Bar-Feature.md](./06-Light-Bar-Feature.md) | 9. Code Examples (battery indicator) |
| BT idle auto-disconnect (10 min firmware) | [05-DS4-Bluetooth-Protocol.md](./05-DS4-Bluetooth-Protocol.md) | 10.2 Keep-Alive and Idle Behavior |
| BT keep-alive output reports | [05-DS4-Bluetooth-Protocol.md](./05-DS4-Bluetooth-Protocol.md) | 10.2 Keep-Alive and Idle Behavior |
| macOS KEXT/DriverKit architecture | [10-macOS-Driver-Architecture.md](./10-macOS-Driver-Architecture.md) | IOKit matching, power states |
| ds4drv battery action source | Example Code: `ds4drv-chrippa/ds4drv/actions/battery.py` | ReportActionBattery class |
| ds4drv status reporting source | Example Code: `ds4drv-chrippa/ds4drv/actions/status.py` | ReportActionStatus class |
| DS4Windows battery parsing source | Example Code: `DS4Windows/DS4Library/DS4Device.cs` | Lines 1266-1298 |
| DS4Windows idle timeout source | Example Code: `DS4Windows/DS4Control/ScpUtil.cs` | idleDisconnectTimeout array |
| DS4Windows battery light bar source | Example Code: `DS4Windows/DS4Control/DS4LightBar.cs` | BatteryIndicatorDurations, updateLightBar |

---

## Sources

- **DS4Windows** -- [GitHub Repository](https://github.com/Ryochan7/DS4Windows):
  `DS4Device.cs` (battery parsing, idle timeout), `DS4LightBar.cs` (battery LED),
  `ScpUtil.cs` (idle disconnect configuration), `DS4State.cs` (Battery field)
- **ds4drv (chrippa)** -- [GitHub Repository](https://github.com/chrippa/ds4drv):
  `device.py` (parse_report battery extraction), `actions/battery.py` (low-battery flash),
  `actions/status.py` (battery percentage logging)
- **ds4drv (clearpathrobotics)** -- Fork with identical battery handling logic
- **psdevwiki.com** -- [DS4-USB](https://www.psdevwiki.com/ps4/DS4-USB) (byte 30 documentation)
- **Apple Developer Documentation** -- IOPMPowerSource, IOPSCreatePowerSource, DriverKit SetPowerState
- **Sony LIP1522 datasheet** -- 3.65V 1000mAh lithium-ion polymer cell specifications

---

*Document generated for the ds4mac project. This document consolidates battery and power
management information that was previously scattered across the overview, protocol, and
light bar feature documents into a single authoritative reference.*
