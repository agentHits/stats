//
//  popup.swift
//  Battery
//
//  Created by Serhiy Mytrovtsiy on 06/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Popup: PopupWrapper {
    private let dashboardHeight: CGFloat = 160
    private let processHeight: CGFloat = 22
    
    private var dashboardBatteryView: BatteryView = BatteryView()
    private var dashboardBatteryStatus: BatteryStatus = BatteryStatus()
    private var levelField: NSTextField? = nil
    
    private var sourceField: NSTextField? = nil
    private var timeLabelField: NSTextField? = nil
    private var timeField: NSTextField? = nil
    private var powerField: NSTextField? = nil
    private var currentField: NSTextField? = nil
    private var voltageField: NSTextField? = nil
    
    private var barView: BarChartView = BarChartView(size: 10, horizontal: true)
    private var maxCapacityField: NSTextField? = nil
    private var designedCapacityField: NSTextField? = nil
    private var healthField: NSTextField? = nil
    private var cyclesField: NSTextField? = nil
    private var temperatureField: NSTextField? = nil
    
    private var adapterView: NSView? = nil
    private var chargingStateField: StatusBadgeView? = nil
    private var adapterPowerField: NSTextField? = nil
    private var chargingCurrentField: NSTextField? = nil
    private var chargingVoltageField: NSTextField? = nil
    
    private var processesView: NSView? = nil
    private var processes: ProcessesView? = nil
    private var processesInitialized: Bool = false
    private var renderedProcessCount: Int = 8
    private var latestTopProcesses: [TopProcess] = []
    
    private let usageCache = PopupCache<Battery_Usage>()
    
    private var numberOfProcesses: Int {
        Store.shared.int(key: "\(self.title)_processes", defaultValue: 8)
    }
    private var processListEnabled: Bool {
        self.numberOfProcesses != 0
    }
    private var processesHeight: CGFloat {
        self.processesHeight(for: self.renderedProcessCount)
    }
    private var timeFormat: String {
        Store.shared.string(key: "\(self.title)_timeFormat", defaultValue: "short")
    }
    
    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))
        
        self.spacing = 0
        self.orientation = .vertical
        self.renderedProcessCount = self.processListEnabled ? self.numberOfProcesses : 0
        
        self.addArrangedSubview(self.initDashboard())
        self.addArrangedSubview(self.initDetails())
        self.addArrangedSubview(self.initBattery())
        self.addArrangedSubview(self.initProcesses())
        
        self.recalculateHeight()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func appear() {
        self.replay(self.usageCache, render: self.renderUsage)
        if !self.latestTopProcesses.isEmpty {
            self.renderProcessList(self.visibleTopProcesses(from: self.latestTopProcesses))
        }
    }
    
    public override func disappear() {
        self.processes?.setLock(false)
    }
    
    private func recalculateHeight() {
        var h: CGFloat = 0
        self.arrangedSubviews.forEach { view in
            if view.bounds.height > 0 {
                h += view.bounds.height
            } else if let stackView = view as? NSStackView {
                h += stackView.arrangedSubviews.map { $0.bounds.height + stackView.spacing }.reduce(0, +)
            }
        }
        if self.frame.size.height != h {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }
    
    private func initDashboard() -> NSView {
        let view: NSStackView = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.dashboardHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        view.orientation = .vertical
        view.spacing = 0
        
        self.dashboardBatteryView.heightAnchor.constraint(equalToConstant: 90).isActive = true
        
        let information = NSStackView()
        information.heightAnchor.constraint(equalToConstant: 70).isActive = true
        information.orientation = .vertical
        information.spacing = 2
        
        var level: NSStackView {
            let view = NSStackView()
            view.orientation = .horizontal
            view.alignment = .firstBaseline
            view.spacing = -2
            view.distribution = .fill
            view.setHuggingPriority(.defaultLow, for: .horizontal)
            
            let value: NSTextField = ValueField("100")
            value.font = .systemFont(ofSize: 28, weight: .medium)
            value.textColor = .labelColor
            self.levelField = value
            
            let percentage: NSTextField = LabelField("%")
            percentage.font = .systemFont(ofSize: 16, weight: .medium)
            percentage.textColor = .tertiaryLabelColor
            
            let leftSpacer = NSView()
            let rightSpacer = NSView()
            
            view.addArrangedSubview(leftSpacer)
            view.addArrangedSubview(value)
            view.addArrangedSubview(percentage)
            view.addArrangedSubview(rightSpacer)
            
            leftSpacer.widthAnchor.constraint(equalTo: rightSpacer.widthAnchor).isActive = true
            
            return view
        }
        
        information.addArrangedSubview(level)
        information.addArrangedSubview(self.dashboardBatteryStatus)
        
        view.addArrangedSubview(self.dashboardBatteryView)
        view.addArrangedSubview(information)
        
        return view
    }

    private func valueRow(_ view: NSStackView, title: String, value: String) -> (LabelField, ValueField) {
        let row = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 22))
        row.heightAnchor.constraint(equalToConstant: 22).isActive = true
        row.orientation = .horizontal
        row.distribution = .fill
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 4)

        let label = LabelField(title)
        label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let valueField = ValueField(value)
        valueField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        valueField.setContentHuggingPriority(.required, for: .horizontal)
        valueField.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.addArrangedSubview(label)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(valueField)
        view.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true

        return (label, valueField)
    }
    
    private func initDetails() -> NSView {
        let view = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 0))
        view.orientation = .vertical
        view.spacing = 0
        view.addArrangedSubview(SeparatorView(label: localizedString("Details")))
        
        self.sourceField = self.valueRow(view, title: "\(localizedString("Source")):", value: localizedString("Unknown")).1
        
        let time = self.valueRow(view, title: "\(localizedString("Time to discharge")):", value: localizedString("Unknown"))
        self.timeLabelField = time.0
        self.timeField = time.1
        
        self.powerField = self.valueRow(view, title: "\(localizedString("Power")):", value: "0 W").1
        self.currentField = self.valueRow(view, title: "\(localizedString("Current")):", value: "0 mA").1
        self.voltageField = self.valueRow(view, title: "\(localizedString("Voltage")):", value: "0 V").1
        
        return view
    }
    
    private func initBattery() -> NSView {
        let view = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 0))
        view.orientation = .vertical
        view.spacing = 0
        view.addArrangedSubview(SeparatorView(label: localizedString("Battery")))
        
        let health: NSStackView = {
            let view = NSStackView()
            view.orientation = .vertical
            view.spacing = 8
            view.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
            
            let capacity: NSStackView = {
                let rows = NSStackView()
                rows.orientation = .vertical
                rows.spacing = 0
                rows.distribution = .fill
                
                let labels: NSStackView = {
                    let row = NSStackView()
                    row.orientation = .horizontal
                    row.distribution = .fillEqually
                    row.spacing = 0
                    
                    let max = LabelField(localizedString("Max capacity"), size: 8)
                    max.textColor = .tertiaryLabelColor
                    let designed = LabelField(localizedString("Designed capacity"), size: 8)
                    designed.textColor = .tertiaryLabelColor
                    designed.alignment = .right
                    
                    row.addArrangedSubview(max)
                    row.addArrangedSubview(NSView())
                    row.addArrangedSubview(designed)
                    
                    return row
                }()
                
                let values: NSStackView = {
                    let row = NSStackView()
                    row.orientation = .horizontal
                    row.distribution = .fillEqually
                    row.spacing = 0
                    
                    let max = LabelField("0 mAh", size: 11)
                    max.textColor = .secondaryLabelColor
                    let designed = LabelField("0 mAh", size: 11)
                    designed.textColor = .secondaryLabelColor
                    designed.alignment = .right
                    
                    self.maxCapacityField = max
                    self.designedCapacityField = designed
                    
                    row.addArrangedSubview(max)
                    row.addArrangedSubview(NSView())
                    row.addArrangedSubview(designed)
                    
                    return row
                }()
                
                rows.addArrangedSubview(labels)
                rows.addArrangedSubview(values)
                
                labels.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
                values.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
                
                return rows
            }()
            
            view.addArrangedSubview(capacity)
            view.addArrangedSubview(self.barView)
            
            return view
        }()
        
        view.addArrangedSubview(health)
        
        self.healthField = self.valueRow(view, title: "\(localizedString("Health")):", value: "").1
        self.cyclesField = self.valueRow(view, title: "\(localizedString("Cycles")):", value: "").1
        self.temperatureField = self.valueRow(view, title: "\(localizedString("Temperature")):", value: "").1
        
        return view
    }
    
    private func initAdapter() -> NSView {
        let view = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 0))
        view.orientation = .vertical
        view.spacing = 0
        view.addArrangedSubview(SeparatorView(label: localizedString("Power adapter")))
        
        self.chargingStateField = popupBadgeRow(view, title: "\(localizedString("Is charging")):", ok: "Yes", notOk: "No").1
        self.adapterPowerField = self.valueRow(view, title: "\(localizedString("Power")):", value: "").1
        
        self.adapterView = view
        
        return view
    }
    
    private func initProcesses() -> NSView {
        if self.renderedProcessCount == 0 { return NSView() }
        
        let view = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.processesHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        view.orientation = .vertical
        view.spacing = 0

        let container: ProcessesView = ProcessesView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: self.frame.width,
                height: self.processHeight * CGFloat(self.renderedProcessCount + 1)
            ),
            values: [(localizedString("Usage"), nil)],
            n: self.renderedProcessCount
        )
        self.processes = container
        
        view.addArrangedSubview(SeparatorView(label: localizedString("Top processes")))
        view.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        
        self.processesView = view
        return view
    }

    private func visibleTopProcesses(from list: [TopProcess]) -> [TopProcess] {
        guard self.processListEnabled else { return [] }
        return Array(list.prefix(self.numberOfProcesses))
    }

    private func processesHeight(for count: Int) -> CGFloat {
        (self.processHeight * CGFloat(count)) + (count == 0 ? 0 : Constants.Popup.separatorHeight + self.processHeight)
    }

    private func rebuildProcesses(count: Int) {
        guard self.renderedProcessCount != count || self.processes == nil else { return }

        self.renderedProcessCount = count

        if let view = self.processesView {
            self.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        self.processesView = nil
        self.processes = nil
        self.addArrangedSubview(self.initProcesses())
        self.processesInitialized = false

        self.recalculateHeight()
    }
    
    public func usageCallback(_ value: Battery_Usage) {
        self.apply(value, to: self.usageCache, render: self.renderUsage)
    }
    
    private func renderUsage(_ value: Battery_Usage) {
        self.dashboardBatteryView.setValue(abs(value.level), connected: !value.isBatteryPowered, charging: value.isCharging)
        self.dashboardBatteryStatus.set(value)
        
        self.levelField?.stringValue = "\(Int(abs(value.level) * 100))"
        self.levelField?.toolTip = "\(value.currentCapacity) mAh"
        
        self.sourceField?.stringValue = localizedString(value.powerSource)
        
        if value.isBatteryPowered {
            self.timeLabelField?.stringValue = "\(localizedString("Time to discharge")):"
            if value.timeToEmpty != -1 && value.timeToEmpty != 0 {
                self.timeField?.stringValue = Double(value.timeToEmpty*60).printSecondsToHoursMinutesSeconds(short: self.timeFormat == "short")
            } else {
                self.timeField?.stringValue = localizedString("Unknown")
            }
            
            if self.adapterView != nil {
                self.adapterView?.removeFromSuperview()
                self.adapterView = nil
                self.recalculateHeight()
            }
            
            self.powerField?.stringValue = "\(abs(value.batteryPower).roundTo(decimalPlaces: 2)) W"
            self.currentField?.stringValue = "\(abs(value.current)) mA"
            self.voltageField?.stringValue = "\(value.voltage.roundTo(decimalPlaces: 2)) V"
        } else {
            self.timeLabelField?.stringValue = "\(localizedString("Time to charge")):"
            if value.timeToCharge != -1 && value.timeToCharge != 0 {
                self.timeField?.stringValue = Double(value.timeToCharge*60).printSecondsToHoursMinutesSeconds(short: self.timeFormat == "short")
            } else {
                self.timeField?.stringValue = localizedString("Unknown")
            }
            
            if self.adapterView == nil {
                self.insertArrangedSubview(self.initAdapter(), at: 3)
                self.recalculateHeight()
            }
            
            let current = value.adapterVoltage > 0 ? Int((value.adapterPower / value.adapterVoltage) * 1000) : 0
            self.powerField?.stringValue = "\(value.adapterPower.roundTo(decimalPlaces: 2)) W"
            self.currentField?.stringValue = "\(current) mA"
            self.voltageField?.stringValue = "\(value.adapterVoltage.roundTo(decimalPlaces: 2)) V"
            
            self.chargingStateField?.setStatus(value.isCharging)
            self.adapterPowerField?.stringValue = "\(value.ACwatts) W"
        }
        
        if value.timeToEmpty == -1 || value.timeToCharge == -1 {
            self.timeField?.stringValue = localizedString("Calculating")
        }
        if value.isCharged {
            self.timeField?.stringValue = localizedString("Fully charged")
        } else if value.optimizedChargingEngaged {
            self.timeField?.stringValue = localizedString("On hold")
        }
        
        self.barView.setValue(ColorValue(Double(value.health)/100, color: .systemGreen))
        self.maxCapacityField?.stringValue = "\(value.maxCapacity) mAh"
        self.designedCapacityField?.stringValue = "\(value.designedCapacity) mAh"
        
        self.healthField?.stringValue = "\(value.health)%"
        self.cyclesField?.stringValue = "\(value.cycles)"
        self.temperatureField?.stringValue = temperature(value.temperature)
    }
    
    public func processCallback(_ list: [TopProcess]) {
        DispatchQueue.main.async(execute: {
            self.latestTopProcesses = list
            self.renderProcessList(self.visibleTopProcesses(from: list))
        })
    }

    private func renderProcessList(_ list: [TopProcess]) {
        guard self.processListEnabled else {
            self.rebuildProcesses(count: 0)
            self.processesInitialized = true
            return
        }

        guard !list.isEmpty else {
            if self.renderedProcessCount != self.numberOfProcesses || self.processes == nil {
                self.rebuildProcesses(count: self.numberOfProcesses)
            }
            self.processes?.clear()
            self.processesInitialized = true
            return
        }

        if list.count != self.processes?.count {
            self.rebuildProcesses(count: list.count)
        } else {
            self.processes?.clear()
        }
            
        for i in 0..<list.count {
            let process = list[i]
            self.processes?.set(i, process, ["\(process.usage.roundTo(decimalPlaces: 1))%"])
        }
            
        self.processesInitialized = true
    }
    
    public func numberOfProcessesUpdated() {
        DispatchQueue.main.async(execute: {
            let list = self.visibleTopProcesses(from: self.latestTopProcesses)
            if !self.processListEnabled {
                self.renderProcessList([])
            } else if !list.isEmpty {
                self.renderProcessList(list)
            } else {
                self.rebuildProcesses(count: self.numberOfProcesses)
            }
        })
    }
    
    // MARK: - Settings
    
    public override func settings() -> NSView? {
        let view = SettingsContainerView()
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Keyboard shortcut"), component: KeyboardShartcutView(
                callback: self.setKeyboardShortcut,
                value: self.keyboardShortcut
            ))
        ]))
        
        return view
    }
}

