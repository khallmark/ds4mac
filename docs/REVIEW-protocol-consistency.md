# Protocol Documentation Consistency Review

> **Reviewer:** Technical documentation cross-reference audit
> **Date:** 2026-02-27
> **Documents reviewed:**
> - `01-DS4-Controller-Overview.md` (abbreviated **DOC-01**)
> - `04-DS4-USB-Protocol.md` (abbreviated **DOC-04**)
> - `05-DS4-Bluetooth-Protocol.md` (abbreviated **DOC-05**)

---

## Executive Summary

Cross-referencing the three protocol documents revealed **13 contradictions or inconsistencies** and **5 ambiguities** that could cause implementation bugs. The most impactful issues involve conflicting report sizes, inconsistent BT-to-USB offset descriptions (a critical +2 vs +3 confusion in DOC-01), and conflicting calibration field ordering between the USB and BT documents. The CRC-32 algorithm parameters are fully consistent across all three documents, which is a strong positive.

---

## Issues Found

### ISSUE 1: BT Input Report 0x11 -- Total Size Contradiction (79 vs 78 bytes)

**Severity:** Medium -- could cause off-by-one buffer allocation

DOC-01 consistently states the BT extended input report is **79 bytes**:

> DOC-01, line 293: `| 17 | 0x11 | 79 | Bluetooth | Extended controller state (full data) |`
>
> DOC-01, line 577: `[75-78] 4 CRC-32 checksum (polynomial 0x04C11DB7)`
>
> DOC-01, line 641: `79-byte reports (incl. 4-byte CRC), BT header overhead, ~125 Hz`

DOC-04 states it is **78 bytes**:

> DOC-04, lines 953-954: `| 0x01 (Input) | 0x11 (Extended) | 78 bytes | Full data + CRC`
>
> DOC-04, line 960: `The Bluetooth extended input report is 78 bytes total.`

DOC-05 clarifies this is a matter of perspective (78 bytes at the hidraw layer, 79 bytes on raw L2CAP):

> DOC-05, lines 315-324:
> ```
> Total Bluetooth report: 78 bytes (as seen by HID layer / hidraw)
> ...
> On raw L2CAP (not hidraw), an additional HID transaction header 0xA1 precedes byte [0], making the total 79 bytes.
> ```

**Verdict:** DOC-01 uses the raw L2CAP perspective (79 bytes including `0xA1` header) without stating so. DOC-04 uses the hidraw perspective (78 bytes). DOC-05 correctly explains both. DOC-01 should clarify which layer perspective it uses, or preferably list both as DOC-05 does. The byte map in DOC-01 (lines 562-577) explicitly includes `[0] = 0xA1` (the HID transaction header), confirming it uses the raw L2CAP perspective, but the Interface Comparison Table at line 192 says "79 bytes (extended)" without qualification.

---

### ISSUE 2: BT Input Report 0x11 -- Offset Description Contradiction (+3 vs +2)

**Severity:** High -- directly affects parsing code correctness

DOC-01 states the offset from USB layout is **+3**:

> DOC-01, line 574: `...etc (offset +3 from USB layout)`

DOC-04 states the offset is **+2** (from the report-ID-relative perspective):

> DOC-04, line 971: `To parse the extended BT report using the same parser as USB, skip the first 2 bytes (or read from offset +2 relative to USB offsets).`

DOC-05 states **+2** consistently:

> DOC-05, line 351: `This creates a **+2 byte offset** when comparing field positions between the BT and USB report byte indices.`
>
> DOC-05, line 1161: `| Field Offset Shift | Baseline | +2 bytes from USB |`

**Analysis:** This is actually both documents being correct from different perspectives, but DOC-01 is internally inconsistent about which perspective it uses:

