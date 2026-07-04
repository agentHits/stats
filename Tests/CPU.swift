//
//  CPU.swift
//  Tests
//
//  Created by AgentHits on 04/07/2026.
//

import XCTest
import Kit
@testable import CPU

final class CPUTests: XCTestCase {
    private var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Stats.xcodeproj").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    func testProcessReaderParseProcessHandlesCommaDecimalAndSpaces() throws {
        let process = try XCTUnwrap(ProcessReader.parseProcess("1234  12,5  Codex Helper"))

        XCTAssertEqual(process.pid, 1234)
        XCTAssertEqual(process.name, "Codex Helper")
        XCTAssertEqual(process.usage, 12.5)
    }

    func testProcessReaderParseProcessRejectsMalformedRows() throws {
        XCTAssertNil(ProcessReader.parseProcess(""))
        XCTAssertNil(ProcessReader.parseProcess("PID  %CPU COMMAND"))
        XCTAssertNil(ProcessReader.parseProcess("1234 not-a-number Safari"))
        XCTAssertNil(ProcessReader.parseProcess("1234 12.5"))
    }

    func testProcessReaderParseProcessesSkipsHeaderAndLimitsRows() throws {
        let output = """
          PID  %CPU COMMAND
          111  8.0  first helper
          222  7.0  second helper
          333  6.0  third helper
        """

        let processes = ProcessReader.parseProcesses(output, limit: 2)

        XCTAssertEqual(processes.map { $0.pid }, [111, 222])
        XCTAssertEqual(processes.map { $0.name }, ["first helper", "second helper"])
    }

    func testTopProcessCommandOutputCarriesProcessResult() throws {
        let output = TopProcessCommandOutput(stdout: "out", stderr: "err", terminationStatus: 7)

        XCTAssertEqual(output.stdout, "out")
        XCTAssertEqual(output.stderr, "err")
        XCTAssertEqual(output.terminationStatus, 7)
    }

    func testProcessReadersDisableReaderPersistence() throws {
        for path in [
            "Modules/CPU/main.swift",
            "Modules/RAM/main.swift",
            "Modules/Battery/main.swift"
        ] {
            let text = try String(contentsOf: self.repoRoot.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(text.contains("ProcessReader(."), path)
            XCTAssertTrue(text.contains("cache: false"), path)
        }
    }

    func testReaderCacheFalseGuardsDBWrites() throws {
        let text = try String(
            contentsOf: self.repoRoot.appendingPathComponent("Kit/module/reader.swift"),
            encoding: .utf8
        )
        let guardedBlocks = [
            #"deinit {\#n        guard self.cache else { return }\#n        DB.shared.insert"#,
            #"guard self.cache else { return }\#n            if let ts = self.lastDBWrite"#,
            #"public func save(_ value: T) {\#n        guard self.cache else { return }\#n        DB.shared.insert"#
        ].map { $0.replacingOccurrences(of: #"\#n"#, with: "\n") }

        for block in guardedBlocks {
            XCTAssertTrue(text.contains(block), "Missing cache guard near DB write block:\n\(block)")
        }
    }
}
