//
//  preview.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 06/04/2026
//  Using Swift 6.0
//  Running on macOS 26.4
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//  

import Cocoa
import Kit

internal class Preview: PreviewWrapper {
    private var usageCircle: PieChartView? = nil
    private var bar: BarChartView? = nil
    private var loadLineChart: LineChartView? = nil
    private var pressureCircle: GaugeChartView? = nil
    private var pressureLineChart: LineChartView? = nil
    private var swapCircle: PieChartView? = nil
    private var swapLineChart: LineChartView? = nil
    private var swapContainer: NSStackView? = nil
    private var swapHeightConstraint: NSLayoutConstraint? = nil
    private var swapInfo: NSView? = nil
    private var swapProcesses: ProcessesView? = nil
    private var swapProcessesInitialized: Bool = false
    private let processHeight: CGFloat = 22
    
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
    
    private var usedField: NSTextField? = nil
    
    private var appField: NSTextField? = nil
    private var wiredField: NSTextField? = nil
    private var compressedField: NSTextField? = nil
    private var freeField: NSTextField? = nil
    private var swapField: NSTextField? = nil
    
    private var initialized: Bool = false
    private var swapProcessCount: Int {
        Store.shared.int(key: "\(self.module.stringValue)_processes", defaultValue: 8)
    }
    private var swapInfoHeight: CGFloat {
        self.swapProcessCount == 0 ? 0 : 58
    }
    private var swapProcessesHeight: CGFloat {
        self.swapProcessCount == 0 ? 0 : self.processHeight * CGFloat(self.swapProcessCount + 1)
    }
    private var swapSpacingHeight: CGFloat {
        self.swapProcessCount == 0 ? 0 : Constants.Settings.margin * 2
    }
    private var swapViewHeight: CGFloat {
        90 + self.swapInfoHeight + self.swapProcessesHeight + self.swapSpacingHeight
    }
    
    public init(_ module: ModuleType) {
        super.init(type: module)
        
        self.loadColors()
        
        let splitView = NSStackView()
        splitView.orientation = .horizontal
        splitView.distribution = .fillEqually
        splitView.addArrangedSubview(PreferencesSection(title: localizedString("Memory pressure"), [self.pressureView()]))
        splitView.addArrangedSubview(PreferencesSection(title: localizedString("Swap"), [self.swapView()]))
        
        self.addArrangedSubview(PreferencesSection([self.usageView()]))
        self.addArrangedSubview(PreferencesSection([self.historyView()]))
        self.addArrangedSubview(splitView)
        
        self.addArrangedSubview(NSView())
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func loadColors() {
        self.appColorState = SColor.fromString(Store.shared.string(key: "\(self.module.stringValue)_appColor", defaultValue: self.appColorState.key))
        self.wiredColorState = SColor.fromString(Store.shared.string(key: "\(self.module.stringValue)_wiredColor", defaultValue: self.wiredColorState.key))
        self.compressedColorState = SColor.fromString(Store.shared.string(key: "\(self.module.stringValue)_compressedColor", defaultValue: self.compressedColorState.key))
        self.freeColorState = SColor.fromString(Store.shared.string(key: "\(self.module.stringValue)_freeColor", defaultValue: self.freeColorState.key))
        self.chartColorState = SColor.fromString(Store.shared.string(key: "\(self.module.stringValue)_chartColor", defaultValue: self.chartColorState.key))
    }
    
    private func usageView() -> NSView {
        let view = NSStackView()
        view.distribution = .fill
        view.orientation = .horizontal
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 90).isActive = true
        view.edgeInsets = NSEdgeInsets(
            top: Constants.Settings.margin,
            left: Constants.Settings.margin,
            bottom: Constants.Settings.margin,
            right: Constants.Settings.margin
        )
        view.spacing = Constants.Settings.margin
        
        let circle = PieChartView(drawValue: true)
        circle.widthAnchor.constraint(equalToConstant: 90).isActive = true
        circle.toolTip = localizedString("Memory usage")
        self.usageCircle = circle
        
        let details: NSView = {
            let view = NSStackView()
            view.orientation = .vertical
            view.distribution = .fillEqually
            view.spacing = 2
            
            let titleField = LabelField()
            self.usedField = titleField
            
            let totalStr = Units(bytes: Int64(ProcessInfo.processInfo.physicalMemory)).getReadableMemory(style: .memory)
            let totalField = LabelField("\(localizedString("Total")): \(totalStr)")
            let buildBadge = LabelField(localizedString("AgentHits build"))
            buildBadge.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            buildBadge.textColor = .systemOrange
            buildBadge.toolTip = localizedString("Local personal AgentHits build, not official Stats.")
            
            let title = NSStackView()
            title.addArrangedSubview(titleField)
            title.addArrangedSubview(buildBadge)
            title.addArrangedSubview(NSView())
            title.addArrangedSubview(totalField)
            
            let bar = BarChartView(size: 11, horizontal: true)
            self.bar = bar
            
            let values: NSStackView = {
                let container = NSStackView()
                container.orientation = .vertical
                container.distribution = .fill
                container.spacing = 0
                
                let topValues = NSStackView()
                topValues.orientation = .horizontal
                topValues.distribution = .fill
                topValues.spacing = Constants.Settings.margin
                
                self.appField = previewRow(topValues, space: false, color: self.appColor, title: "\(localizedString("App")):")
                self.wiredField = previewRow(topValues, space: false, color: self.wiredColor, title: "\(localizedString("Wired")):")
                topValues.addArrangedSubview(NSView())
                
                let bottomValues = NSStackView()
                bottomValues.orientation = .horizontal
                bottomValues.distribution = .fill
                bottomValues.spacing = Constants.Settings.margin
                
                self.compressedField = previewRow(bottomValues, space: false, color: self.compressedColor, title: "\(localizedString("Compressed")):")
                self.freeField = previewRow(bottomValues, space: false, color: self.freeColor, title: "\(localizedString("Free")):")
                bottomValues.addArrangedSubview(NSView())
                
                container.addArrangedSubview(topValues)
                container.addArrangedSubview(bottomValues)
                
                return container
            }()
            
            view.addArrangedSubview(title)
            view.addArrangedSubview(bar)
            view.addArrangedSubview(values)
            
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
        
        let chart = LineChartView(num: 600)
        chart.setColor(self.chartColor)
        chart.setLegend(x: true, y: true)
        self.loadLineChart = chart
        view.addArrangedSubview(chart)
        
        return view
    }
    
    private func pressureView() -> NSView {
        let view = NSStackView()
        view.distribution = .fill
        view.orientation = .horizontal
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 90).isActive = true
        view.edgeInsets = NSEdgeInsets(
            top: Constants.Settings.margin,
            left: Constants.Settings.margin,
            bottom: Constants.Settings.margin,
            right: Constants.Settings.margin
        )
        view.spacing = Constants.Settings.margin
        
        let circle = GaugeChartView(segments: [
            ColorValue(1/3, color: NSColor.systemGreen),
            ColorValue(1/3, color: NSColor.systemYellow),
            ColorValue(1/3, color: NSColor.systemRed)
        ], title: localizedString("Normal"))
        circle.widthAnchor.constraint(equalToConstant: 90).isActive = true
        circle.toolTip = localizedString("Memory pressure")
        self.pressureCircle = circle
        
        let chart = LineChartView(num: 600, fixedScale: 3)
        chart.setColor(self.chartColor)
        chart.setLegend(x: true, y: false)
        chart.setToolTipFunc { v in
            let original = v.value * 2
            let level = RAMPressure(from: Int(original)).rawValue.capitalized
            return "\(level) (\(Int(original)+1))"
        }
        self.pressureLineChart = chart
        
        view.addArrangedSubview(circle)
        view.addArrangedSubview(chart)
        
        return view
    }
    
