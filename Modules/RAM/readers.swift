//
//  readers.swift
//  Memory
//
//  Created by Serhiy Mytrovtsiy on 12/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal struct RAMMemoryBreakdown {
    let app: Double
    let wired: Double
    let compressed: Double
    let cache: Double
    let used: Double
    let free: Double
}

internal class UsageReader: Reader<RAM_Usage> {
    public var totalSize: Double = 0
    
    public override func setup() {
        var stats = host_basic_info()
        var count = UInt32(MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_info(mach_host_self(), HOST_BASIC_INFO, $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            self.totalSize = Double(stats.max_mem)
            return
        }
        
        self.totalSize = 0
        error("host_info(): \(String(cString: mach_error_string(kerr), encoding: String.Encoding.ascii) ?? "unknown error")", log: self.log)
    }
    
    public override func read() {
        var stats = vm_statistics64()
        var count = UInt32(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        let result: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let active = Double(stats.active_count) * Double(vm_page_size)
            let inactive = Double(stats.inactive_count) * Double(vm_page_size)
            let breakdown = Self.memoryBreakdown(
                totalSize: self.totalSize,
                stats: stats,
                pageSize: Double(vm_page_size)
            )
            let swapins = Int64(stats.swapins)
            let swapouts = Int64(stats.swapouts)
            
            var intSize: size_t = MemoryLayout<uint>.size
            var pressureLevel: Int = 0
            sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &intSize, nil, 0)
            
            var pressureValue: RAMPressure
            switch pressureLevel {
            case 2: pressureValue = .warning
            case 4: pressureValue = .critical
            default: pressureValue = .normal
            }
            
            var stringSize: size_t = MemoryLayout<xsw_usage>.size
            var swap: xsw_usage = xsw_usage()
            sysctlbyname("vm.swapusage", &swap, &stringSize, nil, 0)
            
            self.callback(RAM_Usage(
                total: self.totalSize,
                used: breakdown.used,
                free: breakdown.free,
                
                active: active,
                inactive: inactive,
                wired: breakdown.wired,
                compressed: breakdown.compressed,
                
                app: breakdown.app,
                cache: breakdown.cache,
                
                swap: Swap(
                    total: Double(swap.xsu_total),
                    used: Double(swap.xsu_used),
                    free: Double(swap.xsu_avail)
                ),
                pressure: Pressure(level: pressureLevel, value: pressureValue),
                
                swapins: swapins,
                swapouts: swapouts
            ))
            return
        }
        
        error("host_statistics64(): \(String(cString: mach_error_string(result), encoding: String.Encoding.ascii) ?? "unknown error")", log: self.log)
    }

    static func memoryBreakdown(totalSize: Double, stats: vm_statistics64, pageSize: Double) -> RAMMemoryBreakdown {
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let purgeable = Double(stats.purgeable_count) * pageSize
        let external = Double(stats.external_page_count) * pageSize
        let appPages = max(Int64(stats.internal_page_count) - Int64(stats.purgeable_count), 0)
        let app = Double(appPages) * pageSize
        let cache = purgeable + external
        let used = min(max(app + wired + compressed, 0), totalSize)
        let free = max(totalSize - used, 0)

        return RAMMemoryBreakdown(
            app: app,
            wired: wired,
            compressed: compressed,
            cache: cache,
            used: used,
            free: free
        )
    }
}

internal struct SwapProcess: Codable, Process_p {
    let pid: Int
    let name: String
    let memory: Double
    let compressed: Double
    let pageins: Int
    var icon: NSImage {
        get {
            if let app = NSRunningApplication(processIdentifier: pid_t(self.pid)), let icon = app.icon {
                return icon
            }
            return Constants.defaultProcessIcon
        }
    }
}

public class ProcessReader: Reader<[TopProcess]> {
    private let title: String = "RAM"
    
    private var numberOfProcesses: Int {
        get { Store.shared.int(key: "\(self.title)_processes", defaultValue: 8) }
    }
    
    private var combinedProcesses: Bool{
        get { Store.shared.bool(key: "\(self.title)_combinedProcesses", defaultValue: false) }
    }
    
    private typealias dynGetResponsiblePidFuncType = @convention(c) (CInt) -> CInt
    
    public override func setup() {
        self.popup = true
        self.setInterval(Store.shared.int(key: "\(self.title)_updateTopInterval", defaultValue: 1))
    }
    