internal class BatteryView: NSView {
    private var percentage: Double = 0
    private var connected: Bool = false
    private var charging: Bool = false
    
    public override init(frame: NSRect = NSRect.zero) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        let w: CGFloat = min(self.frame.width, 130)
        let h: CGFloat = min(self.frame.height, 60)
        let x: CGFloat = (self.frame.width - w)/2
        let y: CGFloat = (self.frame.size.height - h) / 2
        let batteryFrame = NSBezierPath(roundedRect: NSRect(x: x+1, y: y+1, width: w-8, height: h-2), xRadius: 16, yRadius: 16)
        
        NSColor.secondaryLabelColor.set()
        
        let bPX: CGFloat = batteryFrame.bounds.origin.x + batteryFrame.bounds.width
        let bPY: CGFloat = batteryFrame.bounds.origin.y + (batteryFrame.bounds.height/2) - 12
        let batteryPoint = NSBezierPath(roundedRect: NSRect(x: bPX, y: bPY, width: 7, height: 24), xRadius: 6, yRadius: 6)
        batteryPoint.fill()
        
        let batteryPointSeparator = NSBezierPath()
        batteryPointSeparator.move(to: CGPoint(x: bPX, y: batteryFrame.bounds.origin.y))
        batteryPointSeparator.line(to: CGPoint(x: bPX, y: batteryFrame.bounds.origin.y + batteryFrame.bounds.height))
        ctx.saveGState()
        ctx.setBlendMode(.destinationOut)
        NSColor.textColor.set()
        batteryPointSeparator.lineWidth = 6
        batteryPointSeparator.stroke()
        ctx.restoreGState()
        
