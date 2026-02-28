# Documentation Inventory Freeze

Review date: 2026-02-27
Scope owner: DS4 macOS documentation modernization

## Purpose

Freeze the authoritative documentation inventory before modernization edits.
This file defines:
- Existing baseline documents
- Required target documents
- Review artifacts used to track consistency closure

## Existing Baseline (Before Modernization)

### Core numbered docs
- `docs/01-DS4-Controller-Overview.md`
- `docs/02-Core-Bluetooth-APIs.md`
- `docs/03-USB-Driver-APIs.md`
- `docs/04-DS4-USB-Protocol.md`
- `docs/05-DS4-Bluetooth-Protocol.md`
- `docs/06-Light-Bar-Feature.md`
- `docs/07-Touchpad-Feature.md`
- `docs/08-Gyroscope-IMU-Feature.md`
- `docs/09-Audio-Streaming-Feature.md`
- `docs/10-macOS-Driver-Architecture.md`
- `docs/11-Rumble-Haptics-Feature.md`
- `docs/12-Battery-Power-Management.md`

### Existing review artifacts
- `docs/REVIEW-api-architecture-consistency.md`
- `docs/REVIEW-feature-consistency.md`
- `docs/REVIEW-protocol-consistency.md`

### Existing index
- `docs/README.md`

## Required Target Set (Post-Modernization)

### Update in place
- `docs/01-DS4-Controller-Overview.md`
- `docs/02-Core-Bluetooth-APIs.md`
- `docs/03-USB-Driver-APIs.md`
- `docs/04-DS4-USB-Protocol.md`
- `docs/05-DS4-Bluetooth-Protocol.md`
- `docs/06-Light-Bar-Feature.md`
- `docs/07-Touchpad-Feature.md`
- `docs/08-Gyroscope-IMU-Feature.md`
- `docs/09-Audio-Streaming-Feature.md`
- `docs/10-macOS-Driver-Architecture.md`
- `docs/11-Rumble-Haptics-Feature.md`
- `docs/12-Battery-Power-Management.md`

### Add new concept docs
- `docs/13-HIDDriverKit-Integration.md`
- `docs/14-System-Extensions-Framework.md`
- `docs/15-GameController-Framework.md`
- `docs/16-Companion-App-Architecture.md`
- `docs/17-Build-Distribution-Guide.md`
- `docs/18-Testing-Debugging-Guide.md`
- `docs/19-Migration-Guide.md`
- `docs/20-Troubleshooting-Common-Issues.md`

### Keep and update index
- `docs/README.md`

### Keep and reconcile review artifacts
- `docs/REVIEW-api-architecture-consistency.md`
- `docs/REVIEW-feature-consistency.md`
- `docs/REVIEW-protocol-consistency.md`

## Completion Definition for Inventory Freeze

Inventory freeze is complete when:
1. Every required file path above exists or is queued for creation.
2. Numbered docs are contiguous from 01 through 20.
3. `docs/README.md` reflects the same taxonomy.
4. Review artifacts are either resolved in place or superseded by consolidated findings.