    private func swapView() -> NSView {
        let view = NSStackView()
        view.distribution = .fill
        view.orientation = .vertical
        view.translatesAutoresizingMaskIntoConstraints = false
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: self.swapViewHeight)
        heightConstraint.isActive = true
        self.swapContainer = view
        self.swapHeightConstraint = heightConstraint
        view.edgeInsets = NSEdgeInsets(
            top: Constants.Settings.margin,
            left: Constants.Settings.margin,
            bottom: Constants.Settings.margin,
            right: Constants.Settings.margin
        )
        view.spacing = Constants.Settings.margin

        let chartView = NSStackView()
        chartView.distribution = .fill
        chartView.orientation = .horizontal
        chartView.heightAnchor.constraint(equalToConstant: 90).isActive = true
        chartView.spacing = Constants.Settings.margin
        
        let circle = PieChartView()
        circle.widthAnchor.constraint(equalToConstant: 90).isActive = true
        circle.toolTip = localizedString("Swap")
        self.swapCircle = circle
        
        let chart = LineChartView(num: 600)
        chart.setColor(self.chartColor)
        chart.setLegend(x: true, y: false)
        chart.setToolTipFunc { v in
            return Units(bytes: Int64(v.value)).getReadableMemory(style: .memory)
        }
        self.swapLineChart = chart
        
        chartView.addArrangedSubview(circle)
        chartView.addArrangedSubview(chart)
        view.addArrangedSubview(chartView)

        if self.swapProcessCount > 0 {
            let info = self.makeSwapInfoView()
            self.swapInfo = info
            view.addArrangedSubview(info)

            let processes = self.makeSwapProcessesView()
            self.swapProcesses = processes
            view.addArrangedSubview(processes)
        }
        
