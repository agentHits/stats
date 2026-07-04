//
//  RAMSettingsLayoutSmoke.swift
//  Tests
//
//  Created by AgentHits on 04/07/2026.
//

import XCTest
import Kit
@testable import RAM

@MainActor
final class RAMSettingsLayoutSmokeTests: XCTestCase {
    func testSettingsFitNarrowAndWideContainers() throws {
        try SettingsLayoutSmoke.assertSettingsLayout(
            name: "RAM",
            makeView: {
                let settings = Settings(.RAM)
                settings.load(widgets: [.barChart, .text])
                return settings
            },
            expectedLabels: [
                "Update interval",
                "Update interval for top processes",
                "Combined processes",
                "Number of top processes",
                "Split the value (App/Wired/Compressed)",
                "Text widget value"
            ]
        )
    }
}
