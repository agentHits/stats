//
//  RAM.swift
//  Tests
//
//  Created by Serhiy Mytrovtsiy on 16/04/2022.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2022 Serhiy Mytrovtsiy. All rights reserved.
//

import XCTest
import Darwin
import Kit
@testable import RAM

class RAM: XCTestCase {
    func testProcessReader_parseProcess() throws {
        var process = ProcessReader.parseProcess("3127  lldb-rpc-server  611M")
        XCTAssertEqual(process.pid, 3127)
        XCTAssertEqual(process.name, "lldb-rpc-server")
        XCTAssertEqual(process.usage, 611 * Double(1000 * 1000))
        
        process = ProcessReader.parseProcess("257   WindowServer     210M")
        XCTAssertEqual(process.pid, 257)
        XCTAssertEqual(process.name, "WindowServer")
        XCTAssertEqual(process.usage, 210 * Double(1000 * 1000))
        
        process = ProcessReader.parseProcess("7752  phpstorm         1819M")
        XCTAssertEqual(process.pid, 7752)
        XCTAssertEqual(process.name, "phpstorm")
        XCTAssertEqual(process.usage, 1819.0 / 1024 * 1000 * Double(1000 * 1000))
        
        process = ProcessReader.parseProcess("359   NotificationCent 62M")
        XCTAssertEqual(process.pid, 359)
        XCTAssertEqual(process.name, "NotificationCent")
        XCTAssertEqual(process.usage, 62 * Double(1000 * 1000))
        
        process = ProcessReader.parseProcess("623    SafariCloudHisto 1608K")
        XCTAssertEqual(process.pid, 623)
        XCTAssertEqual(process.name, "SafariCloudHisto")
        XCTAssertEqual(process.usage, (1608/1024) * Double(1000 * 1000))
        
        process = ProcessReader.parseProcess("174    WindowServer     1442M+ ")
        XCTAssertEqual(process.pid, 174)
        XCTAssertEqual(process.name, "WindowServer")
        XCTAssertEqual(process.usage, 1442 * Double(1000 * 1000))
        
        process = ProcessReader.parseProcess("329    Finder           488M+ ")
        XCTAssertEqual(process.pid, 329)
        XCTAssertEqual(process.name, "Finder")
        XCTAssertEqual(process.usage, 488 * Double(1000 * 1000))
        
        process = ProcessReader.parseProcess("7163* AutoCAD LT 2023  11G  ")
        XCTAssertEqual(process.pid, 7163)
        XCTAssertEqual(process.name, "AutoCAD LT 2023")
        XCTAssertEqual(process.usage, 11 * Double(1024 * 1000 * 1000))
    }
    
    func testKernelTask() throws {
        var process = ProcessReader.parseProcess("0      kernel_task      270M ")
        XCTAssertEqual(process.pid, 0)
        XCTAssertEqual(process.name, "kernel_task")
        XCTAssertEqual(process.usage, 270 * Double(1000 * 1000))
        
        process = ProcessReader.parseProcess("0     kernel_task      280M")
        XCTAssertEqual(process.pid, 0)
        XCTAssertEqual(process.name, "kernel_task")
        XCTAssertEqual(process.usage, 280 * Double(1000 * 1000))
    }
    
    func testSizes() throws {
        var process = ProcessReader.parseProcess("0  com.apple.Virtua 8463M")
        XCTAssertEqual(process.pid, 0)
        XCTAssertEqual(process.name, "com.apple.Virtua")
        XCTAssertEqual(process.usage, 8463.0 / 1024 * 1000 * 1000 * 1000)
        
        process = ProcessReader.parseProcess("0  Safari           658M")
        XCTAssertEqual(process.pid, 0)
        XCTAssertEqual(process.name, "Safari")
        XCTAssertEqual(process.usage, 658 * Double(1000 * 1000))
    }

    func testSwapProcessReader_parseProcess() throws {
        let process = try XCTUnwrap(SwapProcessReader.parseProcess("999999  com.docker.backe 2789M 1785M 120116"))
        XCTAssertEqual(process.pid, 999999)
        XCTAssertEqual(process.name, "com.docker.backe")
        XCTAssertEqual(process.memory, 2789.0 / 1024 * 1000 * 1000 * 1000)
        XCTAssertEqual(process.compressed, 1785.0 / 1024 * 1000 * 1000 * 1000)
        XCTAssertEqual(process.pageins, 120116)

        let spacedName = try XCTUnwrap(SwapProcessReader.parseProcess("39628  GitHub Desktop H 1204M 880M  357121"))
        XCTAssertEqual(spacedName.pid, 39628)
        XCTAssertEqual(spacedName.name, "GitHub Desktop H")
        XCTAssertEqual(spacedName.memory, 1204.0 / 1024 * 1000 * 1000 * 1000)
        XCTAssertEqual(spacedName.compressed, 880 * Double(1000 * 1000))
        XCTAssertEqual(spacedName.pageins, 357121)

        let kilobytes = try XCTUnwrap(SwapProcessReader.parseProcess("2002   fairplayd      3792K 2192K 495457"))
        XCTAssertEqual(kilobytes.pid, 2002)
        XCTAssertEqual(kilobytes.name, "fairplayd")
        XCTAssertEqual(kilobytes.memory, 3792.0 / 1024 * 1000 * 1000)
        XCTAssertEqual(kilobytes.compressed, 2192.0 / 1024 * 1000 * 1000)
        XCTAssertEqual(kilobytes.pageins, 495457)
    }

