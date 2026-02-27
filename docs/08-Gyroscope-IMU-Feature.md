# DualShock 4 Gyroscope / Accelerometer (6-Axis IMU) Reference

## Related Documents

- **04-USB-Protocol.md** -- USB input report 0x01 structure (IMU data is embedded within)
- **05-Bluetooth-Protocol.md** -- BT input report 0x11 structure, offset differences, and calibration feature report CRC
- **07-Touchpad-Feature.md** -- Shares the same input reports (0x01 / 0x11); touchpad data follows IMU data

---

## Table of Contents

1. [Hardware Specifications](#1-hardware-specifications)
2. [Input Report Data](#2-input-report-data)
3. [Calibration](#3-calibration)
4. [Unit Conversion](#4-unit-conversion)
5. [Sensor Fusion](#5-sensor-fusion)
6. [Motion Control Applications](#6-motion-control-applications)
7. [Coordinate System](#7-coordinate-system)
8. [Code Examples](#8-code-examples)

---

## 1. Hardware Specifications

### 1.1 IMU Chip: Bosch BMI055

The DualShock 4 controller uses the **Bosch BMI055** 6-axis inertial measurement unit (IMU). This is a combo sensor that pairs an advanced triaxial **16-bit gyroscope** with a versatile triaxial **12-bit accelerometer** in a single compact package.

| Property | Value |
|---|---|
| **Manufacturer** | Bosch Sensortec |
| **Part Number** | BMI055 |
| **Package** | LGA, 3.0 x 4.5 mm, 0.95 mm height |
| **Supply Voltage** | 2.4 V - 3.6 V (VDD), 1.2 V - 3.6 V (VDDIO) |
| **Interface** | Digital SPI and I2C |
| **Total Current** | < 5 mA |
| **Operating Temp** | -40 C to +85 C |

### 1.2 Gyroscope Specifications

The BMI055 gyroscope is a 16-bit digital triaxial angular rate sensor.

| Parameter | Value |
|---|---|
| **Axes** | 3 (X, Y, Z) |
| **Resolution** | 16-bit signed integer |
| **Programmable Ranges** | +/-125, +/-250, +/-500, +/-1000, +/-2000 deg/s |
| **DS4 Operating Range** | +/-2000 deg/s |
| **Sensitivity at +/-2000** | 16.4 LSB/(deg/s) |
| **Sensitivity at +/-1000** | 32.8 LSB/(deg/s) |
| **Sensitivity at +/-500** | 65.6 LSB/(deg/s) |
| **Sensitivity at +/-250** | 131.2 LSB/(deg/s) |
| **Sensitivity at +/-125** | 262.4 LSB/(deg/s) |
| **Zero-Rate Offset** | +/-1 deg/s |
| **Noise Density** | 0.014 deg/s/sqrt(Hz) |
| **Bandwidth** | 12 Hz - 230 Hz (programmable) |
| **Output Data Rate** | Up to 2000 Hz |

### 1.3 Accelerometer Specifications

The BMI055 accelerometer is a 12-bit digital triaxial acceleration sensor.

| Parameter | Value |
|---|---|
| **Axes** | 3 (X, Y, Z) |
| **Resolution** | 12-bit (stored as 16-bit signed, lower 4 bits unused) |
| **Programmable Ranges** | +/-2g, +/-4g, +/-8g, +/-16g |
| **DS4 Operating Range** | +/-4g (most likely configuration) |
| **Sensitivity at +/-2g** | 1024 LSB/g |
| **Sensitivity at +/-4g** | 512 LSB/g |
| **Sensitivity at +/-8g** | 256 LSB/g |
| **Sensitivity at +/-16g** | 128 LSB/g |
| **Zero-g Offset** | +/-70 mg |
| **Noise Density** | 150 ug/sqrt(Hz) |
| **Bandwidth** | 7.81 Hz - 1000 Hz (programmable) |
| **Output Data Rate** | Up to 2000 Hz |

> **Note on DS4 Configuration:** The DS4 firmware configures the BMI055 internally.
> The exact range settings are not directly accessible to the host, but calibration
> data (Section 3) provides the necessary scaling factors. The gyroscope is widely
> confirmed to operate at +/-2000 deg/s. The accelerometer range is inferred from
> calibration denominators and the DS4Windows constant `ACC_RES_PER_G = 8192`,
> which after calibration scaling maps to a consistent unit space.

---

## 2. Input Report Data

### 2.1 USB Input Report (Report ID 0x01)

The standard USB input report is 64 bytes. IMU data is located within what the
DS4Windows codebase calls `GetStateData`, a sub-structure starting at byte 0 of
the report payload (after the report ID byte).

The byte offsets below are **relative to the start of the report payload**
(byte index 0 = report ID `0x01`). Most documentation uses a 0-indexed offset
where byte 0 is the report ID.

#### 2.1.1 Timestamp

| Field | Byte Offset | Size | Format | Description |
|---|---|---|---|---|
| Timestamp | 10 - 11 | 2 bytes | uint16, LE | Increments in 5.33 us units |

The timestamp is a 16-bit unsigned counter. A common increment between consecutive
reports is **188**, corresponding to a report period of approximately **1.25 ms**
(800 Hz) at full rate.

```
timestamp_us = raw_timestamp * 16 / 3    // Convert to microseconds
elapsed_s = delta_timestamp_us * 0.000001 // Convert to seconds
```

When the timestamp wraps around (65535 -> 0):
```
if current_timestamp < previous_timestamp:
    delta = (65535 - previous_timestamp) + current_timestamp + 1
else:
    delta = current_timestamp - previous_timestamp
```

#### 2.1.2 Gyroscope Data

All gyroscope values are **signed 16-bit integers** in **little-endian** byte order.

| Axis | Byte Offset | Bytes | Physical Meaning |
|---|---|---|---|
| Gyro X (Pitch) | 13 - 14 | `[13]=LSB, [14]=MSB` | Angular velocity around X axis |
| Gyro Y (Yaw) | 15 - 16 | `[15]=LSB, [16]=MSB` | Angular velocity around Y axis |
| Gyro Z (Roll) | 17 - 18 | `[17]=LSB, [18]=MSB` | Angular velocity around Z axis |

Reading a value (little-endian signed 16-bit):
```
int16_t gyroX = (int16_t)((report[14] << 8) | report[13]);
int16_t gyroY = (int16_t)((report[16] << 8) | report[15]);
int16_t gyroZ = (int16_t)((report[18] << 8) | report[17]);
```

#### 2.1.3 Accelerometer Data

All accelerometer values are **signed 16-bit integers** in **little-endian** byte order.

| Axis | Byte Offset | Bytes | Physical Meaning |
|---|---|---|---|
| Accel X | 19 - 20 | `[19]=LSB, [20]=MSB` | Linear acceleration along X axis |
| Accel Y | 21 - 22 | `[21]=LSB, [22]=MSB` | Linear acceleration along Y axis |
| Accel Z | 23 - 24 | `[23]=LSB, [24]=MSB` | Linear acceleration along Z axis |

Reading a value (little-endian signed 16-bit):
```
int16_t accelX = (int16_t)((report[20] << 8) | report[19]);
int16_t accelY = (int16_t)((report[22] << 8) | report[21]);
int16_t accelZ = (int16_t)((report[24] << 8) | report[23]);
```

#### 2.1.4 Complete USB IMU Data Map

```
USB Input Report 0x01 (64 bytes):
Offset  Field
------  -----
 0      Report ID (0x01)
 1      Left Stick X
 2      Left Stick Y
 3      Right Stick X
 4      Right Stick Y
 5      Buttons (DPad + face)
 6      Buttons (shoulder + stick)
 7      Buttons (PS + touch) + Frame Counter
 8      L2 Trigger
 9      R2 Trigger
10-11   Timestamp (uint16 LE, 5.33 us units)
12      Temperature (?)
13-14   Gyro X / Pitch  (int16 LE)
15-16   Gyro Y / Yaw    (int16 LE)
17-18   Gyro Z / Roll   (int16 LE)
19-20   Accel X         (int16 LE)
21-22   Accel Y         (int16 LE)
23-24   Accel Z         (int16 LE)
25-29   (other data)
30      Battery + status
31-33   (reserved)
34      Touch packet count
35-42   Touch data 1
43-50   Touch data 2 (if present)
...
```

### 2.2 Bluetooth Input Report

#### 2.2.1 Basic Report (0x01) -- Truncated

Over Bluetooth, the default report ID 0x01 is a **truncated** report that does
**not** include IMU data. It only contains sticks, buttons, and limited data.

To receive full IMU data over Bluetooth, you must:
1. Read the calibration feature report (0x05) -- this acts as a trigger
2. The controller then switches to **extended reports** (0x11 - 0x19)

#### 2.2.2 Extended Report (0x11)

The Bluetooth extended report 0x11 contains the same `GetStateData` structure
but with a **+2 byte offset** due to the Bluetooth header bytes (`0xC0 0x00`
or similar protocol header).

| Field | USB Offset | BT 0x11 Offset | Delta |
|---|---|---|---|
| Timestamp | 10 - 11 | 12 - 13 | +2 |
| Gyro X | 13 - 14 | 15 - 16 | +2 |
| Gyro Y | 15 - 16 | 17 - 18 | +2 |
| Gyro Z | 17 - 18 | 19 - 20 | +2 |
| Accel X | 19 - 20 | 21 - 22 | +2 |
| Accel Y | 21 - 22 | 23 - 24 | +2 |
| Accel Z | 23 - 24 | 25 - 26 | +2 |

> **Implementation Note:** In DS4Windows and ds4drv, the Bluetooth report is
> typically adjusted by stripping the 2-byte header so the remaining parsing
> code uses the same offsets as USB. When processing raw BT reports directly,
> add +2 to all USB offsets.

---

## 3. Calibration

### 3.1 Reading Calibration Data

Calibration data is stored in the DS4's internal flash memory and retrieved via
HID **Feature Reports**:

| Connection | Feature Report ID | Total Size | Data Payload |
|---|---|---|---|
| **USB / Dongle** | `0x02` | 37 bytes | Bytes 1-34 = calibration |
| **Bluetooth** | `0x05` | 41 bytes | Bytes 1-34 = calibration, 37-40 = CRC32 |

> **Important:** Reading the Bluetooth calibration report (0x05) is **required**
> to switch the controller from truncated 0x01 reports to the extended 0x11
> reports that include IMU data.

#### 3.1.1 Bluetooth CRC32 Validation

For Bluetooth connections, the calibration report includes a 4-byte CRC32 at the
end (bytes 37-40). The CRC is computed over:
- A seed byte `0xA3`
- Followed by the report data (bytes 0 through 36)

```
CRC32 seed = CRC32(0xA3)
CRC32 result = CRC32_continue(seed, report[0..36])
expected = report[37] | (report[38] << 8) | (report[39] << 16) | (report[40] << 24)
valid = (result == expected)
```

If the CRC check fails, retry up to 5 times.

### 3.2 Calibration Data Format

All calibration values are **signed 16-bit integers** in **little-endian** byte order.
The byte offsets below are relative to the start of the calibration report payload
(byte 0 = report ID).

#### 3.2.1 Gyroscope Calibration

| Offset | Field | Description |
|---|---|---|
| 1 - 2 | `gyroPitchBias` | Pitch (X) axis zero-rate bias |
| 3 - 4 | `gyroYawBias` | Yaw (Y) axis zero-rate bias |
| 5 - 6 | `gyroRollBias` | Roll (Z) axis zero-rate bias |
| 7 - 8 | `gyroPitchPlus` | Pitch positive reference rotation |
| 9 - 10 | `gyroYawPlus` | Yaw positive reference rotation |
| 11 - 12 | `gyroRollPlus` | Roll positive reference rotation |
| 13 - 14 | `gyroPitchMinus` | Pitch negative reference rotation |
| 15 - 16 | `gyroYawMinus` | Yaw negative reference rotation |
| 17 - 18 | `gyroRollMinus` | Roll negative reference rotation |
| 19 - 20 | `gyroSpeedPlus` | Positive speed reference value |
| 21 - 22 | `gyroSpeedMinus` | Negative speed reference value |

> **Alternate Layout (USB):** DS4Windows notes that USB connections use a different
> ordering for the plus/minus values. With `useAltGyroCalib = true` (USB mode):
> - Bytes 7-8: pitchPlus, 9-10: pitchMinus
> - Bytes 11-12: yawPlus, 13-14: yawMinus
> - Bytes 15-16: rollPlus, 17-18: rollMinus
>
> With `useAltGyroCalib = false` (Bluetooth mode):
> - Bytes 7-8: pitchPlus, 9-10: yawPlus, 11-12: rollPlus
> - Bytes 13-14: pitchMinus, 15-16: yawMinus, 17-18: rollMinus

#### 3.2.2 Accelerometer Calibration

| Offset | Field | Description |
|---|---|---|
| 23 - 24 | `accelXPlus` | X-axis positive 1g reference |
| 25 - 26 | `accelXMinus` | X-axis negative 1g reference |
| 27 - 28 | `accelYPlus` | Y-axis positive 1g reference |
| 29 - 30 | `accelYMinus` | Y-axis negative 1g reference |
| 31 - 32 | `accelZPlus` | Z-axis positive 1g reference |
| 33 - 34 | `accelZMinus` | Z-axis negative 1g reference |

#### 3.2.3 Example Calibration Data

```
Raw report (hex): 02 01 00 00 00 00 00 87 22 7B DD B2 22 47 DD
                  BD 22 43 DD 1C 02 1C 02 7F 1E 2E DF 60 1F 4C E0
                  3A 1D C6 DE 08 00

Decoded:
  Gyro Pitch Bias:   0x0001  =  1
  Gyro Yaw Bias:     0x0000  =  0
  Gyro Roll Bias:    0x0000  =  0
  Gyro Pitch Plus:   0x2287  =  8839
  Gyro Yaw Plus:     0xDD7B  = -8837
  Gyro Roll Plus:    0x22B2  =  8882
  Gyro Pitch Minus:  0xDD47  = -8889
  Gyro Yaw Minus:    0x22BD  =  8893
  Gyro Roll Minus:   0xDD43  = -8893
  Gyro Speed Plus:   0x021C  =  540
  Gyro Speed Minus:  0x021C  =  540
  Accel X Plus:      0x1E7F  =  7807
  Accel X Minus:     0xDF2E  = -8402
  Accel Y Plus:      0x1F60  =  8032
  Accel Y Minus:     0xE04C  = -8116
  Accel Z Plus:      0x1D3A  =  7482
  Accel Z Minus:     0xDEC6  = -8506
```

### 3.3 Applying Calibration

#### 3.3.1 Gyroscope Calibration

The gyroscope calibration produces a value in "calibrated units" where 1 unit =
1/16 degree per second (based on the DS4Windows constant `GYRO_RES_IN_DEG_SEC = 16`).

```
// Compute combined speed factor
gyroSpeed2x = gyroSpeedPlus + gyroSpeedMinus

// For each axis (pitch, yaw, roll):
sensNumer = gyroSpeed2x * GYRO_RES_IN_DEG_SEC    // = gyroSpeed2x * 16
sensDenom = axisPlus - axisMinus

// Apply calibration to raw reading:
calibrated = (raw - bias) * (sensNumer / sensDenom)

// Convert to degrees per second:
degrees_per_sec = calibrated / GYRO_RES_IN_DEG_SEC  // = calibrated / 16.0
```

Step by step for the Pitch axis example:
```
gyroSpeed2x = 540 + 540 = 1080
sensNumer   = 1080 * 16 = 17280
sensDenom   = 8839 - (-8889) = 17728

calibrated_pitch = (raw_pitch - 1) * (17280.0 / 17728)
angular_velocity_dps = calibrated_pitch / 16.0
```

#### 3.3.2 Accelerometer Calibration

The accelerometer calibration produces a value in "calibrated units" where 1 unit =
1/8192 g (based on the DS4Windows constant `ACC_RES_PER_G = 8192`).

```
// For each axis:
accelRange = accelPlus - accelMinus
accelBias  = accelPlus - (accelRange / 2)

sensNumer = 2 * ACC_RES_PER_G    // = 2 * 8192 = 16384
sensDenom = accelRange

// Apply calibration to raw reading:
calibrated = (raw - accelBias) * (sensNumer / sensDenom)

// Convert to g-force:
accel_g = calibrated / ACC_RES_PER_G  // = calibrated / 8192.0

// Convert to m/s^2:
accel_ms2 = accel_g * 9.80665
```

Step by step for the X axis example:
```
accelRange = 7807 - (-8402) = 16209
accelBias  = 7807 - (16209 / 2) = 7807 - 8104 = -297

sensNumer  = 16384
sensDenom  = 16209

calibrated_x = (raw_x - (-297)) * (16384.0 / 16209)
accel_x_g = calibrated_x / 8192.0
```

#### 3.3.3 Calibration Validation

Before using calibration data, verify that no denominator is zero:

```
valid = (pitchPlus - pitchMinus) != 0 &&
        (yawPlus   - yawMinus)   != 0 &&
        (rollPlus  - rollMinus)  != 0 &&
        (accelXPlus - accelXMinus) != 0 &&
        (accelYPlus - accelYMinus) != 0 &&
        (accelZPlus - accelZMinus) != 0
```

If calibration is invalid (e.g., all zeros from a defective controller), skip
calibration and use raw values directly. A zero denominator will cause a
division-by-zero crash.

#### 3.3.4 DS4v1 Inverted Yaw Fix

Some early DualShock 4 v1 controllers (Product ID 0x05C4) have an inverted yaw
axis in their calibration data. The symptom is:

```
gyroYaw sensNumer > 0  AND  gyroYaw sensDenom < 0
(while pitch and roll both have sensDenom > 0)
```

The fix is to negate the yaw denominator:
```
if yawSensDenom < 0 && pitchSensDenom > 0 && rollSensDenom > 0:
    yawSensDenom = -yawSensDenom
```

### 3.4 Continuous Calibration (Runtime Drift Compensation)

Even after applying factory calibration, gyroscopes experience slow drift over
time due to temperature changes and bias instability. DS4Windows implements a
**continuous calibration** system inspired by JoyShockLibrary:

1. Collect gyroscope samples in rolling time windows (e.g., 3 windows of 5 seconds each)
2. While the controller is stationary (accelerometer magnitude near 1g), average
   the gyro readings to detect residual bias
3. Subtract the averaged offsets from subsequent readings

```
// Detect stationary state:
accelMagnitude = sqrt(accelX^2 + accelY^2 + accelZ^2)
isStationary = abs(accelMagnitude - 8192) < threshold  // ~1g in calibrated units

// If stationary, accumulate offset averages:
gyro_offset_x = weighted_average(gyro samples over recent windows)
gyro_offset_y = weighted_average(...)
gyro_offset_z = weighted_average(...)

// Apply:
corrected_gyroX = calibrated_gyroX - gyro_offset_x
corrected_gyroY = calibrated_gyroY - gyro_offset_y
corrected_gyroZ = calibrated_gyroZ - gyro_offset_z
```

---

## 4. Unit Conversion

### 4.1 Gyroscope: Raw to Degrees Per Second

**Without calibration** (using raw BMI055 sensitivity at +/-2000 deg/s range):

```
angular_velocity_dps = raw_value / 16.4
```

**With calibration** (recommended):

```
// After applying calibration (Section 3.3.1):
angular_velocity_dps = calibrated_value / GYRO_RES_IN_DEG_SEC
angular_velocity_dps = calibrated_value / 16.0
```

**To radians per second:**

```
angular_velocity_rps = angular_velocity_dps * (PI / 180.0)
```

### 4.2 Accelerometer: Raw to G-Force and m/s^2

**Without calibration** (using raw BMI055 sensitivity -- assuming +/-4g range):

```
accel_g = raw_value / 512.0    // At +/-4g: 512 LSB/g
```

**With calibration** (recommended):

```
// After applying calibration (Section 3.3.2):
accel_g = calibrated_value / ACC_RES_PER_G
accel_g = calibrated_value / 8192.0
```

**To m/s^2:**

```
accel_ms2 = accel_g * 9.80665
```

### 4.3 Timestamp: Raw to Microseconds

```
elapsed_us = delta_raw * 16 / 3    // 5.333... microseconds per tick
elapsed_s  = elapsed_us * 0.000001
```

At full report rate (~800 Hz), typical delta = 188 ticks = ~1002 us ~ 1.0 ms.

### 4.4 Summary of Constants

| Constant | Value | Unit | Usage |
|---|---|---|---|
| `GYRO_RES_IN_DEG_SEC` | 16 | LSB/(deg/s) | Post-calibration gyro resolution |
| `ACC_RES_PER_G` | 8192 | LSB/g | Post-calibration accel resolution |
| `BMI055_GYRO_SENS_2000` | 16.4 | LSB/(deg/s) | Raw BMI055 gyro sensitivity |
| `BMI055_ACCEL_SENS_4G` | 512 | LSB/g | Raw BMI055 accel sensitivity |
| `TIMESTAMP_TICK_US` | 5.333 | us/tick | `16/3` microseconds per tick |
| `GRAVITY_MS2` | 9.80665 | m/s^2 | Standard gravity |

---

## 5. Sensor Fusion

Sensor fusion combines gyroscope and accelerometer data to estimate the
controller's orientation in 3D space. The gyroscope provides fast, accurate
short-term rotation data but drifts over time. The accelerometer provides a
stable gravity reference but is noisy and affected by linear acceleration.

### 5.1 Complementary Filter

The simplest fusion approach. It high-pass filters the gyroscope data (trusting
it for fast changes) and low-pass filters the accelerometer data (trusting it
for long-term stability).

```
// Alpha = 0.98 is typical (98% gyro, 2% accel)
alpha = 0.98

// Estimate orientation from accelerometer alone:
accel_pitch = atan2(accelX, sqrt(accelY^2 + accelZ^2))
accel_roll  = atan2(accelY, sqrt(accelX^2 + accelZ^2))

// Integrate gyroscope:
gyro_pitch = previous_pitch + gyroPitch_dps * dt
gyro_roll  = previous_roll  + gyroRoll_dps  * dt
gyro_yaw   = previous_yaw   + gyroYaw_dps   * dt

// Fuse:
pitch = alpha * gyro_pitch + (1 - alpha) * accel_pitch
roll  = alpha * gyro_roll  + (1 - alpha) * accel_roll
yaw   = gyro_yaw  // No magnetometer correction available
```

**Pros:** Simple, low computational cost, easy to tune.
**Cons:** Yaw drifts (no magnetometer), single alpha for all dynamics.

### 5.2 Madgwick Filter

The Madgwick AHRS (Attitude and Heading Reference System) algorithm uses
gradient descent optimization to fuse sensor data into a quaternion
orientation estimate. It is computationally efficient and provides excellent
results for 6-axis IMUs.

#### 5.2.1 Algorithm Overview

```
Given:
  q = current quaternion estimate [w, x, y, z]
  g = gyroscope reading [gx, gy, gz] in rad/s
  a = accelerometer reading [ax, ay, az] (normalized)
  beta = filter gain (tuning parameter, typically 0.01 - 0.1)
  dt = time step in seconds

1. Compute quaternion rate of change from gyroscope:
   q_dot_gyro = 0.5 * q * [0, gx, gy, gz]

2. Compute objective function and Jacobian:
   // The accelerometer should measure only gravity in the earth frame
   // Rotate the expected gravity [0,0,0,1] by inverse of q to get
   // expected measurement, then compute error
   f = [2(q.x*q.z - q.w*q.y) - ax,
        2(q.w*q.x + q.y*q.z) - ay,
        2(0.5 - q.x^2 - q.y^2) - az]

3. Compute gradient:
   J = Jacobian of f with respect to q
   gradient = J^T * f
   gradient = normalize(gradient)

4. Fuse:
   q_dot = q_dot_gyro - beta * gradient

5. Integrate:
   q = q + q_dot * dt
   q = normalize(q)
```

#### 5.2.2 Tuning Parameter (beta)

- **Higher beta** (0.1): More accelerometer influence, less drift but more noise
- **Lower beta** (0.01): More gyroscope influence, smoother but more drift
- **Typical for game controllers:** 0.04 - 0.1
- **For slow movements:** 0.01 - 0.04

### 5.3 Quaternion Representation

Quaternions avoid gimbal lock and provide smooth interpolation. A quaternion
`q = [w, x, y, z]` represents a rotation where:

```
w = cos(angle/2)
x = axis.x * sin(angle/2)
y = axis.y * sin(angle/2)
z = axis.z * sin(angle/2)
```

**Quaternion multiplication:**
```
q1 * q2 = [w1*w2 - x1*x2 - y1*y2 - z1*z2,
           w1*x2 + x1*w2 + y1*z2 - z1*y2,
           w1*y2 - x1*z2 + y1*w2 + z1*x2,
           w1*z2 + x1*y2 - y1*x2 + z1*w2]
```

**Normalization:**
```
magnitude = sqrt(w^2 + x^2 + y^2 + z^2)
q_normalized = [w/mag, x/mag, y/mag, z/mag]
```

### 5.4 Euler Angles (Pitch, Yaw, Roll)

Converting quaternion to Euler angles (ZYX convention):

```
// Roll (X-axis rotation)
sinr_cosp = 2 * (q.w * q.x + q.y * q.z)
cosr_cosp = 1 - 2 * (q.x * q.x + q.y * q.y)
roll = atan2(sinr_cosp, cosr_cosp)

// Pitch (Y-axis rotation)
sinp = 2 * (q.w * q.y - q.z * q.x)
if abs(sinp) >= 1:
    pitch = copysign(PI/2, sinp)  // Clamp at +/-90 degrees
else:
    pitch = asin(sinp)

// Yaw (Z-axis rotation)
siny_cosp = 2 * (q.w * q.z + q.x * q.y)
cosy_cosp = 1 - 2 * (q.y * q.y + q.z * q.z)
yaw = atan2(siny_cosp, cosy_cosp)
```

### 5.5 Sensor Fusion Algorithm Comparison

```
+-------------------------------------------------------------------+
|                   Sensor Fusion Pipeline                          |
|                                                                   |
|  Raw Gyro -----> Calibrate ---+                                   |
|  (deg/s)         (bias/gain)  |                                   |
|                               v                                   |
|                         +----------+                              |
|                         |  Fusion  |-----> Quaternion              |
|                         | Algorithm|       [w, x, y, z]           |
|                         +----------+       |                      |
|                               ^            v                      |
|  Raw Accel ----> Calibrate ---+     Euler Angles                  |
|  (g)             (bias/gain)        [pitch, yaw, roll]            |
|                                                                   |
+-------------------------------------------------------------------+

Algorithm         | Complexity | Drift | Noise | CPU Cost | Best For
------------------|------------|-------|-------|----------|------------------
Complementary     | Low        | Med   | Low   | Minimal  | Simple tilt
Madgwick          | Medium     | Low   | Low   | Low      | General purpose
Mahony            | Medium     | Low   | Med   | Low      | Responsive motion
Extended Kalman   | High       | V.Low | V.Low | High     | Precision tracking
```

---

## 6. Motion Control Applications

### 6.1 Pointer / Cursor Control (Gyro Aim)

Maps the gyroscope angular velocity directly to cursor movement. This is the
most common use for gyro aiming in games.

```
// DS4Windows approach:
deltaX = gyroYawFull   // or gyroRollFull, user-selectable
deltaY = -gyroPitchFull

// Apply deadzone (default = 10 in calibrated units)
if abs(deltaX) > deadzone: deltaX -= sign(deltaX) * deadzone
else: deltaX = 0

if abs(deltaY) > deadzone: deltaY -= sign(deltaY) * deadzone
else: deltaY = 0

// Scale by sensitivity and elapsed time
sensitivity = 0.012  // coefficient, user-adjustable
offset = 0.2         // minimum movement threshold
timeScale = elapsed_seconds * 200.0  // base on 5ms reference

mouseX = sensitivity * deltaX * timeScale + offset * sign(deltaX)
mouseY = sensitivity * verticalScale * deltaY * timeScale + offset * sign(deltaY)
```

**Key parameters:**
- `sensitivity`: Overall speed multiplier (0.001 - 0.05 typical)
- `deadzone`: Ignore small movements (5 - 20 in calibrated units)
- `verticalScale`: Separate Y-axis sensitivity (0.5 - 1.5)
- `offset`: Minimum pixel movement to overcome sub-pixel threshold

### 6.2 Steering Wheel Emulation

Uses the roll axis (tilting controller left/right) to simulate a steering wheel.

```
// Get roll angle from sensor fusion (Section 5):
roll_degrees = roll * (180.0 / PI)

// Map to steering range (-1.0 to 1.0):
max_tilt = 45.0  // maximum tilt angle in degrees
steering = clamp(roll_degrees / max_tilt, -1.0, 1.0)

// Apply deadzone:
if abs(steering) < 0.05: steering = 0.0

// Optional: apply non-linear curve for precision around center:
steering = sign(steering) * pow(abs(steering), 1.5)
```

### 6.3 Tilt Controls

Uses accelerometer data to detect the direction of gravity relative to the
controller, providing absolute tilt angle.

```
// Direct tilt from accelerometer (no gyro needed):
tilt_x = atan2(accelX, sqrt(accelY*accelY + accelZ*accelZ)) * (180/PI)
tilt_y = atan2(accelY, sqrt(accelX*accelX + accelZ*accelZ)) * (180/PI)

// Map to game input (-1.0 to 1.0):
input_x = clamp(tilt_x / max_tilt, -1.0, 1.0)
input_y = clamp(tilt_y / max_tilt, -1.0, 1.0)
```

### 6.4 Motion Gestures: Shake Detection

Detect sudden acceleration changes to trigger shake events.

```
// Compute total acceleration magnitude:
accelMag = sqrt(accelX_g^2 + accelY_g^2 + accelZ_g^2)

// Shake threshold (deviation from 1g gravity):
shakeThreshold = 1.5  // in g-force

// Track acceleration history:
if abs(accelMag - 1.0) > shakeThreshold:
    shakeCount += 1
    lastShakeTime = now
else:
    if (now - lastShakeTime) > 0.3:  // 300ms cooldown
        shakeCount = 0

// Trigger shake event:
if shakeCount >= 3:  // At least 3 spikes in quick succession
    fireShakeEvent()
    shakeCount = 0
```

### 6.5 Flick Stick

An advanced aiming technique (popularized by JoyShockMapper) that uses the right
stick for yaw flicks and the gyro for fine aiming:

```
// When stick crosses threshold from center:
stickAngle = atan2(stickX, -stickY)
// Instantly rotate view to match stick angle

// While stick is held past threshold:
// Smooth rotation to track stick angle changes

// Gyro provides fine aiming on top of flick stick
```

---

## 7. Coordinate System

### 7.1 Controller Axes Diagram

```
                    +Y (Up)
                     ^
                     |
                     |
         +-----------+-----------+
        /           /|          /|
       /    [PS]   / |   [OPT]/  |
      /           /  |        /  |
     +-----------+   |       +   |
     | [L1]      |   +-------|---+---> +X (Right)
     | [L2]      |  /  [R1]  |  /
     |           | /   [R2]  | /
     |  [LSTK]  |/  [RSTK]  |/
     +-----------+-----------+
                /
               /
              v
            +Z (Toward Player / Forward)


  Gyroscope (Angular Velocity) -- Right-Hand Rule:
  ================================================

    +X rotation (Pitch): Tilting controller forward/backward
                         (top edge dips forward = positive)

    +Y rotation (Yaw):   Rotating controller left/right (flat)
                         (counterclockwise viewed from above = positive)

    +Z rotation (Roll):  Tilting controller sideways
                         (right side dips down = positive)


  Accelerometer (Linear Acceleration):
  =====================================

    +X: Acceleration to the right
    +Y: Acceleration upward (gravity reads as -1g when flat on table)
    +Z: Acceleration toward the player

    At rest (flat, face up):
      accelX ~= 0
      accelY ~= -8192 calibrated (~-1g, gravity pulling down)
      accelZ ~= 0
```

### 7.2 Right-Hand Rule

The DS4 IMU follows the **right-hand rule** for angular velocity:

```
Point your RIGHT THUMB along the positive axis direction:
  - Your fingers curl in the direction of POSITIVE rotation.

Example -- Pitch (+X axis):
  1. Point right thumb to the RIGHT (+X)
  2. Fingers curl from +Y toward +Z
  3. Positive pitch = top of controller tilts FORWARD (away from player)
```

### 7.3 DS4Windows Axis Conventions

DS4Windows applies sign inversions when populating the `SixAxis` structure.
Understanding these is critical for matching DS4Windows behavior:

```
// From DS4Sixaxis.cs populate():
gyroYaw      = -X / 256      // Inverted, scaled down
gyroPitch    =  Y / 256      // Direct, scaled down
gyroRoll     = -Z / 256      // Inverted, scaled down

gyroYawFull  = -X            // Full resolution, inverted
gyroPitchFull=  Y            // Full resolution, direct
gyroRollFull = -Z            // Full resolution, inverted

accelXFull   = -aX           // Inverted
accelYFull   = -aY           // Inverted
accelZFull   =  aZ           // Direct
```

These inversions map the controller's physical coordinate system to a
screen-oriented coordinate system where:
- Positive yaw = rotating view rightward
- Positive pitch = rotating view upward
- Positive accelX = tilting left (gravity pulls right)

### 7.4 ds4drv Axis Naming

In ds4drv (Python), the axes are named differently:

```python
# From ds4drv device.py parse_report():
# "Acceleration" (actually gyroscope readings):
motion_y = int16 at offset 13   # Gyro Pitch
motion_x = int16 at offset 15   # Gyro Yaw
motion_z = int16 at offset 17   # Gyro Roll

# "Orientation" (actually accelerometer readings):
orientation_roll  = -(int16 at offset 19)  # Accel X (negated)
orientation_yaw   = int16 at offset 21     # Accel Y
orientation_pitch = int16 at offset 23     # Accel Z
```

> **Warning:** The ds4drv naming convention reverses the typical gyro/accel
> terminology. What it calls "motion" is gyroscope data, and what it calls
> "orientation" is accelerometer data.

---

## 8. Code Examples

### 8.1 Parsing Raw IMU Data (Swift)

```swift
import Foundation

/// Raw IMU data parsed from a DS4 input report
struct DS4IMUData {
    /// Gyroscope angular velocity (raw signed 16-bit values)
    var gyroPitch: Int16  // X-axis rotation
    var gyroYaw: Int16    // Y-axis rotation
    var gyroRoll: Int16   // Z-axis rotation

    /// Accelerometer linear acceleration (raw signed 16-bit values)
    var accelX: Int16
    var accelY: Int16
    var accelZ: Int16

    /// Timestamp in 5.33us ticks
    var timestamp: UInt16
}

/// Parse IMU data from a USB input report (Report ID 0x01)
/// - Parameter report: Raw HID report bytes (64 bytes, index 0 = report ID)
/// - Returns: Parsed IMU data structure
///
/// Note: IOKit HID callbacks provide an `UnsafeMutablePointer<UInt8>` and a length.
/// Wrap it with `Data(bytes: pointer, count: length)` before passing to this parser.
func parseIMUData(from report: Data) -> DS4IMUData {
    // Timestamp: bytes 10-11 (uint16 LE)
    let timestamp = UInt16(report[10]) | (UInt16(report[11]) << 8)

    // Gyroscope: bytes 13-18 (three int16 LE values)
    let gyroPitch = Int16(bitPattern: UInt16(report[13]) | (UInt16(report[14]) << 8))
    let gyroYaw   = Int16(bitPattern: UInt16(report[15]) | (UInt16(report[16]) << 8))
    let gyroRoll  = Int16(bitPattern: UInt16(report[17]) | (UInt16(report[18]) << 8))

    // Accelerometer: bytes 19-24 (three int16 LE values)
    let accelX = Int16(bitPattern: UInt16(report[19]) | (UInt16(report[20]) << 8))
    let accelY = Int16(bitPattern: UInt16(report[21]) | (UInt16(report[22]) << 8))
    let accelZ = Int16(bitPattern: UInt16(report[23]) | (UInt16(report[24]) << 8))

    return DS4IMUData(
        gyroPitch: gyroPitch, gyroYaw: gyroYaw, gyroRoll: gyroRoll,
        accelX: accelX, accelY: accelY, accelZ: accelZ,
        timestamp: timestamp
    )
}

/// Parse IMU data from a Bluetooth extended report (Report ID 0x11)
/// - Parameter report: Raw HID report bytes (index 0 = report ID 0x11)
/// - Returns: Parsed IMU data structure
func parseIMUDataBluetooth(from report: Data) -> DS4IMUData {
    // BT extended report has +2 byte offset for all fields
    let btOffset = 2

    let timestamp = UInt16(report[10 + btOffset]) | (UInt16(report[11 + btOffset]) << 8)

    let gyroPitch = Int16(bitPattern: UInt16(report[13 + btOffset]) | (UInt16(report[14 + btOffset]) << 8))
    let gyroYaw   = Int16(bitPattern: UInt16(report[15 + btOffset]) | (UInt16(report[16 + btOffset]) << 8))
    let gyroRoll  = Int16(bitPattern: UInt16(report[17 + btOffset]) | (UInt16(report[18 + btOffset]) << 8))

    let accelX = Int16(bitPattern: UInt16(report[19 + btOffset]) | (UInt16(report[20 + btOffset]) << 8))
    let accelY = Int16(bitPattern: UInt16(report[21 + btOffset]) | (UInt16(report[22 + btOffset]) << 8))
    let accelZ = Int16(bitPattern: UInt16(report[23 + btOffset]) | (UInt16(report[24 + btOffset]) << 8))

    return DS4IMUData(
        gyroPitch: gyroPitch, gyroYaw: gyroYaw, gyroRoll: gyroRoll,
        accelX: accelX, accelY: accelY, accelZ: accelZ,
        timestamp: timestamp
    )
}
```

### 8.2 Applying Calibration (Swift)

```swift
import Foundation

/// Calibration data for a single sensor axis
struct AxisCalibration {
    var bias: Int32
    var sensNumer: Int32
    var sensDenom: Int32

    /// Apply calibration to a raw reading
    func calibrate(_ raw: Int16) -> Int32 {
        guard sensDenom != 0 else { return Int32(raw) }
        let adjusted = Int32(raw) - bias
        return Int32(Float(adjusted) * (Float(sensNumer) / Float(sensDenom)))
    }
}

/// Full 6-axis calibration data
struct DS4Calibration {
    // Gyroscope axes
    var gyroPitch = AxisCalibration(bias: 0, sensNumer: 1, sensDenom: 1)
    var gyroYaw   = AxisCalibration(bias: 0, sensNumer: 1, sensDenom: 1)
    var gyroRoll  = AxisCalibration(bias: 0, sensNumer: 1, sensDenom: 1)

    // Accelerometer axes
    var accelX = AxisCalibration(bias: 0, sensNumer: 1, sensDenom: 1)
    var accelY = AxisCalibration(bias: 0, sensNumer: 1, sensDenom: 1)
    var accelZ = AxisCalibration(bias: 0, sensNumer: 1, sensDenom: 1)

    var isValid: Bool = false

    static let gyroResInDegSec: Int32 = 16
    static let accResPerG: Int32 = 8192
}

/// Parse calibration from a feature report (0x02 USB or 0x05 BT)
/// - Parameters:
///   - report: Raw feature report bytes
///   - isUSB: Whether this is a USB connection (affects plus/minus ordering)
/// - Returns: Parsed calibration data
func parseCalibration(from report: Data, isUSB: Bool) -> DS4Calibration {
    var cal = DS4Calibration()

    // Helper: read int16 LE from report at given offset
    func readInt16(_ offset: Int) -> Int16 {
        return Int16(bitPattern: UInt16(report[offset]) | (UInt16(report[offset + 1]) << 8))
    }

    // Gyro bias: bytes 1-6
    let pitchBias = Int32(readInt16(1))
    let yawBias   = Int32(readInt16(3))
    let rollBias  = Int32(readInt16(5))

    cal.gyroPitch.bias = pitchBias
    cal.gyroYaw.bias   = yawBias
    cal.gyroRoll.bias  = rollBias

    // Gyro plus/minus reference values: bytes 7-18
    var pitchPlus, yawPlus, rollPlus: Int32
    var pitchMinus, yawMinus, rollMinus: Int32

    if isUSB {
        // USB alternate layout: interleaved plus/minus per axis
        pitchPlus  = Int32(readInt16(7))
        pitchMinus = Int32(readInt16(9))
        yawPlus    = Int32(readInt16(11))
        yawMinus   = Int32(readInt16(13))
        rollPlus   = Int32(readInt16(15))
        rollMinus  = Int32(readInt16(17))
    } else {
        // BT layout: all plus then all minus
        pitchPlus  = Int32(readInt16(7))
        yawPlus    = Int32(readInt16(9))
        rollPlus   = Int32(readInt16(11))
        pitchMinus = Int32(readInt16(13))
        yawMinus   = Int32(readInt16(15))
        rollMinus  = Int32(readInt16(17))
    }

    // Gyro speed references: bytes 19-22
    let gyroSpeedPlus  = Int32(readInt16(19))
    let gyroSpeedMinus = Int32(readInt16(21))
    let gyroSpeed2x = gyroSpeedPlus + gyroSpeedMinus

    // Compute gyro sensitivity factors
    cal.gyroPitch.sensNumer = gyroSpeed2x * DS4Calibration.gyroResInDegSec
    cal.gyroPitch.sensDenom = pitchPlus - pitchMinus

    cal.gyroYaw.sensNumer = gyroSpeed2x * DS4Calibration.gyroResInDegSec
    cal.gyroYaw.sensDenom = yawPlus - yawMinus

    cal.gyroRoll.sensNumer = gyroSpeed2x * DS4Calibration.gyroResInDegSec
    cal.gyroRoll.sensDenom = rollPlus - rollMinus

    // Accelerometer references: bytes 23-34
    let accelXPlus  = Int32(readInt16(23))
    let accelXMinus = Int32(readInt16(25))
    let accelYPlus  = Int32(readInt16(27))
    let accelYMinus = Int32(readInt16(29))
    let accelZPlus  = Int32(readInt16(31))
    let accelZMinus = Int32(readInt16(33))

    let twoG = 2 * DS4Calibration.accResPerG  // 16384

    var accelRange = accelXPlus - accelXMinus
    cal.accelX.bias = accelXPlus - accelRange / 2
    cal.accelX.sensNumer = twoG
    cal.accelX.sensDenom = accelRange

    accelRange = accelYPlus - accelYMinus
    cal.accelY.bias = accelYPlus - accelRange / 2
    cal.accelY.sensNumer = twoG
    cal.accelY.sensDenom = accelRange

    accelRange = accelZPlus - accelZMinus
    cal.accelZ.bias = accelZPlus - accelRange / 2
    cal.accelZ.sensNumer = twoG
    cal.accelZ.sensDenom = accelRange

    // Validate: no zero denominators
    cal.isValid = cal.gyroPitch.sensDenom != 0
        && cal.gyroYaw.sensDenom != 0
        && cal.gyroRoll.sensDenom != 0
        && cal.accelX.sensDenom != 0
        && cal.accelY.sensDenom != 0
        && cal.accelZ.sensDenom != 0

    return cal
}

/// Fix inverted yaw axis on DS4 v1 controllers (PID 0x05C4)
func fixInvertedYaw(_ cal: inout DS4Calibration) -> Bool {
    if cal.gyroYaw.sensNumer > 0 && cal.gyroYaw.sensDenom < 0
        && cal.gyroPitch.sensDenom > 0 && cal.gyroRoll.sensDenom > 0 {
        cal.gyroYaw.sensDenom *= -1
        return true
    }
    return false
}

/// Calibrated 6-axis data with physical units
struct CalibratedIMU {
    // Gyroscope in degrees per second
    var pitchDPS: Double
    var yawDPS: Double
    var rollDPS: Double

    // Accelerometer in g-force
    var accelXG: Double
    var accelYG: Double
    var accelZG: Double

    // Elapsed time in seconds
    var elapsedSeconds: Double
}

/// Apply calibration to raw IMU data
func calibrateIMU(_ raw: DS4IMUData, calibration: DS4Calibration) -> CalibratedIMU {
    let gyroRes = Double(DS4Calibration.gyroResInDegSec)
    let accelRes = Double(DS4Calibration.accResPerG)

    let calPitch = calibration.gyroPitch.calibrate(raw.gyroPitch)
    let calYaw   = calibration.gyroYaw.calibrate(raw.gyroYaw)
    let calRoll  = calibration.gyroRoll.calibrate(raw.gyroRoll)

    let calAX = calibration.accelX.calibrate(raw.accelX)
    let calAY = calibration.accelY.calibrate(raw.accelY)
    let calAZ = calibration.accelZ.calibrate(raw.accelZ)

    return CalibratedIMU(
        pitchDPS: Double(calPitch) / gyroRes,
        yawDPS:   Double(calYaw)   / gyroRes,
        rollDPS:  Double(calRoll)  / gyroRes,
        accelXG:  Double(calAX)    / accelRes,
        accelYG:  Double(calAY)    / accelRes,
        accelZG:  Double(calAZ)    / accelRes,
        elapsedSeconds: 0.0  // Set by timestamp delta computation
    )
}
```

### 8.3 Complementary Filter Sensor Fusion (Swift)

```swift
import Foundation

/// Simple complementary filter for orientation estimation
class ComplementaryFilter {
    /// Orientation in degrees
    var pitch: Double = 0.0
    var roll: Double = 0.0
    var yaw: Double = 0.0

    /// Filter coefficient (0.0 - 1.0)
    /// Higher = more trust in gyroscope (less noise, more drift)
    /// Lower = more trust in accelerometer (more noise, less drift)
    var alpha: Double = 0.98

    /// Update orientation estimate with new sensor data
    /// - Parameters:
    ///   - imu: Calibrated IMU data with physical units
    ///   - dt: Time delta in seconds since last update
    func update(imu: CalibratedIMU, dt: Double) {
        guard dt > 0 && dt < 1.0 else { return }  // Sanity check

        // --- Gyroscope integration ---
        let gyroPitch = pitch + imu.pitchDPS * dt
        let gyroRoll  = roll  + imu.rollDPS  * dt
        let gyroYaw   = yaw   + imu.yawDPS   * dt

        // --- Accelerometer tilt estimate ---
        // Only valid when controller is not being linearly accelerated
        let accelPitch = atan2(imu.accelXG,
            sqrt(imu.accelYG * imu.accelYG + imu.accelZG * imu.accelZG))
            * (180.0 / .pi)

        let accelRoll = atan2(imu.accelYG,
            sqrt(imu.accelXG * imu.accelXG + imu.accelZG * imu.accelZG))
            * (180.0 / .pi)

        // --- Fuse ---
        pitch = alpha * gyroPitch + (1.0 - alpha) * accelPitch
        roll  = alpha * gyroRoll  + (1.0 - alpha) * accelRoll
        yaw   = gyroYaw  // No absolute yaw reference without magnetometer
    }

    /// Reset orientation to zero
    func reset() {
        pitch = 0.0
        roll = 0.0
        yaw = 0.0
    }
}
```

### 8.4 Madgwick Filter (Swift)

```swift
import Foundation

/// Madgwick AHRS filter for 6-axis IMU sensor fusion
class MadgwickFilter {
    /// Quaternion orientation estimate [w, x, y, z]
    var q0: Double = 1.0  // w
    var q1: Double = 0.0  // x
    var q2: Double = 0.0  // y
    var q3: Double = 0.0  // z

    /// Filter gain (beta). Controls accelerometer influence.
    /// Typical: 0.01 (low influence) to 0.1 (high influence)
    var beta: Double = 0.04

    /// Update with gyroscope and accelerometer data
    /// - Parameters:
    ///   - gx, gy, gz: Gyroscope in RADIANS per second
    ///   - ax, ay, az: Accelerometer (any consistent unit, will be normalized)
    ///   - dt: Time delta in seconds
    func update(gx: Double, gy: Double, gz: Double,
                ax: Double, ay: Double, az: Double,
                dt: Double) {
        var q0 = self.q0, q1 = self.q1, q2 = self.q2, q3 = self.q3

        // Rate of change of quaternion from gyroscope
        var qDot1 = 0.5 * (-q1 * gx - q2 * gy - q3 * gz)
        var qDot2 = 0.5 * ( q0 * gx + q2 * gz - q3 * gy)
        var qDot3 = 0.5 * ( q0 * gy - q1 * gz + q3 * gx)
        var qDot4 = 0.5 * ( q0 * gz + q1 * gy - q2 * gx)

        // Compute feedback only if accelerometer measurement valid
        // (avoids NaN in normalization)
        let aMag = ax * ax + ay * ay + az * az
        if aMag > 0.0 {
            // Normalize accelerometer measurement
            let recipNorm = 1.0 / sqrt(aMag)
            let ax = ax * recipNorm
            let ay = ay * recipNorm
            let az = az * recipNorm

            // Auxiliary variables to avoid repeated arithmetic
            let _2q0 = 2.0 * q0
            let _2q1 = 2.0 * q1
            let _2q2 = 2.0 * q2
            let _2q3 = 2.0 * q3
            let _4q0 = 4.0 * q0
            let _4q1 = 4.0 * q1
            let _4q2 = 4.0 * q2
            let _8q1 = 8.0 * q1
            let _8q2 = 8.0 * q2
            let q0q0 = q0 * q0
            let q1q1 = q1 * q1
            let q2q2 = q2 * q2
            let q3q3 = q3 * q3

            // Gradient descent algorithm corrective step
            var s0 = _4q0 * q2q2 + _2q2 * ax + _4q0 * q1q1 - _2q1 * ay
            var s1 = _4q1 * q3q3 - _2q3 * ax + 4.0 * q0q0 * q1 - _2q0 * ay - _4q1 + _8q1 * q1q1 + _8q1 * q2q2 + _4q1 * az
            var s2 = 4.0 * q0q0 * q2 + _2q0 * ax + _4q2 * q3q3 - _2q3 * ay - _4q2 + _8q2 * q1q1 + _8q2 * q2q2 + _4q2 * az
            var s3 = 4.0 * q1q1 * q3 - _2q1 * ax + 4.0 * q2q2 * q3 - _2q2 * ay

            // Normalize step magnitude
            let sNorm = 1.0 / sqrt(s0 * s0 + s1 * s1 + s2 * s2 + s3 * s3)
            s0 *= sNorm
            s1 *= sNorm
            s2 *= sNorm
            s3 *= sNorm

            // Apply feedback step
            qDot1 -= beta * s0
            qDot2 -= beta * s1
            qDot3 -= beta * s2
            qDot4 -= beta * s3
        }

        // Integrate rate of change of quaternion
        q0 += qDot1 * dt
        q1 += qDot2 * dt
        q2 += qDot3 * dt
        q3 += qDot4 * dt

        // Normalize quaternion
        let norm = 1.0 / sqrt(q0 * q0 + q1 * q1 + q2 * q2 + q3 * q3)
        self.q0 = q0 * norm
        self.q1 = q1 * norm
        self.q2 = q2 * norm
        self.q3 = q3 * norm
    }

    /// Get Euler angles in degrees
    var eulerAngles: (pitch: Double, yaw: Double, roll: Double) {
        // Roll (X-axis rotation)
        let sinr_cosp = 2.0 * (q0 * q1 + q2 * q3)
        let cosr_cosp = 1.0 - 2.0 * (q1 * q1 + q2 * q2)
        let roll = atan2(sinr_cosp, cosr_cosp) * (180.0 / .pi)

        // Pitch (Y-axis rotation)
        let sinp = 2.0 * (q0 * q2 - q3 * q1)
        let pitch: Double
        if abs(sinp) >= 1.0 {
            pitch = copysign(90.0, sinp)
        } else {
            pitch = asin(sinp) * (180.0 / .pi)
        }

        // Yaw (Z-axis rotation)
        let siny_cosp = 2.0 * (q0 * q3 + q1 * q2)
        let cosy_cosp = 1.0 - 2.0 * (q2 * q2 + q3 * q3)
        let yaw = atan2(siny_cosp, cosy_cosp) * (180.0 / .pi)

        return (pitch: pitch, yaw: yaw, roll: roll)
    }

    /// Reset to identity quaternion
    func reset() {
        q0 = 1.0; q1 = 0.0; q2 = 0.0; q3 = 0.0
    }
}

// Usage with DS4 calibrated data:
//
// let madgwick = MadgwickFilter()
// madgwick.beta = 0.04
//
// let degToRad = Double.pi / 180.0
// madgwick.update(
//     gx: imu.pitchDPS * degToRad,
//     gy: imu.yawDPS   * degToRad,
//     gz: imu.rollDPS  * degToRad,
//     ax: imu.accelXG,
//     ay: imu.accelYG,
//     az: imu.accelZG,
//     dt: elapsedSeconds
// )
// let angles = madgwick.eulerAngles
```

### 8.5 Motion-to-Cursor Mapping (Swift)

```swift
import Foundation

/// Maps DS4 gyroscope data to mouse/cursor movement
class GyroMouseMapper {
    // Configuration
    var sensitivity: Double = 0.012
    var verticalScale: Double = 1.0
    var deadzone: Int32 = 10
    var offset: Double = 0.2
    var useYawForHorizontal: Bool = true  // false = use roll instead

    // State for sub-pixel remainders
    private var hRemainder: Double = 0.0
    private var vRemainder: Double = 0.0

    /// Compute mouse movement from calibrated IMU data
    /// - Parameters:
    ///   - imu: Calibrated IMU data (in DS4Windows internal units)
    ///   - gyroYawFull: Full-resolution calibrated yaw value
    ///   - gyroPitchFull: Full-resolution calibrated pitch value
    ///   - gyroRollFull: Full-resolution calibrated roll value
    ///   - elapsed: Elapsed time in seconds
    /// - Returns: Tuple of (deltaX, deltaY) in pixels
    func computeMouseDelta(gyroYawFull: Int32, gyroPitchFull: Int32,
                           gyroRollFull: Int32, elapsed: Double) -> (dx: Double, dy: Double) {
        // Select horizontal axis
        var deltaX = useYawForHorizontal ? -gyroYawFull : -gyroRollFull
        var deltaY = gyroPitchFull

        let timeScale = elapsed * 200.0  // Normalize to 5ms reference

        // Apply deadzone with directional awareness
        let signX = deltaX > 0 ? Int32(1) : (deltaX < 0 ? Int32(-1) : Int32(0))
        let signY = deltaY > 0 ? Int32(1) : (deltaY < 0 ? Int32(-1) : Int32(0))

        if abs(deltaX) > deadzone {
            deltaX -= signX * deadzone
        } else {
            deltaX = 0
        }

        if abs(deltaY) > deadzone {
            deltaY -= signY * deadzone
        } else {
            deltaY = 0
        }

        // Direction change resets remainder
        if deltaX == 0 || (hRemainder > 0) != (deltaX > 0) { hRemainder = 0.0 }
        if deltaY == 0 || (vRemainder > 0) != (deltaY > 0) { vRemainder = 0.0 }

        // Compute motion with sensitivity and minimum offset
        let xMotion: Double
        if deltaX != 0 {
            xMotion = sensitivity * Double(deltaX) * timeScale
                + offset * Double(signX)
        } else {
            xMotion = 0.0
        }

        let yMotion: Double
        if deltaY != 0 {
            yMotion = (sensitivity * verticalScale) * Double(deltaY) * timeScale
                + offset * Double(signY)
        } else {
            yMotion = 0.0
        }

        return (dx: xMotion, dy: yMotion)
    }
}
```

### 8.6 Shake Detection (Swift)

```swift
import Foundation

/// Detects shake gestures from accelerometer data
class ShakeDetector {
    /// Minimum g-force deviation from 1g to count as a shake impulse
    var shakeThreshold: Double = 1.5

    /// Minimum number of impulses to trigger a shake event
    var requiredImpulses: Int = 3

    /// Maximum time between impulses (seconds)
    var impulseTimeout: TimeInterval = 0.4

    /// Callback when shake is detected
    var onShake: (() -> Void)?

    // Internal state
    private var impulseCount: Int = 0
    private var lastImpulseTime: Date = .distantPast
    private var inImpulse: Bool = false

    /// Feed accelerometer data to the shake detector
    /// - Parameters:
    ///   - accelXG: X acceleration in g
    ///   - accelYG: Y acceleration in g
    ///   - accelZG: Z acceleration in g
    func update(accelXG: Double, accelYG: Double, accelZG: Double) {
        let magnitude = sqrt(accelXG * accelXG + accelYG * accelYG + accelZG * accelZG)
        let deviation = abs(magnitude - 1.0)  // Deviation from resting 1g
        let now = Date()

        // Check if impulse has timed out
        if now.timeIntervalSince(lastImpulseTime) > impulseTimeout {
            impulseCount = 0
            inImpulse = false
        }

        if deviation > shakeThreshold {
            if !inImpulse {
                // New impulse detected (rising edge)
                inImpulse = true
                impulseCount += 1
                lastImpulseTime = now

                if impulseCount >= requiredImpulses {
                    onShake?()
                    impulseCount = 0
                }
            }
        } else {
            inImpulse = false  // Reset for next impulse detection
        }
    }

    /// Reset detector state
    func reset() {
        impulseCount = 0
        lastImpulseTime = .distantPast
        inImpulse = false
    }
}
```

### 8.7 Complete Integration Example (Swift)

```swift
import Foundation
import IOKit.hid

/// Complete DS4 IMU processing pipeline
class DS4MotionProcessor {
    // Calibration
    private var calibration = DS4Calibration()

    // Sensor fusion
    private let madgwick = MadgwickFilter()
    private let complementary = ComplementaryFilter()

    // Motion mapping
    private let gyroMouse = GyroMouseMapper()
    private let shakeDetector = ShakeDetector()

    // Timestamp tracking
    private var previousTimestamp: UInt16 = 0
    private var timestampInitialized = false

    init() {
        madgwick.beta = 0.04
        complementary.alpha = 0.98
    }

    /// Load calibration from feature report data
    func loadCalibration(reportData: Data, isUSB: Bool, isDS4v1: Bool) {
        calibration = parseCalibration(from: reportData, isUSB: isUSB)

        if isDS4v1 {
            let fixed = fixInvertedYaw(&calibration)
            if fixed {
                print("Fixed inverted yaw axis on DS4 v1")
            }
        }

        if !calibration.isValid {
            print("WARNING: Calibration data is invalid (zero denominators)")
        }
    }

    /// Process a single input report
    /// - Parameter report: Raw USB input report bytes
    func processReport(_ report: Data) {
        // 1. Parse raw IMU data
        let raw = parseIMUData(from: report)

        // 2. Compute elapsed time from timestamp
        let dt = computeElapsedTime(currentTimestamp: raw.timestamp)
        guard dt > 0 && dt < 0.1 else { return }  // Skip bad timestamps

        // 3. Apply calibration
        var imu = calibrateIMU(raw, calibration: calibration)
        imu.elapsedSeconds = dt

        // 4. Update sensor fusion
        let degToRad = Double.pi / 180.0
        madgwick.update(
            gx: imu.pitchDPS * degToRad,
            gy: imu.yawDPS * degToRad,
            gz: imu.rollDPS * degToRad,
            ax: imu.accelXG,
            ay: imu.accelYG,
            az: imu.accelZG,
            dt: dt
        )

        complementary.update(imu: imu, dt: dt)

        // 5. Process motion applications
        let calPitch = calibration.gyroPitch.calibrate(raw.gyroPitch)
        let calYaw   = calibration.gyroYaw.calibrate(raw.gyroYaw)
        let calRoll  = calibration.gyroRoll.calibrate(raw.gyroRoll)

        let mouseDelta = gyroMouse.computeMouseDelta(
            gyroYawFull: -calYaw,      // Invert for screen coordinates
            gyroPitchFull: calPitch,
            gyroRollFull: -calRoll,     // Invert for screen coordinates
            elapsed: dt
        )

        // 6. Shake detection
        shakeDetector.update(
            accelXG: imu.accelXG,
            accelYG: imu.accelYG,
            accelZG: imu.accelZG
        )

        // 7. Use the results
        let euler = madgwick.eulerAngles
        // euler.pitch, euler.yaw, euler.roll are now available
        // mouseDelta.dx, mouseDelta.dy are cursor movement amounts
    }

    /// Compute elapsed time from DS4 timestamps
    private func computeElapsedTime(currentTimestamp: UInt16) -> Double {
        if !timestampInitialized {
            timestampInitialized = true
            previousTimestamp = currentTimestamp
            return 0.00125  // Default ~1.25ms for first report
        }

        let delta: UInt32
        if previousTimestamp > currentTimestamp {
            // Timestamp wrapped around
            delta = UInt32(UInt16.max) - UInt32(previousTimestamp) + UInt32(currentTimestamp) + 1
        } else {
            delta = UInt32(currentTimestamp) - UInt32(previousTimestamp)
        }

        previousTimestamp = currentTimestamp

        // Convert from 5.33us ticks to seconds: ticks * 16/3 = microseconds
        let microseconds = delta * 16 / 3
        return Double(microseconds) * 0.000001
    }
}
```

---

## References

### Documentation Sources
- [Sony DualShock 4 - Game Controller Collective Wiki](https://controllers.fandom.com/wiki/Sony_DualShock_4)
- [Sony DualShock 4 Data Structures - Game Controller Collective Wiki](https://controllers.fandom.com/wiki/Sony_DualShock_4/Data_Structures)
- [DS4-USB - PS4 Developer Wiki](https://www.psdevwiki.com/ps4/DS4-USB)
- [DS4 Reverse Engineering Blog Series](https://blog.the.al/2023/01/01/ds4-reverse-engineering.html)
- [dsremap Reverse Engineering Documentation](https://dsremap.readthedocs.io/en/latest/reverse.html)

### Hardware Datasheets
- [BMI055 Datasheet (Bosch Sensortec)](https://www.mouser.com/datasheet/2/783/BST-BMI055-DS000-08-786482.pdf)
- [BMI055 Overview - Allicdata](https://www.allicdata.com/products/bmi055/2725038.html)
- [DS4 vs DS3 IMU Sensor Analysis](https://forum.beyond3d.com/threads/inertial-sensors-dualshock-4-vs-sixaxis-ds3-accelerometer-gyroscope-chips.56000/)

### Reference Implementations
- [DS4Windows](https://github.com/Ryochan7/DS4Windows) -- DS4Sixaxis.cs, DS4Device.cs, MouseCursor.cs
- [ds4drv (chrippa)](https://github.com/chrippa/ds4drv) -- device.py
- [JoyShockLibrary](https://github.com/JibbSmart/JoyShockLibrary) -- Multi-controller input library
- [GamepadMotionHelpers](https://github.com/JibbSmart/GamepadMotionHelpers) -- Sensor fusion helpers
- [Madgwick AHRS Algorithm](https://x-io.co.uk/open-source-imu-and-ahrs-algorithms/)
