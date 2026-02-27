# DualShock 4 Touchpad -- Comprehensive Reference

## Related Documents

- **04-USB-Protocol.md** -- USB input report 0x01 structure (touchpad data is embedded within)
- **05-Bluetooth-Protocol.md** -- BT input report 0x11 structure and offset differences
- **08-Gyroscope-IMU-Feature.md** -- Shares the same input reports (0x01 / 0x11); IMU data precedes touchpad data

---

This document provides a complete technical reference for the DualShock 4 (DS4) capacitive touchpad, covering hardware specifications, raw data parsing, coordinate systems, gesture recognition, mouse emulation, and macOS integration with Swift code examples.

---

## Table of Contents

1. [Hardware Specifications](#1-hardware-specifications)
2. [Input Report Data](#2-input-report-data)
3. [Coordinate System](#3-coordinate-system)
4. [Multi-touch Support](#4-multi-touch-support)
5. [Touch Data Parsing](#5-touch-data-parsing)
6. [Gesture Recognition](#6-gesture-recognition)
7. [Mouse Emulation](#7-mouse-emulation)
8. [macOS Integration](#8-macos-integration)
9. [Code Examples](#9-code-examples)

---

## 1. Hardware Specifications

### Physical Characteristics

| Property                | Value                            |
|-------------------------|----------------------------------|
| Touch Technology        | Capacitive (mutual capacitance)  |
| Simultaneous Touch Points | 2 fingers maximum              |
| Physical Width          | ~45 mm                           |
| Physical Height         | ~20 mm                           |
| Click Mechanism         | Mechanical dome switch beneath pad |
| Surface Material        | Matte plastic                    |
| Controller Dimensions   | 162 mm x 52 mm x 98 mm (W x H x D) |
| Controller Weight       | 210 g                            |

### Sensor Resolution

| Property         | Value          |
|------------------|----------------|
| X Resolution     | 1920 units (0-1919) |
| Y Resolution     | 943 units (0-942)   |
| X Bits           | 12-bit field (4096 possible values, 0-1919 used) |
| Y Bits           | 12-bit field (4096 possible values, 0-942 used) |
| Effective DPI    | ~1082 DPI horizontal, ~1197 DPI vertical (approximate) |

### Click Mechanism

The entire touchpad surface acts as a single physical button. When pressed firmly, a mechanical dome switch underneath registers a digital click. The click state is reported separately from touch tracking data. The touchpad click appears in the button bitfield at byte 7, bit 1 of the standard report.

---

## 2. Input Report Data

### USB Report Structure (Report ID 0x01)

The USB input report is 64 bytes. The touchpad data region begins at byte offset 33 (0-indexed from the start of report data, after the report ID byte).

#### Report Layout Overview

```
Byte   0:     Report ID (0x01)
Bytes  1-32:  Sticks, buttons, triggers, IMU data, battery, etc.
Byte  33:     Touch packet count (number of touch data packets in report)
Byte  34:     Touch packet counter / timestamp (auto-incrementing)
Bytes 35-42:  Touch Data Packet 0 (current touch state)
Bytes 43-51:  Touch Data Packet 1 (previous touch state, historical)
```

#### Touch Packet Count (Byte 33)

This byte indicates how many touch data packets are present in this report:
- `0x00` = No new touch data
- `0x01` = 1 touch packet (most common -- contains current touch state)
- `0x02` = 2 touch packets (current + 1 historical)
- `0x03` = 3 touch packets (current + 2 historical)

In practice, most implementations only process the first (current) touch packet. DS4Windows and ds4drv both use only the first packet.

#### Touch Packet Counter (Byte 34)

An auto-incrementing counter that tracks the last touchpad state update. This value increments each time the touchpad sensor detects any change, providing temporal ordering for touch events.

#### Touch Data Packet Format (8 bytes per packet)

Each touch data packet contains data for two finger slots (4 bytes per finger):

```
Offset  Description
------  -----------
  +0    Finger 0: Touch ID + Active flag
  +1    Finger 0: X coordinate (low 8 bits)
  +2    Finger 0: X[11:8] (low nibble) | Y[3:0] (high nibble)
  +3    Finger 0: Y coordinate (high 8 bits)
  +4    Finger 1: Touch ID + Active flag
  +5    Finger 1: X coordinate (low 8 bits)
  +6    Finger 1: X[11:8] (low nibble) | Y[3:0] (high nibble)
  +7    Finger 1: Y coordinate (high 8 bits)
```

#### Complete USB Touchpad Byte Map

| USB Byte | Description                              |
|----------|------------------------------------------|
| 7        | Bit 1: Touchpad click button (digital)   |
| 33       | Touch packet count                       |
| 34       | Touch packet counter / timestamp         |
| 35       | Finger 0: ID (bits 0-6), Not-touching (bit 7) |
| 36       | Finger 0: X coordinate low byte          |
| 37       | Finger 0: X high nibble (bits 0-3) / Y low nibble (bits 4-7) |
| 38       | Finger 0: Y coordinate high byte         |
| 39       | Finger 1: ID (bits 0-6), Not-touching (bit 7) |
| 40       | Finger 1: X coordinate low byte          |
| 41       | Finger 1: X high nibble (bits 0-3) / Y low nibble (bits 4-7) |
| 42       | Finger 1: Y coordinate high byte         |

### Bluetooth Report Structure

On Bluetooth, the DS4 sends report ID 0x11 (extended report, 78 bytes). The data payload begins at byte offset 2, effectively adding +2 to all USB offsets.

#### USB vs Bluetooth Offset Comparison

| Field                    | USB Offset | BT Offset (in 0x11) |
|--------------------------|------------|----------------------|
| Touchpad click button    | 7          | 9                    |
| Touch packet count       | 33         | 35                   |
| Touch packet counter     | 34         | 36                   |
| Finger 0 ID + active     | 35         | 37                   |
| Finger 0 X low           | 36         | 38                   |
| Finger 0 X/Y shared      | 37         | 39                   |
| Finger 0 Y high          | 38         | 40                   |
| Finger 1 ID + active     | 39         | 41                   |
| Finger 1 X low           | 40         | 42                   |
| Finger 1 X/Y shared      | 41         | 43                   |
| Finger 1 Y high          | 42         | 44                   |

**Important**: In the DS4Windows codebase, Bluetooth reports are copied into the same `inputReport` buffer with the 2-byte BT header stripped, so the same byte offsets apply regardless of connection type once the data is in the processing buffer.

The Bluetooth 0x11 report can contain up to 4 touch data packets (vs. 3 for USB), providing more historical touch data due to the lower polling frequency.

### Touchpad Click Button

The touchpad click is a digital button reported in the main button bitfield:

```
Byte 7 (USB) / Byte 9 (BT):
  Bit 0: PS button
  Bit 1: Touchpad click button    <-- This one
  Bits 2-7: Frame counter (6 bits)
```

---

## 3. Coordinate System

### Origin and Axes

```
(0,0) -----------------------> X+ (1919)
  |
  |     TOUCHPAD SURFACE
  |     (viewed from above,
  |      player perspective)
  |
  v
  Y+ (942)
```

- **Origin (0, 0)**: Top-left corner of the touchpad
- **X axis**: Increases left-to-right (0 to 1919)
- **Y axis**: Increases top-to-bottom (0 to 942)
- **X range**: 0 to 1919 (1920 discrete values)
- **Y range**: 0 to 942 (943 discrete values)

### Coordinate Space Diagram

```
+--------------------------------------------------+
|  (0,0)                               (1919,0)    |
|                                                    |
|              TOUCHPAD SURFACE                      |
|                                                    |
|  (0,942)                             (1919,942)  |
+--------------------------------------------------+
      Left side         |         Right side
                    (960, ~)
                   Center line
```

### Mapping to Screen Coordinates

To map touchpad coordinates to a screen region:

```
screenX = (touchX / 1919.0) * screenWidth
screenY = (touchY / 942.0) * screenHeight
```

For normalized [0.0, 1.0] output:

```
normalizedX = touchX / 1919.0
normalizedY = touchY / 942.0
```

### Left/Right Zone Detection

DS4Windows uses the 2/5 threshold for left/right zone detection:

```
isLeft  = touchX < (1920 * 2 / 5)   // touchX < 768
isRight = touchX >= (1920 * 2 / 5)  // touchX >= 768
```

DS4Windows also uses a 3/4 threshold for the lower-right corner (right-click zone):

```
isLowerRight = touchX > (1920 * 3 / 4) && touchY > (942 * 3 / 4)
//             touchX > 1440          && touchY > 706
```

---

## 4. Multi-touch Support

### Overview

The DS4 touchpad supports simultaneous tracking of up to 2 fingers. Each finger occupies a fixed slot in the touch data packet:

- **Finger 0 (Slot 0)**: Bytes 35-38 (USB)
- **Finger 1 (Slot 1)**: Bytes 39-42 (USB)

### Finger Identification

Each touch contact is assigned a 7-bit tracking ID:

| Field         | Bits  | Range | Description                          |
|---------------|-------|-------|--------------------------------------|
| Touch ID      | 0-6   | 0-127 | Unique identifier for this contact   |
| Not-Touching  | 7     | 0/1   | 0 = finger is touching, 1 = not touching |

The Touch ID:
- Is assigned when a finger first makes contact
- Remains constant throughout the entire touch gesture (finger down -> move -> finger up)
- Increments globally with each new touch contact
- Wraps around after reaching 127

### Touch Lifecycle

```
State 1: No Touch
  Finger 0: Not-Touching = 1, ID = (last ID)
  Finger 1: Not-Touching = 1, ID = (last ID)

State 2: Single Finger Down
  Finger 0: Not-Touching = 0, ID = N (new ID assigned)
  Finger 1: Not-Touching = 1, ID = (last ID)

State 3: Second Finger Down (while first still touching)
  Finger 0: Not-Touching = 0, ID = N (same as before)
  Finger 1: Not-Touching = 0, ID = N+1 (new ID assigned)

State 4: First Finger Lifted (second still touching)
  Finger 0: Not-Touching = 1, ID = N
  Finger 1: Not-Touching = 0, ID = N+1 (still same)

State 5: All Fingers Lifted
  Finger 0: Not-Touching = 1, ID = N
  Finger 1: Not-Touching = 1, ID = N+1
```

### Tracking ID Persistence

The tracking ID is crucial for correlating touch events across report frames:

- Same ID across frames = same finger (calculate delta for movement)
- Different ID = new finger contact (reset delta calculation)
- When a finger lifts and re-touches, it receives a new incremented ID

### Touch State Flags (from DS4Windows)

DS4Windows derives several convenience flags from the raw touch data:

| Flag           | Meaning                                    |
|----------------|--------------------------------------------|
| `Touch1`       | Finger 0 is actively touching              |
| `Touch2`       | Finger 1 is actively touching              |
| `Touch1Finger` | At least 1 finger touching (`Touch1 OR Touch2`) |
| `Touch2Fingers`| Exactly 2 fingers touching (`Touch1 AND Touch2`) |
| `TouchButton`  | Physical click button is pressed           |

---

## 5. Touch Data Parsing

### Bitfield Breakdown

Each finger's touch data occupies 4 bytes with the following bit layout:

```
Byte 0 (ID + Active):
  Bits [6:0] = Touch tracking ID (7 bits, 0-127)
  Bit  [7]   = Not-Touching flag (1 = inactive, 0 = active)
               NOTE: This is INVERTED -- 0 means touching!

Byte 1 (X low):
  Bits [7:0] = X coordinate bits [7:0]

Byte 2 (X high + Y low):
  Bits [3:0] = X coordinate bits [11:8]
  Bits [7:4] = Y coordinate bits [3:0]

Byte 3 (Y high):
  Bits [7:0] = Y coordinate bits [11:4]
```

### Visual Bit Layout

```
Byte 0:  [ NT | ID6 | ID5 | ID4 | ID3 | ID2 | ID1 | ID0 ]
Byte 1:  [ X7 | X6  | X5  | X4  | X3  | X2  | X1  | X0  ]
Byte 2:  [ Y3 | Y2  | Y1  | Y0  | X11 | X10 | X9  | X8  ]
Byte 3:  [ Y11| Y10 | Y9  | Y8  | Y7  | Y6  | Y5  | Y4  ]
```

### Extraction Formulas

```c
// From raw report bytes at finger offset
uint8_t raw_id_byte = data[offset + 0];
uint8_t x_low       = data[offset + 1];
uint8_t xy_shared   = data[offset + 2];
uint8_t y_high      = data[offset + 3];

// Parse fields
uint8_t  touch_id    = raw_id_byte & 0x7F;          // Bits 0-6
bool     is_active   = (raw_id_byte & 0x80) == 0;   // Bit 7 inverted
uint16_t x_coord     = ((xy_shared & 0x0F) << 8) | x_low;     // 12-bit X
uint16_t y_coord     = (y_high << 4) | ((xy_shared & 0xF0) >> 4); // 12-bit Y
```

### Reconstruction Proof

The X coordinate is reconstructed as:
```
X = (Byte2[3:0] << 8) | Byte1[7:0]
  = 12-bit value with range 0-4095 (practical range 0-1919)
```

The Y coordinate is reconstructed as:
```
Y = (Byte3[7:0] << 4) | Byte2[7:4]
  = 12-bit value with range 0-4095 (practical range 0-942)
```

### Historical Touch Data

Each input report may contain multiple touch data packets, each representing a snapshot from a different time:

```
USB Report Layout (with historical data):
  Byte 33:     Number of touch packets (N, typically 1-3)
  Byte 34:     Timestamp for packet 0
  Bytes 35-42: Touch Packet 0 (most recent / current)
  Byte 43:     Timestamp for packet 1
  Bytes 44-51: Touch Packet 1 (previous state)
  ...additional packets at +9 byte intervals
```

Each touch packet is 9 bytes: 1 byte timestamp + 8 bytes (2 fingers x 4 bytes each).

Most implementations only process Touch Packet 0 (the current state). The historical packets can theoretically be used for:
- Higher precision gesture detection
- Interpolation between reports
- Recovery from dropped reports

---

## 6. Gesture Recognition

### 6.1 Tap / Click Detection

A tap is a quick touch-and-release without significant movement.

**Algorithm:**

```
Parameters:
  TAP_MAX_DURATION     = 200 ms    // Maximum time finger can be down
  TAP_MAX_DISTANCE     = 10 units  // Maximum movement allowed
  DOUBLE_TAP_WINDOW    = 300 ms    // Window for second tap (double-tap)

On touchesBegan:
  Record start position (startX, startY)
  Record start time

On touchesEnded:
  elapsed = currentTime - startTime
  distX = abs(endX - startX)
  distY = abs(endY - startY)

  if elapsed < TAP_MAX_DURATION AND distX < TAP_MAX_DISTANCE AND distY < TAP_MAX_DISTANCE:
    if previousTapTime exists AND (currentTime - previousTapTime) < DOUBLE_TAP_WINDOW:
      -> Double Tap detected
    else:
      -> Single Tap detected
      Record previousTapTime = currentTime
```

DS4Windows uses a configurable `TapSensitivity` value (in milliseconds) and checks displacement < 10 units for tap detection.

### 6.2 Swipe Detection

Detect directional finger movement exceeding a threshold.

**Algorithm (from DS4Windows):**

```
Parameters:
  SWIPE_THRESHOLD      = 300 units  // Minimum distance for swipe
  SWIPE_ANALOG_SCALE   = 1.5       // Scale factor for analog swipe value

On touchesMoved (single finger):
  deltaX = currentX - startX
  deltaY = currentY - startY

  // Directional swipe (boolean)
  if deltaX > SWIPE_THRESHOLD:  swipeRight = true
  if deltaX < -SWIPE_THRESHOLD: swipeLeft  = true
  if deltaY > SWIPE_THRESHOLD:  swipeDown  = true
  if deltaY < -SWIPE_THRESHOLD: swipeUp    = true

  // Analog swipe (0-255 intensity)
  swipeRightB = clamp(deltaX * SWIPE_ANALOG_SCALE, 0, 255)
  swipeLeftB  = clamp(-deltaX * SWIPE_ANALOG_SCALE, 0, 255)
  swipeDownB  = clamp(deltaY * SWIPE_ANALOG_SCALE, 0, 255)
  swipeUpB    = clamp(-deltaY * SWIPE_ANALOG_SCALE, 0, 255)
```

### 6.3 Two-Finger Scroll

Use two fingers moving in the same direction to generate scroll events.

**Algorithm (from DS4Windows MouseWheel):**

```
Parameters:
  SCROLL_COEFFICIENT = scrollSensitivity / 100.0
  STANDARD_DISTANCE  = 960 pixels  // Reference finger separation

On touchesMoved (two fingers):
  // Calculate midpoint of both fingers
  lastMidX = (prevFinger0.X + prevFinger1.X) / 2
  lastMidY = (prevFinger0.Y + prevFinger1.Y) / 2
  currMidX = (finger0.X + finger1.X) / 2
  currMidY = (finger0.Y + finger1.Y) / 2

  // Scale by finger separation distance
  touchDistance = sqrt((f1.X - f0.X)^2 + (f1.Y - f0.Y)^2)
  coefficient = SCROLL_COEFFICIENT * (touchDistance / STANDARD_DISTANCE)

  // Calculate scroll amounts
  scrollX = coefficient * (currMidX - lastMidX)
  scrollY = coefficient * (lastMidY - currMidY)  // Note: Y is inverted

  // Apply with remainder tracking
  scrollXAction = int(scrollX + horizontalRemainder)
  horizontalRemainder = scrollX + horizontalRemainder - scrollXAction
  // ... same for Y
```

### 6.4 Pinch-to-Zoom

Detect two fingers moving toward or away from each other.

**Algorithm:**

```
Parameters:
  PINCH_THRESHOLD = 50 units  // Minimum distance change to register

On touchesMoved (two fingers):
  prevDistance = sqrt((prevF0.X - prevF1.X)^2 + (prevF0.Y - prevF1.Y)^2)
  currDistance = sqrt((currF0.X - currF1.X)^2 + (currF0.Y - currF1.Y)^2)

  deltaDistance = currDistance - prevDistance

  if abs(totalPinchDelta) > PINCH_THRESHOLD:
    if totalPinchDelta > 0: -> Pinch Out (zoom in)
    if totalPinchDelta < 0: -> Pinch In (zoom out)

  pinchScale = currDistance / prevDistance
  // pinchScale > 1.0 = spreading apart
  // pinchScale < 1.0 = pinching together
```

### 6.5 Two-Finger Slide (Profile Switching)

DS4Windows implements horizontal two-finger slides for profile switching:

```
Parameters:
  SLIDE_THRESHOLD = 200 units
  MAX_Y_DEVIATION = 50 units  // Fingers must stay roughly horizontal

On touchesMoved (two fingers):
  if abs(startY - currentY) < MAX_Y_DEVIATION:
    if (finger0.X - startX) > SLIDE_THRESHOLD AND NOT slideLeft:
      slideRight = true
    if (startX - finger0.X) > SLIDE_THRESHOLD AND NOT slideRight:
      slideLeft = true
```

### 6.6 Drag Operations

A drag is a tap-and-hold followed by movement.

**Algorithm (from DS4Windows):**

```
Parameters:
  TAP_SENSITIVITY  = configurable (ms)
  DOUBLE_TAP_SCALE = 1.5x TAP_SENSITIVITY

State Machine:
  1. First tap detected (touch + release within TAP_SENSITIVITY)
  2. Record firstTapTime
  3. Second touch begins within DOUBLE_TAP_SCALE of firstTapTime
     -> secondTouchBegin = true
  4. While secondTouchBegin is true:
     -> Map Click.Left (holding down mouse button)
     -> dragging = true
     -> Movement generates mouse cursor movement
  5. On second touch release:
     -> dragging = false
```

---

## 7. Mouse Emulation

### 7.1 Relative Positioning (Touchpad as Trackpad)

The standard approach uses delta (change in position) between consecutive reports to move the mouse cursor.

**Algorithm (from DS4Windows MouseCursor):**

```
Constants:
  TOUCHPAD_MOUSE_OFFSET = 0.015  // Small offset to ensure sub-pixel movement
                                  // still produces some cursor motion

On touchesMoved:
  // Track finger identity to avoid jumps
  if currentTouchID != lastTouchID:
    reset deltas and remainders
    lastTouchID = currentTouchID
    return

  deltaX = current.X - previous.X
  deltaY = current.Y - previous.Y

  // Apply sensitivity coefficient
  coefficient = touchSensitivity * 0.01
  xMotion = coefficient * deltaX + (normX * TOUCHPAD_MOUSE_OFFSET * signX)
  yMotion = coefficient * deltaY + (normY * TOUCHPAD_MOUSE_OFFSET * signY)

  // Jitter compensation (optional)
  if jitterCompensation:
    threshold = 0.15
    if abs(xMotion) <= normX * threshold:
      xMotion = signX * pow(abs(xMotion) / threshold, 1.408) * threshold

  // Remainder tracking (preserve fractional pixel movement)
  xMotion += horizontalRemainder  // Add previous remainder
  xAction = int(xMotion)          // Integer pixels to move
  horizontalRemainder = xMotion - xAction  // Save remainder

  // Apply inversion settings
  if invertX: xAction *= -1
  if invertY: yAction *= -1

  // Move cursor
  moveMouse(xAction, yAction)
```

### 7.2 Absolute Positioning

Maps the entire touchpad surface to a screen region. Touching a position on the touchpad places the cursor at the corresponding screen position.

**Algorithm (from DS4Windows MouseCursor.TouchesMovedAbsolute):**

```
Parameters:
  maxZoneX = configurable percentage (default 100%)
  maxZoneY = configurable percentage (default 100%)

On touchesMoved:
  // Calculate active zone boundaries
  minX = RES_HALF_X - (maxZoneX * 0.01 * RES_HALF_X)  // 960 - zone
  maxX = RES_HALF_X + (maxZoneX * 0.01 * RES_HALF_X)  // 960 + zone
  minY = RES_HALF_Y - (maxZoneY * 0.01 * RES_HALF_Y)  // 471 - zone
  maxY = RES_HALF_Y + (maxZoneY * 0.01 * RES_HALF_Y)  // 471 + zone

  // Clamp touch position to active zone
  clampedX = clamp(touchX, minX, maxX)
  clampedY = clamp(touchY, minY, maxY)

  // Normalize to [0.0, 1.0]
  absX = (clampedX - minX) / (maxX - minX)
  absY = (clampedY - minY) / (maxY - minY)

  // Move cursor to absolute screen position
  moveMouseAbsolute(absX, absY)
```

### 7.3 Cursor Acceleration

DS4Windows provides multiple output curve options for touchpad-to-stick mapping (applicable to cursor acceleration as well):

- **Linear**: Direct 1:1 mapping
- **Enhanced Precision**: Higher precision at low speeds, faster at high speeds
- **Quadratic**: Acceleration proportional to speed squared
- **Cubic**: More aggressive acceleration curve
- **Custom Bezier**: User-defined curve via control points

### 7.4 Trackball / Inertia Mode

Simulates a physical trackball -- when the finger lifts, the cursor continues moving with gradually decaying velocity.

**Physics Model (from DS4Windows FakeTrackball):**

```
Constants:
  TRACKBALL_MASS        = 45
  TRACKBALL_RADIUS      = 0.0245
  TRACKBALL_INERTIA     = 2.0 * (MASS * RADIUS^2) / 5.0
  TRACKBALL_SCALE       = 0.004
  TRACKBALL_FRICTION    = 10 (configurable)
  TRACKBALL_BUFFER_LEN  = 8

  deceleration = RADIUS * FRICTION / INERTIA

While finger is touching:
  Store velocity samples in circular buffer:
    buffer[tail] = (deltaXY * SCALE) / 0.004  // Normalize to 4ms base

On finger lift:
  Calculate initial velocity from buffer (weighted average)
  xVel = weightedAverage(xBuffer)
  yVel = weightedAverage(yBuffer)

Each frame while velocity > 0:
  // Directional deceleration
  angle = atan2(-yVel, xVel)
  normX = abs(cos(angle))
  normY = abs(sin(angle))

  // Decay velocity
  xDecay = min(abs(xVel), deceleration * elapsedTime * normX)
  yDecay = min(abs(yVel), deceleration * elapsedTime * normY)
  xVel -= xDecay * sign(xVel)
  yVel -= yDecay * sign(yVel)

  // Convert velocity to cursor movement
  xMotion = (xVel * elapsedTime) / SCALE + xRemainder
  yMotion = (yVel * elapsedTime) / SCALE + yRemainder
  dx = int(xMotion)
  dy = int(yMotion)
  xRemainder = xMotion - dx
  yRemainder = yMotion - dy

  if dx == 0 AND dy == 0:
    trackballActive = false  // Stop
  else:
    moveCursor(dx, dy)
```

---

## 8. macOS Integration

### 8.1 IOKit HID Access

On macOS, the DS4 is accessed via the IOKit HID framework. The touchpad data is embedded within the standard HID input report.

```swift
// Key IOKit constants for DS4
let kDS4VendorID:  Int = 0x054C  // Sony
let kDS4ProductID: Int = 0x05C4  // DS4 v1
let kDS4V2ProductID: Int = 0x09CC  // DS4 v2
```

### 8.2 Posting Mouse Events via CGEvent

macOS provides `CGEvent` for synthesizing mouse input:

```swift
import CoreGraphics

// Relative mouse movement
func moveMouseRelative(dx: Int, dy: Int) {
    if let event = CGEvent(mouseEventSource: nil,
                           mouseType: .mouseMoved,
                           mouseCursorPosition: .zero,
                           mouseButton: .left) {
        // For relative movement, get current position and offset
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        let newPos = CGPoint(x: currentPos.x + CGFloat(dx),
                             y: currentPos.y + CGFloat(dy))
        event.location = newPos
        event.post(tap: .cghidEventTap)
    }
}

// Absolute mouse positioning
func moveMouseAbsolute(normalizedX: Double, normalizedY: Double) {
    guard let screen = NSScreen.main else { return }
    let screenFrame = screen.frame
    let point = CGPoint(
        x: normalizedX * Double(screenFrame.width),
        y: normalizedY * Double(screenFrame.height)
    )
    if let event = CGEvent(mouseEventSource: nil,
                           mouseType: .mouseMoved,
                           mouseCursorPosition: point,
                           mouseButton: .left) {
        event.post(tap: .cghidEventTap)
    }
}
```

### 8.3 Posting Scroll Events

```swift
func postScrollEvent(deltaY: Int, deltaX: Int) {
    if let event = CGEvent(scrollWheelEvent2Source: nil,
                           units: .pixel,
                           wheelCount: 2,
                           wheel1: Int32(deltaY),
                           wheel2: Int32(deltaX)) {
        event.post(tap: .cghidEventTap)
    }
}
```

### 8.4 Posting Click Events

```swift
func postMouseClick(button: CGMouseButton, isDown: Bool, at point: CGPoint) {
    let eventType: CGEventType
    switch (button, isDown) {
    case (.left, true):  eventType = .leftMouseDown
    case (.left, false): eventType = .leftMouseUp
    case (.right, true):  eventType = .rightMouseDown
    case (.right, false): eventType = .rightMouseUp
    default: return
    }

    if let event = CGEvent(mouseEventSource: nil,
                           mouseType: eventType,
                           mouseCursorPosition: point,
                           mouseButton: button) {
        event.post(tap: .cghidEventTap)
    }
}
```

### 8.5 Accessibility Permissions

Mouse event posting via `CGEvent` requires Accessibility permissions on macOS. The application must be added to System Settings > Privacy & Security > Accessibility. Without this permission, posted events will be silently dropped.

---

## 9. Code Examples

### 9.1 Complete Touch Data Parser (Swift)

```swift
import Foundation

// MARK: - Data Structures

/// Represents a single touch contact point on the DS4 touchpad
struct DS4TouchPoint {
    /// 7-bit tracking ID (0-127), persists for the lifetime of one touch contact
    let trackingID: UInt8
    /// Whether this finger is actively touching the pad
    let isActive: Bool
    /// X coordinate (0-1919)
    let x: UInt16
    /// Y coordinate (0-942)
    let y: UInt16
}

/// Complete touchpad state from one report
struct DS4TouchpadState {
    /// Number of touch packets in this report
    let packetCount: UInt8
    /// Auto-incrementing counter for temporal ordering
    let packetCounter: UInt8
    /// First finger slot
    let finger0: DS4TouchPoint
    /// Second finger slot
    let finger1: DS4TouchPoint
    /// Whether the touchpad click button is physically pressed
    let isClicked: Bool

    /// True if at least one finger is touching
    var isTouched: Bool { finger0.isActive || finger1.isActive }
    /// True if exactly two fingers are touching
    var isTwoFingerTouch: Bool { finger0.isActive && finger1.isActive }
}

// MARK: - Parser

/// Parses DS4 touchpad data from raw HID input reports
struct DS4TouchpadParser {

    /// Standard byte offset for touchpad data in USB reports.
    /// For Bluetooth 0x11 reports that have been stripped of the 2-byte header,
    /// use the same offset.
    static let touchpadDataOffset: Int = 35

    /// Parse a single touch finger from 4 bytes of data
    /// - Parameters:
    ///   - data: Raw report bytes
    ///   - offset: Byte offset to the start of this finger's 4-byte block
    /// - Returns: Parsed touch point
    static func parseTouchPoint(from data: [UInt8], at offset: Int) -> DS4TouchPoint {
        let idByte   = data[offset + 0]
        let xLow     = data[offset + 1]
        let xyShared = data[offset + 2]
        let yHigh    = data[offset + 3]

        let trackingID = idByte & 0x7F
        let isActive   = (idByte & 0x80) == 0  // Bit 7: 0 = touching, 1 = not touching

        let x = UInt16(xyShared & 0x0F) << 8 | UInt16(xLow)
        let y = UInt16(yHigh) << 4 | UInt16((xyShared & 0xF0) >> 4)

        return DS4TouchPoint(trackingID: trackingID, isActive: isActive, x: x, y: y)
    }

    /// Parse complete touchpad state from a USB input report
    /// - Parameter report: Raw 64-byte USB input report (including report ID at byte 0)
    /// - Returns: Parsed touchpad state
    static func parse(usbReport report: [UInt8]) -> DS4TouchpadState {
        // Touchpad click button: byte 7, bit 1
        let isClicked = (report[7] & 0x02) != 0

        // Touch packet count: byte 33
        let packetCount = report[33]

        // Touch packet counter/timestamp: byte 34
        let packetCounter = report[34]

        // Finger 0: bytes 35-38
        let finger0 = parseTouchPoint(from: report, at: touchpadDataOffset)

        // Finger 1: bytes 39-42
        let finger1 = parseTouchPoint(from: report, at: touchpadDataOffset + 4)

        return DS4TouchpadState(
            packetCount: packetCount,
            packetCounter: packetCounter,
            finger0: finger0,
            finger1: finger1,
            isClicked: isClicked
        )
    }

    /// Parse complete touchpad state from a Bluetooth 0x11 report
    /// - Parameter report: Raw 78-byte Bluetooth report (report ID 0x11)
    /// - Returns: Parsed touchpad state
    static func parse(btReport report: [UInt8]) -> DS4TouchpadState {
        // BT 0x11 reports have a 2-byte offset compared to USB
        let btOffset = 2

        let isClicked = (report[7 + btOffset] & 0x02) != 0
        let packetCount = report[33 + btOffset]
        let packetCounter = report[34 + btOffset]

        let finger0 = parseTouchPoint(from: report, at: touchpadDataOffset + btOffset)
        let finger1 = parseTouchPoint(from: report, at: touchpadDataOffset + btOffset + 4)

        return DS4TouchpadState(
            packetCount: packetCount,
            packetCounter: packetCounter,
            finger0: finger0,
            finger1: finger1,
            isClicked: isClicked
        )
    }
}
```

### 9.2 Coordinate-to-Screen Conversion (Swift)

```swift
import CoreGraphics

struct DS4ScreenMapper {
    /// Maximum X coordinate reported by the touchpad
    static let maxX: CGFloat = 1919.0
    /// Maximum Y coordinate reported by the touchpad
    static let maxY: CGFloat = 942.0

    /// Convert touchpad coordinates to normalized [0, 1] range
    static func normalize(touchX: UInt16, touchY: UInt16) -> CGPoint {
        return CGPoint(
            x: CGFloat(touchX) / maxX,
            y: CGFloat(touchY) / maxY
        )
    }

    /// Convert touchpad coordinates to screen pixel coordinates
    static func toScreenPoint(touchX: UInt16, touchY: UInt16,
                              screenWidth: CGFloat, screenHeight: CGFloat) -> CGPoint {
        let norm = normalize(touchX: touchX, touchY: touchY)
        return CGPoint(
            x: norm.x * screenWidth,
            y: norm.y * screenHeight
        )
    }

    /// Determine which zone of the touchpad is being touched
    static func zone(touchX: UInt16) -> TouchZone {
        let threshold = Int(1920 * 2 / 5)  // 768
        if touchX < threshold {
            return .left
        } else {
            return .right
        }
    }

    enum TouchZone {
        case left
        case right
    }
}
```

### 9.3 Gesture Detector (Swift)

```swift
import Foundation
import CoreGraphics

/// Detected gesture types
enum DS4Gesture {
    case tap(position: CGPoint)
    case doubleTap(position: CGPoint)
    case swipeLeft
    case swipeRight
    case swipeUp
    case swipeDown
    case twoFingerScroll(deltaX: CGFloat, deltaY: CGFloat)
    case pinch(scale: CGFloat)
}

/// Detects gestures from a stream of DS4 touchpad states
class DS4GestureDetector {

    // MARK: - Configuration

    /// Maximum duration for a tap (seconds)
    var tapMaxDuration: TimeInterval = 0.2
    /// Maximum movement for a tap (touchpad units)
    var tapMaxDistance: CGFloat = 15.0
    /// Window for detecting double-taps (seconds)
    var doubleTapWindow: TimeInterval = 0.3
    /// Minimum distance for swipe detection (touchpad units)
    var swipeThreshold: CGFloat = 300.0

    // MARK: - Internal State

    private var touchStartTime: Date?
    private var touchStartPosition: CGPoint?
    private var lastTapTime: Date?
    private var lastTapPosition: CGPoint?

    private var previousState: DS4TouchpadState?
    private var previousFinger0Pos: CGPoint?
    private var previousFinger1Pos: CGPoint?
    private var lastTrackingID0: UInt8?
    private var lastTrackingID1: UInt8?

    // MARK: - Public Interface

    /// Process a new touchpad state and return any detected gestures
    func process(state: DS4TouchpadState) -> [DS4Gesture] {
        var gestures: [DS4Gesture] = []

        let wasActive = previousState?.isTouched ?? false
        let isActive = state.isTouched

        // Touch began
        if isActive && !wasActive {
            handleTouchBegan(state: state)
        }

        // Touch moved
        if isActive && wasActive {
            gestures.append(contentsOf: handleTouchMoved(state: state))
        }

        // Touch ended
        if !isActive && wasActive {
            gestures.append(contentsOf: handleTouchEnded(state: state))
        }

        previousState = state
        return gestures
    }

    // MARK: - Touch Lifecycle

    private func handleTouchBegan(state: DS4TouchpadState) {
        let finger = state.finger0.isActive ? state.finger0 : state.finger1
        touchStartTime = Date()
        touchStartPosition = CGPoint(x: CGFloat(finger.x), y: CGFloat(finger.y))
        lastTrackingID0 = state.finger0.trackingID
        lastTrackingID1 = state.finger1.trackingID

        if state.finger0.isActive {
            previousFinger0Pos = CGPoint(x: CGFloat(state.finger0.x),
                                         y: CGFloat(state.finger0.y))
        }
        if state.finger1.isActive {
            previousFinger1Pos = CGPoint(x: CGFloat(state.finger1.x),
                                         y: CGFloat(state.finger1.y))
        }
    }

    private func handleTouchMoved(state: DS4TouchpadState) -> [DS4Gesture] {
        var gestures: [DS4Gesture] = []

        // Two-finger gestures
        if state.isTwoFingerTouch {
            let f0 = CGPoint(x: CGFloat(state.finger0.x), y: CGFloat(state.finger0.y))
            let f1 = CGPoint(x: CGFloat(state.finger1.x), y: CGFloat(state.finger1.y))

            if let prevF0 = previousFinger0Pos, let prevF1 = previousFinger1Pos,
               state.finger0.trackingID == lastTrackingID0,
               state.finger1.trackingID == lastTrackingID1 {

                // Scroll detection (midpoint movement)
                let prevMid = CGPoint(x: (prevF0.x + prevF1.x) / 2,
                                      y: (prevF0.y + prevF1.y) / 2)
                let currMid = CGPoint(x: (f0.x + f1.x) / 2,
                                      y: (f0.y + f1.y) / 2)
                let scrollDX = currMid.x - prevMid.x
                let scrollDY = prevMid.y - currMid.y  // Inverted for natural scrolling

                if abs(scrollDX) > 1 || abs(scrollDY) > 1 {
                    gestures.append(.twoFingerScroll(deltaX: scrollDX, deltaY: scrollDY))
                }

                // Pinch detection (distance change)
                let prevDist = distance(prevF0, prevF1)
                let currDist = distance(f0, f1)
                if prevDist > 0 {
                    let scale = currDist / prevDist
                    if abs(scale - 1.0) > 0.01 {
                        gestures.append(.pinch(scale: scale))
                    }
                }
            }

            previousFinger0Pos = f0
            previousFinger1Pos = f1
            lastTrackingID0 = state.finger0.trackingID
            lastTrackingID1 = state.finger1.trackingID
        } else if state.finger0.isActive {
            previousFinger0Pos = CGPoint(x: CGFloat(state.finger0.x),
                                         y: CGFloat(state.finger0.y))
            lastTrackingID0 = state.finger0.trackingID
        }

        return gestures
    }

    private func handleTouchEnded(state: DS4TouchpadState) -> [DS4Gesture] {
        var gestures: [DS4Gesture] = []

        guard let startTime = touchStartTime,
              let startPos = touchStartPosition else {
            return gestures
        }

        let prev = previousState!
        let endFinger = prev.finger0.isActive ? prev.finger0 : prev.finger1
        let endPos = CGPoint(x: CGFloat(endFinger.x), y: CGFloat(endFinger.y))
        let elapsed = Date().timeIntervalSince(startTime)
        let dx = endPos.x - startPos.x
        let dy = endPos.y - startPos.y
        let dist = sqrt(dx * dx + dy * dy)

        // Tap detection
        if elapsed < tapMaxDuration && dist < tapMaxDistance {
            let now = Date()
            if let lastTap = lastTapTime,
               now.timeIntervalSince(lastTap) < doubleTapWindow {
                gestures.append(.doubleTap(position: endPos))
                lastTapTime = nil
            } else {
                gestures.append(.tap(position: endPos))
                lastTapTime = now
                lastTapPosition = endPos
            }
        }
        // Swipe detection
        else if elapsed < 1.0 {
            if dx > swipeThreshold { gestures.append(.swipeRight) }
            if dx < -swipeThreshold { gestures.append(.swipeLeft) }
            if dy > swipeThreshold { gestures.append(.swipeDown) }
            if dy < -swipeThreshold { gestures.append(.swipeUp) }
        }

        // Reset state
        touchStartTime = nil
        touchStartPosition = nil
        previousFinger0Pos = nil
        previousFinger1Pos = nil

        return gestures
    }

    // MARK: - Utilities

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        return sqrt(dx * dx + dy * dy)
    }
}
```

### 9.4 Mouse Cursor Controller (Swift)

```swift
import CoreGraphics
import Foundation

/// Controls the mouse cursor using DS4 touchpad input
class DS4TouchpadMouseController {

    // MARK: - Configuration

    /// Sensitivity multiplier (1.0 = default, higher = faster)
    var sensitivity: Double = 1.0
    /// Enable jitter compensation to reduce cursor shake on small movements
    var jitterCompensation: Bool = true
    /// Enable trackball mode (cursor continues moving after finger lifts)
    var trackballMode: Bool = false
    /// Trackball friction (higher = stops faster). Range: 1-50
    var trackballFriction: Double = 10.0

    // MARK: - Internal State

    private var lastTrackingID: UInt8 = 0
    private var horizontalRemainder: Double = 0.0
    private var verticalRemainder: Double = 0.0
    private var isFirstTouch: Bool = true
    private var previousPosition: CGPoint = .zero

    // Trackball state
    private var trackballActive: Bool = false
    private var trackballXVel: Double = 0.0
    private var trackballYVel: Double = 0.0
    private let trackballScale: Double = 0.004
    private let trackballRadius: Double = 0.0245
    private let trackballMass: Double = 45.0
    private var trackballInertia: Double {
        2.0 * (trackballMass * trackballRadius * trackballRadius) / 5.0
    }
    private var trackballDeceleration: Double {
        trackballRadius * trackballFriction / trackballInertia
    }
    private var velocityBuffer: [(Double, Double)] = []
    private let velocityBufferSize: Int = 8

    // Click state
    private var isLeftButtonDown: Bool = false

    // MARK: - Constants

    private let mouseOffset: Double = 0.015
    private let jitterThreshold: Double = 0.15

    // MARK: - Public Interface

    /// Process a touchpad state update and move the cursor accordingly
    func update(state: DS4TouchpadState, elapsedTime: Double) {
        // Handle touchpad click
        handleClick(state: state)

        // Find the active finger
        let activeFinger: DS4TouchPoint?
        if state.finger0.isActive {
            activeFinger = state.finger0
        } else if state.finger1.isActive {
            activeFinger = state.finger1
        } else {
            activeFinger = nil
        }

        if let finger = activeFinger {
            // Finger is touching
            trackballActive = false
            let currentPos = CGPoint(x: CGFloat(finger.x), y: CGFloat(finger.y))

            if finger.trackingID != lastTrackingID || isFirstTouch {
                // New finger contact -- reset tracking
                lastTrackingID = finger.trackingID
                isFirstTouch = false
                horizontalRemainder = 0
                verticalRemainder = 0
                velocityBuffer.removeAll()
                previousPosition = currentPos
                return
            }

            // Calculate delta
            let dx = Int(currentPos.x - previousPosition.x)
            let dy = Int(currentPos.y - previousPosition.y)

            // Store velocity sample for trackball
            if trackballMode {
                let vx = (Double(dx) * trackballScale) / max(elapsedTime, 0.001)
                let vy = (Double(dy) * trackballScale) / max(elapsedTime, 0.001)
                velocityBuffer.append((vx, vy))
                if velocityBuffer.count > velocityBufferSize {
                    velocityBuffer.removeFirst()
                }
            }

            // Move cursor with sensitivity and jitter compensation
            moveCursorRelative(dx: dx, dy: dy)
            previousPosition = currentPos

        } else {
            // No finger touching
            isFirstTouch = true

            if trackballMode && !trackballActive && !velocityBuffer.isEmpty {
                // Initialize trackball velocity from buffer
                let avgVel = velocityBuffer.reduce((0.0, 0.0)) { ($0.0 + $1.0, $0.1 + $1.1) }
                let count = Double(velocityBuffer.count)
                trackballXVel = avgVel.0 / count
                trackballYVel = avgVel.1 / count
                trackballActive = true
                velocityBuffer.removeAll()
            }

            if trackballActive {
                processTrackball(elapsedTime: elapsedTime)
            }
        }
    }

    // MARK: - Cursor Movement

    private func moveCursorRelative(dx: Int, dy: Int) {
        let signX = dx >= 0 ? 1.0 : -1.0
        let signY = dy >= 0 ? 1.0 : -1.0
        let angle = atan2(Double(-dy), Double(dx))
        let normX = abs(cos(angle))
        let normY = abs(sin(angle))

        var xMotion: Double = dx != 0
            ? sensitivity * Double(dx) + (normX * mouseOffset * signX)
            : 0.0
        var yMotion: Double = dy != 0
            ? sensitivity * Double(dy) + (normY * mouseOffset * signY)
            : 0.0

        // Jitter compensation
        if jitterCompensation {
            let absX = abs(xMotion)
            if absX <= normX * jitterThreshold && absX > 0 {
                xMotion = signX * pow(absX / jitterThreshold, 1.408) * jitterThreshold
            }
            let absY = abs(yMotion)
            if absY <= normY * jitterThreshold && absY > 0 {
                yMotion = signY * pow(absY / jitterThreshold, 1.408) * jitterThreshold
            }
        }

        // Accumulate remainders
        xMotion += horizontalRemainder
        yMotion += verticalRemainder
        let xAction = Int(xMotion)
        let yAction = Int(yMotion)
        horizontalRemainder = xMotion - Double(xAction)
        verticalRemainder = yMotion - Double(yAction)

        if xAction != 0 || yAction != 0 {
            postRelativeMouseMove(dx: xAction, dy: yAction)
        }
    }

    private func processTrackball(elapsedTime: Double) {
        let angle = atan2(-trackballYVel, trackballXVel)
        let normX = abs(cos(angle))
        let normY = abs(sin(angle))
        let signX = trackballXVel >= 0 ? 1.0 : -1.0
        let signY = trackballYVel >= 0 ? 1.0 : -1.0

        let xDecay = min(abs(trackballXVel), trackballDeceleration * elapsedTime * normX)
        let yDecay = min(abs(trackballYVel), trackballDeceleration * elapsedTime * normY)

        trackballXVel -= xDecay * signX
        trackballYVel -= yDecay * signY

        var xMotion = (trackballXVel * elapsedTime) / trackballScale + horizontalRemainder
        var yMotion = (trackballYVel * elapsedTime) / trackballScale + verticalRemainder

        let dx = Int(xMotion)
        let dy = Int(yMotion)
        horizontalRemainder = xMotion - Double(dx)
        verticalRemainder = yMotion - Double(dy)

        if dx == 0 && dy == 0 {
            trackballActive = false
            horizontalRemainder = 0
            verticalRemainder = 0
        } else {
            postRelativeMouseMove(dx: dx, dy: dy)
        }
    }

    // MARK: - Click Handling

    private func handleClick(state: DS4TouchpadState) {
        if state.isClicked && !isLeftButtonDown {
            isLeftButtonDown = true
            let pos = currentCursorPosition()
            postMouseButton(button: .left, isDown: true, at: pos)
        } else if !state.isClicked && isLeftButtonDown {
            isLeftButtonDown = false
            let pos = currentCursorPosition()
            postMouseButton(button: .left, isDown: false, at: pos)
        }
    }

    // MARK: - CGEvent Helpers

    private func currentCursorPosition() -> CGPoint {
        return CGEvent(source: nil)?.location ?? .zero
    }

    private func postRelativeMouseMove(dx: Int, dy: Int) {
        let currentPos = currentCursorPosition()
        let newPos = CGPoint(x: currentPos.x + CGFloat(dx),
                             y: currentPos.y + CGFloat(dy))

        let eventType: CGEventType = isLeftButtonDown ? .leftMouseDragged : .mouseMoved
        if let event = CGEvent(mouseEventSource: nil,
                               mouseType: eventType,
                               mouseCursorPosition: newPos,
                               mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
    }

    private func postMouseButton(button: CGMouseButton, isDown: Bool, at point: CGPoint) {
        let eventType: CGEventType
        switch (button, isDown) {
        case (.left, true):   eventType = .leftMouseDown
        case (.left, false):  eventType = .leftMouseUp
        case (.right, true):  eventType = .rightMouseDown
        case (.right, false): eventType = .rightMouseUp
        default: return
        }

        if let event = CGEvent(mouseEventSource: nil,
                               mouseType: eventType,
                               mouseCursorPosition: point,
                               mouseButton: button) {
            event.post(tap: .cghidEventTap)
        }
    }
}
```

### 9.5 Integration Example (Swift)

```swift
import Foundation
import IOKit.hid

/// Example: Wiring together the parser, gesture detector, and mouse controller
/// within an IOKit HID input report callback.
class DS4TouchpadIntegration {

    let parser = DS4TouchpadParser.self
    let gestureDetector = DS4GestureDetector()
    let mouseController = DS4TouchpadMouseController()

    private var lastReportTime: Date = Date()

    /// Called from the IOKit HID report callback
    func handleInputReport(_ report: [UInt8], isUSB: Bool) {
        // Calculate elapsed time
        let now = Date()
        let elapsed = now.timeIntervalSince(lastReportTime)
        lastReportTime = now

        // Parse touchpad data
        let touchState: DS4TouchpadState
        if isUSB {
            touchState = parser.parse(usbReport: report)
        } else {
            touchState = parser.parse(btReport: report)
        }

        // Update mouse cursor
        mouseController.update(state: touchState, elapsedTime: elapsed)

        // Detect gestures
        let gestures = gestureDetector.process(state: touchState)
        for gesture in gestures {
            handleGesture(gesture)
        }
    }

    private func handleGesture(_ gesture: DS4Gesture) {
        switch gesture {
        case .tap(let pos):
            print("Tap at (\(pos.x), \(pos.y))")
        case .doubleTap(let pos):
            print("Double-tap at (\(pos.x), \(pos.y))")
        case .swipeLeft:
            print("Swipe left")
        case .swipeRight:
            print("Swipe right")
        case .swipeUp:
            print("Swipe up")
        case .swipeDown:
            print("Swipe down")
        case .twoFingerScroll(let dx, let dy):
            // Post scroll events to macOS
            let scrollX = Int(dx * 0.1)  // Scale down for reasonable scroll speed
            let scrollY = Int(dy * 0.1)
            if let event = CGEvent(scrollWheelEvent2Source: nil,
                                   units: .pixel,
                                   wheelCount: 2,
                                   wheel1: Int32(scrollY),
                                   wheel2: Int32(scrollX)) {
                event.post(tap: .cghidEventTap)
            }
        case .pinch(let scale):
            print("Pinch scale: \(scale)")
            // Could map to zoom via keyboard shortcut simulation (Cmd+/Cmd-)
        }
    }
}
```

---

## References

### Data Sources

- [Sony DualShock 4 -- Controllers Wiki](https://controllers.fandom.com/wiki/Sony_DualShock_4) -- Resolution (1920x943), capacitive specs, report IDs
- [Sony DualShock 4 Data Structures -- Controllers Wiki](https://controllers.fandom.com/wiki/Sony_DualShock_4/Data_Structures) -- TouchFingerData struct, bitfield layout, packet format
- [DS4-USB -- PS4 Developer Wiki](https://www.psdevwiki.com/ps4/DS4-USB) -- Byte offsets, coordinate encoding, USB report layout
- [DualShock 4 -- PCGamingWiki](https://www.pcgamingwiki.com/wiki/Controller:DualShock_4) -- General specifications

### Reference Implementations

- **DS4Windows** (`DS4Touchpad.cs`, `Mouse.cs`, `MouseCursor.cs`, `MouseWheel.cs`, `FakeTrackball.cs`) -- Complete touchpad parsing, gesture detection, mouse/trackball emulation, and two-finger scroll implementation
- **ds4drv (chrippa)** (`device.py`, `uinput.py`, `actions/input.py`) -- Python touchpad parsing with byte-level coordinate extraction, mouse emulation via uinput
- **ds4drv (clearpath robotics fork)** (`device.py`, `uinput.py`) -- Same parsing logic with ROS integration improvements
