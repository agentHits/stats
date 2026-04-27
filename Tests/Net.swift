//
//  Net.swift
//  Tests
//
//  Created by Serhiy Mytrovtsiy on 27/04/2026.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import XCTest
@testable import Net

class Net: XCTestCase {
    func testResetTotalUsageResetsCountersAndStartDate() throws {
        var usage = Network_Usage()
        usage.total = Bandwidth(upload: 123, download: 456)
        usage.totalSince = Date(timeIntervalSince1970: 100)

        let resetDate = Date(timeIntervalSince1970: 200)
        usage.resetTotal(since: resetDate)

        XCTAssertEqual(usage.total.upload, 0)
        XCTAssertEqual(usage.total.download, 0)
        XCTAssertEqual(usage.totalSince, resetDate)
    }

    func testNetworkUsageDecodesSavedValuesWithoutTotalSince() throws {
        let data = """
        {
            "bandwidth": { "upload": 0, "download": 0 },
            "total": { "upload": 1024, "download": 2048 },
            "laddr": {},
            "raddr": {},
            "dns": [],
            "status": true,
            "wifiDetails": {}
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(Network_Usage.self, from: data)

        XCTAssertEqual(usage.total.upload, 1024)
        XCTAssertEqual(usage.total.download, 2048)
        XCTAssertLessThan(abs(usage.totalSince.timeIntervalSinceNow), 5)
    }
}
