//
//  DiskActivityHistory.swift
//  Tests
//
//  Created by OpenAI on 02/07/2026.
//

import XCTest
@testable import Disk

final class DiskActivityHistoryTests: XCTestCase {
    func testDiskActivitySummaryAggregatesSelectedDiskPeriod() throws {
        let store = DiskActivityHistoryStore(persistenceURL: nil)
        let now = Date(timeIntervalSince1970: 10_000)

        store.recordDisk(diskID: "main", read: 100, write: 50, at: now.addingTimeInterval(-120))
        store.recordDisk(diskID: "external", read: 1_000, write: 2_000, at: now.addingTimeInterval(-60))
        store.recordDisk(diskID: "main", read: 300, write: 400, at: now.addingTimeInterval(-30))

        let summary = store.summary(diskID: "main", period: .hour1, now: now)

        XCTAssertEqual(summary.read, 400)
        XCTAssertEqual(summary.write, 450)
        XCTAssertEqual(summary.total, 850)
        XCTAssertEqual(summary.peakRead, 300)
        XCTAssertEqual(summary.peakWrite, 400)
        XCTAssertEqual(summary.diskSampleCount, 2)
    }

    func testDiskActivitySummaryGroupsProcessesAndSortsByTotal() throws {
        let store = DiskActivityHistoryStore(persistenceURL: nil)
        let now = Date(timeIntervalSince1970: 10_000)
        var editor = Disk_process(pid: 100, name: "Editor", read: 100, write: 50)
        editor.bundleIdentifier = "com.example.editor"
        var editorHelper = Disk_process(pid: 101, name: "Editor Helper", read: 200, write: 100)
        editorHelper.bundleIdentifier = "com.example.editor"
        let backup = Disk_process(pid: 102, name: "Backup", read: 25, write: 300)

        store.recordProcesses([editor, editorHelper, backup], at: now)

        let summary = store.summary(diskID: nil, period: .hour1, sort: .total, limit: 10, now: now)

        XCTAssertEqual(summary.processSampleCount, 2)
        XCTAssertEqual(summary.processes.map(\.identity), ["com.example.editor", "Backup"])
        XCTAssertEqual(summary.processes[0].name, "Editor Helper")
        XCTAssertEqual(summary.processes[0].read, 300)
        XCTAssertEqual(summary.processes[0].write, 150)
        XCTAssertEqual(summary.processes[0].total, 450)
        XCTAssertEqual(summary.processes[0].share, Double(450) / Double(775), accuracy: 0.0001)

        let disabledSummary = store.summary(diskID: nil, period: .hour1, sort: .total, limit: 0, now: now)
        XCTAssertTrue(disabledSummary.processes.isEmpty)
    }

    func testDiskActivitySummarySortsProcessesByReadAndWrite() throws {
        let store = DiskActivityHistoryStore(persistenceURL: nil)
        let now = Date(timeIntervalSince1970: 10_000)
        let reader = Disk_process(pid: 100, name: "Reader", read: 500, write: 1)
        let writer = Disk_process(pid: 101, name: "Writer", read: 5, write: 400)
        let mixed = Disk_process(pid: 102, name: "Mixed", read: 300, write: 200)

        store.recordProcesses([reader, writer, mixed], at: now)

        let readSummary = store.summary(diskID: nil, period: .hour1, sort: .read, limit: 2, now: now)
        XCTAssertEqual(readSummary.processes.map(\.name), ["Reader", "Mixed"])

        let writeSummary = store.summary(diskID: nil, period: .hour1, sort: .write, limit: 2, now: now)
        XCTAssertEqual(writeSummary.processes.map(\.name), ["Writer", "Mixed"])
    }

    func testDiskActivityRetentionDropsRowsOlderThanSevenDays() throws {
        let store = DiskActivityHistoryStore(persistenceURL: nil)
        let now = Date(timeIntervalSince1970: 1_000_000)

        store.recordDisk(diskID: "main", read: 1_000, write: 2_000, at: now.addingTimeInterval(-DiskActivityPeriod.day7.interval - 60))
        store.recordDisk(diskID: "main", read: 10, write: 20, at: now.addingTimeInterval(-60))
        store.prune(now: now)

        let summary = store.summary(diskID: "main", period: .day7, now: now)

        XCTAssertEqual(summary.read, 10)
        XCTAssertEqual(summary.write, 20)
        XCTAssertEqual(summary.total, 30)
        XCTAssertEqual(summary.diskSampleCount, 1)
    }
}