        batteryFrame.lineWidth = 2
        batteryFrame.stroke()
        
        if self.percentage == 0 {
            return
        }
        
        let innerHeight: CGFloat = h-10
        let minWidth: CGFloat = 8
        let track: CGFloat = w-16
        var fillWidth: CGFloat = 0
        if self.percentage > 0 {
            fillWidth = minWidth + (track - minWidth) * CGFloat(self.percentage)
        }
        let fillRadius: CGFloat = Swift.min(12, fillWidth/2, innerHeight/2)
        let inner = NSBezierPath(roundedRect: NSRect(
            x: x+5,
            y: y+5,
            width: fillWidth,
            height: innerHeight
        ), xRadius: fillRadius, yRadius: fillRadius)
        self.percentage.batteryColorV2().set()
        inner.lineWidth = 0
        inner.stroke()
        inner.close()
        inner.fill()
        
        if self.connected {
            let center = CGPoint(
                x: batteryFrame.bounds.origin.x + (batteryFrame.bounds.width/2),
                y: batteryFrame.bounds.origin.y + (batteryFrame.bounds.height/2)
            )
            let symbolName: String = self.charging ? "bolt.fill" : "powerplug.fill"
            
            if self.percentage > 0.55 {
                guard let body = self.coloredSymbol(symbolName, color: .white) else { return }
                let size: NSSize = body.size
                body.draw(in: NSRect(x: center.x - (size.width/2), y: center.y - (size.height/2), width: size.width, height: size.height))
                return
            }
            
            guard let outline = self.coloredSymbol(symbolName, color: .black),
                  let body = self.coloredSymbol(symbolName, color: self.percentage.batteryColorV2()) else { return }
            
            let size: NSSize = body.size
            let border: CGFloat = 2
            let origin = CGPoint(x: center.x - (size.width/2), y: center.y - (size.height/2))
            
            let steps: Int = 24
            for i in 0..<steps {
                let angle: CGFloat = (CGFloat(i) / CGFloat(steps)) * 2 * .pi
                outline.draw(in: NSRect(
                    x: origin.x + (cos(angle) * border),
                    y: origin.y + (sin(angle) * border),
                    width: size.width,
                    height: size.height
                ), from: .zero, operation: .destinationOut, fraction: 1.0)
            }
            body.draw(in: NSRect(origin: origin, size: size))
        }
    }
    
    public func setValue(_ value: Double, connected: Bool, charging: Bool) {
        if self.percentage == value && self.connected == connected && self.charging == charging { return }
        
        self.percentage = value
        self.connected = connected
        self.charging = charging
        
        DispatchQueue.main.async(execute: {
            self.display()
        })
    }
    
    private func coloredSymbol(_ name: String, color: NSColor) -> NSImage? {
        var config = NSImage.SymbolConfiguration(pointSize: 24, weight: .bold)
        config = config.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        image?.isTemplate = false
        return image
    }
}

