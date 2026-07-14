//
//  activity.swift
//  Stats
//

import Cocoa
import Kit

internal final class DiskActivityTimelineChart: NSView {
    private var points: [DiskActivityTimelinePoint] = []
    private var readColor: NSColor = .systemBlue
    private var writeColor: NSColor = .systemRed

    init() {
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.canDrawSubviewsIntoLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(points: [DiskActivityTimelinePoint], readColor: NSColor, writeColor: NSColor) {
        self.points = points
        self.readColor = readColor
        self.writeColor = writeColor
        self.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let content = self.bounds.insetBy(dx: 2, dy: 4)
        guard content.width > 1, content.height > 1 else { return }

        NSColor.separatorColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(rect: NSRect(x: content.minX, y: content.minY, width: content.width, height: 1)).fill()

        let maxTotal = self.points.map(\.total).max() ?? 0
        guard maxTotal > 0 else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            let value = localizedString("No activity data yet") as NSString
            let size = value.size(withAttributes: attrs)
            value.draw(
                at: NSPoint(x: content.midX - size.width / 2, y: content.midY - size.height / 2),
                withAttributes: attrs
            )
            return
        }

        let gap: CGFloat = 2
        let barCount = max(1, self.points.count)
        let availableWidth = max(1, content.width - CGFloat(barCount - 1) * gap)
        let barWidth = max(1, availableWidth / CGFloat(barCount))

        for (idx, point) in self.points.enumerated() where point.total > 0 {
            let totalRatio = CGFloat(Double(point.total) / Double(maxTotal))
            let totalHeight = max(1, content.height * totalRatio)
            let readRatio = CGFloat(Double(point.read) / Double(point.total))
            let readHeight = totalHeight * readRatio
            let writeHeight = totalHeight - readHeight
            let x = content.minX + CGFloat(idx) * (barWidth + gap)
            var y = content.minY

            if readHeight > 0 {
                let rect = NSRect(x: x, y: y, width: barWidth, height: readHeight)
                self.readColor.withAlphaComponent(0.85).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
                y += readHeight
            }

            if writeHeight > 0 {
                let rect = NSRect(x: x, y: y, width: barWidth, height: writeHeight)
                self.writeColor.withAlphaComponent(0.85).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            }
        }
    }
}

internal struct DiskActivityProcessDisplayRow {
    let name: String
    let read: Int64
    let write: Int64
    let total: Int64
    let share: Double
    let color: NSColor
    let tooltip: String?
    let copyText: String?

    init(process: DiskActivityProcessSummary) {
        self.name = process.name
        self.read = process.read
        self.write = process.write
        self.total = process.total
        self.share = process.share
        self.color = .labelColor
        var details = [
            localizedString("Disk activity is local, not cloud upload"),
            localizedString("Disk activity source is process counters"),
            "\(localizedString("Read")): \(Units(bytes: process.read).getReadableMemory())",
            "\(localizedString("Write")): \(Units(bytes: process.write).getReadableMemory())",
            "\(localizedString("Process ID")): \(process.pid)"
        ]
        if let bundleIdentifier = process.bundleIdentifier, !bundleIdentifier.isEmpty {
            details.append("\(localizedString("Bundle ID")): \(bundleIdentifier)")
        }
        if let executablePath = process.executablePath, !executablePath.isEmpty {
            details.append("\(localizedString("Executable")): \(executablePath)")
        }
        details.append(localizedString("Past exact files cannot be reconstructed"))
        self.copyText = details.joined(separator: "\n")
        self.tooltip = (details + [localizedString("Right-click to copy process details")]).joined(separator: "\n")
    }

    init(name: String, read: Int64, write: Int64, shareDenominator: Int64, color: NSColor, tooltip: String?) {
        self.name = name
        self.read = read
        self.write = write
        self.total = diskActivitySaturatingAdd(read, write)
        self.share = shareDenominator == 0 ? 0 : Double(self.total) / Double(shareDenominator)
        self.color = color
        self.tooltip = tooltip
        self.copyText = nil
    }
}

internal final class DiskActivityProcessTable: NSStackView {
    private let maxRows: Int = diskActivityExpandedProcessLimit + 2
    private var rowViews: [DiskActivityProcessRow] = []

