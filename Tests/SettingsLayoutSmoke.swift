//
//  SettingsLayoutSmoke.swift
//  Tests
//
//  Created by AgentHits on 04/07/2026.
//

import Cocoa
import XCTest
import Kit

@MainActor
enum SettingsLayoutSmoke {
    private static let sizes = [
        NSSize(width: 360, height: 900),
        NSSize(width: 900, height: 900)
    ]

    static func assertSettingsLayout(
        name: String,
        makeView: () -> NSView,
        expectedLabels: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for size in sizes {
            let settings = makeView()
            settings.translatesAutoresizingMaskIntoConstraints = false

            let container = NSView(frame: NSRect(origin: .zero, size: size))
            container.addSubview(settings)
            NSLayoutConstraint.activate([
                settings.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                settings.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                settings.topAnchor.constraint(equalTo: container.topAnchor)
            ])

            container.layoutSubtreeIfNeeded()
            settings.layoutSubtreeIfNeeded()

            let labels = self.textLabels(in: settings)
            for key in expectedLabels {
                let expected = localizedString(key)
                XCTAssertTrue(
                    labels.contains(expected),
                    "\(name) settings at width \(size.width) missing label: \(expected)",
                    file: file,
                    line: line
                )
            }

            let rows = self.allSubviews(in: settings).compactMap { $0 as? PreferencesRow }
            XCTAssertFalse(rows.isEmpty, "\(name) settings at width \(size.width) has no preference rows", file: file, line: line)

            for row in rows where !row.isHidden {
                let frame = row.convert(row.bounds, to: settings)
                XCTAssertTrue(frame.width.isFinite && frame.height.isFinite, "\(name) has non-finite row frame", file: file, line: line)
                XCTAssertGreaterThan(frame.width, 0, "\(name) row width is zero at width \(size.width)", file: file, line: line)
                XCTAssertGreaterThan(frame.height, 0, "\(name) row height is zero at width \(size.width)", file: file, line: line)
                XCTAssertGreaterThanOrEqual(frame.minX, -0.5, "\(name) row starts outside container at width \(size.width)", file: file, line: line)
                XCTAssertLessThanOrEqual(frame.maxX, size.width + 0.5, "\(name) row exceeds container at width \(size.width)", file: file, line: line)
            }

            let controls = self.allSubviews(in: settings).filter { view in
                view is NSPopUpButton || view is NSSwitch || view is NSTextField
            }
            XCTAssertFalse(controls.isEmpty, "\(name) settings at width \(size.width) has no controls", file: file, line: line)
            for control in controls where !control.isHidden {
                let frame = control.convert(control.bounds, to: settings)
                XCTAssertLessThanOrEqual(frame.maxX, size.width + 0.5, "\(name) control exceeds container at width \(size.width)", file: file, line: line)
            }
        }
    }

    private static func textLabels(in root: NSView) -> Set<String> {
        Set(allSubviews(in: root).compactMap { view in
            guard let field = view as? NSTextField, !field.stringValue.isEmpty else { return nil }
            return field.stringValue
        })
    }

    private static func allSubviews(in root: NSView) -> [NSView] {
        root.subviews + root.subviews.flatMap { allSubviews(in: $0) }
    }
}