internal class BatteryStatus: NSStackView {
    private var view: NSView? = nil
    private var icon: NSImageView? = nil
    private var field: NSTextField? = nil
    
    public override init(frame: NSRect = NSRect.zero) {
        super.init(frame: frame)
        
        self.orientation = .horizontal
        self.alignment = .firstBaseline
        self.spacing = 0
        self.distribution = .fill
        self.setHuggingPriority(.defaultLow, for: .horizontal)
        
        let block = NSStackView()
        block.orientation = .horizontal
        block.alignment = .centerY
        block.spacing = 4
        block.translatesAutoresizingMaskIntoConstraints = false
        block.wantsLayer = true
        block.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.18).cgColor
        block.layer?.cornerRadius = 8
        block.edgeInsets = NSEdgeInsets(top: 3, left: 7, bottom: 3, right: 7)
        self.view = block
        
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: localizedString("Unknown"))
        icon.contentTintColor = .systemGray
        icon.symbolConfiguration = .init(pointSize: 10, weight: .bold)
        icon.isHidden = true
        self.icon = icon
        
        let label = NSTextField(labelWithString: localizedString("Unknown"))
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .systemGray
        self.field = label
        
        block.addArrangedSubview(icon)
        block.addArrangedSubview(label)
        
        let leftSpacer = NSView()
        let rightSpacer = NSView()
        
        self.addArrangedSubview(leftSpacer)
        self.addArrangedSubview(block)
        self.addArrangedSubview(rightSpacer)
        
        leftSpacer.widthAnchor.constraint(equalTo: rightSpacer.widthAnchor).isActive = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func set(_ value: Battery_Usage) {
        var text: String = localizedString("Charging")
        var color: NSColor = .systemGreen
        var symbol: String = "bolt.fill"
        
        if value.isBatteryPowered {
            text = localizedString("On battery")
            color = value.level > 0.15 ? .systemGray : .systemRed
        } else if !value.isCharging {
            if value.isCharged && value.level >= 1 {
                text = localizedString("Plugged in")
                symbol = "powerplug.fill"
            } else if value.optimizedChargingEngaged {
                text = localizedString("On hold")
                color = .systemGray
                symbol = "powerplug.fill"
            }
        }
        
        self.icon?.isHidden = value.isBatteryPowered
        self.icon?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)
        self.icon?.contentTintColor = color
        self.field?.textColor = color
        self.field?.stringValue = text
        self.view?.layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor
    }
}