    init() {
        super.init(frame: .zero)
        self.orientation = .vertical
        self.alignment = .width
        self.distribution = .fill
        self.spacing = 2
        self.translatesAutoresizingMaskIntoConstraints = false

        self.addArrangedSubview(DiskActivityProcessRow.header())
        for _ in 0..<self.maxRows {
            let row = DiskActivityProcessRow()
            self.rowViews.append(row)
            self.addArrangedSubview(row)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setRows(_ rows: [DiskActivityProcessDisplayRow]) {
        for (idx, view) in self.rowViews.enumerated() {
            if idx < rows.count {
                view.update(rows[idx])
                view.isHidden = false
            } else {
                view.reset()
                view.isHidden = true
            }
        }
    }
}

private final class DiskActivityProcessRow: NSView {
    private static let headerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private static let rowFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let rowHeight: CGFloat = 20
    private static let metricColumnWidth: CGFloat = 64
    private static let shareColumnWidth: CGFloat = 40
    private static let columnSpacing: CGFloat = 1

    private let isHeader: Bool
    private var share: Double = 0
    private var shareColor: NSColor = .clear
    private var copyText: String?

    private let nameField = LabelField("-")
    private let readField = LabelField("-")
    private let writeField = LabelField("-")
    private let totalField = LabelField("-")
    private let shareField = LabelField("-")

    init(header: Bool = false) {
        self.isHeader = header
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true

        [self.nameField, self.readField, self.writeField, self.totalField, self.shareField].forEach { field in
            field.font = header ? Self.headerFont : Self.rowFont
            field.textColor = header ? .secondaryLabelColor : .labelColor
            field.lineBreakMode = .byTruncatingTail
            field.translatesAutoresizingMaskIntoConstraints = false
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        self.nameField.alignment = .left
        self.nameField.lineBreakMode = .byTruncatingMiddle
        self.nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.readField.alignment = .right
        self.writeField.alignment = .right
        self.totalField.alignment = .right
        self.shareField.alignment = .right

        [self.nameField, self.readField, self.writeField, self.totalField, self.shareField].forEach(self.addSubview)

        NSLayoutConstraint.activate([
            self.nameField.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.nameField.centerYAnchor.constraint(equalTo: self.centerYAnchor),

            self.readField.leadingAnchor.constraint(equalTo: self.nameField.trailingAnchor, constant: Self.columnSpacing),
            self.readField.widthAnchor.constraint(equalToConstant: Self.metricColumnWidth),
            self.readField.centerYAnchor.constraint(equalTo: self.centerYAnchor),

            self.writeField.leadingAnchor.constraint(equalTo: self.readField.trailingAnchor, constant: Self.columnSpacing),
            self.writeField.widthAnchor.constraint(equalToConstant: Self.metricColumnWidth),
            self.writeField.centerYAnchor.constraint(equalTo: self.centerYAnchor),

            self.totalField.leadingAnchor.constraint(equalTo: self.writeField.trailingAnchor, constant: Self.columnSpacing),
            self.totalField.widthAnchor.constraint(equalToConstant: Self.metricColumnWidth),
            self.totalField.centerYAnchor.constraint(equalTo: self.centerYAnchor),

            self.shareField.leadingAnchor.constraint(equalTo: self.totalField.trailingAnchor, constant: Self.columnSpacing),
            self.shareField.widthAnchor.constraint(equalToConstant: Self.shareColumnWidth),
            self.shareField.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.shareField.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func header() -> DiskActivityProcessRow {
        let row = DiskActivityProcessRow(header: true)
        row.nameField.stringValue = localizedString("Process")
        row.readField.stringValue = localizedString("Read")
        row.writeField.stringValue = localizedString("Write")
        row.totalField.stringValue = localizedString("Total")
        row.shareField.stringValue = localizedString("Share")
        return row
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !self.isHeader, self.share > 0 else { return }

        let shareWidth = CGFloat(max(0, min(1, self.share))) * self.bounds.width
        guard shareWidth > 1 else { return }

        let rect = NSRect(x: 0, y: 1, width: shareWidth, height: max(0, self.bounds.height - 2))
        self.shareColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
    }

    func update(_ row: DiskActivityProcessDisplayRow) {
        self.nameField.stringValue = row.name
        self.nameField.toolTip = row.name
        self.nameField.textColor = row.color
        self.readField.stringValue = Units(bytes: row.read).getReadableMemory()
        self.writeField.stringValue = Units(bytes: row.write).getReadableMemory()
        self.totalField.stringValue = Units(bytes: row.total).getReadableMemory()
        self.shareField.stringValue = String(format: "%.0f%%", row.share * 100)
        self.share = row.share
        self.shareColor = row.write >= row.read ? NSColor.systemRed : NSColor.systemBlue
        self.toolTip = row.tooltip
        self.copyText = row.copyText
        self.needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard !self.isHeader, let copyText, !copyText.isEmpty else {
            return super.menu(for: event)
        }
        let menu = NSMenu()
        let item = NSMenuItem(
            title: localizedString("Copy process details"),
            action: #selector(self.copyProcessDetails(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = copyText
        menu.addItem(item)
        return menu
    }

    @objc private func copyProcessDetails(_ sender: NSMenuItem) {
        guard let copyText = sender.representedObject as? String, !copyText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(copyText, forType: .string)
    }

    func reset() {
        [self.nameField, self.readField, self.writeField, self.totalField, self.shareField].forEach {
            $0.stringValue = "-"
            $0.toolTip = nil
        }
        self.nameField.textColor = .labelColor
        self.share = 0
        self.copyText = nil
        self.toolTip = nil
        self.needsDisplay = true
    }
}