    public override func read() {
        if self.numberOfProcesses == 0 {
            return
        }
        
        let task = Process()
        task.launchPath = "/usr/bin/top"
        if self.combinedProcesses {
            task.arguments = ["-l", "1", "-o", "mem", "-stats", "pid,command,mem"]
        } else {
            task.arguments = ["-l", "1", "-o", "mem", "-n", "\(self.numberOfProcesses)", "-stats", "pid,command,mem"]
        }
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        defer {
            outputPipe.fileHandleForReading.closeFile()
            errorPipe.fileHandleForReading.closeFile()
        }
        
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        do {
            try task.run()
        } catch let err {
            error("top(): \(err.localizedDescription)", log: self.log)
            return
        }
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)
        _ = String(data: errorData, encoding: .utf8)
        guard let output, !output.isEmpty else { return }
        
        var processes: [TopProcess] = []
        output.enumerateLines { (line, _) in
            if line.matches("^\\d+\\** +.* +\\d+[A-Z]*\\+?\\-? *$") {
                processes.append(ProcessReader.parseProcess(line))
            }
        }
        
        if !self.combinedProcesses {
            self.callback(processes)
            return
        }
        
        var processGroups: [String: [TopProcess]] = [:]
        for process in processes {
            let responsiblePid = ProcessReader.getResponsiblePid(process.pid)
            let groupKey = "\(responsiblePid)"
            
            if processGroups[groupKey] != nil {
                processGroups[groupKey]!.append(process)
            } else {
                processGroups[groupKey] = [process]
            }
        }
        
        var result: [TopProcess] = []
        for (_, processes) in processGroups {
            let totalUsage = processes.reduce(0) { $0 + $1.usage }
            let firstProcess = processes.first!
            let name: String
            
            if let app = NSRunningApplication(processIdentifier: pid_t(ProcessReader.getResponsiblePid(firstProcess.pid))),
               let appName = app.localizedName {
                name = appName
            } else {
                name = firstProcess.name
            }
            
            result.append(TopProcess(
                pid: ProcessReader.getResponsiblePid(firstProcess.pid),
                name: name,
                usage: totalUsage
            ))
        }
        
        result.sort { $0.usage > $1.usage }
        self.callback(Array(result.prefix(self.numberOfProcesses)))
    }
    
    private static let dynGetResponsiblePidFunc: UnsafeMutableRawPointer? = {
        let result = dlsym(UnsafeMutableRawPointer(bitPattern: -1), "responsibility_get_pid_responsible_for_pid")
        if result == nil {
            error("Error loading responsibility_get_pid_responsible_for_pid")
        }
        return result
    }()
    
    static func getResponsiblePid(_ childPid: Int) -> Int {
        guard ProcessReader.dynGetResponsiblePidFunc != nil else {
            return childPid
        }
        let responsiblePid = unsafeBitCast(ProcessReader.dynGetResponsiblePidFunc, to: dynGetResponsiblePidFuncType.self)(CInt(childPid))
        guard responsiblePid != -1 else {
            return childPid
        }
        return Int(responsiblePid)
    }
    
    static public func parseProcess(_ raw: String) -> TopProcess {
        var str = raw.trimmingCharacters(in: .whitespaces)
        let pidString = str.find(pattern: "^\\d+")
        
        if let range = str.range(of: pidString) {
            str = str.replacingCharacters(in: range, with: "")
        }
        
        var arr = str.split(separator: " ")
        if arr.first == "*" {
            arr.removeFirst()
        }
        
        var usageString = str.suffix(6)
        if let lastElement = arr.last {
            usageString = lastElement
            arr.removeLast()
        }
        
        var command = arr.joined(separator: " ")
            .replacingOccurrences(of: pidString, with: "")
            .trimmingCharacters(in: .whitespaces)
        
        if let regex = try? NSRegularExpression(pattern: " (\\+|\\-)*$", options: .caseInsensitive) {
            command = regex.stringByReplacingMatches(in: command, options: [], range: NSRange(location: 0, length: command.count), withTemplate: "")
        }
        
        let pid = Int(pidString.filter("01234567890.".contains)) ?? 0
        let usage = ProcessReader.parseTopMemory(usageString)
        
        var name: String = command
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)), let n = app.localizedName {
            name = n
        }
        
        if command.contains("com.apple.Virtua") && name.contains("Docker") {
            name = "Docker"
        }
        
        return TopProcess(pid: pid, name: name, usage: usage)
    }

    static func parseTopMemory(_ raw: Substring) -> Double {
        let rawString = String(raw)
        var usage = Double(rawString.filter("01234567890.".contains)) ?? 0
        if rawString.last == "G" {
            usage *= 1024 * 1000 * 1000
        } else if rawString.last == "K" {
            usage = usage / 1024 * 1000 * 1000
        } else if rawString.last == "M" && rawString.count == 5 {
            usage = usage / 1024 * 1000 * 1000 * 1000
        } else {
            usage *= 1000 * 1000
        }
        return usage
    }
}

