# 09 - Audio Streaming Feature

## Related Documents

- **04-USB-Protocol.md** -- USB output report 0x05 volume fields (effective range for headphone/speaker volume is 0x00-0x4F, mic is 0x00-0x40)
- **05-Bluetooth-Protocol.md** -- BT output report 0x11 structure, CRC-32 computation, and audio report IDs (0x14, 0x17, 0x18, 0x19)
- **06-Light-Bar-Feature.md** -- Shares the same output reports (0x05 / 0x11) for LED and rumble fields

---

## Table of Contents

1. [Overview](#1-overview)
2. [Audio Hardware](#2-audio-hardware)
3. [USB vs Bluetooth Audio](#3-usb-vs-bluetooth-audio)
4. [Bluetooth Audio Interface](#4-bluetooth-audio-interface)
5. [Speaker Audio Output](#5-speaker-audio-output)
6. [Headphone Jack Audio](#6-headphone-jack-audio)
7. [Microphone Input](#7-microphone-input)
8. [Output Report Audio Fields](#8-output-report-audio-fields)
9. [Input Report Audio Detection](#9-input-report-audio-detection)
10. [SBC Audio Codec](#10-sbc-audio-codec)
11. [Bluetooth Audio Packet Format](#11-bluetooth-audio-packet-format)
12. [Audio Streaming Implementation for macOS](#12-audio-streaming-implementation-for-macos)
13. [Code Examples](#13-code-examples)
14. [References](#14-references)

---

## 1. Overview

The DualShock 4 (DS4) controller contains a built-in mono speaker, a 3.5mm TRRS headphone/microphone jack, and an internal audio codec. Audio streaming to and from the controller is handled **exclusively over Bluetooth** -- the DS4 does not carry audio data over its USB connection.

Audio data is transmitted as SBC-encoded (Low Complexity Subband Codec) frames embedded within Bluetooth HID output reports. The controller supports multiple audio targets: the internal speaker, a connected headset (via the 3.5mm jack), and microphone input from a connected headset.

**Critical Limitation:** Audio does not carry through USB on the DualShock 4. When connected via USB, the controller functions only as a HID gamepad with interrupt endpoints. All audio functionality requires a Bluetooth connection.

---

## 2. Audio Hardware

### 2.1 Internal Speaker

| Property | Value |
|---|---|
| Type | Mono speaker |
| Location | Front-center of controller body |
| Connection | Raised contact connections to main PCB |
| Audio Codec | Wolfson Microelectronics WM18016 (or similar) |
| Interface | SPI activity observed, I2C pull-up resistors present |
| Max Sample Rate | 32 kHz (2 players), 16 kHz (3+ players) |

The speaker is a small mono driver designed for haptic feedback sounds, notification tones, and game audio effects. It is not removable and connects to the main PCB via spring-loaded contact pads.

### 2.2 Audio Codec/DAC

The controller contains a chip marked "WM18016" located near audio-related components on the PCB. This is believed to be a Wolfson Microelectronics audio codec that handles:

- SBC decoding for speaker/headphone output
- SBC encoding for microphone input
- DAC conversion for speaker and headphone output
- ADC conversion for microphone input
- Volume control for all audio channels

The codec communicates with the main MCU (Spansion MB9BF002, ARM Cortex-M3) via SPI, with I2C pull-up resistors observed on nearby traces.

### 2.3 3.5mm Headphone/Microphone Jack

| Property | Value |
|---|---|
| Connector | 3.5mm TRRS (Tip-Ring-Ring-Sleeve) |
| Standard | CTIA/AHJ wiring (Tip=Left, Ring1=Right, Ring2=Ground, Sleeve=Mic) |
| Headphone Output | Stereo (Left + Right channels) |
| Microphone Input | Mono |
| Detection | Hardware detection with status bits in input report |

The TRRS jack supports:
- **Headphones only** (TRS plug): Stereo audio output, no microphone
- **Headset** (TRRS plug): Stereo audio output + mono microphone input
- **No device**: Audio routes to internal speaker

### 2.4 Main MCU

| Property | Value |
|---|---|
| Chip | Spansion MB9BF002 |
| Architecture | ARM Cortex-M3, BGA package |
| Bluetooth Module | Qualcomm Atheros AR3002 |
| BT UART Baud Rate | 3 Mbit/s (8N1) |

---

## 3. USB vs Bluetooth Audio

### 3.1 USB Mode (No Audio)

When connected via USB, the DualShock 4 presents itself as a standard HID device with:

| Property | Value |
|---|---|
| Interface Class | 0x03 (HID) |
| Endpoints | 2 interrupt endpoints (IN 0x84 + OUT 0x03) |
| Max Packet Size | 64 bytes |
| Report Interval | 5 ms |
| Audio Support | **None** |

There are **no** USB Audio Class (UAC) interface descriptors, no isochronous endpoints, and no audio streaming capability over USB. The USB HID descriptor defines only:

- **Report ID 0x01** (Input): 64 bytes -- gamepad state
- **Report ID 0x05** (Output): 32 bytes -- rumble, LED, volume control

While USB output report 0x05 does contain volume control fields (bytes 18-21), these only configure volumes for audio that arrives over Bluetooth. They do not enable USB audio streaming.

### 3.2 Bluetooth Mode (Full Audio)

Over Bluetooth, the DS4 supports full bidirectional audio through dedicated HID output report types:

| Report ID | Size (bytes) | Purpose | Audio Frames |
|---|---|---|---|
| 0x11 | 78 | Controller state + volume control | 0 (control only) |
| 0x14 | 270 | Audio data (small packet) | 2 |
| 0x15 | ~334 | Combined control + audio | Variable |
| 0x17 | 462 | Audio data (medium packet) | 4 |
| 0x18 | ~478 | Audio data (large packet) | 6 |
| 0x19 | ~551 | Combined control + audio (largest) | Variable |

All Bluetooth reports require a CRC-32 checksum appended as the final 4 bytes.

---

## 4. Bluetooth Audio Interface

### 4.1 HID Transport Layer

Audio data is carried within Bluetooth HID output reports, not through standard Bluetooth A2DP or HFP profiles. This means:

- Audio is part of the HID channel, sharing bandwidth with controller input/output
- No standard Bluetooth audio pairing is required beyond the HID connection
- The host application must handle SBC encoding/decoding in software
- Audio quality and latency are constrained by the HID report scheduling

### 4.2 Report Structure Overview

Each Bluetooth audio packet follows this general structure:

```
[Report ID] [Config Bytes] [Frame Counter] [Audio Target] [SBC Data...] [CRC-32]
```

The report ID determines the packet size and how many SBC frames can be carried. The CRC-32 is mandatory -- the controller silently ignores packets without a valid checksum.

### 4.3 CRC-32 Computation

The CRC-32 used by the DS4 is a standard CRC-32 with polynomial `0xEDB88320` (reflected form of `0x04C11DB7`). The computation must include a virtual `0xA2` byte prepended to the report data:

```
CRC seed: ~0xEADA2D49 (which equals CRC32 of the byte 0xA2)
Polynomial: 0xEDB88320 (reflected)
Input: report bytes [0..size-5] (everything except the final 4 CRC bytes)
Output: 4-byte little-endian CRC appended at [size-4..size-1]
```

The `0xA2` byte represents the Bluetooth HID transaction header (DATA | OUTPUT = 0xA2) and must be included in the CRC calculation even though it is not present in the HID report payload sent through the OS HID API.

**CRC-32 Implementation (C):**

```c
uint32_t ds4_compute_crc32(const uint8_t *data, int offset, int length) {
    // Seed incorporates the 0xA2 BT header byte.
    // ~0xEADA2D49u == CRC32(0xA2), so pre-seeding with this value is
    // equivalent to the "prepend a 0xA2 byte and compute from scratch" approach.
    uint32_t crc = ~0xEADA2D49u;
    for (int i = offset; i < offset + length; i++) {
        crc ^= data[i];
        for (int b = 0; b < 8; b++) {
            crc = (crc & 1) ? (crc >> 1) ^ 0xEDB88320u : crc >> 1;
        }
    }
    return ~crc;
}
```

Alternatively, compute the CRC from scratch with the 0xA2 header:

```c
uint32_t ds4_compute_crc32_with_header(const uint8_t *report, int report_len) {
    uint8_t bt_header = 0xA2;
    uint32_t crc = CRC32_SEED; // 0xFFFFFFFF

    // Include the BT header byte
    crc = crc32_update(crc, &bt_header, 1);

    // Include report data (excluding final 4 CRC bytes)
    crc = crc32_update(crc, report, report_len - 4);

    return crc32_finalize(crc);
}
```

---

## 5. Speaker Audio Output

### 5.1 Audio Format

The DS4 speaker accepts SBC-encoded audio with the following parameters:

| Parameter | Value |
|---|---|
| Codec | SBC (Low Complexity Subband Codec) |
| Sample Rate | 32,000 Hz (32 kHz) |
| Channels | 2 (Joint Stereo) |
| Sub-bands | 8 |
| Block Count | 16 |
| Bitpool | 48 (configurable, max ~53 for stereo) |
| Allocation Mode | SNR (Signal-to-Noise Ratio) |
| Endianness | Little-Endian |
| Bitrate | ~345 kbps (with bitpool 48) |

**Note:** The bitpool value must not exceed the SBC specification limit, which is 32 * subbands for stereo/joint-stereo modes (32 * 8 = 256 theoretical max, but practical max is much lower). A bitpool of 48 with the above settings yields an SBC frame size of approximately 109 bytes.

When 3 or more controllers are connected to a PS4, the sample rate drops to 16 kHz to conserve Bluetooth bandwidth. For a PC host with a single controller, 32 kHz is used.

### 5.2 Audio Target Identifier

The audio target byte in the packet header controls routing:

| Value | Target | Description |
|---|---|---|
| `0x02` | Speaker | Routes audio to the internal mono speaker |
| `0x24` | Headset | Routes audio to the 3.5mm headphone jack (stereo) |
| `0x03` | Microphone | Used for microphone data direction |

### 5.3 Speaker Volume Control

Speaker volume is controlled via output report 0x11 (Bluetooth) or 0x05 (USB):

| Field | Range | Description |
|---|---|---|
| VolumeSpeaker | 0x00 - 0x4F | Internal speaker volume (0 = mute, 79 = max) |

The volume update must be explicitly enabled by setting `EnableVolumeSpeakerUpdate` (bit 7 of the enable flags byte) to 1.

---

## 6. Headphone Jack Audio

### 6.1 Headphone Detection

The controller detects whether headphones or a headset are plugged into the 3.5mm jack. This status is reported in the input report:

| Field | Bit Position (Input Byte 29/30) | Description |
|---|---|---|
| PluggedHeadphones | Bit 5 of status byte | `1` = headphones detected |
| PluggedMic | Bit 6 of status byte | `1` = microphone detected |

**Detection Logic:**

| PluggedHeadphones | PluggedMic | Device |
|---|---|---|
| 0 | 0 | Nothing plugged in (use speaker) |
| 1 | 0 | Headphones only (TRS plug) |
| 1 | 1 | Headset with microphone (TRRS plug) |
| 0 | 1 | Microphone only (unusual) |

In the ds4drv Python implementation, byte 30 of the USB input report contains these flags:

```python
# Byte 30 of USB input report (byte index from report start, excluding report ID)
plug_usb   = (buf[30] & 0x10) != 0  # bit 4
plug_audio = (buf[30] & 0x20) != 0  # bit 5 (headphones)
plug_mic   = (buf[30] & 0x40) != 0  # bit 6 (microphone)
```

### 6.2 Audio Routing

When headphones or a headset are detected, the host application should switch the audio target byte from `0x02` (speaker) to `0x24` (headset) in the audio output packets. The DS4AudioStreamer reference implements this as a toggle:

```csharp
private const int SpeakerModeOnFlag = 0x02;
private const int HeadsetModeOnFlag = 0x24;

private byte _currentOutputFlag = SpeakerModeOnFlag;

public void ToggleOutput() {
    _currentOutputFlag = _currentOutputFlag != SpeakerModeOnFlag
        ? (byte)SpeakerModeOnFlag
        : (byte)HeadsetModeOnFlag;
}
```

### 6.3 Headphone Volume Control

Headphone volume is controlled independently for left and right channels:

| Field | Range | Description |
|---|---|---|
| VolumeLeft | 0x00 - 0x4F | Left headphone channel volume |
| VolumeRight | 0x00 - 0x4F | Right headphone channel volume |

Both volume updates must be explicitly enabled by setting `EnableVolumeLeftUpdate` (bit 4) and `EnableVolumeRightUpdate` (bit 5) in the enable flags byte.

---

## 7. Microphone Input

### 7.1 Microphone Audio Format

The DS4 supports microphone input from a headset connected to the 3.5mm TRRS jack. Microphone audio is SBC-encoded by the controller's audio codec and sent to the host via Bluetooth HID input reports.

| Parameter | Value |
|---|---|
| Codec | SBC |
| Audio Target ID | `0x03` |
| Channels | Mono (1 channel) |
| Direction | Controller to Host |

**Note:** Detailed microphone SBC parameters (sample rate, bitpool, etc.) are not fully documented in available reverse engineering sources. The microphone likely uses a lower bitpool and potentially 16 kHz sample rate to conserve bandwidth.

### 7.2 Microphone Volume Control

| Field | Range | Description |
|---|---|---|
| VolumeMic | 0x00, 0x01 - 0x40 | Microphone volume/gain (0x00 has special behavior, possibly mute) |

The volume update must be enabled by setting `EnableVolumeMicUpdate` (bit 6 of the enable flags byte).

### 7.3 Reading Microphone Data

Microphone data arrives in Bluetooth HID input reports larger than the standard 0x01 report. When the `EnableAudio` bit is set in the input report header, the packet contains audio data (potentially alongside controller state). The BTAudio structure identifies microphone data by the AudioTarget byte value of `0x03`.

---

## 8. Output Report Audio Fields

### 8.1 USB Output Report 0x05 (32 bytes)

The USB output report includes volume control fields even though audio streaming itself is Bluetooth-only. Setting these volumes via USB affects the levels for Bluetooth audio playback.

| Byte Offset | Field | Type | Range | Description |
|---|---|---|---|---|
| 0 | ReportID | uint8 | 0x05 | Fixed report identifier |
| 1 | EnableFlags | uint8 | Bitmask | See enable flags table below |
| 2 | ControlFlags | uint8 | Bitmask | Reset and unknown flags |
| 3 | Empty | uint8 | 0x00 | Reserved |
| 4 | RumbleRight | uint8 | 0x00-0xFF | Weak (right) rumble motor |
| 5 | RumbleLeft | uint8 | 0x00-0xFF | Strong (left) rumble motor |
| 6 | LedRed | uint8 | 0x00-0xFF | Light bar red intensity |
| 7 | LedGreen | uint8 | 0x00-0xFF | Light bar green intensity |
| 8 | LedBlue | uint8 | 0x00-0xFF | Light bar blue intensity |
| 9 | LedFlashOn | uint8 | 0x00-0xFF | Flash on duration |
| 10 | LedFlashOff | uint8 | 0x00-0xFF | Flash off duration |
| 11-18 | ExtDataSend | uint8[8] | - | I2C EXT port data |
| 19 | VolumeLeft | uint8 | 0x00-0x4F | Left headphone volume |
| 20 | VolumeRight | uint8 | 0x00-0x4F | Right headphone volume |
| 21 | VolumeMic | uint8 | 0x00-0x40 | Microphone volume |
| 22 | VolumeSpeaker | uint8 | 0x00-0x4F | Internal speaker volume |
| 23 | UNK_AUDIO1 | uint8 (7-bit) | 1-64 | Audio config (set to 5 for audio) |
| 23.7 | UNK_AUDIO2 | uint8 (1-bit) | 0-1 | Audio enable flag (set to 1) |
| 24-31 | Padding | uint8[8] | 0x00 | Zeroed padding |

### 8.2 Enable Flags (Byte 1 of USB Report 0x05)

| Bit | Flag | Description |
|---|---|---|
| 0 | EnableRumbleUpdate | Apply rumble motor values |
| 1 | EnableLedUpdate | Apply LED color values |
| 2 | EnableLedBlink | Apply LED flash timing |
| 3 | EnableExtWrite | Write to I2C EXT port |
| 4 | EnableVolumeLeftUpdate | Apply left headphone volume |
| 5 | EnableVolumeRightUpdate | Apply right headphone volume |
| 6 | EnableVolumeMicUpdate | Apply microphone volume |
| 7 | EnableVolumeSpeakerUpdate | Apply speaker volume |

**Common enable flag value:** `0xF3` = Enable rumble + LED + flash + all volume controls (`0x01 | 0x02 | 0x10 | 0x20 | 0x40 | 0x80`).

### 8.3 Bluetooth Output Report 0x11 (78 bytes)

The Bluetooth output report wraps the same control data with additional Bluetooth-specific headers:

| Byte Offset | Field | Type | Description |
|---|---|---|---|
| 0 | ReportID | uint8 | 0x11 |
| 1 | Config | uint8 | Bits 0-5: PollingRate, Bit 6: EnableCRC, Bit 7: EnableHID |
| 2 | BT Flags 2 | uint8 | Typically 0x00 for standard control output; see BT Protocol doc for audio-specific flag values |
| 3 | EnableFlags | uint8 | Same bitmask as USB byte 1 (see table above) |
| 4 | ControlFlags | uint8 | 0x04 typical |
| 5 | Empty | uint8 | 0x00 |
| 6 | RumbleRight | uint8 | Weak rumble motor |
| 7 | RumbleLeft | uint8 | Strong rumble motor |
| 8 | LedRed | uint8 | Light bar red |
| 9 | LedGreen | uint8 | Light bar green |
| 10 | LedBlue | uint8 | Light bar blue |
| 11 | LedFlashOn | uint8 | Flash on duration |
| 12 | LedFlashOff | uint8 | Flash off duration |
| 13-20 | ExtDataSend | uint8[8] | I2C EXT port data |
| 21 | VolumeLeft | uint8 | Left headphone volume (0x00-0x4F) |
| 22 | VolumeRight | uint8 | Right headphone volume (0x00-0x4F) |
| 23 | VolumeMic | uint8 | Microphone volume (0x00-0x40) |
| 24 | VolumeSpeaker | uint8 | Speaker volume (0x00-0x4F) |
| 25-72 | Padding | uint8[48] | Zeroed BT padding |
| 73 | UNK_AUDIO1/2 | uint8 | Audio config flags |
| 74-77 | CRC-32 | uint32 | CRC checksum (little-endian) |

**Config byte (byte 1):** Typically set to `0xC0` (`EnableCRC | EnableHID`). For audio, the DS4AudioStreamer uses `0x40 | 0x80 = 0xC0`.

**Byte 2 (BT Flags 2 / MicControl):**

| Bit | Field | Description |
|---|---|---|
| 0-2 | EnableMic | 3-bit microphone enable flags |
| 3 | UnkA4 | Unknown |
| 4 | UnkB1 | Unknown |
| 5 | UnkB2 | Unknown (typically 1) |
| 6 | UnkB3 | Unknown |
| 7 | EnableAudio | Set high when packet contains audio data |

---

## 9. Input Report Audio Detection

### 9.1 Status Byte Layout

In the standard Bluetooth input report, the device status byte (offset 29 from the report data start, or offset 30 from the USB buffer start including report ID) contains:

| Bit | Field | Description |
|---|---|---|
| 0-3 | PowerPercent | Battery level (0x00-0x0A, or 0x01-0x0B when charging) |
| 4 | PluggedPowerCable | USB cable connected |
| 5 | PluggedHeadphones | Headphones detected in 3.5mm jack |
| 6 | PluggedMic | Microphone detected in 3.5mm jack |
| 7 | PluggedExt | External accessory connected |

### 9.2 Bluetooth Input Reports with Audio

For Bluetooth input reports larger than the basic 0x01 report, the header includes additional flags:

- **EnableHID bit:** When clear, the packet contains only audio data (no controller state)
- **EnableAudio bit:** When set, the packet contains audio data
- When both are set, controller state data appears first, followed by audio data

The BTAudio structure embedded in input reports has the same format as output:

```c
struct BTAudio {
    uint16_t frame_number;   // Incrementing frame counter
    uint8_t  audio_target;   // 0x03 = microphone data from controller
    uint8_t  sbc_data[];     // SBC-encoded audio frames
};
```

---

## 10. SBC Audio Codec

### 10.1 SBC Overview

SBC (Low Complexity Subband Codec) is the mandatory codec for Bluetooth A2DP audio. The DS4 uses SBC not through the standard A2DP profile, but embedded within HID reports. This allows audio to share the same Bluetooth HID channel as controller data.

### 10.2 DS4-Compatible SBC Parameters

The following SBC encoder settings are confirmed compatible with the DS4 controller:

| Parameter | Value | SBC Constant |
|---|---|---|
| Sample Rate | 32,000 Hz | `SBC_FREQ_32000` (0x01) |
| Sub-bands | 8 | `SBC_SB_8` (0x01) |
| Bitpool | 48 | - |
| Channel Mode | Joint Stereo | `SBC_MODE_JOINT_STEREO` (0x03) |
| Allocation Mode | SNR | `SBC_AM_SNR` (0x01) |
| Block Count | 16 | `SBC_BLK_16` (0x03) |
| Endianness | Little-Endian | `SBC_LE` (0x00) |

Alternative configurations that have been reported to work:

| Parameter | Alternative Value |
|---|---|
| Channel Mode | Dual Channel |
| Bitpool | 25 |
| Sample Rate | 16,000 Hz (for lower bandwidth) |

### 10.3 SBC Frame Structure

Each SBC frame begins with the sync word `0x9C` followed by header fields:

```
Byte 0:    0x9C (sync word)
Byte 1:    [Sampling Freq (2b)] [Block Count (2b)] [Channel Mode (2b)] [Alloc Method (1b)] [Subbands (1b)]
Byte 2:    Bitpool value
Byte 3+:   Encoded subband samples
```

### 10.4 Frame Size Calculation

With the recommended settings (32 kHz, Joint Stereo, 8 subbands, 16 blocks, bitpool 48):

- **Input (PCM) block size:** `sbc_get_codesize()` -- typically 1024 bytes (16 blocks * 8 subbands * 2 channels * 2 bytes/sample / factor)
- **Output (SBC) frame size:** `sbc_get_frame_length()` -- approximately 109 bytes

### 10.5 Audio Pipeline

The complete audio pipeline from host audio to controller speaker:

```
Host Audio Source (any sample rate, any channels)
    |
    v
Downmix to Stereo (if needed)
    |
    v
Resample to 32,000 Hz (if needed)
    |
    v
Convert to 16-bit Signed Integer PCM (Little-Endian)
    |
    v
SBC Encode (produces ~109-byte frames)
    |
    v
Pack 2 or 4 frames into HID output report
    |
    v
Add CRC-32 checksum
    |
    v
Write to HID device (Bluetooth)
    |
    v
Controller decodes SBC and drives speaker/headphone DAC
```

---

## 11. Bluetooth Audio Packet Format

### 11.1 Report 0x14 (Small Audio Packet -- 270 bytes)

| Byte Offset | Size | Field | Description |
|---|---|---|---|
| 0 | 1 | ReportID | `0x14` |
| 1 | 1 | Config | `0x40` |
| 2 | 1 | BT Flags 2 | `0xA2` (audio-specific: EnableAudio set) |
| 3-4 | 2 | FrameCounter | Little-endian incrementing counter |
| 5 | 1 | AudioTarget | `0x02` (speaker) or `0x24` (headset) |
| 6-265 | 260 | SBCData | 2 SBC frames (~109 bytes each) + padding |
| 266-269 | 4 | CRC-32 | Checksum (little-endian) |

### 11.2 Report 0x17 (Medium Audio Packet -- 462 bytes)

| Byte Offset | Size | Field | Description |
|---|---|---|---|
| 0 | 1 | ReportID | `0x17` |
| 1 | 1 | Config | `0x40` |
| 2 | 1 | BT Flags 2 | `0xA2` (audio-specific: EnableAudio set) |
| 3-4 | 2 | FrameCounter | Little-endian incrementing counter |
| 5 | 1 | AudioTarget | `0x02` (speaker) or `0x24` (headset) |
| 6-457 | 452 | SBCData | 4 SBC frames (~109 bytes each) + padding |
| 458-461 | 4 | CRC-32 | Checksum (little-endian) |

### 11.3 Report Selection Logic

The DS4AudioStreamer uses this logic to select the report type:

```
if (buffered_frames >= 4):
    use Report 0x17 (462 bytes, 4 frames)
    increment counter by 4
elif (buffered_frames >= 2):
    use Report 0x14 (270 bytes, 2 frames)
    increment counter by 2
else:
    wait for more frames
```

### 11.4 Frame Counter

The frame counter is a 16-bit unsigned integer (little-endian) that increments by the number of SBC frames sent in each packet. It wraps around at 65535. This counter helps the controller's audio codec maintain synchronization and detect dropped packets.

### 11.5 Complete Packet Construction

```
1. Zero-fill output buffer (640 bytes max)
2. Set report ID at byte 0
3. Set byte 1 = 0x40 (unknown, required)
4. Set byte 2 = 0xA2 (BT Flags 2: audio-specific, EnableAudio set)
5. Write frame counter (little-endian) at bytes 3-4
6. Set audio target at byte 5
7. Copy SBC frame data starting at byte 6
8. Compute CRC-32 over [0xA2 header byte] + [bytes 0..size-5]
9. Write CRC-32 (little-endian) at bytes [size-4..size-1]
10. Send [0..size-1] via HID write
```

---

## 12. Audio Streaming Implementation for macOS

### 12.1 Architecture Overview

Implementing DS4 audio streaming on macOS requires:

1. **Bluetooth HID Connection** -- Connect to the DS4 via IOKit/IOHID frameworks
2. **Audio Capture** -- Use Core Audio to capture system or application audio
3. **Audio Processing** -- Downmix, resample, and format-convert the audio
4. **SBC Encoding** -- Encode PCM audio into SBC frames using libsbc
5. **Packet Assembly** -- Build HID output reports with SBC data and CRC
6. **HID Output** -- Write reports to the controller via the HID device handle

### 12.2 Bluetooth HID Connection on macOS

On macOS, the DS4 Bluetooth connection can be managed through:

- **IOKit HID Manager** (`IOHIDManager`): For user-space access to the HID device
- **DriverKit** (modern approach): For creating a driver extension
- **IOKit KEXT** (legacy, pre-macOS 11): The approach used by the existing ds4mac project

```c
// User-space HID device discovery (IOKit)
IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);

// Match Sony DS4 devices
CFMutableDictionaryRef match = CFDictionaryCreateMutable(...);
CFDictionarySetValue(match, CFSTR(kIOHIDVendorIDKey),
    CFNumberCreate(NULL, kCFNumberIntType, &(int){0x054C}));  // Sony
CFDictionarySetValue(match, CFSTR(kIOHIDProductIDKey),
    CFNumberCreate(NULL, kCFNumberIntType, &(int){0x05C4}));  // DS4 v1
// Also match 0x09CC for DS4 v2

IOHIDManagerSetDeviceMatching(manager, match);
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
```

**Device Identification:**

| Property | DS4 v1 | DS4 v2 |
|---|---|---|
| Vendor ID | `0x054C` (Sony) | `0x054C` (Sony) |
| Product ID | `0x05C4` | `0x09CC` |

To verify the device is connected via Bluetooth (required for audio), check the transport property or device path for Bluetooth indicators.

### 12.3 Core Audio Capture

macOS Core Audio provides several APIs for audio capture:

**Option A: AVAudioEngine (recommended for app-level audio)**

```swift
import AVFoundation

let engine = AVAudioEngine()
let inputNode = engine.inputNode  // System microphone
// Or use an output tap for loopback:
let mainMixer = engine.mainMixerNode

mainMixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, time in
    // Process audio buffer
    let pcmData = buffer.floatChannelData
    let frameCount = buffer.frameLength
    // Feed into SBC encoder pipeline...
}
```

**Option B: Audio Unit (lower-level, more control)**

```c
// Set up an AudioUnit for capturing default output
AudioComponentDescription desc = {
    .componentType = kAudioUnitType_Output,
    .componentSubType = kAudioUnitSubType_DefaultOutput,
    .componentManufacturer = kAudioUnitManufacturer_Apple
};
```

**Option C: ScreenCaptureKit Audio (macOS 13+, system-wide audio capture)**

```swift
import ScreenCaptureKit

// Capture system audio output
let config = SCStreamConfiguration()
config.capturesAudio = true
config.sampleRate = 32000  // Match DS4 target
config.channelCount = 2
```

### 12.4 Audio Processing Pipeline

The captured audio must be processed before SBC encoding:

#### Step 1: Downmix to Stereo

If the source audio has more than 2 channels (e.g., 5.1 or 7.1 surround), downmix to stereo:

```c
// Standard downmix coefficients
void downmix_to_stereo(float *input, float *output, int frames, int src_channels) {
    for (int i = 0; i < frames; i++) {
        float left  = input[i * src_channels + 0];   // Front Left
        float right = input[i * src_channels + 1];    // Front Right

        if (src_channels > 2) {
            float center = input[i * src_channels + 2] * 0.7f;
            left  += center;
            right += center;
        }
        if (src_channels > 3) {
            float lfe = input[i * src_channels + 3] * 0.5f;
            left  += lfe;
            right += lfe;
        }
        if (src_channels > 4) left  += input[i * src_channels + 4] * 0.7f;  // Surround L
        if (src_channels > 5) right += input[i * src_channels + 5] * 0.7f;  // Surround R
        if (src_channels > 6) left  += input[i * src_channels + 6] * 0.7f;  // Rear L
        if (src_channels > 7) right += input[i * src_channels + 7] * 0.7f;  // Rear R

        // Prevent clipping
        output[i * 2 + 0] = left  * 0.5f;
        output[i * 2 + 1] = right * 0.5f;
    }
}
```

#### Step 2: Resample to 32 kHz

If the source sample rate differs from 32,000 Hz (common rates: 44,100 or 48,000):

```c
// Using libsamplerate (recommended)
#include <samplerate.h>

SRC_STATE *resampler = src_new(SRC_SINC_BEST_QUALITY, 2 /* channels */, &error);
double ratio = 32000.0 / source_sample_rate;

SRC_DATA convert = {
    .data_in = input_float,
    .data_out = output_float,
    .input_frames = input_frame_count,
    .output_frames = (int)ceil(input_frame_count * ratio),
    .src_ratio = ratio
};
src_process(resampler, &convert);
```

Alternatively, use Apple's AudioConverter:

```c
AudioConverterRef converter;
AudioStreamBasicDescription srcFormat = { .mSampleRate = 48000.0, ... };
AudioStreamBasicDescription dstFormat = { .mSampleRate = 32000.0, ... };
AudioConverterNew(&srcFormat, &dstFormat, &converter);
```

#### Step 3: Convert to 16-bit Signed Integer

SBC expects 16-bit signed integer PCM input:

```c
// Float32 [-1.0, 1.0] to Int16 [-32768, 32767]
void float_to_int16(const float *input, int16_t *output, int sample_count) {
    for (int i = 0; i < sample_count; i++) {
        float clamped = fmaxf(-1.0f, fminf(1.0f, input[i]));
        output[i] = (int16_t)(clamped * 32767.0f);
    }
}
```

### 12.5 SBC Encoding with libsbc

The [libsbc](https://github.com/nefarius/libsbc) library provides the SBC encoder/decoder. On macOS, you can build it from source or use a precompiled dylib.

```c
#include <sbc/sbc.h>

// Initialize encoder
sbc_t sbc;
sbc_init(&sbc, 0);

sbc.frequency  = SBC_FREQ_32000;     // 32 kHz
sbc.subbands   = SBC_SB_8;           // 8 sub-bands
sbc.bitpool    = 48;                  // Bitpool size
sbc.mode       = SBC_MODE_JOINT_STEREO;
sbc.allocation = SBC_AM_SNR;
sbc.blocks     = SBC_BLK_16;         // 16 blocks
sbc.endian     = SBC_LE;             // Little-endian

size_t code_size  = sbc_get_codesize(&sbc);   // Input PCM block size
size_t frame_size = sbc_get_frame_length(&sbc); // Output SBC frame size

// Encode one block
uint8_t pcm_input[code_size];
uint8_t sbc_output[frame_size];
ssize_t written;

ssize_t consumed = sbc_encode(&sbc, pcm_input, code_size,
                               sbc_output, frame_size, &written);

// Clean up
sbc_finish(&sbc);
```

### 12.6 Buffer Management

Audio streaming requires careful buffer management to avoid underruns (gaps) and overruns (latency buildup):

**Circular Buffer Design:**

```
[Audio Source] --> [PCM Ring Buffer] --> [SBC Encoder] --> [SBC Frame Ring Buffer] --> [HID Writer]
```

Key parameters (from the DS4AudioStreamer reference):

| Parameter | Value | Description |
|---|---|---|
| Min Buffered Frames | 4 | Minimum SBC frames before sending |
| Max Wait Timeout | 20 ms | Max time waiting for new frames |
| Output Buffer Size | 640 bytes | Max HID report buffer |
| Preferred Packet | 4 frames (0x17) | Preferred over 2-frame packets |

**Latency Budget:**

| Component | Approximate Latency |
|---|---|
| Audio capture | 5-10 ms |
| Resampling | <1 ms |
| SBC encoding | <1 ms |
| Buffer accumulation (4 frames) | ~20 ms |
| Bluetooth HID transport | 5-15 ms |
| Controller SBC decode + DAC | ~5 ms |
| **Total estimated** | **~40-50 ms** |

### 12.7 Threading Model

The recommended threading model:

```
Main Thread:        UI / RunLoop management
Audio Thread:       Core Audio callback -> Downmix -> Resample -> SBC encode -> Ring buffer
HID Writer Thread:  Wait for frames -> Build packet -> CRC -> Write to device
```

The HID writer thread uses an event-based wait mechanism to avoid spinning:

- Wait on event with 20ms timeout
- When SBC frame buffer has >= 4 frames, signal the event
- Build and send the packet
- Repeat

---

## 13. Code Examples

### 13.1 Sending a Volume Control Report (Bluetooth)

This example sends an output report 0x11 to configure all volume levels:

```c
#include <IOKit/hid/IOHIDDevice.h>

void ds4_set_volumes(IOHIDDeviceRef device,
                     uint8_t vol_left,      // 0x00-0x4F
                     uint8_t vol_right,     // 0x00-0x4F
                     uint8_t vol_mic,       // 0x00-0x40
                     uint8_t vol_speaker)   // 0x00-0x4F
{
    uint8_t report[78];
    memset(report, 0, sizeof(report));

    report[0] = 0x11;   // Report ID
    report[1] = 0xC0;   // EnableCRC | EnableHID
    report[2] = 0x00;   // BT Flags 2: 0x00 for standard control output

    // Enable flags: rumble + LED + all volumes
    report[3] = 0xF3;   // 0x01|0x02|0x10|0x20|0x40|0x80
    report[4] = 0x04;   // Control flags

    // Rumble (off)
    report[6] = 0x00;   // Right (weak)
    report[7] = 0x00;   // Left (strong)

    // LED (purple for visibility)
    report[8]  = 0xFF;  // Red
    report[9]  = 0x00;  // Green
    report[10] = 0xFF;  // Blue
    report[11] = 0x00;  // Flash on
    report[12] = 0x00;  // Flash off

    // Volume controls
    report[21] = vol_left;
    report[22] = vol_right;
    report[23] = vol_mic;
    report[24] = vol_speaker;

    // Compute CRC-32
    uint32_t crc = ds4_compute_crc32(report, 0, 74);
    report[74] = (uint8_t)(crc & 0xFF);
    report[75] = (uint8_t)((crc >> 8) & 0xFF);
    report[76] = (uint8_t)((crc >> 16) & 0xFF);
    report[77] = (uint8_t)((crc >> 24) & 0xFF);

    // Send via IOKit HID
    // IOKit expects data starting after the report ID byte, with
    // length excluding the report ID. This is the standard IOKit HID pattern.
    IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11,
                         report + 1, sizeof(report) - 1);
}
```

### 13.2 Streaming Audio to the Speaker (Bluetooth)

Complete example of building and sending an audio packet:

```c
#include <sbc/sbc.h>

typedef struct {
    sbc_t         encoder;
    size_t        code_size;      // PCM input block size
    size_t        frame_size;     // SBC output frame size
    uint16_t      frame_counter;  // Packet sequence number
    uint8_t       audio_target;   // 0x02=speaker, 0x24=headset
    uint8_t       output_buf[640];
    IOHIDDeviceRef device;
} DS4AudioContext;

// Initialize the audio context
void ds4_audio_init(DS4AudioContext *ctx, IOHIDDeviceRef device) {
    memset(ctx, 0, sizeof(*ctx));
    ctx->device = device;
    ctx->audio_target = 0x02;  // Default to speaker

    sbc_init(&ctx->encoder, 0);
    ctx->encoder.frequency  = SBC_FREQ_32000;
    ctx->encoder.subbands   = SBC_SB_8;
    ctx->encoder.bitpool    = 48;
    ctx->encoder.mode       = SBC_MODE_JOINT_STEREO;
    ctx->encoder.allocation = SBC_AM_SNR;
    ctx->encoder.blocks     = SBC_BLK_16;
    ctx->encoder.endian     = SBC_LE;

    ctx->code_size  = sbc_get_codesize(&ctx->encoder);
    ctx->frame_size = sbc_get_frame_length(&ctx->encoder);
}

// Send a packet containing 'num_frames' SBC frames
// sbc_frames: array of SBC frame data, each of ctx->frame_size bytes
void ds4_audio_send(DS4AudioContext *ctx, uint8_t **sbc_frames, int num_frames) {
    int report_id, total_size;

    if (num_frames >= 4) {
        report_id  = 0x17;
        total_size = 462;
        num_frames = 4;
    } else {
        report_id  = 0x14;
        total_size = 270;
        num_frames = 2;
    }

    uint8_t *buf = ctx->output_buf;
    memset(buf, 0, 640);

    // Header
    buf[0] = (uint8_t)report_id;
    buf[1] = 0x40;
    buf[2] = 0xA2;  // BT Flags 2: audio-specific (EnableAudio set)

    // Frame counter (little-endian)
    buf[3] = (uint8_t)(ctx->frame_counter & 0xFF);
    buf[4] = (uint8_t)((ctx->frame_counter >> 8) & 0xFF);

    // Audio target
    buf[5] = ctx->audio_target;

    // Copy SBC frames starting at byte 6
    for (int i = 0; i < num_frames; i++) {
        memcpy(&buf[6 + i * ctx->frame_size],
               sbc_frames[i], ctx->frame_size);
    }

    ctx->frame_counter += num_frames;

    // CRC-32 (include virtual 0xA2 BT header)
    uint32_t crc = ds4_compute_crc32(buf, 0, total_size - 4);
    buf[total_size - 4] = (uint8_t)(crc & 0xFF);
    buf[total_size - 3] = (uint8_t)((crc >> 8) & 0xFF);
    buf[total_size - 2] = (uint8_t)((crc >> 16) & 0xFF);
    buf[total_size - 1] = (uint8_t)((crc >> 24) & 0xFF);

    // Send via IOKit HID
    // IOKit expects data starting after the report ID byte, with
    // length excluding the report ID. This is the standard IOKit HID pattern.
    IOHIDDeviceSetReport(ctx->device, kIOHIDReportTypeOutput,
                         report_id, buf + 1, total_size - 1);
}

// Cleanup
void ds4_audio_cleanup(DS4AudioContext *ctx) {
    sbc_finish(&ctx->encoder);
}
```

### 13.3 Reading Headphone/Microphone Status

```c
// Process an input report to detect headphone/mic status
void ds4_check_audio_status(const uint8_t *report, int report_len) {
    // For Bluetooth input report 0x11, status byte is at offset 30
    // For USB input report 0x01, status byte is at offset 30
    // (offset from buffer start including report ID)

    uint8_t status_byte;
    if (report[0] == 0x01) {
        // USB report: status at byte 30
        status_byte = report[30];
    } else if (report[0] == 0x11) {
        // BT report: status at byte 32 (2-byte BT header offset)
        status_byte = report[32];
    } else {
        return;
    }

    bool usb_connected     = (status_byte & 0x10) != 0;
    bool headphones_plugged = (status_byte & 0x20) != 0;
    bool mic_plugged        = (status_byte & 0x40) != 0;

    if (headphones_plugged && mic_plugged) {
        printf("Headset connected (headphones + mic)\n");
        // Route audio to headset (0x24)
    } else if (headphones_plugged) {
        printf("Headphones connected (no mic)\n");
        // Route audio to headset (0x24)
    } else {
        printf("No headphones - using speaker\n");
        // Route audio to speaker (0x02)
    }
}
```

### 13.4 Complete Audio Streaming Loop (Pseudocode)

```
function audio_streaming_main():
    device = discover_ds4_bluetooth()
    if device is NULL:
        print("No DS4 found via Bluetooth")
        return

    // Initialize volumes
    ds4_set_volumes(device, 0x50, 0x50, 0x50, 0x50)

    // Initialize SBC encoder
    ctx = ds4_audio_init(device)

    // Start audio capture (Core Audio)
    capture = start_audio_capture(sample_rate=48000, channels=2)

    // Audio processing + encoding thread
    sbc_frame_buffer = CircularBuffer(capacity=8192)

    on_audio_captured(pcm_float, frame_count):
        stereo = downmix_to_stereo(pcm_float, frame_count, source_channels)
        resampled = resample(stereo, 48000, 32000)
        int16_pcm = float_to_int16(resampled)

        while int16_pcm has enough samples for one SBC block:
            sbc_frame = sbc_encode(ctx.encoder, int16_pcm_block)
            sbc_frame_buffer.push(sbc_frame)

    // HID writer thread
    while device.is_connected:
        wait_for_frames(sbc_frame_buffer, min_count=4, timeout_ms=20)

        if sbc_frame_buffer.count >= 4:
            frames = sbc_frame_buffer.pop(4)
            ds4_audio_send(ctx, frames, 4)     // Report 0x17
        elif sbc_frame_buffer.count >= 2:
            frames = sbc_frame_buffer.pop(2)
            ds4_audio_send(ctx, frames, 2)     // Report 0x14

    ds4_audio_cleanup(ctx)
```

---

## 14. References

### Primary Sources

- [Game Controller Collective Wiki - Sony DualShock 4](https://controllers.fandom.com/wiki/Sony_DualShock_4)
- [Game Controller Collective Wiki - DS4 Data Structures](https://controllers.fandom.com/wiki/Sony_DualShock_4/Data_Structures)
- [PS4 Developer Wiki - DS4-USB](https://www.psdevwiki.com/ps4/DS4-USB)
- [PS4 Developer Wiki - DS4-BT](https://www.psdevwiki.com/ps4/DS4-BT)
- [GIMX Wiki - DualShock 4](https://gimx.fr/wiki/index.php?title=DualShock_4)
- [Eleccelerator Wiki - DualShock 4](http://eleccelerator.com/wiki/index.php?title=DualShock_4)

### Reference Implementations

- [DS4AudioStreamer](https://github.com/nefarius/DS4AudioStreamer) -- Primary reference for Bluetooth audio streaming (C#/.NET)
- [DS4Windows](https://github.com/Ryochan7/DS4Windows) -- Volume control and output report structure
- [ds4drv](https://github.com/chrippa/ds4drv) -- Headphone/microphone detection (Python)
- [DS4Windows Issue #123](https://github.com/Jays2Kings/DS4Windows/issues/123) -- Original audio research
- [ViGEmBus Issue #61](https://github.com/ViGEm/ViGEmBus/issues/61) -- Audio streaming code references

### Libraries

- [libsbc](https://github.com/nefarius/libsbc) -- SBC encoder/decoder library
- [libsamplerate](https://github.com/libsndfile/libsamplerate) -- Sample rate conversion library
- [SBC Codec Wikipedia](https://en.wikipedia.org/wiki/SBC_(codec)) -- SBC codec background

### Related Blog Posts

- [DualShock4 Reverse Engineering - Part 2](https://blog.the.al/2023/01/02/ds4-reverse-engineering-part-2.html) -- HID protocol details
- [SensePost - Dual-Pod-Shock](https://sensepost.com/blog/2020/dual-pod-shock-emotional-abuse-of-a-dualshock/) -- DS4 reverse engineering