    func testProcessDisplayFiltersTopProcessesFrom50MB() throws {
        let visible = RAMProcessDisplay.visibleTopProcesses([
            TopProcess(pid: 1, name: "small", usage: 49 * 1000 * 1000),
            TopProcess(pid: 2, name: "edge", usage: 50 * 1000 * 1000),
            TopProcess(pid: 3, name: "large", usage: 150 * 1000 * 1000)
        ])

        XCTAssertEqual(visible.map { $0.pid }, [3, 2])
    }

    func testProcessReader_parseResidentProcess() throws {
        let process = try XCTUnwrap(ProcessReader.parseResidentProcess("agent 999999 51200 /Applications/Foo.app/Contents/MacOS/Foo"))
        XCTAssertEqual(process.pid, 999999)
        XCTAssertEqual(process.name, "Foo")
        XCTAssertEqual(process.usage, Double(51200 * 1024))
        XCTAssertEqual(process.owner, "agent")
    }

    func testProcessReader_parseResidentProcessHandlesSpacesAndMalformedRows() throws {
        let process = try XCTUnwrap(ProcessReader.parseResidentProcess("agent 999999 51200 GitHub Desktop Helper"))
        XCTAssertEqual(process.pid, 999999)
        XCTAssertEqual(process.name, "GitHub Desktop Helper")
        XCTAssertEqual(process.usage, Double(51200 * 1024))
        XCTAssertEqual(process.owner, "agent")

        XCTAssertNil(ProcessReader.parseResidentProcess(""))
        XCTAssertNil(ProcessReader.parseResidentProcess("agent not-a-pid 51200 Safari"))
        XCTAssertNil(ProcessReader.parseResidentProcess("agent 999999 not-rss Safari"))
        XCTAssertNil(ProcessReader.parseResidentProcess("agent 999999 51200"))
    }

    func testTopProcessDecodesCachedRowsWithoutOwner() throws {
        let data = try XCTUnwrap(#"{"pid":1,"name":"cached","usage":1024}"#.data(using: .utf8))
        let process = try JSONDecoder().decode(TopProcess.self, from: data)

        XCTAssertEqual(process.pid, 1)
        XCTAssertEqual(process.name, "cached")
        XCTAssertEqual(process.usage, 1024)
        XCTAssertNil(process.owner)
    }

    func testProcessReaderReadReturnsVisibleTopProcesses() throws {
        let hadProcessCount = Store.shared.exist(key: "RAM_processes")
        let previousProcessCount = Store.shared.int(key: "RAM_processes", defaultValue: 8)
        let hadCombinedProcesses = Store.shared.exist(key: "RAM_combinedProcesses")
        let previousCombinedProcesses = Store.shared.bool(key: "RAM_combinedProcesses", defaultValue: false)

        Store.shared.set(key: "RAM_processes", value: 15)
        Store.shared.set(key: "RAM_combinedProcesses", value: false)
        XCTAssertEqual(Store.shared.int(key: "RAM_processes", defaultValue: 8), 15)
        XCTAssertFalse(Store.shared.bool(key: "RAM_combinedProcesses", defaultValue: true))

        defer {
            if hadProcessCount {
                Store.shared.set(key: "RAM_processes", value: previousProcessCount)
            } else {
                Store.shared.remove("RAM_processes")
            }

            if hadCombinedProcesses {
                Store.shared.set(key: "RAM_combinedProcesses", value: previousCombinedProcesses)
            } else {
                Store.shared.remove("RAM_combinedProcesses")
            }
        }

        let expectation = self.expectation(description: "RAM ProcessReader returns visible processes")
        let reader = ProcessReader(.RAM, cache: false) { list in
            guard let list else { return }
            XCTAssertFalse(list.isEmpty)
            XCTAssertTrue(list.allSatisfy { $0.usage >= RAMProcessDisplay.minimumMemoryBytes })
            XCTAssertTrue(list.contains { $0.owner != nil })
            expectation.fulfill()
        }

        reader.read()
        wait(for: [expectation], timeout: 8)
    }

    func testProcessDisplayFiltersSwapProcessesFrom50MBMemory() throws {
        let visible = RAMProcessDisplay.visibleSwapProcesses([
            SwapProcess(pid: 1, name: "small", memory: 49 * 1000 * 1000, compressed: 900 * 1000 * 1000, pageins: 1),
            SwapProcess(pid: 2, name: "edge", memory: 50 * 1000 * 1000, compressed: 50 * 1000 * 1000, pageins: 2),
            SwapProcess(pid: 3, name: "large", memory: 150 * 1000 * 1000, compressed: 10 * 1000 * 1000, pageins: 3)
        ])

        XCTAssertEqual(visible.map { $0.pid }, [3, 2])
    }

    func testMemoryBreakdownUsesAppWiredAndCompressedMemory() throws {
        var stats = vm_statistics64()
        stats.internal_page_count = 100
        stats.purgeable_count = 10
        stats.wire_count = 20
        stats.compressor_page_count = 5
        stats.external_page_count = 30
        stats.active_count = 40
        stats.inactive_count = 50

        let pageSize = Double(4_096)
        let totalSize = Double(200) * pageSize
        let breakdown = UsageReader.memoryBreakdown(totalSize: totalSize, stats: stats, pageSize: pageSize)

        XCTAssertEqual(breakdown.app, Double(90) * pageSize)
        XCTAssertEqual(breakdown.wired, Double(20) * pageSize)
        XCTAssertEqual(breakdown.compressed, Double(5) * pageSize)
        XCTAssertEqual(breakdown.cache, Double(40) * pageSize)
        XCTAssertEqual(breakdown.used, Double(115) * pageSize)
        XCTAssertEqual(breakdown.free, Double(85) * pageSize)
    }

}