internal class SwapProcessReader: Reader<[SwapProcess]> {
    private let title: String = "RAM"

    private var numberOfProcesses: Int {
        get { Store.shared.int(key: "\(self.title)_processes", defaultValue: 8) }
    }

    private var combinedProcesses: Bool {
        get { Store.shared.bool(key: "\(self.title)_combinedProcesses", defaultValue: false) }
    }

    public override func setup() {
        self.preview = true
        self.setInterval(Store.shared.int(key: "\(self.title)_updateTopInterval", defaultValue: 1))
    }

    public override func read() {
        if self.numberOfProcesses == 0 {
            return
        }

        let task = Process()
        task.launchPath = "/usr/bin/top"
        var arguments = [
            "-l", "1",
            "-o", "compressed",
            "-stats", "pid,command,mem,compressed,pageins"
        ]
        if !self.combinedProcesses {
            arguments.insert(contentsOf: ["-n", "\(self.numberOfProcesses)"], at: 4)
        }
        task.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        defer {
            outputPipe.fileHandleForReading.closeFile()
            errorPipe.fileHandleForReading.closeFile()
        }

        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
        } catch let err {
            error("top(): \(err.localizedDescription)", log: self.log)
            return
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)
        let errorOutput = String(data: errorData, encoding: .utf8)
        if let errorOutput, !errorOutput.isEmpty {
            error("top(): \(errorOutput)", log: self.log)
        }
        guard let output, !output.isEmpty else { return }

        var processes: [SwapProcess] = []
        output.enumerateLines { (line, _) in
            if let process = SwapProcessReader.parseProcess(line) {
                processes.append(process)
            }
        }

        if !self.combinedProcesses {
            self.callback(processes.filter { $0.compressed > 0 })
            return
        }

        var processGroups: [String: [SwapProcess]] = [:]
        for process in processes {
            let responsiblePid = ProcessReader.getResponsiblePid(process.pid)
            let groupKey = "\(responsiblePid)"

            if processGroups[groupKey] != nil {
                processGroups[groupKey]!.append(process)
            } else {
                processGroups[groupKey] = [process]
            }
        }

        var result: [SwapProcess] = []
        for (_, processes) in processGroups {
            let firstProcess = processes.first!
            let responsiblePid = ProcessReader.getResponsiblePid(firstProcess.pid)
            let name: String

            if let app = NSRunningApplication(processIdentifier: pid_t(responsiblePid)),
               let appName = app.localizedName {
                name = appName
            } else {
                name = firstProcess.name
            }

            result.append(SwapProcess(
                pid: responsiblePid,
                name: name,
                memory: processes.reduce(0) { $0 + $1.memory },
                compressed: processes.reduce(0) { $0 + $1.compressed },
                pageins: processes.reduce(0) { $0 + $1.pageins }
            ))
        }

        result.sort { $0.compressed > $1.compressed }
        self.callback(Array(result.filter { $0.compressed > 0 }.prefix(self.numberOfProcesses)))
    }

    static func parseProcess(_ raw: String) -> SwapProcess? {
        var str = raw.trimmingCharacters(in: .whitespaces)
        let pidString = str.find(pattern: "^\\d+\\**")
        guard !pidString.isEmpty, let range = str.range(of: pidString) else {
            return nil
        }

        str = str.replacingCharacters(in: range, with: "")
        var arr = str.split(separator: " ")
        guard arr.count >= 4 else { return nil }

        let pageinsString = arr.removeLast()
        let compressedString = arr.removeLast()
        let memoryString = arr.removeLast()
        let command = arr.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let pid = Int(pidString.filter("01234567890".contains)) ?? 0
        let pageins = Int(pageinsString.filter("01234567890".contains)) ?? 0
        var name = command

        if let app = NSRunningApplication(processIdentifier: pid_t(pid)), let n = app.localizedName {
            name = n
        }

        if command.contains("com.apple.Virtua") && name.contains("Docker") {
            name = "Docker"
        }

        return SwapProcess(
            pid: pid,
            name: name,
            memory: ProcessReader.parseTopMemory(memoryString),
            compressed: ProcessReader.parseTopMemory(compressedString),
            pageins: pageins
        )
    }
}
