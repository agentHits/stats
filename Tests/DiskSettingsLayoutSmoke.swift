//
//  DiskSettingsLayoutSmoke.swift
//  Tests
//
//  Created by AgentHits on 04/07/2026.
//

import XCTest
import Kit
@testable import Disk

@MainActor
final class DiskSettingsLayoutSmokeTests: XCTestCase {
    func testSettingsFitNarrowAndWideContainers() throws {
        try SettingsLayoutSmoke.assertSettingsLayout(
            name: "Disk",
            makeView: {
                let settings = Settings(.disk)
                settings.load(widgets: [.speed, .text])
                return settings
            },
            expectedLabels: [
                "Update interval",
                "Number of top processes",
                "Disk to show",
                "Show removable disks",
                "SMART data",
                "Text widget value"
            ]
        )
    }
}