- From the **hidraw** view: BT byte [0] = Report ID. Controller data starts at BT byte [3]. USB controller data starts at USB byte [1]. So the offset is BT[3] = USB[1], which is +2 when comparing byte indices.
- From the **raw L2CAP** view (which DOC-01's byte map uses, starting with `0xA1`): controller data starts at raw byte [4]. USB data starts at byte [1]. So the offset is +3 from raw L2CAP perspective.

DOC-01's byte map (lines 562-577) uses the raw L2CAP view (byte [0] = `0xA1`), so "+3 from USB layout" is correct *for that byte map*. But if someone reads DOC-01 alongside DOC-04/DOC-05, the apparent contradiction is confusing.

**Verdict:** DOC-01 should explicitly label its byte map as "raw L2CAP perspective" and note that hidraw users should use +2. DOC-04 and DOC-05 agree on +2 from the hidraw perspective.

---

### ISSUE 3: BT Basic Input Report 0x01 Size Inconsistency

**Severity:** Low -- affects edge case handling

The size of the reduced Bluetooth input report 0x01 varies across documents:

> DOC-01, line 192: `11 bytes (basic)`
>
> DOC-01, line 548: `Controller sends basic 0x01 reports (11 bytes)`

> DOC-04, line 952: `| 0x01 (Basic) | 10 bytes | Truncated: sticks, buttons, triggers only`
>
> DOC-04, line 996: `the controller initially sends only basic 10-byte reports`

> DOC-05, line 233: `reduced input reports using Report ID 0x01 (9-11 bytes)`
>
> DOC-05, line 302: `Total size: 9-11 bytes (report data only, excluding HID header)`

**Verdict:** Three different sizes are stated: 9, 10, and 11 bytes. DOC-05 hedges by saying "9-11 bytes." DOC-04 says 10 bytes. DOC-01 says 11 bytes. The actual size likely depends on whether the Report ID byte and/or HID header is counted. This should be standardized across all documents with explicit inclusion/exclusion of the report ID byte.

---

### ISSUE 4: BT Calibration Feature Report -- Triggering Mode Switch

**Severity:** Medium -- affects initialization code

The documents disagree on which feature report triggers the BT mode switch:

DOC-01 says read feature report `0x02`:

> DOC-01, line 549: `Host->>DS4: GET_FEATURE(0x02) -- request calibration`
>
> DOC-01, line 771: `Sending feature report 0x02 is required to activate extended 0x11 reports`

DOC-04 says read feature report `0x02`:

> DOC-04, lines 998-999: `1. Read Feature Report 0x02 (calibration data)` / `2. The controller switches to sending Report ID 0x11 automatically`

DOC-05 says read feature report `0x05`:

> DOC-05, lines 240-241: `| Bluetooth | Calibration | 0x05 (40 bytes, CRC-32 protected) |`
>
> DOC-05, line 1165: `| Mode Switch | Immediate | After reading Feature Report 0x05 |`

However, DOC-05 also shows ds4drv's hidraw backend reading `0x02`:

> DOC-05, lines 252-253:
> ```python
> def set_operational(self):
>     self.read_feature_report(0x02, 37)
> ```

**Analysis:** The BT calibration report *is* report ID `0x05`, but the hidraw layer may translate `0x02` (USB calibration ID) to `0x05` (BT calibration ID) transparently. DOC-01 and DOC-04 describe the hidraw perspective where you request `0x02` and the OS translates it. DOC-05 Section 7.1 correctly maps USB `0x02` to BT `0x05`. The ds4drv code in DOC-05 confirms that on hidraw, you still use `0x02`.

**Verdict:** Not a true contradiction, but extremely confusing. DOC-01's mermaid diagram (line 549) and DOC-04's Section 8.4 should note that `0x02` is the USB report ID, and that on raw BT (not hidraw), `0x05` is the correct report ID. DOC-05 gets this mostly right but its own code example contradicts its own table.

---

### ISSUE 5: Calibration Report -- Field Ordering Contradiction (Gyro Plus/Minus)

**Severity:** High -- directly affects calibration math and IMU accuracy

DOC-04 lists the gyro calibration fields in this order for report `0x02`:

> DOC-04, lines 547-551:
> ```
> | 7-8   | int16 | Gyro Pitch Plus (positive range calibration) |
> | 9-10  | int16 | Gyro Yaw Plus |
> | 11-12 | int16 | Gyro Roll Plus |
> | 13-14 | int16 | Gyro Pitch Minus (negative range calibration) |
> | 15-16 | int16 | Gyro Yaw Minus |
> | 17-18 | int16 | Gyro Roll Minus |
> ```

That is: **Plus(Pitch, Yaw, Roll), then Minus(Pitch, Yaw, Roll)** -- all three plus values grouped, then all three minus values grouped.

DOC-05 lists the gyro calibration fields for BT report `0x05` in a different order:

> DOC-05, lines 714-719:
> ```
> | 7-8   | Gyro Pitch Plus  | int16 LE |
> | 9-10  | Gyro Pitch Minus | int16 LE |
> | 11-12 | Gyro Yaw Plus    | int16 LE |
> | 13-14 | Gyro Yaw Minus   | int16 LE |
> | 15-16 | Gyro Roll Plus   | int16 LE |
> | 17-18 | Gyro Roll Minus  | int16 LE |
> ```

That is: **Plus/Minus paired per axis** -- Pitch(Plus, Minus), Yaw(Plus, Minus), Roll(Plus, Minus).

**Verdict:** These two orderings are mutually exclusive. The calibration data is the same between USB and BT (just a different report ID wrapper), so the field ordering must be the same. Only one can be correct. Checking against the Linux kernel `hid-sony.c` driver would resolve this. This is a **critical bug** in one of the two documents -- if a developer follows the wrong ordering, the gyro calibration will produce incorrect results.

---

### ISSUE 6: Calibration Report Size -- 36 vs 37 vs 40 vs 41 Bytes

**Severity:** Medium -- affects buffer allocation

Multiple size values appear:

DOC-01:

> Line 198: `| 0x02 (36 bytes) | 0x05 (41 bytes) |` (USB calibration = 36, BT calibration = 41)
> Line 307: `| 2 | 0x02 | 37 | ... | IMU calibration data (USB) |`

DOC-04:

> Line 487: `| 0x02 | 37 | GET | ... | Calibration Data |`
> Line 533: `Size: 37 bytes (1 byte Report ID + 36 bytes data)`
> Line 955: `| 0x02 (Calibration) | 0x05 (Calibration) | 41 bytes |`

DOC-05:

> Line 241: `| Bluetooth | Calibration | 0x05 (40 bytes, CRC-32 protected) |`
> Line 706: heading says "41 bytes"
> Line 1190: `| Calibration | 0x02 | 0x05 | 37 bytes | 41 bytes | Yes |`

**Summary of sizes claimed:**

| Report | DOC-01 | DOC-04 | DOC-05 |
|--------|--------|--------|--------|
| USB 0x02 | 36 (line 198), 37 (line 307) | 37 | 37 |
| BT 0x05 | 41 | 41 | 40 (line 241), 41 (line 706, 1190) |

**Verdict:** DOC-01 gives two different sizes for USB calibration (36 and 37) -- line 198 says 36 bytes, line 307 says 37 bytes. The correct value is 37 (1 byte Report ID + 36 bytes data), so line 198 apparently excludes the Report ID. DOC-05 gives two different sizes for BT calibration (40 at line 241, 41 at lines 706/1190). The correct value is 41 (37 bytes of calibration data + 4 bytes CRC), so line 241 is off by 1. Both documents have internal inconsistencies regarding whether sizes include the Report ID byte.

---

### ISSUE 7: BT Output Report -- Legacy Size and Flags Byte Contradiction

**Severity:** Medium

DOC-01 describes the BT output report 0x11 at lines 585-605 and states:

> DOC-01, line 591: `[1] Flags (0x80 = control, 0xC0 = control + poll rate)`
>
> DOC-01, line 592: `[2] Protocol Flags (0xFF typical)`

DOC-05 describes the same report at lines 543-544:

> DOC-05, line 543: `| 1 | -- | BT Flags 1 | 0xC0 | btPollRate: EnableCRC + EnableHID + poll rate |`
>
> DOC-05, line 544: `| 2 | -- | BT Flags 2 | 0x00: Microphone enable flags (bits 2:0) |`

DOC-04 at lines 977-979:

> DOC-04, line 978: `[1] 0x80 | poll_rate (CRC + HID flags)`
>
> DOC-04, line 979: `[2] 0xA0 or 0xFF (control flags)`

**Verdict:** Byte [2] has three different "typical" values: `0xFF` (DOC-01 and DOC-04), `0xA0` (DOC-04), and `0x00` (DOC-05). The meaning of byte [1] also differs: DOC-01 says `0x80` or `0xC0`, DOC-04 says `0x80 | poll_rate`, DOC-05 says `0xC0 | btPollRate`. These should be reconciled. The DS4Windows code shown in DOC-05 line 571 (`0xC0 | btPollRate`) is likely the most authoritative.

---

### ISSUE 8: BT Output Report -- Byte [3] vs Byte [4] for Feature Enable 2

**Severity:** Low

DOC-01 describes the BT output report as:

> DOC-01, lines 594-595:
> ```
> [4]     Feature flags (same meaning as USB byte [1])
> [5]     0x04
> ```

DOC-05 describes:

> DOC-05, lines 545-547:
> ```
> | 3 | 1 | Feature Enable 1 | ...rumble (0x01), lightbar (0x02), flash (0x04) |
> | 4 | 2 | Feature Enable 2 | 0x04 (typically) |
> | 5 | 3 | Reserved | 0x00 |
> ```

**Verdict:** DOC-01 has the feature flags at byte [4] (raw L2CAP view where byte [0] = Report ID, plus there appears to be an extra byte). DOC-05 has feature flags at byte [3] (hidraw view). Checking DOC-01's full map: `[0]=0x11, [1]=Flags, [2]=Protocol, [3]=Unknown, [4]=Feature flags`. DOC-05's map: `[0]=0x11, [1]=BT Flags 1, [2]=BT Flags 2, [3]=Feature Enable, [4]=Feature Enable 2`. DOC-01 has an extra "Unknown" byte at [3] before the feature flags, while DOC-05 does not. One of these is wrong. The ds4drv code in DOC-05 (line 619-621) and the DS4Windows code both put feature flags at byte [3] in the hidraw view. DOC-01 appears to have an erroneous extra byte in its output report layout.

---

### ISSUE 9: Feature Report 0x02 Size in HID Descriptor Section

**Severity:** Low -- internal inconsistency in DOC-04

DOC-04's Summary Table (line 487) says report `0x02` is **37 bytes**. But DOC-04's HID Descriptor analysis section (line 695) says:

> DOC-04, line 695: `+-- ID 0x02: 36 bytes, Usage 0x24 (Vendor 0xFF00) [Calibration]`

Similarly, report `0x04`:
- Summary Table (line 488): **37 bytes**
- HID Descriptor (line 694): **36 bytes**

**Verdict:** The HID descriptor defines the *data payload* size (excluding the report ID byte), while the Summary Table includes the Report ID. Both are technically correct but use different conventions. This should be explicitly stated. The HID descriptor section should note that sizes listed are payload-only (excluding the 1-byte Report ID prefix).

---

### ISSUE 10: BT Reduced Report 0x01 -- Calibration Read Triggers Mode Switch

**Severity:** Low -- conflicting information about which report triggers the switch

DOC-01 line 822 says:

> `A host must read feature report 0x02 (USB) or 0x05 (BT) to trigger the controller to switch to extended 0x11 reports.`

DOC-04 line 536 says:

> `Reading it on Bluetooth triggers the switch from basic input report (0x01, 9 bytes) to extended input reports (0x11, 78 bytes).`

Note DOC-04 says "9 bytes" for the basic report here, but earlier said "10 bytes" at line 952. This is an internal inconsistency in DOC-04.

---

### ISSUE 11: CRC-32 Polynomial Notation

**Severity:** Informational -- not a true contradiction

DOC-01 line 225 uses the **normal** representation:

> `| CRC-32 Integrity | Polynomial 0x4C11DB7 |`

Note: this is missing the leading `0` -- it should be `0x04C11DB7`.

DOC-01 line 576:

> `CRC-32 checksum (polynomial 0x04C11DB7)`

DOC-04 line 893:

> `Polynomial | 0xEDB88320 (reversed representation of 0x04C11DB7)`

DOC-05 line 768:

> `Polynomial | 0xEDB88320 (reflected) / 0x04C11DB7 (normal)`

**Verdict:** DOC-01 line 225 writes `0x4C11DB7` (missing leading zero) instead of `0x04C11DB7`. This is technically the same value but could confuse readers. DOC-04 and DOC-05 are precise and consistent.

---

### ISSUE 12: BT Report Rate Contradictions

**Severity:** Medium -- could affect timing-sensitive code

DOC-01 line 195:

> `~125 Hz (8 ms) single controller`

DOC-05 lines 142-146:

> `| 1 | ~800 Hz (1.25 ms) | ~400 Hz (2.50 ms) | ~125 Hz (8 ms) |`
>
> `Typical report interval is approximately 1.3 ms with occasional gaps reaching 15 ms due to Bluetooth scheduling. This is notably faster than USB mode (~4 ms / 250 Hz).`

DOC-05 line 1164:

> `| Rate | ~250 Hz (4 ms) | ~800 Hz (1.25 ms) single controller |`

**Verdict:** DOC-01 says BT is ~125 Hz. DOC-05 says BT can be ~800 Hz (when both input and output are active) but the input-only rate is indeed ~125 Hz. The ~800 Hz figure is the combined input+output rate, not the input-only rate. DOC-01 is correct for input-only polling but DOC-05 provides the complete picture. The DOC-05 latency table at line 1092 also claims BT latency is ~1.25 ms (lower than USB), which contradicts DOC-01's implied higher-latency BT. Both can be true depending on the scenario, but the discrepancy is not explained.

---

### ISSUE 13: Authentication Feature Report Sizes

**Severity:** Low

DOC-01 lines 363-366:

> ```
> | 240 | 0xF0 | 64 | Authentication challenge data |
> | 241 | 0xF1 | 64 | Authentication response / key data |
> | 242 | 0xF2 | 16 | Authentication ready status |
> ```

DOC-04 lines 527-529:

> ```
> | 0xF0 | 64 | GET/SET | ... | Authentication challenge |
> | 0xF1 | 64 | GET/SET | ... | Authentication response |
> | 0xF2 | 16 | GET | ... | Authentication status |
> ```

DOC-05 lines 1195-1197:

> ```
> | Auth Challenge | -- | 0xF0 | -- | 65 bytes | Yes |
> | Auth Response | -- | 0xF1 | -- | 65 bytes | Yes |
> | Auth Status | -- | 0xF2 | -- | 17 bytes | Yes |
> ```

**Verdict:** DOC-01 and DOC-04 say `0xF0`/`0xF1` are 64 bytes and `0xF2` is 16 bytes. DOC-05 says they are 65 bytes and 17 bytes respectively for BT. The +1 difference is likely the Report ID byte (DOC-01/DOC-04 include it; or DOC-05 adds +4 for CRC and subtracts differently). Actually, looking at DOC-05's auth section more carefully (lines 957-963), report `0xF0` over BT is 64 bytes total (bytes [0-63], with [60-63] being CRC). The 65-byte figure in DOC-05's feature report comparison table (line 1195) appears inconsistent with its own detailed description at line 957.

---

## Ambiguities (Not Contradictions, But Unclear)

### AMBIGUITY 1: "Size" Convention -- With or Without Report ID

Across all three documents, report sizes are sometimes stated including the Report ID byte and sometimes excluding it. For example:

- DOC-04 line 533: "37 bytes (1 byte Report ID + 36 bytes data)" -- explicitly inclusive
- DOC-04 HID Descriptor section line 695: "36 bytes" -- exclusive
- DOC-01 line 198: "36 bytes" for USB calibration -- exclusive
- DOC-01 line 307: "37" for report `0x02` -- inclusive

**Recommendation:** Establish a convention (preferably "size always includes Report ID") and apply it uniformly across all documents.

### AMBIGUITY 2: ds4drv hidraw Slice Offset

DOC-05 lines 370-373 shows ds4drv stripping bytes from BT hidraw reports:

```python
if self.type == "bluetooth":
    buf = zero_copy_slice(self.buf, 2)
```

This slices off **2 bytes** (Report ID + first flag byte), but the text at line 351 says the offset is "+2 bytes" (comparing BT byte indices to USB byte indices). Since the hidraw buffer starts with Report ID `0x11`, slicing off 2 bytes means the first byte in the resulting buffer would be BT byte [2] (BT Flags 2), which maps to... nothing in USB. The actual USB parser expects byte [0] to be the Report ID `0x01`. This implies the ds4drv parser may start from byte [1] (skipping Report ID), or the slice offset is actually meant to skip bytes [0-1] to align with USB bytes [1+]. The document does not fully explain this alignment.

### AMBIGUITY 3: Touchpad Physical Size

DOC-04 line 326:

> `~38.6 mm x ~19.1 mm`

DOC-01 line 693:

> `~62 x 28 mm physical area`

**Verdict:** These are very different physical dimensions for the same touchpad. One of these is likely wrong. The ~62 x 28 mm figure from DOC-01 aligns better with the actual physical DS4 touchpad dimensions.

### AMBIGUITY 4: BT Output Report -- "Legacy" Designation

DOC-01 labels the 78-byte BT output report as "legacy" (line 585: "Bluetooth Output Report 0x11 Byte Map (78 bytes, legacy)"), while DOC-04 and DOC-05 treat it as the current/standard format. The term "legacy" is unexplained.

### AMBIGUITY 5: Feature Report 0x80 -- Direction and Purpose

DOC-04 line 496:

> `| 0x80 | 7 | GET/SET | ... | Unknown |`

DOC-05 line 1193:

> `| MAC Address (write) | 0x13 / 0x80 | -- | 23 bytes | -- | -- |`

DOC-01 line 323:

> `| 128 | 0x80 | 7 | Controller hardware/firmware version info |`

Three different purposes are attributed to report `0x80`: "Unknown" (DOC-04), "MAC Address write" (DOC-05), and "hardware/firmware version info" (DOC-01).

---

## Consistent Items (What's Good)

### VID/PID Values
All three documents agree on:
- Sony VID: `0x054C`
- DS4 v1 PID: `0x05C4`
- DS4 v2 PID: `0x09CC`
- Dongle PID: `0x0BA0`
- Dongle DFU PID: `0x0BA1`

### USB Input Report 0x01 Byte Layout
DOC-01 (lines 444-505) and DOC-04 (lines 65-103) agree on all byte offsets for the USB input report. Every field position matches exactly between the two documents.

### Button Bitmask Layout
All three documents agree on the exact button bitmask layout:
- Byte 5 (USB): D-Pad [3:0], Square [4], Cross [5], Circle [6], Triangle [7]
- Byte 6 (USB): L1 [0], R1 [1], L2 [2], R2 [3], Share [4], Options [5], L3 [6], R3 [7]
- Byte 7 (USB): PS [0], Touchpad Click [1], Counter [7:2]

### USB Output Report 0x05 Byte Layout
DOC-01 (lines 507-531) and DOC-04 (lines 378-397) agree on all byte offsets for the USB output report.

### CRC-32 Algorithm Parameters
All documents that specify CRC parameters agree:
- Polynomial: `0xEDB88320` (reflected) / `0x04C11DB7` (normal)
- Seed: `0xFFFFFFFF`
- Final XOR: `0xFFFFFFFF`
- Output prefix: `0xA2` for output reports, `0xA1` for input reports
- CRC stored as little-endian uint32 in last 4 bytes

### CRC Prefix Bytes
DOC-04 (lines 903-912) and DOC-05 (lines 791-796) agree completely on the CRC prefix bytes:
- Input: `0xA1`
- Output: `0xA2`
- Feature GET: `0xA3`
- Feature SET: `0x53`

### BT-to-USB Offset for Input Fields (+2 in hidraw view)
DOC-04 and DOC-05 consistently state that BT input fields are at USB offset + 2 when using hidraw. The complete BT byte map in DOC-05 (lines 381-424) correctly maps every field to its USB equivalent with a consistent +2 offset.

### BT Output Report Field Mapping (+2 offset)
DOC-05's output comparison table (lines 599-610) correctly shows every USB output field shifted by +2 in the BT report.

### Touchpad Data Format
All documents agree on the touchpad encoding:
- Active flag: bit 7 (inverted: 0 = touching, 1 = not touching)
- Tracking ID: bits 6:0
- X: 12-bit (0-1919)
- Y: 12-bit (0-942)
- Encoding: X[7:0] in byte 1, X[11:8] in byte 2 bits [3:0], Y[3:0] in byte 2 bits [7:4], Y[11:4] in byte 3

### IMU Data Layout
All documents agree that gyroscope data is at USB bytes 13-18 (three int16 LE values) and accelerometer data is at USB bytes 19-24 (three int16 LE values).

### Battery/Status Byte Layout
DOC-01, DOC-04, and DOC-05 all agree that byte 30 (USB) / byte 32 (BT) contains:
- Battery level in bits [3:0]
- Cable connected in bit [4]
- Headphones in bit [5]
- Microphone in bit [6]

### Authentication Reports
All documents agree on the basic authentication flow (0xF0 for challenge, 0xF1 for response, 0xF2 for status) and that authentication is not required for PC/Mac usage.

---

## Recommendations

1. **Standardize size conventions:** All report sizes should consistently include the Report ID byte, with a parenthetical note for payload-only size (e.g., "37 bytes (Report ID + 36 bytes payload)").

2. **Resolve calibration field ordering (ISSUE 5):** This is the highest-priority fix. Check against the Linux kernel `hid-sony.c` or `hid-playstation.c` to determine whether gyro calibration fields are grouped by axis (Plus/Minus per axis) or grouped by polarity (all Plus, then all Minus).

3. **Standardize BT report layer perspective:** Always state whether a byte map uses the hidraw view or raw L2CAP view. Preferably show both, as DOC-05 does.

4. **Fix DOC-01 BT output report byte map (ISSUE 8):** Remove or explain the extra byte at position [3] that is not present in DOC-04 or DOC-05.

5. **Reconcile BT report rates (ISSUE 12):** Add context to DOC-01's "125 Hz" claim, noting that this is the input-only rate and that bidirectional communication can achieve higher throughput.

6. **Fix the polynomial typo (ISSUE 11):** Change `0x4C11DB7` to `0x04C11DB7` in DOC-01 line 225.

7. **Resolve touchpad physical dimensions (AMBIGUITY 3):** Verify which measurement is correct and update the other.

---

*Review completed 2026-02-27. All line references are to the documents as read on this date.*
