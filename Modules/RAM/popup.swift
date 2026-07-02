//
//  popup.swift
//  Memory
//
//  Created by Serhiy Mytrovtsiy on 18/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Popup: PopupWrapper {
    private let dashboardHeight: CGFloat = 90
    private let chartHeight: CGFloat = 90 + Constants.Popup.separatorHeight
    private let detailsHeight: CGFloat = (22*6) + Constants.Popup.separatorHeight + 16
    private let processHeight: CGFloat = 22
    private let maxVisibleProcessRows: Int = 15
    
    private var usedField: NSTextField? = nil
    private var freeField: NSTextField? = nil
    
    private var appField: NSTextField? = nil
    private var inactiveField: NSTextField? = nil
    private var wiredField: NSTextField? = nil
    private var compressedField: NSTextField? = nil
    private var swapField: NSTextField? = nil
    
    private var appColorView: NSView? = nil
    private var wiredColorView: NSView? = nil
    private var compressedColorView: NSView? = nil
    private var freeColorView: NSView? = nil
    private var sliderView: NSView? = nil
    
    private var chart: LineChartView? = nil
    private var bar: BarChartView = BarChartView(size: 10, horizontal: true)
    private var circle: PieChartView? = nil
    private var level: GaugeChartView? = nil
    private var processesInitialized: Bool = false
    
    private let loadCache = PopupCache<RAM_Usage>()
    
    private var processes: ProcessesView? = nil
    private var processesView: NSView? = nil
    private var renderedProcessCount: Int = 8
    private var latestTopProcesses: [TopProcess] = []
    
    private var numberOfProcesses: Int {
        Store.shared.int(key: "\(self.title)_processes", defaultValue: 8)
    }
    private var processListEnabled: Bool {
        self.numberOfProcesses != 0
    }
    private var processesHeight: CGFloat {
        self.processesHeight(for: self.renderedProcessCount)
    }
    
    private var lineChartHistory: Int = 180
    private var lineChartScale: Scale = .none
    private var lineChartFixedScale: Double = 1
    private var chartPrefSection: PreferencesSection? = nil
    
    private var appColorState: SColor = .secondBlue
    private var appColor: NSColor { self.appColorState.additional as? NSColor ?? NSColor.systemRed }
    private var wiredColorState: SColor = .secondOrange
    private var wiredColor: NSColor { self.wiredColorState.additional as? NSColor ?? NSColor.systemBlue }
    private var compressedColorState: SColor = .pink
    private var compressedColor: NSColor { self.compressedColorState.additional as? NSColor ?? NSColor.lightGray }
    private var freeColorState: SColor = .lightGray
    private var freeColor: NSColor { self.freeColorState.additional as? NSColor ?? NSColor.systemBlue }
    private var chartColorState: SColor = .systemAccent
    private var chartColor: NSColor { self.chartColorState.additional as? NSColor ?? NSColor.systemBlue }
    
    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.spacing = 0
        self.orientation = .vertical
        
        self.appColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_appColor", defaultValue: self.appColorState.key))
        self.wiredColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_wiredColor", defaultValue: self.wiredColorState.key))
        self.compressedColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_compressedColor", defaultValue: self.compressedColorState.key))
        self.freeColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_freeColor", defaultValue: self.freeColorState.key))
        self.chartColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_chartColor", defaultValue: self.chartColorState.key))
        self.lineChartHistory = Store.shared.int(key: "\(self.title)_lineChartHistory", defaultValue: self.lineChartHistory)
        self.lineChartScale = Scale.fromString(Store.shared.string(key: "\(self.title)_lineChartScale", defaultValue: self.lineChartScale.key))
        self.lineChartFixedScale = Double(Store.shared.int(key: "\(self.title)_lineChartFixedScale", defaultValue: 100)) / 100
        self.renderedProcessCount = self.processListEnabled ? self.numberOfProcesses : 0
        
        self.addArrangedSubview(self.initDashboard())
        self.addArrangedSubview(self.initChart())
        self.addArrangedSubview(self.initDetails())
        self.addArrangedSubview(self.initProcesses())
        
        self.recalculateHeight()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func updateLayer() {
        self.chart?.display()
    }
    
    public override func appear() {
        self.replay(self.loadCache, render: self.renderLoad)
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

    private func visibleTopProcesses(from list: [TopProcess]) -> [TopProcess] {
        guard self.processListEnabled else { return [] }
        return Array(list.prefix(self.numberOfProcesses))
    }

    private func processesHeight(for count: Int) -> CGFloat {
        let visibleCount = min(count, self.maxVisibleProcessRows)
        return (self.processHeight * CGFloat(visibleCount)) + (count == 0 ? 0 : Constants.Popup.separatorHeight + 22)
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
    
    private func initDashboard() -> NSView {
        let view = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.dashboardHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        view.orientation = .horizontal
        view.distribution = .fillEqually
        
        let circle = PieChartView(drawValue: true)
        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.toolTip = localizedString("Memory usage")
        self.circle = circle
        
        let circleContainer = NSView()
        circleContainer.addSubview(circle)
        
        let gauge = GaugeChartView(segments: [
            ColorValue(1/3, color: NSColor.systemGreen),
            ColorValue(1/3, color: NSColor.systemYellow),
            ColorValue(1/3, color: NSColor.systemRed)
        ], title: localizedString("Normal"))
        gauge.translatesAutoresizingMaskIntoConstraints = false
        gauge.toolTip = localizedString("Memory pressure")
        self.level = gauge
        
        let gaugeContainer = NSView()
        gaugeContainer.addSubview(gauge)
        
        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: 70),
            circle.heightAnchor.constraint(equalToConstant: 70),
            circle.centerXAnchor.constraint(equalTo: circleContainer.centerXAnchor, constant: -15),
            circle.centerYAnchor.constraint(equalTo: circleContainer.centerYAnchor),
            
            gauge.widthAnchor.constraint(equalToConstant: 70),
            gauge.heightAnchor.constraint(equalToConstant: 60),
            gauge.centerXAnchor.constraint(equalTo: gaugeContainer.centerXAnchor, constant: 15),
            gauge.centerYAnchor.constraint(equalTo: gaugeContainer.centerYAnchor)
        ])
        
        view.addArrangedSubview(gaugeContainer)
        view.addArrangedSubview(circleContainer)
        
        return view
    }
    
    private func initChart() -> NSView  {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.chartHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        let separator = separatorView(localizedString("Usage history"), origin: NSPoint(x: 0, y: self.chartHeight-Constants.Popup.separatorHeight), width: self.frame.width)
        let container: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: separator.frame.origin.y))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.1).cgColor
        container.layer?.cornerRadius = Constants.Popup.radius
        
        let chartFrame = NSRect(x: 1, y: 0, width: view.frame.width - 2, height: container.frame.height)
        self.chart = LineChartView(frame: chartFrame, num: self.lineChartHistory, scale: self.lineChartScale, fixedScale: self.lineChartFixedScale)
        self.chart?.setColor(self.chartColor)
        container.addSubview(self.chart!)
        
        view.addSubview(separator)
        view.addSubview(container)
        
        return view
    }
    
    private func initDetails() -> NSView  {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.detailsHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        let separator = separatorView(localizedString("Details"), origin: NSPoint(x: 0, y: self.detailsHeight-Constants.Popup.separatorHeight), width: self.frame.width)
        let container: NSStackView = NSStackView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: separator.frame.origin.y))
        container.orientation = .vertical
        container.spacing = 0
        
        self.usedField = popupRow(container, title: "\(localizedString("Used")):", value: "").1
        container.addArrangedSubview(self.bar)
        (self.appColorView, _, self.appField) = popupWithColorRow(container, color: self.appColor, title: "\(localizedString("App")):", value: "")
        (self.wiredColorView, _, self.wiredField) = popupWithColorRow(container, color: self.wiredColor, title: "\(localizedString("Wired")):", value: "")
        (self.compressedColorView, _, self.compressedField) = popupWithColorRow(container, color: self.compressedColor, title: "\(localizedString("Compressed")):", value: "")
        (self.freeColorView, _, self.freeField) = popupWithColorRow(container, color: self.freeColor.withAlphaComponent(0.5), title: "\(localizedString("Free")):", value: "")
        self.swapField = popupRow(container, title: "\(localizedString("Swap")):", value: "").1
        
        view.addSubview(separator)
        view.addSubview(container)
        
        return view
    }
    
    private func initProcesses() -> NSView  {
        if self.renderedProcessCount == 0 {
            let view = NSView()
            self.processesView = view
            return view
        }
        
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.processesHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        let separator = separatorView(localizedString("Top processes"), origin: NSPoint(x: 0, y: self.processesHeight-Constants.Popup.separatorHeight), width: self.frame.width)
        let scrollFrame = NSRect(x: 0, y: 0, width: self.frame.width, height: separator.frame.origin.y)
        let scrollView = NSScrollView(frame: scrollFrame)
        scrollView.hasVerticalScroller = self.renderedProcessCount > self.maxVisibleProcessRows
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false

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
        scrollView.documentView = container
        
        view.addSubview(separator)
        view.addSubview(scrollView)
        
        self.processesView = view
        return view
    }
    
    public func loadCallback(_ value: RAM_Usage) {
        self.apply(value, to: self.loadCache, render: self.renderLoad)
        self.chart?.addValue(value.usage)
    }
    
    private func renderLoad(_ value: RAM_Usage) {
        self.appField?.stringValue = Units(bytes: Int64(value.app)).getReadableMemory(style: .memory)
        self.inactiveField?.stringValue = Units(bytes: Int64(value.inactive)).getReadableMemory(style: .memory)
        self.wiredField?.stringValue = Units(bytes: Int64(value.wired)).getReadableMemory(style: .memory)
        self.compressedField?.stringValue = Units(bytes: Int64(value.compressed)).getReadableMemory(style: .memory)
        self.swapField?.stringValue = Units(bytes: Int64(value.swap.used)).getReadableMemory(style: .memory)
        
        self.usedField?.stringValue = Units(bytes: Int64(value.used)).getReadableMemory(style: .memory)
        self.freeField?.stringValue = Units(bytes: Int64(value.free)).getReadableMemory(style: .memory)
        
        let values = [
            ColorValue(value.app/value.total, color: self.appColor),
            ColorValue(value.wired/value.total, color: self.wiredColor),
            ColorValue(value.compressed/value.total, color: self.compressedColor)
        ]
        
        self.circle?.toolTip = "\(localizedString("Memory usage")): \(Int(value.usage*100))%"
        self.circle?.setValue(value.usage)
        self.circle?.setSegments(values)
        self.circle?.setNonActiveSegmentColor(self.freeColor)
        self.circle?.display()
        
        self.level?.setActiveSegment(value.pressure.value.number())
        self.level?.setTitle(localizedString(value.pressure.value.rawValue.capitalized))
        self.level?.toolTip = "\(localizedString("Memory pressure")): \(value.pressure.value.rawValue)"
        self.level?.display()
        
        self.bar.setValues(values)
        
        self.chart?.display()
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
            self.processes?.set(i, process, [Units(bytes: Int64(process.usage)).getReadableMemory(style: .memory)])
        }

        self.processesInitialized = true
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
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("App color"), component: colorSelectView(
                action: #selector(toggleAppColor),
                items: SColor.allColors,
                selected: self.appColorState.key
            )),
            PreferencesRow(localizedString("Wired color"), component: colorSelectView(
                action: #selector(toggleWiredColor),
                items: SColor.allColors,
                selected: self.wiredColorState.key
            )),
            PreferencesRow(localizedString("Compressed color"), component: colorSelectView(
                action: #selector(toggleCompressedColor),
                items: SColor.allColors,
                selected: self.compressedColorState.key
            )),
            PreferencesRow(localizedString("Free color"), component: colorSelectView(
                action: #selector(toggleFreeColor),
                items: SColor.allColors,
                selected: self.freeColorState.key
            ))
        ]))
        
        self.sliderView = sliderView(
            action: #selector(self.toggleLineChartFixedScale),
            value: Int(self.lineChartFixedScale * 100),
            initialValue: "\(Int(self.lineChartFixedScale * 100)) %"
        )
        self.chartPrefSection = PreferencesSection([
            PreferencesRow(localizedString("Chart color"), component: colorSelectView(
                action: #selector(self.toggleChartColor),
                items: SColor.allColors,
                selected: self.chartColorState.key
            )),
            PreferencesRow(localizedString("Chart history"), component: selectView(
                action: #selector(self.toggleLineChartHistory),
                items: LineChartHistory,
                selected: "\(self.lineChartHistory)"
            )),
            PreferencesRow(localizedString("Main chart scaling"), component: selectView(
                action: #selector(self.toggleLineChartScale),
                items: Scale.allCases,
                selected: self.lineChartScale.key
            )),
            PreferencesRow(localizedString("Scale value"), component: self.sliderView!)
        ])
        self.chartPrefSection?.setRowVisibility(3, newState: self.lineChartScale == .fixed)
        view.addArrangedSubview(self.chartPrefSection!)
        
        return view
    }
    
    @objc private func toggleAppColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.appColorState = SColor.fromString(key, defaultValue: self.appColorState)
        Store.shared.set(key: "\(self.title)_appColor", value: self.appColorState.key)
        if let color = self.appColorState.additional as? NSColor {
            self.appColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func toggleWiredColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.wiredColorState = SColor.fromString(key, defaultValue: self.wiredColorState)
        Store.shared.set(key: "\(self.title)_wiredColor", value: self.wiredColorState.key)
        if let color = self.wiredColorState.additional as? NSColor {
            self.wiredColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func toggleCompressedColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.compressedColorState = SColor.fromString(key, defaultValue: self.compressedColorState)
        Store.shared.set(key: "\(self.title)_compressedColor", value: self.compressedColorState.key)
        if let color = self.compressedColorState.additional as? NSColor {
            self.compressedColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func toggleFreeColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.freeColorState = SColor.fromString(key, defaultValue: self.freeColorState)
        Store.shared.set(key: "\(self.title)_freeColor", value: self.freeColorState.key)
        if let color = self.freeColorState.additional as? NSColor {
            self.freeColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func toggleChartColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.chartColorState = SColor.fromString(key, defaultValue: self.chartColorState)
        Store.shared.set(key: "\(self.title)_chartColor", value: self.chartColorState.key)
        if let color = self.chartColorState.additional as? NSColor {
            self.chart?.setColor(color)
        }
    }
    @objc private func toggleLineChartHistory(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.lineChartHistory = value
        Store.shared.set(key: "\(self.title)_lineChartHistory", value: value)
        self.chart?.reinit(self.lineChartHistory)
    }
    @objc private func toggleLineChartScale(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let value = Scale.allCases.first(where: { $0.key == key }) else { return }
        self.chartPrefSection?.setRowVisibility(3, newState: value == .fixed)
        self.lineChartScale = value
        self.chart?.setScale(self.lineChartScale, fixedScale: self.lineChartFixedScale)
        Store.shared.set(key: "\(self.title)_lineChartScale", value: key)
        self.display()
    }
    @objc private func toggleLineChartFixedScale(_ sender: NSSlider) {
        let value = Int(sender.doubleValue)
        
        if let field = self.sliderView?.subviews.first(where: { $0 is NSTextField }), let view = field as? NSTextField {
            view.stringValue = "\(value) %"
        }
        
        self.lineChartFixedScale = sender.doubleValue / 100
        self.chart?.setScale(self.lineChartScale, fixedScale: self.lineChartFixedScale)
        Store.shared.set(key: "\(self.title)_lineChartFixedScale", value: value)
    }
}
