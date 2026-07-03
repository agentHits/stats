//
//  preview.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 22/04/2026
//  Using Swift 6.0
//  Running on macOS 26.4
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Preview: PreviewWrapper {
    private var mainID: String? = nil
    
    private var circle: PieChartView? = nil
    private var bar: BarChartView? = nil
    private var chart: NetworkChartView? = nil
    
    private var mainNameField: NSButton? = nil
    private var mainFileSystemField: NSTextField? = nil
    private var mainSizeField: NSTextField? = nil
    private var usedField: NSTextField? = nil
    private var freeField: NSTextField? = nil
    
    private var readState: NSView? = nil
    private var writeState: NSView? = nil
    
    private var allDisks: PreferencesSection? = nil
    private var disks: NSGridView = {
        let grid = NSGridView(frame: .zero)
        grid.rowSpacing = Constants.Settings.margin
        grid.rowAlignment = .none
        grid.yPlacement = .center
        return grid
    }()
    private var diskRows: [String: DiskRow] = [:]
    
    private var initialized: Bool = false
    
    private var readColorState: SColor = .secondBlue
    private var readColor: NSColor { self.readColorState.additional as? NSColor ?? NSColor.systemRed }
    private var writeColorState: SColor = .secondRed
    private var writeColor: NSColor { self.writeColorState.additional as? NSColor ?? NSColor.systemBlue }
    private var reverseOrderState: Bool = false
    private var base: DataSizeBase {
        DataSizeBase(rawValue: Store.shared.string(key: "\(self.module.stringValue)_base", defaultValue: DataSizeBase.byte.rawValue)) ?? .byte
    }
    private var speedUnit: String {
        networkSpeedUnit(from: Store.shared.string(key: "\(self.module.stringValue)_speedUnit", defaultValue: NetworkSpeedUnitAuto)).key
    }
    private var processLimit: Int {
        min(6, max(0, Store.shared.int(key: "\(self.module.stringValue)_processes", defaultValue: 5)))
    }
    
    private var uri: URL? = nil
    private let finder: URL?
    
    private var readSpeedValueField: ValueField?
    private var writeSpeedValueField: ValueField?
    
    private var totalReadValueField: ValueField?
    private var totalWrittenValueField: ValueField?
    
    private var smartTotalReadValueField: ValueField?
    private var smartTotalWrittenValueField: ValueField?
    private var temperatureValueField: ValueField?
    private var healthValueField: ValueField?
    private var powerCyclesValueField: ValueField?
    private var powerOnHoursValueField: ValueField?
    
    private var activityPeriod: DiskActivityPeriod = .hour1
    private var activitySort: DiskActivityProcessSort = .total
    private var periodReadValueField: ValueField?
    private var periodWriteValueField: ValueField?
    private var periodTotalValueField: ValueField?
    private var periodPeakReadValueField: ValueField?
    private var periodPeakWriteValueField: ValueField?
    private var periodCoverageField: NSTextField?
    private var periodCoverageProgress: NSProgressIndicator?
    private var periodTopSourceValueField: ValueField?
    private var periodTimelineChart: DiskActivityTimelineChart?
    private var periodProcessTable: DiskActivityProcessTable?
    private lazy var periodCoverageTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    public init(_ module: ModuleType) {
        self.finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Finder")
        
        super.init(type: module)

        self.alignment = .width
        
        self.loadColors()
        self.activityPeriod = DiskActivityPeriod(
            rawValue: Store.shared.string(key: "\(self.module.stringValue)_activityPeriod", defaultValue: self.activityPeriod.rawValue)
        ) ?? self.activityPeriod
        self.activitySort = DiskActivityProcessSort(
            rawValue: Store.shared.string(key: "\(self.module.stringValue)_activitySort", defaultValue: self.activitySort.rawValue)
        ) ?? self.activitySort
        
        self.addArrangedSubview(PreferencesSection([self.usageView()]))
        
        let allDisks = PreferencesSection(title: localizedString("All disks"), subtitle: "", [self.disks])
        allDisks.isHidden = true
        self.addArrangedSubview(allDisks)
        self.allDisks = allDisks
        
        self.addArrangedSubview(PreferencesSection(title: localizedString("Read / Write history"), [self.historyView()]))
        
        let splitView = NSStackView()
        splitView.orientation = .horizontal
        splitView.distribution = .fillEqually
        splitView.alignment = .top
        splitView.addArrangedSubview(PreferencesSection(title: localizedString("Details"), [self.detailsView()]))
        splitView.addArrangedSubview(PreferencesSection(title: localizedString("SMART"), [self.smartView()]))
        
        self.addArrangedSubview(splitView)
        let periodActivitySection = self.periodActivitySection()
        periodActivitySection.setContentHuggingPriority(.defaultLow, for: .horizontal)
        periodActivitySection.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        self.addArrangedSubview(periodActivitySection)
        periodActivitySection.widthAnchor.constraint(equalTo: self.widthAnchor).isActive = true
        self.addArrangedSubview(NSView())
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func loadColors() {
        self.readColorState = SColor.fromString(Store.shared.string(key: "\(self.module.stringValue)_readColor", defaultValue: self.readColorState.key))
        self.writeColorState = SColor.fromString(Store.shared.string(key: "\(self.module.stringValue)_writeColor", defaultValue: self.writeColorState.key))
        self.reverseOrderState = Store.shared.bool(key: "\(self.module.stringValue)_reverseOrder", defaultValue: self.reverseOrderState)
    }
    
    private func usageView() -> NSView {
        let view = NSStackView()
        view.distribution = .fill
        view.orientation = .horizontal
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 90).isActive = true
        view.edgeInsets = NSEdgeInsets(
            top: Constants.Settings.margin,
            left: 0,
            bottom: Constants.Settings.margin,
            right: 0
        )
        view.spacing = Constants.Settings.margin
        
        let circle = PieChartView(drawValue: true)
        circle.widthAnchor.constraint(equalToConstant: 90).isActive = true
        circle.toolTip = localizedString("Disk usage")
        self.circle = circle
        
        let details: NSView = {
            let view = NSStackView()
            view.orientation = .vertical
            view.distribution = .fillEqually
            view.spacing = 2
            
            var nameValue = localizedString("Unknown")
            var fileSystemValue = localizedString("Unknown")
            var sizeValue = localizedString("Unknown")
            if let disk = SystemKit.shared.device.info.disk?.first {
                if let name = disk.name {
                    nameValue = name
                }
                if let fileSystem = disk.fileSystem {
                    fileSystemValue = fileSystem.uppercased()
                }
                if let size = disk.size {
                    sizeValue = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                }
                self.mainID = disk.id
            }
            
            let title: NSView = {
                let view = NSStackView()
                view.orientation = .horizontal
                view.spacing = 2
                
                let nameField = NSButton()
                nameField.bezelStyle = .inline
                nameField.isBordered = false
                nameField.contentTintColor = .labelColor
                nameField.action = #selector(self.openDisk)
                nameField.target = self
                nameField.toolTip = nameValue
                nameField.title = nameValue
                nameField.cell?.truncatesLastVisibleLine = true
                self.mainNameField = nameField
                
                let fileSystemField = LabelField(fileSystemValue)
                fileSystemField.textColor = .tertiaryLabelColor
                self.mainFileSystemField = fileSystemField
                
                let activity: NSStackView = NSStackView()
                activity.distribution = .fill
                activity.spacing = 2
                
                let readState: NSView = NSView()
                readState.widthAnchor.constraint(equalToConstant: 8).isActive = true
                readState.heightAnchor.constraint(equalToConstant: 8).isActive = true
                readState.wantsLayer = true
                readState.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.75).cgColor
                readState.layer?.cornerRadius = 4
                readState.toolTip = localizedString("Read")
                let writeState: NSView = NSView()
                writeState.widthAnchor.constraint(equalToConstant: 8).isActive = true
                writeState.heightAnchor.constraint(equalToConstant: 8).isActive = true
                writeState.wantsLayer = true
                writeState.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.75).cgColor
                writeState.layer?.cornerRadius = 4
                writeState.toolTip = localizedString("Write")
                self.readState = readState
                self.writeState = writeState
                
                activity.addArrangedSubview(readState)
                activity.addArrangedSubview(writeState)
                
                view.addArrangedSubview(nameField)
                view.addArrangedSubview(activity)
                view.addArrangedSubview(NSView())
                view.addArrangedSubview(fileSystemField)
                
                return view
            }()
            
            let bar = BarChartView(size: 11, horizontal: true)
            self.bar = bar
            
            let levels = NSStackView()
            levels.orientation = .horizontal
            levels.distribution = .fill
            
            self.usedField = previewRow(levels, space: false, color: NSColor.systemBlue, title: "\(localizedString("Used")):", value: "")
            self.freeField = previewRow(levels, space: false, color: NSColor.lightGray, title: "\(localizedString("Free")):", value: "")
            
            let sizeField = LabelField(sizeValue)
            sizeField.textColor = .tertiaryLabelColor
            self.mainSizeField = sizeField
            
            levels.addArrangedSubview(NSView())
            levels.addArrangedSubview(sizeField)
            
            view.addArrangedSubview(title)
            view.addArrangedSubview(bar)
            view.addArrangedSubview(levels)
            
            return view
        }()
        
        view.addArrangedSubview(circle)
        view.addArrangedSubview(details)
        
        return view
    }
    
    private func historyView() -> NSView {
        let view: NSStackView = NSStackView()
        view.orientation = .vertical
        view.distribution = .fillEqually
        view.spacing = Constants.Settings.margin*2
        view.heightAnchor.constraint(equalToConstant: 140).isActive = true
        
        let chart = NetworkChartView(frame: .zero, num: 600)
        self.chart = chart
        chart.setColors(in: self.readColor, out: self.writeColor)
        chart.setReverseOrder(self.reverseOrderState)
        chart.setLegend(x: true, y: false)
        view.addArrangedSubview(chart)
        
        return view
    }
    
    private func detailsView() -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.distribution = .fillEqually
        view.spacing = 2
        
        self.readSpeedValueField = previewRow(view, color: self.readColor, title: "\(localizedString("Read")):", value: "0 KB/s")
        self.writeSpeedValueField = previewRow(view, color: self.writeColor, title: "\(localizedString("Write")):", value: "0 KB/s")
        self.totalReadValueField = previewRow(view, title: "\(localizedString("Total read")):", value: "0 KB")
        self.totalWrittenValueField = previewRow(view, title: "\(localizedString("Total written")):", value: "0 KB")
        
        return view
    }
    
    private func smartView() -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.distribution = .fillEqually
        view.spacing = 2
        
        self.smartTotalReadValueField = previewRow(view, title: "\(localizedString("Total read")):", value: "0 KB")
        self.smartTotalWrittenValueField = previewRow(view, title: "\(localizedString("Total written")):", value: "0 KB")
        self.temperatureValueField = previewRow(view, title: "\(localizedString("Temperature")):", value: "\(temperature(0))")
        self.healthValueField = previewRow(view, title: "\(localizedString("Health")):", value: "0%")
        self.powerCyclesValueField = previewRow(view, title: "\(localizedString("Power cycles")):", value: "0")
        self.powerOnHoursValueField = previewRow(view, title: "\(localizedString("Power on hours")):", value: "0")
        
        return view
    }
    
    private func periodActivitySection() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .top
        row.spacing = Constants.Settings.margin
        row.translatesAutoresizingMaskIntoConstraints = false

        let periodSection = self.periodActivityCard(
            title: localizedString("Activity by period"),
            headerAccessory: self.periodActivityHeaderControls(),
            content: self.periodActivityView()
        )
        periodSection.setContentHuggingPriority(.required, for: .horizontal)
        periodSection.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let insightSection = self.periodActivityCard(
            title: localizedString("Activity by time"),
            content: self.periodActivityInsightView()
        )
        insightSection.setContentHuggingPriority(.defaultLow, for: .horizontal)
        insightSection.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(periodSection)
        row.addArrangedSubview(insightSection)

        let compactPeriodWidth: CGFloat = 360
        periodSection.widthAnchor.constraint(lessThanOrEqualToConstant: compactPeriodWidth).isActive = true
        let periodWidth = periodSection.widthAnchor.constraint(equalToConstant: compactPeriodWidth)
        periodWidth.priority = .defaultHigh
        periodWidth.isActive = true
        return row
    }

    private func periodActivityCard(title: String, headerAccessory: NSView? = nil, content: NSView) -> NSStackView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .width
        section.distribution = .fill
        section.spacing = 0
        section.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill
        header.spacing = Constants.Settings.margin/1.5
        header.heightAnchor.constraint(equalToConstant: headerAccessory == nil ? 26 : 34).isActive = true

        let space = NSView()
        space.widthAnchor.constraint(equalToConstant: 4).isActive = true

        let titleField = LabelField(title)
        titleField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        header.addArrangedSubview(space)
        header.addArrangedSubview(titleField)
        if let headerAccessory {
            header.addArrangedSubview(headerAccessory)
        }
        header.addArrangedSubview(NSView())

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.025).cgColor
        container.layer?.cornerRadius = Constants.Settings.margin

        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Constants.Settings.margin),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Constants.Settings.margin),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: Constants.Settings.margin/1.25),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Constants.Settings.margin/1.25)
        ])

        section.addArrangedSubview(header)
        section.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
    }

    private func periodActivityHeaderControls() -> NSView {
        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = Constants.Settings.margin/1.5
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.setContentHuggingPriority(.required, for: .horizontal)
        controls.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let periodSelect = selectView(
            action: #selector(self.changeActivityPeriod),
            items: DiskActivityPeriod.menuItems,
            selected: self.activityPeriod.rawValue
        )
        periodSelect.toolTip = localizedString("Period")

        let sortSelect = selectView(
            action: #selector(self.changeActivitySort),
            items: DiskActivityProcessSort.menuItems,
            selected: self.activitySort.rawValue
        )
        sortSelect.toolTip = localizedString("Sort by")

        [periodSelect, sortSelect].forEach { control in
            control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let preferredWidth = control.widthAnchor.constraint(equalToConstant: 84)
            preferredWidth.priority = .defaultHigh
            preferredWidth.isActive = true
            control.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        }

        controls.addArrangedSubview(periodSelect)
        controls.addArrangedSubview(sortSelect)
        return controls
    }

    private func periodActivityView() -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.distribution = .fill
        view.alignment = .width
        view.translatesAutoresizingMaskIntoConstraints = false
        view.spacing = Constants.Settings.margin
        view.heightAnchor.constraint(equalToConstant: 266).isActive = true
        view.edgeInsets = NSEdgeInsets(
            top: Constants.Settings.margin,
            left: 0,
            bottom: Constants.Settings.margin,
            right: 0
        )

        let coverageStatus = self.periodCoverageStatusView()

        let summary = NSStackView()
        summary.orientation = .horizontal
        summary.distribution = .fillEqually
        summary.alignment = .width
        summary.translatesAutoresizingMaskIntoConstraints = false
        summary.spacing = Constants.Settings.margin
        summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let totals = NSStackView()
        totals.orientation = .vertical
        totals.alignment = .width
        totals.translatesAutoresizingMaskIntoConstraints = false
        totals.spacing = 2
        totals.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.periodReadValueField = previewRow(totals, color: self.readColor, title: "\(localizedString("Read")):", value: "0 KB")
        self.periodWriteValueField = previewRow(totals, color: self.writeColor, title: "\(localizedString("Write")):", value: "0 KB")
        self.periodTotalValueField = previewRow(totals, title: "\(localizedString("Total")):", value: "0 KB")

        let peaks = NSStackView()
        peaks.orientation = .vertical
        peaks.alignment = .width
        peaks.translatesAutoresizingMaskIntoConstraints = false
        peaks.spacing = 2
        peaks.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.periodPeakReadValueField = previewRow(peaks, color: self.readColor, title: "\(localizedString("Peak read")):", value: "0 KB/s")
        self.periodPeakWriteValueField = previewRow(peaks, color: self.writeColor, title: "\(localizedString("Peak write")):", value: "0 KB/s")
        peaks.addArrangedSubview(NSView())
        self.makePeriodRowsCompressible(totals)
        self.makePeriodRowsCompressible(peaks)

        summary.addArrangedSubview(totals)
        summary.addArrangedSubview(peaks)

        let processTitle = LabelField(localizedString("Disk activity processes"))
        processTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        let table = DiskActivityProcessTable()
        table.setContentHuggingPriority(.defaultLow, for: .horizontal)
        table.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.periodProcessTable = table

        view.addArrangedSubview(coverageStatus)
        view.addArrangedSubview(summary)
        view.addArrangedSubview(processTitle)
        view.addArrangedSubview(table)
        [coverageStatus, summary, processTitle, table].forEach { item in
            item.translatesAutoresizingMaskIntoConstraints = false
            item.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        }

        self.refreshPeriodActivity()

        return view
    }

    private func makePeriodRowsCompressible(_ stack: NSStackView) {
        stack.arrangedSubviews.forEach(self.makePeriodRowCompressible)
    }

    private func makePeriodRowCompressible(_ row: NSView) {
        row.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        guard let rowStack = row as? NSStackView else { return }
        rowStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rowStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rowStack.arrangedSubviews.forEach { item in
            item.setContentHuggingPriority(.defaultLow, for: .horizontal)
            item.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            if let field = item as? NSTextField {
                field.lineBreakMode = .byTruncatingTail
                field.cell?.truncatesLastVisibleLine = true
            }
        }
    }

    private func periodCoverageStatusView() -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.distribution = .fill
        view.alignment = .width
        view.spacing = 4
        view.translatesAutoresizingMaskIntoConstraints = false

        let progress = NSProgressIndicator()
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 100
        progress.doubleValue = 0
        progress.controlSize = .small
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.heightAnchor.constraint(equalToConstant: 6).isActive = true
        self.periodCoverageProgress = progress

        let field = LabelField(localizedString("No activity data yet"))
        field.font = .systemFont(ofSize: 11, weight: .medium)
        field.textColor = .secondaryLabelColor
        field.lineBreakMode = .byTruncatingTail
        self.periodCoverageField = field

        view.addArrangedSubview(progress)
        view.addArrangedSubview(field)
        return view
    }

    private func periodActivityInsightView() -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.distribution = .fill
        view.alignment = .width
        view.translatesAutoresizingMaskIntoConstraints = false
        view.spacing = Constants.Settings.margin
        view.heightAnchor.constraint(equalToConstant: 266).isActive = true
        view.edgeInsets = NSEdgeInsets(
            top: Constants.Settings.margin,
            left: 0,
            bottom: Constants.Settings.margin,
            right: 0
        )

        let topSource = previewRow(view, title: "\(localizedString("Top source")):", value: "-")
        let topSourceRow = view.arrangedSubviews.last
        topSource.lineBreakMode = .byTruncatingMiddle
        topSource.cell?.truncatesLastVisibleLine = true
        self.periodTopSourceValueField = topSource
        if let topSourceRow {
            self.makePeriodRowCompressible(topSourceRow)
        }

        let legend = NSStackView()
        legend.orientation = .horizontal
        legend.alignment = .centerY
        legend.spacing = Constants.Settings.margin
        legend.translatesAutoresizingMaskIntoConstraints = false
        legend.setContentHuggingPriority(.defaultLow, for: .horizontal)
        legend.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        legend.addArrangedSubview(self.periodActivityLegend(color: self.readColor, title: localizedString("Read")))
        legend.addArrangedSubview(self.periodActivityLegend(color: self.writeColor, title: localizedString("Write")))
        legend.addArrangedSubview(NSView())

        let chart = DiskActivityTimelineChart()
        chart.heightAnchor.constraint(equalToConstant: 196).isActive = true
        chart.setContentHuggingPriority(.defaultLow, for: .horizontal)
        chart.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.periodTimelineChart = chart

        view.addArrangedSubview(legend)
        view.addArrangedSubview(chart)
        [topSourceRow, legend, chart].compactMap { $0 }.forEach { item in
            item.translatesAutoresizingMaskIntoConstraints = false
            item.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        }

        return view
    }

    private func periodActivityLegend(color: NSColor, title: String) -> NSView {
        let item = NSStackView()
        item.orientation = .horizontal
        item.alignment = .centerY
        item.spacing = 4

        let swatch = NSView()
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.widthAnchor.constraint(equalToConstant: 8).isActive = true
        swatch.heightAnchor.constraint(equalToConstant: 8).isActive = true
        swatch.wantsLayer = true
        swatch.layer?.backgroundColor = color.cgColor
        swatch.layer?.cornerRadius = 2

        let field = LabelField(title)
        field.font = .systemFont(ofSize: 11, weight: .medium)

        item.addArrangedSubview(swatch)
        item.addArrangedSubview(field)
        return item
    }

    internal func capacityCallback(_ value: Disks) {
        DispatchQueue.main.async(execute: {
            if (self.window?.isVisible ?? false) || !self.initialized {
                if let update = self.selectedDrive(from: value) {
                    self.mainID = update.uuid
                    self.updateMainDisk(update)
                }
                
                let drives = value.filter(where: { $0.uuid != self.mainID })
                
                if drives.isEmpty {
                    self.allDisks?.isHidden = true
                } else if !drives.isEmpty {
                    self.allDisks?.isHidden = false
                }
                
                let mounted = value.count
                let external = value.filter(where: { $0.removable }).count
                self.allDisks?.setSubtitle("\(mounted) \(localizedString("mounted")) · \(external) \(localizedString("removable"))")
                
                let driveUUIDs = Set(drives.map { $0.uuid })
                for uuid in Array(self.diskRows.keys) where !driveUUIDs.contains(uuid) {
                    if let row = self.diskRows[uuid] {
                        row.cells.forEach { $0.removeFromSuperview() }
                        if let gridRow = row.gridRow {
                            let index = self.disks.index(of: gridRow)
                            if index != NSNotFound {
                                self.disks.removeRow(at: index)
                            }
                        }
                        if let sepRow = row.separatorRow {
                            let index = self.disks.index(of: sepRow)
                            if index != NSNotFound {
                                self.disks.removeRow(at: index)
                            }
                        }
                        self.diskRows.removeValue(forKey: uuid)
                    }
                }
                let firstRow = self.diskRows.values
                    .compactMap { row -> (row: DiskRow, index: Int)? in
                        guard let gr = row.gridRow else { return nil }
                        let idx = self.disks.index(of: gr)
                        return idx == NSNotFound ? nil : (row, idx)
                    }
                    .min(by: { $0.index < $1.index })?.row
                if let firstRow = firstRow, let sepRow = firstRow.separatorRow {
                    let index = self.disks.index(of: sepRow)
                    if index != NSNotFound {
                        self.disks.removeRow(at: index)
                    }
                    firstRow.separatorRow = nil
                }
                
                drives.forEach { drive in
                    if let row = self.diskRows[drive.uuid] {
                        row.update(drive)
                    } else {
                        let row = DiskRow(drive)
                        let isFirst = self.disks.numberOfRows == 0
                        if !self.diskRows.isEmpty {
                            let sep = NSView()
                            sep.wantsLayer = true
                            sep.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.05).cgColor
                            sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
                            let sepCells = (0..<max(1, self.disks.numberOfColumns)).map { _ -> NSView in NSView() }
                            var cells: [NSView] = sepCells
                            cells[0] = sep
                            let sepRow = self.disks.addRow(with: cells)
                            if self.disks.numberOfColumns > 1 {
                                sepRow.mergeCells(in: NSRange(location: 0, length: self.disks.numberOfColumns))
                            }
                            row.separatorRow = sepRow
                        }
                        row.gridRow = self.disks.addRow(with: row.cells)
                        if isFirst {
                            self.disks.column(at: 0).xPlacement = .leading
                            self.disks.column(at: 1).xPlacement = .center
                            self.disks.column(at: 2).xPlacement = .trailing
                        }
                        self.diskRows[drive.uuid] = row
                    }
                }
                
                self.initialized = true
            }
        })
    }
    
    internal func activityCallback(_ value: Disks) {
        guard let mainID = self.mainID, let update = value.first(where: { $0.uuid == mainID }) else {
            return
        }
        let read = update.activity.read
        let write = update.activity.write
        
        self.chart?.addValue(upload: Double(write), download: Double(read))
        
        self.readState?.toolTip = "Read: \(Units(bytes: read).getReadableSpeed(base: self.base, unit: self.speedUnit))"
        self.readState?.layer?.backgroundColor = read != 0 ? self.readColor.cgColor : NSColor.lightGray.withAlphaComponent(0.75).cgColor
        
        self.writeState?.toolTip = "Write: \(Units(bytes: write).getReadableSpeed(base: self.base, unit: self.speedUnit))"
        self.writeState?.layer?.backgroundColor = write != 0 ? self.writeColor.cgColor : NSColor.lightGray.withAlphaComponent(0.75).cgColor
        
        self.readSpeedValueField?.stringValue = Units(bytes: read).getReadableSpeed(base: self.base, unit: self.speedUnit)
        self.writeSpeedValueField?.stringValue = Units(bytes: write).getReadableSpeed(base: self.base, unit: self.speedUnit)
        
        let stats = update.activity
        self.totalReadValueField?.stringValue = Units(bytes: stats.readBytes).getReadableMemory()
        self.totalReadValueField?.toolTip = "\(stats.readBytes / (512 * 1000))"
        self.totalWrittenValueField?.stringValue = Units(bytes: stats.writeBytes).getReadableMemory()
        self.totalWrittenValueField?.toolTip = "\(stats.writeBytes / (512 * 1000))"

        self.refreshPeriodActivity()
    }

    internal func processCallback() {
        DispatchQueue.main.async(execute: {
            self.refreshPeriodActivity()
        })
    }

    private func refreshPeriodActivity() {
        let summary = DiskActivityHistoryStore.shared.summary(
            diskID: self.mainID,
            period: self.activityPeriod,
            sort: self.activitySort,
            limit: self.processLimit
        )

        self.periodReadValueField?.stringValue = Units(bytes: summary.read).getReadableMemory()
        self.periodWriteValueField?.stringValue = Units(bytes: summary.write).getReadableMemory()
        self.periodTotalValueField?.stringValue = Units(bytes: summary.total).getReadableMemory()
        self.periodPeakReadValueField?.stringValue = Units(bytes: summary.peakRead).getReadableSpeed(base: self.base, unit: self.speedUnit)
        self.periodPeakWriteValueField?.stringValue = Units(bytes: summary.peakWrite).getReadableSpeed(base: self.base, unit: self.speedUnit)
        self.updatePeriodCoverage(summary.coverage)
        self.periodTimelineChart?.update(points: summary.timeline, readColor: self.readColor, writeColor: self.writeColor)
        if let topProcess = summary.processes.first {
            let share = String(format: "%.0f%%", topProcess.share * 100)
            self.periodTopSourceValueField?.stringValue = "\(topProcess.name) · \(Units(bytes: topProcess.total).getReadableMemory()) · \(share)"
            self.periodTopSourceValueField?.toolTip = [
                topProcess.name,
                "\(localizedString("Read")): \(Units(bytes: topProcess.read).getReadableMemory())",
                "\(localizedString("Write")): \(Units(bytes: topProcess.write).getReadableMemory())"
            ].joined(separator: "\n")
        } else {
            self.periodTopSourceValueField?.stringValue = "-"
            self.periodTopSourceValueField?.toolTip = nil
        }
        self.periodProcessTable?.setRows(summary.processes)
    }

    private func updatePeriodCoverage(_ coverage: DiskActivityCoverage) {
        let percent = Int((coverage.coverageRatio * 100).rounded())
        let title = self.periodCoverageTitle(for: coverage.state)
        var parts = [title]

        if coverage.state != .empty {
            parts.append("\(percent)% \(localizedString("Activity period covered"))")
            if let lastUpdatedAt = coverage.lastUpdatedAt {
                let updated = self.periodCoverageTimeFormatter.string(from: Date(timeIntervalSince1970: lastUpdatedAt))
                parts.append("\(localizedString("Activity updated at")) \(updated)")
            }
        }

        let text = parts.joined(separator: " · ")
        self.periodCoverageField?.stringValue = text
        self.periodCoverageField?.toolTip = text
        self.periodCoverageProgress?.isHidden = coverage.state == .empty
        self.periodCoverageProgress?.doubleValue = Double(percent)
    }

    private func periodCoverageTitle(for state: DiskActivityDataState) -> String {
        switch state {
        case .ready:
            return localizedString("Activity data is current")
        case .collecting:
            return localizedString("Activity data is collecting")
        case .partial:
            return localizedString("Activity data is partial")
        case .stale:
            return localizedString("Activity data is stale")
        case .empty:
            return localizedString("No activity data yet")
        }
    }

    @objc private func changeActivityPeriod(_ sender: Any) {
        guard let key = self.selectedKey(from: sender), let period = DiskActivityPeriod(rawValue: key) else { return }
        self.activityPeriod = period
        Store.shared.set(key: "\(self.module.stringValue)_activityPeriod", value: period.rawValue)
        self.refreshPeriodActivity()
    }

    @objc private func changeActivitySort(_ sender: Any) {
        guard let key = self.selectedKey(from: sender), let sort = DiskActivityProcessSort(rawValue: key) else { return }
        self.activitySort = sort
        Store.shared.set(key: "\(self.module.stringValue)_activitySort", value: sort.rawValue)
        self.refreshPeriodActivity()
    }

    private func selectedKey(from sender: Any) -> String? {
        if let item = sender as? NSMenuItem {
            return item.representedObject as? String
        }
        if let button = sender as? NSPopUpButton {
            return button.selectedItem?.representedObject as? String
        }
        return nil
    }

    private func selectedDrive(from disks: Disks) -> drive? {
        let selectedName = Store.shared.string(key: "\(self.module.stringValue)_disk", defaultValue: "")
        if !selectedName.isEmpty, let selected = disks.first(where: { $0.mediaName == selectedName }) {
            return selected
        }
        return disks.first(where: { $0.root }) ?? disks.array.first
    }

    private func updateMainDisk(_ disk: drive) {
        let name = disk.mediaName.isEmpty ? localizedString("Unknown") : disk.mediaName
        if self.mainNameField?.title != name {
            self.mainNameField?.title = name
            self.mainNameField?.toolTip = name
        }

        let fileSystem = disk.fileSystem.isEmpty ? localizedString("Unknown") : disk.fileSystem.uppercased()
        if self.mainFileSystemField?.stringValue != fileSystem {
            self.mainFileSystemField?.stringValue = fileSystem
        }

        let size = ByteCountFormatter.string(fromByteCount: disk.size, countStyle: .file)
        if self.mainSizeField?.stringValue != size {
            self.mainSizeField?.stringValue = size
        }

        let free = disk.free
        let used = disk.size - free
        self.usedField?.stringValue = DiskSize(used).getReadableMemory()
        self.freeField?.stringValue = DiskSize(free).getReadableMemory()

        self.circle?.setValue(disk.percentage)
        self.bar?.setValue(ColorValue(disk.percentage, color: disk.percentage.usageColor()))
        self.uri = disk.path

        if let smart = disk.smart {
            self.smartTotalReadValueField?.toolTip = "\(smart.totalRead / (512 * 1000))"
            self.smartTotalWrittenValueField?.toolTip = "\(smart.totalWritten / (512 * 1000))"
            self.smartTotalReadValueField?.stringValue = Units(bytes: smart.totalRead).getReadableMemory()
            self.smartTotalWrittenValueField?.stringValue = Units(bytes: smart.totalWritten).getReadableMemory()
            self.temperatureValueField?.stringValue = "\(temperature(Double(smart.temperature)))"
            self.healthValueField?.stringValue = "\(smart.life)%"
            self.powerCyclesValueField?.stringValue = "\(smart.powerCycles)"
            self.powerOnHoursValueField?.stringValue = "\(smart.powerOnHours)"
        } else {
            self.smartTotalReadValueField?.toolTip = nil
            self.smartTotalWrittenValueField?.toolTip = nil
            self.smartTotalReadValueField?.stringValue = "0 KB"
            self.smartTotalWrittenValueField?.stringValue = "0 KB"
            self.temperatureValueField?.stringValue = "\(temperature(0))"
            self.healthValueField?.stringValue = "0%"
            self.powerCyclesValueField?.stringValue = "0"
            self.powerOnHoursValueField?.stringValue = "0"
        }
    }
    
    @objc private func openDisk() {
        if let uri = self.uri, let finder = self.finder {
            NSWorkspace.shared.open([uri], withApplicationAt: finder, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

internal class DiskRow {
    public let uuid: String
    public var gridRow: NSGridRow?
    public var separatorRow: NSGridRow?
    
    private let nameField: NSButton
    private let capacityField: LegendView
    private let bar: BarChartView = BarChartView(size: 6, horizontal: true)
    private let capacityView: NSStackView = NSStackView()
    private let fileSystemField: NSTextField
    private let ejectButton: NSButton = NSButton()

    private let uri: URL?
    private let finder: URL?

    public var cells: [NSView] { [self.nameField, self.capacityView, self.fileSystemField, self.ejectButton] }
    
    init(_ drive: drive) {
        self.uuid = drive.uuid
        self.uri = drive.path
        self.finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Finder")
        
        self.nameField = NSButton()
        self.nameField.bezelStyle = .inline
        self.nameField.isBordered = false
        self.nameField.contentTintColor = .labelColor
        self.nameField.action = #selector(self.openDisk)
        self.nameField.toolTip = drive.mediaName
        self.nameField.title = drive.mediaName
        self.nameField.cell?.truncatesLastVisibleLine = true
        self.nameField.font = .systemFont(ofSize: 11, weight: .semibold)
        
        self.fileSystemField = LabelField(drive.fileSystem.uppercased())
        self.fileSystemField.font = .systemFont(ofSize: 10, weight: .regular)
        self.fileSystemField.textColor = .tertiaryLabelColor
        
        self.ejectButton.bezelStyle = .inline
        self.ejectButton.isBordered = false
        self.ejectButton.imagePosition = .imageOnly
        self.ejectButton.image = NSImage(systemSymbolName: "eject", accessibilityDescription: localizedString("Eject"))
        self.ejectButton.contentTintColor = .secondaryLabelColor
        self.ejectButton.toolTip = localizedString("Eject")
        self.ejectButton.isEnabled = drive.removable && drive.path != nil
        self.ejectButton.action = #selector(self.ejectDisk)
        
        let topRow = NSStackView()
        topRow.orientation = .horizontal
        self.capacityField = LegendView(id: drive.uuid, size: drive.size, free: drive.free)
        topRow.addArrangedSubview(self.capacityField)
        topRow.addArrangedSubview(NSView())
        
        self.capacityView.orientation = .vertical
        self.capacityView.translatesAutoresizingMaskIntoConstraints = false
        self.capacityView.edgeInsets = NSEdgeInsets(top: 0, left: Constants.Settings.margin, bottom: 0, right: 0)
        
        self.capacityView.addArrangedSubview(topRow)
        self.capacityView.addArrangedSubview(self.bar)
        
        self.update(drive)
        
        self.nameField.target = self
        self.ejectButton.target = self
    }
    
    public func update(_ drive: drive) {
        if self.nameField.title != drive.mediaName {
            self.nameField.title = drive.mediaName
            self.nameField.toolTip = drive.mediaName
        }
        let fs = drive.fileSystem.uppercased()
        if self.fileSystemField.stringValue != fs {
            self.fileSystemField.stringValue = fs
        }
        self.ejectButton.isEnabled = drive.removable && drive.path != nil
        self.capacityField.update(free: drive.free)
        self.bar.setValue(ColorValue(drive.percentage, color: drive.percentage.usageColor()))
    }
    
    @objc private func openDisk() {
        if let uri = self.uri, let finder = self.finder {
            NSWorkspace.shared.open([uri], withApplicationAt: finder, configuration: NSWorkspace.OpenConfiguration())
        }
    }
    
    @objc private func ejectDisk() {
        guard let uri = self.uri else { return }
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: uri)
        } catch let err {
            error("failed to eject \(uri.path): \(err.localizedDescription)")
        }
    }
}

private class DiskActivityTimelineChart: NSView {
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

private class DiskActivityProcessTable: NSStackView {
    private let maxRows: Int = 6
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

    func setRows(_ rows: [DiskActivityProcessSummary]) {
        for (idx, view) in self.rowViews.enumerated() {
            if idx < rows.count {
                view.update(rows[idx])
            } else {
                view.reset()
            }
        }
    }
}

private class DiskActivityProcessRow: NSView {
    private static let headerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private static let rowFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let rowHeight: CGFloat = 20
    private static let metricColumnWidth: CGFloat = 64
    private static let shareColumnWidth: CGFloat = 40
    private static let columnSpacing: CGFloat = 1

    private let isHeader: Bool
    private var share: Double = 0
    private var shareColor: NSColor = .clear

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

    func update(_ row: DiskActivityProcessSummary) {
        self.nameField.stringValue = row.name
        self.nameField.toolTip = row.name
        self.readField.stringValue = Units(bytes: row.read).getReadableMemory()
        self.writeField.stringValue = Units(bytes: row.write).getReadableMemory()
        self.totalField.stringValue = Units(bytes: row.total).getReadableMemory()
        self.shareField.stringValue = String(format: "%.0f%%", row.share * 100)
        self.share = row.share
        self.shareColor = row.write >= row.read ? NSColor.systemRed : NSColor.systemBlue
        self.toolTip = "pid: \(row.pid)"
        self.needsDisplay = true
    }

    func reset() {
        [self.nameField, self.readField, self.writeField, self.totalField, self.shareField].forEach {
            $0.stringValue = "-"
            $0.toolTip = nil
        }
        self.share = 0
        self.toolTip = nil
        self.needsDisplay = true
    }
}

private class LegendView: NSStackView {
    private let size: Int64
    private var free: Int64
    private let id: String
    private var ready: Bool = false
    
    private var showUsedSpace: Bool {
        get { Store.shared.bool(key: "\(self.id)_preview_usedSpace", defaultValue: false) }
        set { Store.shared.set(key: "\(self.id)_preview_usedSpace", value: newValue) }
    }
    
    private var legendField: NSTextField? = nil
    
    public init(id: String, size: Int64, free: Int64) {
        self.id = id
        self.size = size
        self.free = free
        
        super.init(frame: .zero)
        self.toolTip = localizedString("Switch view")
        
        let legendField = TextView()
        legendField.font = NSFont.systemFont(ofSize: 11, weight: .light)
        legendField.stringValue = self.legend(free: free)
        legendField.cell?.truncatesLastVisibleLine = true
        
        self.addArrangedSubview(legendField)
        
        self.legendField = legendField
        
        let trackingArea = NSTrackingArea(
            rect: CGRect(x: 0, y: 0, width: self.frame.width, height: self.frame.height),
            options: [NSTrackingArea.Options.activeAlways, NSTrackingArea.Options.mouseEnteredAndExited, NSTrackingArea.Options.activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(trackingArea)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(free: Int64) {
        self.free = free
        
        if (self.window?.isVisible ?? false) || !self.ready {
            if let view = self.legendField {
                view.stringValue = self.legend(free: free)
            }
            self.ready = true
        }
    }
    
    private func legend(free: Int64) -> String {
        var value: String
        var percentage: Int
        
        if self.showUsedSpace {
            var usedSpace = self.size - free
            if usedSpace < 0 {
                usedSpace = 0
            }
            percentage = Int((Double(self.size - free) / Double(self.size)) * 100)
            value = localizedString("Used disk memory", DiskSize(usedSpace).getReadableMemory(), DiskSize(self.size).getReadableMemory())
        } else {
            percentage = Int((Double(free) / Double(self.size)).rounded(toPlaces: 2) * 100)
            value = localizedString("Free disk memory", DiskSize(free).getReadableMemory(), DiskSize(self.size).getReadableMemory())
        }
        
        value += " (\(percentage)%)"
        
        return value
    }
    
    override func mouseEntered(with: NSEvent) {
        NSCursor.pointingHand.set()
    }
    
    override func mouseExited(with: NSEvent) {
        NSCursor.arrow.set()
    }
    
    override func mouseDown(with: NSEvent) {
        self.showUsedSpace = !self.showUsedSpace
        
        if let view = self.legendField {
            view.stringValue = self.legend(free: self.free)
        }
    }
}
