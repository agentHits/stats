//
//  BatterySettingsLayoutSmoke.swift
//  Tests
//
//  Created by AgentHits on 04/07/2026.
//

import XCTest
import Kit
@testable import Battery

@MainActor
final class BatterySettingsLayoutSmokeTests: XCTestCase {
    func testSettingsFitNarrowAndWideContainers() throws {
        try SettingsLayoutSmoke.assertSettingsLayout(
            name: "Battery",
            makeView: {
                let settings = Settings(.battery)
                settings.load(widgets: [.battery])
                return settings
            },
            expectedLabels: [
                "Number of top processes",
                "Time format"
            ]
        )
    }
}
