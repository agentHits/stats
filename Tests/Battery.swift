//
//  Battery.swift
//  Tests
//
//  Created by AgentHits on 03/07/2026.
//

import XCTest
import Kit
@testable import Battery

class BatteryTests: XCTestCase {
    func testProcessReaderParseProcessWithSpacesAndParentheses() throws {
        let process = try XCTUnwrap(ProcessReader.parseProcess("888888  Codex (Renderer) 34.5"))

        XCTAssertEqual(process.pid, 888888)
        XCTAssertEqual(process.name, "Codex (Renderer)")
        XCTAssertEqual(process.usage, 34.5)
    }

    func testProcessReaderParseProcessesUsesLatestTopSample() throws {
        let output = """
        Processes: 743 total

        PID    COMMAND          POWER
        111111 stale            0.0
        222222 older sample     0.0

        Processes: 743 total

        PID    COMMAND          POWER
        777777 Telegram         77.6
        888888 Codex (Renderer) 34.5
        999999 Google Chrome He 27.0
        """

        let processes = ProcessReader.parseProcesses(output, limit: 2)

        XCTAssertEqual(processes.map { $0.pid }, [777777, 888888])
        XCTAssertEqual(processes.map { $0.name }, ["Telegram", "Codex (Renderer)"])
        XCTAssertEqual(processes.map { $0.usage }, [77.6, 34.5])
    }

    func testProcessReaderParseProcessesRejectsEmptyAndMalformedRows() throws {
        XCTAssertTrue(ProcessReader.parseProcesses("", limit: 2).isEmpty)
        XCTAssertTrue(ProcessReader.parseProcesses("PID COMMAND POWER\nbad row", limit: 2).isEmpty)
        XCTAssertTrue(ProcessReader.parseProcesses("777777 Telegram 10.0", limit: 0).isEmpty)
    }

    func testProcessReaderParseProcessesSortsAndLimitsLatestSample() throws {
        let output = """
        PID COMMAND POWER
        111111 low 1.0
        222222 high 9.0
        333333 mid 5.0
        """

        let processes = ProcessReader.parseProcesses(output, limit: 2)

        XCTAssertEqual(processes.map { $0.pid }, [222222, 333333])
    }
}