        return view
    }

    private func makeSwapInfoView() -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.distribution = .fillEqually
        view.spacing = 2
        view.heightAnchor.constraint(equalToConstant: self.swapInfoHeight).isActive = true

        let source = self.swapInfoLabel(localizedString("Processes below do not show exact swap by PID: macOS does not expose those bytes directly."))
        let diagnostic = self.swapInfoLabel(localizedString("Diagnostics: high Compressed/Page-ins + growing Swap - close or restart the process."))

        view.addArrangedSubview(source)
        view.addArrangedSubview(diagnostic)

        return view
    }

    private func swapInfoLabel(_ value: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        field.textColor = .secondaryLabelColor
        field.maximumNumberOfLines = 2
        field.lineBreakMode = .byWordWrapping
        field.toolTip = value
        return field
    }

    private func makeSwapProcessesView() -> ProcessesView {
        let processes = ProcessesView(
            values: [
                (localizedString("Compressed"), self.compressedColor),
                ("Page-ins", self.chartColor)
            ],
            n: self.swapProcessCount
        )
        processes.toolTip = localizedString("Swap")
        processes.heightAnchor.constraint(equalToConstant: self.processHeight * CGFloat(self.swapProcessCount + 1)).isActive = true
        return processes
    }

    public func numberOfProcessesUpdated() {
        DispatchQueue.main.async(execute: {
            self.rebuildSwapProcessesView()
        })
    }

    private func rebuildSwapProcessesView() {
        if let info = self.swapInfo {
            self.swapContainer?.removeArrangedSubview(info)
            info.removeFromSuperview()
            self.swapInfo = nil
        }

        if let processes = self.swapProcesses {
            self.swapContainer?.removeArrangedSubview(processes)
            processes.removeFromSuperview()
            self.swapProcesses = nil
        }

        if self.swapProcessCount > 0 {
            let info = self.makeSwapInfoView()
            self.swapInfo = info
            self.swapContainer?.addArrangedSubview(info)

            let processes = self.makeSwapProcessesView()
            self.swapProcesses = processes
            self.swapContainer?.addArrangedSubview(processes)
        }

        self.swapHeightConstraint?.constant = self.swapViewHeight
        self.swapProcessesInitialized = false
    }
    
    public func loadCallback(_ value: RAM_Usage) {
        DispatchQueue.main.async(execute: {
            if (self.window?.isVisible ?? false) || !self.initialized {
                self.appField?.stringValue = Units(bytes: Int64(value.app)).getReadableMemory(style: .memory)
                self.wiredField?.stringValue = Units(bytes: Int64(value.wired)).getReadableMemory(style: .memory)
                self.compressedField?.stringValue = Units(bytes: Int64(value.compressed)).getReadableMemory(style: .memory)
                self.freeField?.stringValue = Units(bytes: Int64(value.free)).getReadableMemory(style: .memory)
                self.swapField?.stringValue = Units(bytes: Int64(value.swap.used)).getReadableMemory(style: .memory)
                
                let usedStr = Units(bytes: Int64(value.used)).getReadableMemory(style: .memory)
                self.usedField?.stringValue = "\(localizedString("Used")): \(usedStr)"
                
                let values = [
                    ColorValue(value.app/value.total, color: self.appColor),
                    ColorValue(value.wired/value.total, color: self.wiredColor),
                    ColorValue(value.compressed/value.total, color: self.compressedColor)
                ]
                
                self.usageCircle?.toolTip = "\(localizedString("Memory usage")): \(Int(value.usage*100))%"
                self.usageCircle?.setValue(value.usage)
                self.usageCircle?.setSegments(values)
                self.usageCircle?.setNonActiveSegmentColor(self.freeColor)
                
                self.bar?.setValues(values)
                
                self.pressureCircle?.setActiveSegment(value.pressure.value.number())
                self.pressureCircle?.setTitle(localizedString(value.pressure.value.rawValue.capitalized))
                self.pressureCircle?.toolTip = "\(localizedString("Memory pressure")): \(value.pressure.value.rawValue)"
                
                self.swapCircle?.setValue(value.swap.total > 0 ? (value.swap.used*100)/value.swap.total : 0)
                self.swapCircle?.setText(Units(bytes: Int64(value.swap.used)).getReadableMemory(style: .memory))
                
                self.initialized = true
            }
            self.loadLineChart?.addValue(value.usage)
            self.pressureLineChart?.addValue(Double(value.pressure.value.number())/2)
            self.swapLineChart?.addValue(value.swap.used)
        })
    }

    public func swapProcessCallback(_ list: [SwapProcess]) {
        DispatchQueue.main.async(execute: {
            if !(self.window?.isVisible ?? false) && self.swapProcessesInitialized {
                return
            }
            if self.swapProcesses?.count != self.swapProcessCount {
                self.rebuildSwapProcessesView()
            }
            self.swapProcesses?.clear()

            for (idx, process) in list.prefix(self.swapProcessCount).enumerated() {
                self.swapProcesses?.set(idx, process, [
                    Units(bytes: Int64(process.compressed)).getReadableMemory(style: .memory),
                    "\(process.pageins)"
                ])
            }

            self.swapProcessesInitialized = true
        })
    }
}
