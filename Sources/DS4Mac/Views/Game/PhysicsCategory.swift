// PhysicsCategory.swift — Bitmask categories for SceneKit physics contact detection.
// Used by all game entities (ship, aliens, lasers, missiles) for collision filtering.

import Foundation

enum PhysicsCategory {
    static let player:  Int = 1 << 0  // 1
    static let alien:   Int = 1 << 1  // 2
    static let laser:   Int = 1 << 2  // 4
    static let missile: Int = 1 << 3  // 8
}
