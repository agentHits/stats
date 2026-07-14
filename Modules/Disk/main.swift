//
//  main.swift
//  Disk
//
//  Created by Serhiy Mytrovtsiy on 07/05/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit
import WidgetKit

public struct stats: Codable {
    var read: Int64 = 0
    var write: Int64 = 0
    
    var readBytes: Int64 = 0
    var writeBytes: Int64 = 0
}

public struct smart_t: Codable {
    var temperature: Int = 0
    var life: Int = 0
    var totalRead: Int64 = 0
    var totalWritten: Int64 = 0
    var powerCycles: Int = 0
    var powerOnHours: Int = 0
}

public struct drive: Codable {
    var parent: io_object_t = 0
    
    var uuid: String = ""
    var mediaName: String = ""
    var BSDName: String = ""
    
    var root: Bool = false
    var removable: Bool = false
    
    var model: String = ""
    var path: URL?
    var connectionType: String = ""
    var fileSystem: String = ""
    
    var size: Int64 = 1
    var free: Int64 = 0
    
    var activity: stats = stats()
    var smart: smart_t? = nil
    
    public var percentage: Double {
        let total = self.size
        let free = self.free
        var usedSpace = total - free
        if usedSpace < 0 {
            usedSpace = 0
        }
        if total == 0 {
            return 0
        }
        return Double(usedSpace) / Double(total)
    }
    
    public var popupState: Bool {
        Store.shared.bool(key: "Disk_\(self.uuid)_popup", defaultValue: true)
    }
    
    public func remote() -> String {
        return "\(self.uuid),\(self.size),\(self.size-self.free),\(self.free),\(self.activity.read),\(self.activity.write)"
    }
}

public class Disks: Codable, RemoteType {
    private var queue: DispatchQueue = DispatchQueue(label: "eu.exelban.Stats.Disk.SynchronizedArray")
    private var _array: [drive] = []
    public var array: [drive] {
        get { self.queue.sync { self._array } }
        set { self.queue.sync { self._array = newValue } }
    }
    
    enum CodingKeys: String, CodingKey {
        case array
    }
    
    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.array = try container.decode(Array<drive>.self, forKey: CodingKeys.array)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(array, forKey: .array)
    }
    
    init() {}
    
    public var count: Int {
        self.queue.sync { self._array.count }
    }
    
    public func first(where predicate: (drive) -> Bool) -> drive? {
        return self.array.first(where: predicate)
    }
    
    public func index(where predicate: (drive) -> Bool) -> Int? {
        return self.array.firstIndex(where: predicate)
    }
    
    public func map<ElementOfResult>(_ transform: (drive) -> ElementOfResult?) -> [ElementOfResult] {
        return self.array.compactMap(transform)
    }
    
    public func filter(where isIncluded: (drive) -> Bool) -> [drive] {
        return self.array.filter(isIncluded)
    }
    
    public func reversed() -> [drive] {
        return self.array.reversed()
    }
    
    func forEach(_ body: (drive) -> Void) {
        self.array.forEach(body)
    }
    
    public func append( _ element: drive) {
        if !self.array.contains(where: {$0.BSDName == element.BSDName}) {
            self.array.append(element)
        }
    }
    
    public func remove(at index: Int) {
        self.array.remove(at: index)
    }
    
    public func sort() {
        self.array.sort{ $1.removable }
    }
    
    func updateFreeSize(_ idx: Int, newValue: Int64) {
        self.array[idx].free = newValue
    }
    
    func updateReadWrite(_ idx: Int, read: Int64, write: Int64) {
        self.array[idx].activity.readBytes = read
        self.array[idx].activity.writeBytes = write
    }
    
    func updateRead(_ idx: Int, newValue: Int64) {
        self.array[idx].activity.read = newValue
    }
    
    func updateWrite(_ idx: Int, newValue: Int64) {
        self.array[idx].activity.write = newValue
    }
    
    func updateSMARTData(_ idx: Int, smart: smart_t?) {
        self.array[idx].smart = smart
    }
    
    public func remote() -> Data? {
        let arr = self.array.filter({ !$0.removable })
        var string = "\(arr.count),"
        for (i, v) in arr.enumerated() {
            string += v.remote()
            if i != self.array.count {
                string += ","
            }
        }
        string += "$"
        return string.data(using: .utf8)
    }
}

public struct Disk_process: Process_p, Codable {
    public var base: DataSizeBase {
        DataSizeBase(rawValue: Store.shared.string(key: "\(ModuleType.disk.stringValue)_base", defaultValue: "byte")) ?? .byte
    }
    public var speedUnit: String {
        networkSpeedUnit(from: Store.shared.string(key: "\(ModuleType.disk.stringValue)_speedUnit", defaultValue: NetworkSpeedUnitAuto)).key
    }
    
    public var pid: Int
    public var name: String
    public var bundleIdentifier: String?
    public var executablePath: String?
    public var icon: NSImage {
        if let app = NSRunningApplication(processIdentifier: pid_t(self.pid)) {
            return app.icon ?? Constants.defaultProcessIcon
        }
        return Constants.defaultProcessIcon
    }
    
    var read: Int
    var write: Int
    
    init(pid: Int, name: String, read: Int, write: Int) {
        self.pid = pid
        self.name = name
        self.read = read
        self.write = write
        
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            if let name = app.localizedName {
                self.name = name
            }
            self.bundleIdentifier = app.bundleIdentifier
            self.executablePath = app.executableURL?.path
        } else if name.hasPrefix("/") {
            self.executablePath = name
        }
    }
}

public enum DiskActivityPeriod: String, CaseIterable, Codable {
    case hour1 = "1h"
    case hour3 = "3h"
    case hour6 = "6h"
    case hour12 = "12h"
    case day1 = "24h"
    case day3 = "3d"
    case day7 = "7d"

    public var interval: TimeInterval {
        switch self {
        case .hour1: return 60 * 60
        case .hour3: return 3 * 60 * 60
        case .hour6: return 6 * 60 * 60
        case .hour12: return 12 * 60 * 60
        case .day1: return 24 * 60 * 60
        case .day3: return 3 * 24 * 60 * 60
        case .day7: return 7 * 24 * 60 * 60
        }
    }

    public var title: String {
        switch self {
        case .hour1: return "1 hour"
        case .hour3: return "3 hours"
        case .hour6: return "6 hours"
        case .hour12: return "12 hours"
        case .day1: return "24 hours"
        case .day3: return "3 days"
        case .day7: return "7 days"
        }
    }

    public static var menuItems: [KeyValue_t] {
        Self.allCases.map { KeyValue_t(key: $0.rawValue, value: $0.title) }
    }
}

public enum DiskActivityProcessSort: String, CaseIterable, Codable {
    case total
    case read
    case write

    public var title: String {
        switch self {
        case .total: return "Total"
        case .read: return "Read"
        case .write: return "Write"
        }
    }

    public static var menuItems: [KeyValue_t] {
        Self.allCases.map { KeyValue_t(key: $0.rawValue, value: $0.title) }
    }
}

func diskActivitySaturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    guard overflow else { return sum }
    return rhs >= 0 ? .max : .min
}

public struct DiskActivityProcessSummary: Codable {
    public let identity: String
    public let pid: Int
    public let name: String
    public let bundleIdentifier: String?
    public let executablePath: String?
    public let read: Int64
    public let write: Int64
    public let total: Int64
    public let share: Double
}

public struct DiskActivityTimelinePoint: Codable {
    public let read: Int64
    public let write: Int64

    public var total: Int64 {
        diskActivitySaturatingAdd(self.read, self.write)
    }
}

public enum DiskActivityDataState: String, Codable {
    case ready
    case collecting
    case partial
    case stale
    case empty
}

public struct DiskActivityCoverage: Codable {
    public let requestedStart: TimeInterval
    public let requestedEnd: TimeInterval
    public let coverageStart: TimeInterval?
    public let coverageEnd: TimeInterval?
    public let coveredDuration: TimeInterval
    public let coverageRatio: Double
    public let actualBucketCount: Int
    public let expectedBucketCount: Int
    public let lastUpdatedAt: TimeInterval?
    public let state: DiskActivityDataState

    public var hasData: Bool {
        self.actualBucketCount != 0
    }

    public var isComplete: Bool {
        self.state == .ready
    }
}

public struct DiskActivitySummary: Codable {
    public let period: DiskActivityPeriod
    public let read: Int64
    public let write: Int64
    public let total: Int64
    public let peakRead: Int64
    public let peakWrite: Int64
    public let capturedProcessRead: Int64
    public let capturedProcessWrite: Int64
    public let capturedProcessTotal: Int64
    public let hiddenProcessRead: Int64
    public let hiddenProcessWrite: Int64
    public let hiddenProcessTotal: Int64
    public let unattributedRead: Int64
    public let unattributedWrite: Int64
    public let unattributedTotal: Int64
    public let diskSampleCount: Int
    public let processSampleCount: Int
    public let totalProcessCount: Int
    public let timeline: [DiskActivityTimelinePoint]
    public let coverage: DiskActivityCoverage
    public let processes: [DiskActivityProcessSummary]

    public var hasData: Bool {
        self.diskSampleCount != 0 || self.processSampleCount != 0
    }
}

private struct DiskActivityDiskBucket: Codable {
    var ts: TimeInterval
    var diskID: String
    var read: Int64
    var write: Int64
    var peakRead: Int64
    var peakWrite: Int64
}

private struct DiskActivityProcessBucket: Codable {
    var ts: TimeInterval
    var identity: String
    var pid: Int
    var name: String
    var bundleIdentifier: String?
    var executablePath: String?
    var read: Int64
    var write: Int64
}

private struct DiskActivityHistorySnapshot: Codable {
    var disk: [DiskActivityDiskBucket] = []
    var processes: [DiskActivityProcessBucket] = []
}

public final class DiskActivityHistoryStore {
    public static let shared = DiskActivityHistoryStore()

    private let queue = DispatchQueue(label: "eu.exelban.Stats.Disk.ActivityHistory")
    private let bucketSize: TimeInterval = 60
    private let retention: TimeInterval = DiskActivityPeriod.day7.interval
    private let maxProcessesPerRead = 24
    private let maxProcessesPerBucket = 24
    private var snapshot = DiskActivityHistorySnapshot()

    public init(persistenceURL _: URL? = nil) {}

    public func recordDisk(diskID: String, read: Int64, write: Int64, at date: Date = Date()) {
        let safeRead = max(0, read)
        let safeWrite = max(0, write)

        self.queue.sync {
            let bucketTS = self.bucketStart(for: date)
            if let idx = self.snapshot.disk.firstIndex(where: { $0.ts == bucketTS && $0.diskID == diskID }) {
                self.snapshot.disk[idx].read = diskActivitySaturatingAdd(self.snapshot.disk[idx].read, safeRead)
                self.snapshot.disk[idx].write = diskActivitySaturatingAdd(self.snapshot.disk[idx].write, safeWrite)
                self.snapshot.disk[idx].peakRead = max(self.snapshot.disk[idx].peakRead, safeRead)
                self.snapshot.disk[idx].peakWrite = max(self.snapshot.disk[idx].peakWrite, safeWrite)
            } else {
                self.snapshot.disk.append(DiskActivityDiskBucket(
                    ts: bucketTS,
                    diskID: diskID,
                    read: safeRead,
                    write: safeWrite,
                    peakRead: safeRead,
                    peakWrite: safeWrite
                ))
            }
            self.pruneLocked(now: date)
        }
    }

    public func recordDisk(_ disk: drive, at date: Date = Date()) {
        self.recordDisk(diskID: disk.uuid, read: disk.activity.read, write: disk.activity.write, at: date)
    }

    public func recordProcesses(_ processes: [Disk_process], at date: Date = Date()) {
        let active = processes
            .filter { $0.read > 0 || $0.write > 0 }
            .sorted { lhs, rhs in
                let lhsTotal = diskActivitySaturatingAdd(Int64(max(0, lhs.read)), Int64(max(0, lhs.write)))
                let rhsTotal = diskActivitySaturatingAdd(Int64(max(0, rhs.read)), Int64(max(0, rhs.write)))
                if lhsTotal == rhsTotal {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhsTotal > rhsTotal
            }
            .prefix(self.maxProcessesPerRead)
        guard !active.isEmpty else { return }

        self.queue.sync {
            let bucketTS = self.bucketStart(for: date)
            active.forEach { process in
                let identity = self.identity(for: process)
                let safeRead = Int64(max(0, process.read))
                let safeWrite = Int64(max(0, process.write))
                if let idx = self.snapshot.processes.firstIndex(where: { $0.ts == bucketTS && ($0.identity == identity || $0.pid == process.pid) }) {
                    self.snapshot.processes[idx].read = diskActivitySaturatingAdd(self.snapshot.processes[idx].read, safeRead)
                    self.snapshot.processes[idx].write = diskActivitySaturatingAdd(self.snapshot.processes[idx].write, safeWrite)
                    self.snapshot.processes[idx].pid = process.pid
                    if process.bundleIdentifier != nil {
                        self.snapshot.processes[idx].bundleIdentifier = process.bundleIdentifier
                        self.snapshot.processes[idx].identity = identity
                    }
                    if process.executablePath != nil {
                        self.snapshot.processes[idx].executablePath = process.executablePath
                    }
                    self.snapshot.processes[idx].name = self.displayName(
                        name: process.name,
                        bundleIdentifier: self.snapshot.processes[idx].bundleIdentifier,
                        executablePath: self.snapshot.processes[idx].executablePath
                    )
                } else {
                    self.snapshot.processes.append(DiskActivityProcessBucket(
                        ts: bucketTS,
                        identity: identity,
                        pid: process.pid,
                        name: self.displayName(for: process),
                        bundleIdentifier: process.bundleIdentifier,
                        executablePath: process.executablePath,
                        read: safeRead,
                        write: safeWrite
                    ))
                }
            }
            self.pruneLocked(now: date)
            self.trimProcessBucketLocked(bucketTS)
        }
    }

    public func summary(
        diskID: String?,
        period: DiskActivityPeriod,
        sort: DiskActivityProcessSort = .total,
        limit: Int = 6,
        timelinePoints: Int = 24,
        now: Date = Date()
    ) -> DiskActivitySummary {
        self.queue.sync {
            let nowTS = now.timeIntervalSince1970
            let minTS = nowTS - period.interval
            let diskBuckets = self.snapshot.disk.filter { bucket in
                bucket.ts >= minTS && (diskID == nil || bucket.diskID == diskID)
            }
            let processBuckets = self.snapshot.processes.filter { $0.ts >= minTS }

            let read = diskBuckets.reduce(Int64(0)) { diskActivitySaturatingAdd($0, $1.read) }
            let write = diskBuckets.reduce(Int64(0)) { diskActivitySaturatingAdd($0, $1.write) }
            let peakRead = diskBuckets.map { $0.peakRead }.max() ?? 0
            let peakWrite = diskBuckets.map { $0.peakWrite }.max() ?? 0
            let timeline = self.timeline(from: diskBuckets, startTS: minTS, endTS: nowTS, points: timelinePoints)
            let coverage = self.coverage(from: diskBuckets, startTS: minTS, endTS: nowTS)

            var grouped: [String: DiskActivityProcessBucket] = [:]
            processBuckets.forEach { bucket in
                let groupKey = self.groupKey(for: bucket, in: grouped)
                if var existing = grouped[groupKey] {
                    existing.read = diskActivitySaturatingAdd(existing.read, bucket.read)
                    existing.write = diskActivitySaturatingAdd(existing.write, bucket.write)
                    existing.pid = bucket.pid
                    if bucket.bundleIdentifier != nil {
                        existing.identity = bucket.identity
                    }
                    if existing.bundleIdentifier == nil {
                        existing.bundleIdentifier = bucket.bundleIdentifier
                    }
                    if existing.executablePath == nil {
                        existing.executablePath = bucket.executablePath
                    }
                    existing.name = self.displayName(
                        name: bucket.name,
                        bundleIdentifier: existing.bundleIdentifier,
                        executablePath: existing.executablePath
                    )
                    grouped.removeValue(forKey: groupKey)
                    grouped[existing.identity] = existing
                } else {
                    grouped[bucket.identity] = bucket
                }
            }

            let capturedProcessRead = grouped.values.reduce(Int64(0)) { diskActivitySaturatingAdd($0, $1.read) }
            let capturedProcessWrite = grouped.values.reduce(Int64(0)) { diskActivitySaturatingAdd($0, $1.write) }
            let capturedProcessTotal = diskActivitySaturatingAdd(capturedProcessRead, capturedProcessWrite)
            let unattributedRead = max(0, read - capturedProcessRead)
            let unattributedWrite = max(0, write - capturedProcessWrite)
            let unattributedTotal = diskActivitySaturatingAdd(unattributedRead, unattributedWrite)
            let shareDenominator = max(
                diskActivitySaturatingAdd(read, write),
                diskActivitySaturatingAdd(capturedProcessTotal, unattributedTotal)
            )
            let rows = grouped.values.map { bucket -> DiskActivityProcessSummary in
                let total = diskActivitySaturatingAdd(bucket.read, bucket.write)
                let share = shareDenominator == 0 ? 0 : Double(total) / Double(shareDenominator)
                return DiskActivityProcessSummary(
                    identity: bucket.identity,
                    pid: bucket.pid,
                    name: bucket.name,
                    bundleIdentifier: bucket.bundleIdentifier,
                    executablePath: bucket.executablePath,
                    read: bucket.read,
                    write: bucket.write,
                    total: total,
                    share: share
                )
            }.sorted { lhs, rhs in
                switch sort {
                case .total:
                    if lhs.total == rhs.total {
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                    return lhs.total > rhs.total
                case .read:
                    if lhs.read == rhs.read { return lhs.total > rhs.total }
                    return lhs.read > rhs.read
                case .write:
                    if lhs.write == rhs.write { return lhs.total > rhs.total }
                    return lhs.write > rhs.write
                }
            }
            let visibleRows = Array(rows.prefix(limit))
            let hiddenRows = rows.dropFirst(max(0, limit))
            let hiddenProcessRead = hiddenRows.reduce(Int64(0)) { diskActivitySaturatingAdd($0, $1.read) }
            let hiddenProcessWrite = hiddenRows.reduce(Int64(0)) { diskActivitySaturatingAdd($0, $1.write) }
            let hiddenProcessTotal = diskActivitySaturatingAdd(hiddenProcessRead, hiddenProcessWrite)

            return DiskActivitySummary(
                period: period,
                read: read,
                write: write,
                total: diskActivitySaturatingAdd(read, write),
                peakRead: peakRead,
                peakWrite: peakWrite,
                capturedProcessRead: capturedProcessRead,
                capturedProcessWrite: capturedProcessWrite,
                capturedProcessTotal: capturedProcessTotal,
                hiddenProcessRead: hiddenProcessRead,
                hiddenProcessWrite: hiddenProcessWrite,
                hiddenProcessTotal: hiddenProcessTotal,
                unattributedRead: unattributedRead,
                unattributedWrite: unattributedWrite,
                unattributedTotal: unattributedTotal,
                diskSampleCount: diskBuckets.count,
                processSampleCount: processBuckets.count,
                totalProcessCount: rows.count,
                timeline: timeline,
                coverage: coverage,
                processes: visibleRows
            )
        }
    }

    public func prune(now: Date = Date()) {
        self.queue.sync {
            self.pruneLocked(now: now)
        }
    }

    public func flush() {}

    private func identity(for process: Disk_process) -> String {
        if let bundle = process.bundleIdentifier, !bundle.isEmpty {
            return bundle
        }
        return process.name
    }

    private func groupKey(for bucket: DiskActivityProcessBucket, in grouped: [String: DiskActivityProcessBucket]) -> String {
        if grouped[bucket.identity] != nil {
            return bucket.identity
        }
        if let pidMatch = grouped.first(where: { _, existing in existing.pid == bucket.pid && self.canMerge(existing, with: bucket) }) {
            return pidMatch.key
        }
        return bucket.identity
    }

    private func canMerge(_ lhs: DiskActivityProcessBucket, with rhs: DiskActivityProcessBucket) -> Bool {
        if lhs.identity == rhs.identity {
            return true
        }
        guard lhs.pid == rhs.pid else {
            return false
        }
        if lhs.name == rhs.name {
            return true
        }
        return lhs.bundleIdentifier != nil || rhs.bundleIdentifier != nil || lhs.executablePath != nil || rhs.executablePath != nil
    }

    private func displayName(for process: Disk_process) -> String {
        self.displayName(
            name: process.name,
            bundleIdentifier: process.bundleIdentifier,
            executablePath: process.executablePath
        )
    }

    private func displayName(name: String, bundleIdentifier: String?, executablePath: String?) -> String {
        let bundle = bundleIdentifier?.lowercased() ?? ""
        let executable = executablePath?.lowercased() ?? ""
        let executableName = executablePath.map { ($0 as NSString).lastPathComponent.lowercased() } ?? ""
        if bundle.contains("drivefs") ||
            executable.contains("/google drive.app/") ||
            executableName == "google drive" ||
            executable.contains("drivefs") {
            return "Google Drive"
        }
        return name
    }

    private func bucketStart(for date: Date) -> TimeInterval {
        floor(date.timeIntervalSince1970 / self.bucketSize) * self.bucketSize
    }

    private func timeline(
        from buckets: [DiskActivityDiskBucket],
        startTS: TimeInterval,
        endTS: TimeInterval,
        points requestedPoints: Int
    ) -> [DiskActivityTimelinePoint] {
        let count = max(1, requestedPoints)
        let duration = max(1, endTS - startTS)
        let step = duration / TimeInterval(count)
        return (0..<count).map { idx in
            let segmentStart = startTS + TimeInterval(idx) * step
            let segmentEnd = idx == count - 1 ? endTS + self.bucketSize : segmentStart + step
            let segment = buckets.filter { $0.ts >= segmentStart && $0.ts < segmentEnd }
            return DiskActivityTimelinePoint(
                read: segment.reduce(Int64(0)) { diskActivitySaturatingAdd($0, $1.read) },
                write: segment.reduce(Int64(0)) { diskActivitySaturatingAdd($0, $1.write) }
            )
        }
    }

    private func coverage(
        from buckets: [DiskActivityDiskBucket],
        startTS: TimeInterval,
        endTS: TimeInterval
    ) -> DiskActivityCoverage {
        let expectedBucketCount = max(1, Int(ceil(max(1, endTS - startTS) / self.bucketSize)))
        let bucketTimes = Set(buckets.map(\.ts))
        let actualBucketCount = min(bucketTimes.count, expectedBucketCount)
        let coverageStart = bucketTimes.min()
        let coverageEnd = bucketTimes.max()
        let coverageRatio = min(1, Double(actualBucketCount) / Double(expectedBucketCount))
        let coveredDuration = min(max(0, endTS - startTS), TimeInterval(actualBucketCount) * self.bucketSize)

        let state: DiskActivityDataState
        if actualBucketCount == 0 {
            state = .empty
        } else if coverageRatio >= 0.995 {
            state = .ready
        } else if let coverageEnd, endTS - coverageEnd > self.bucketSize * 2 {
            state = .stale
        } else if let coverageStart, coverageStart > startTS + self.bucketSize {
            state = .collecting
        } else {
            state = .partial
        }

        return DiskActivityCoverage(
            requestedStart: startTS,
            requestedEnd: endTS,
            coverageStart: coverageStart,
            coverageEnd: coverageEnd,
            coveredDuration: coveredDuration,
            coverageRatio: coverageRatio,
            actualBucketCount: actualBucketCount,
            expectedBucketCount: expectedBucketCount,
            lastUpdatedAt: coverageEnd,
            state: state
        )
    }

    private func pruneLocked(now: Date) {
        let minTS = now.timeIntervalSince1970 - self.retention
        self.snapshot.disk.removeAll { $0.ts < minTS }
        self.snapshot.processes.removeAll { $0.ts < minTS }
    }

    private func trimProcessBucketLocked(_ bucketTS: TimeInterval) {
        let bucketIndexes = self.snapshot.processes.indices.filter { self.snapshot.processes[$0].ts == bucketTS }
        guard bucketIndexes.count > self.maxProcessesPerBucket else { return }

        let keep = Set(bucketIndexes.sorted { lhs, rhs in
            let lhsBucket = self.snapshot.processes[lhs]
            let rhsBucket = self.snapshot.processes[rhs]
            let lhsTotal = diskActivitySaturatingAdd(lhsBucket.read, lhsBucket.write)
            let rhsTotal = diskActivitySaturatingAdd(rhsBucket.read, rhsBucket.write)
            if lhsTotal == rhsTotal {
                return lhsBucket.name.localizedCaseInsensitiveCompare(rhsBucket.name) == .orderedAscending
            }
            return lhsTotal > rhsTotal
        }.prefix(self.maxProcessesPerBucket))

        self.snapshot.processes = self.snapshot.processes.enumerated().compactMap { idx, bucket in
            bucket.ts == bucketTS && !keep.contains(idx) ? nil : bucket
        }
    }
}

public class Disk: Module {
    private let popupView: Popup = Popup(.disk)
    private let settingsView: Settings = Settings(.disk)
    private let portalView: Portal = Portal(.disk)
    private let notificationsView: Notifications = Notifications(.disk)
    private let previewView: Preview = Preview(.disk)
    
    private var capacityReader: CapacityReader?
    private var activityReader: ActivityReader?
    private var processReader: ProcessReader?
    
    private var selectedDisk: String = ""
    
    private var textValue: String {
        Store.shared.string(key: "\(self.name)_textWidgetValue", defaultValue: "$capacity.free/$capacity.total")
    }
    
    private var systemWidgetsUpdatesState: Bool {
        self.userDefaults?.bool(forKey: "systemWidgetsUpdates_state") ?? false
    }
    
    private var mainColor: NSColor {
        SColor.fromString(Store.shared.string(key: "\(self.name)_mainColor", defaultValue: SColor.secondBlue.key)).additional as! NSColor
    }
    
    public init() {
        super.init(
            moduleType: .disk,
            popup: self.popupView,
            settings: self.settingsView,
            portal: self.portalView,
            notifications: self.notificationsView,
            preview: self.previewView
        )
        guard self.available else { return }
        
        self.capacityReader = CapacityReader(.disk) { [weak self] value in
            if let value {
                self?.capacityCallback(value)
            }
        }
        self.activityReader = ActivityReader(.disk) { [weak self] value in
            if let value {
                self?.activityCallback(value)
            }
        }
        self.processReader = ProcessReader(.disk) { [weak self] value in
            if let list = value {
                self?.popupView.processCallback(list)
                self?.previewView.processCallback()
            }
        }
        
        self.selectedDisk = Store.shared.string(key: "\(ModuleType.disk.stringValue)_disk", defaultValue: self.selectedDisk)
        
        self.settingsView.selectedDiskHandler = { [weak self] value in
            self?.selectedDisk = value
            self?.capacityReader?.read()
        }
        self.settingsView.callback = { [weak self] in
            self?.capacityReader?.read()
        }
        self.settingsView.setInterval = { [weak self] value in
            self?.capacityReader?.setInterval(value)
        }
        self.settingsView.callbackWhenUpdateNumberOfProcesses = { [weak self] in
            self?.popupView.numberOfProcessesUpdated()
            DispatchQueue.global(qos: .background).async {
                self?.processReader?.read()
            }
        }
        
        self.setReaders([self.capacityReader, self.activityReader, self.processReader])
        NotificationCenter.default.addObserver(self, selector: #selector(self.batterySaverModeDidChange), name: .batterySaverModeDidChange, object: nil)
        self.applyBatterySaverPolicy()
    }

    @objc private func batterySaverModeDidChange() {
        self.applyBatterySaverPolicy()
    }

    private func applyBatterySaverPolicy() {
        self.capacityReader?.sleepMode(state: BatterySaverPolicy.shared.shouldPauseDetailedDiskReader(module: .disk))
        self.processReader?.sleepMode(state: BatterySaverPolicy.shared.shouldPauseDetailedProcessReader(module: .disk))
        self.syncSleepingReadersWithVisibility()
    }

    private func capacityCallback(_ value: Disks) {
        guard self.enabled else { return }
        
        DispatchQueue.main.async(execute: {
            self.popupView.capacityCallback(value)
            self.previewView.capacityCallback(value)
        })
        self.settingsView.setList(value)
        
        guard let d = value.first(where: { $0.mediaName == self.selectedDisk }) ?? value.first(where: { $0.root }) else {
            return
        }
        
        self.portalView.utilizationCallback(d)
        self.notificationsView.utilizationCallback(d.percentage)
        
        self.menuBar.widgets.filter{ $0.isActive }.forEach { (w: SWidget) in
            switch w.item {
            case let widget as Mini: widget.setValue(d.percentage)
            case let widget as BarChart: widget.setValue([[ColorValue(d.percentage)]])
            case let widget as MemoryWidget:
                widget.setValue((DiskSize(d.free).getReadableMemory(), DiskSize(d.size - d.free).getReadableMemory()), usedPercentage: d.percentage)
            case let widget as PieChart:
                widget.setValue([
                    ColorValue(d.percentage, color: self.mainColor)
                ])
            case let widget as TextWidget:
                var text = "\(self.textValue)"
                let pairs = TextWidget.parseText(text)
                pairs.forEach { pair in
                    var replacement: String? = nil
                    
                    switch pair.key {
                    case "$capacity":
                        switch pair.value {
                        case "total": replacement = DiskSize(d.size).getReadableMemory()
                        case "used": replacement = DiskSize(d.size - d.free).getReadableMemory()
                        case "free": replacement = DiskSize(d.free).getReadableMemory()
                        default: return
                        }
                    case "$percentage":
                        var percentage: Int
                        if d.size == 0 {
                            percentage = 0
                        } else {
                            switch pair.value {
                            case "used": percentage = Int((Double(d.size - d.free) / Double(d.size)) * 100)
                            case "free": percentage = Int((Double(d.free) / Double(d.size)) * 100)
                            default: return
                            }
                        }
                        replacement = "\(percentage < 0 ? 0 : percentage)%"
                    default: return
                    }
                    
                    if let replacement {
                        let key = pair.value.isEmpty ? pair.key : "\(pair.key).\(pair.value)"
                        text = text.replacingOccurrences(of: key, with: replacement)
                    }
                }
                widget.setValue(text)
            default: break
            }
        }
        
        if self.systemWidgetsUpdatesState {
            if isWidgetActive(self.userDefaults, [Disk_entry.kind, "UnitedWidget"]), let blobData = try? JSONEncoder().encode(d) {
                self.userDefaults?.set(blobData, forKey: "Disk@CapacityReader")
            }
            WidgetCenter.shared.reloadTimelines(ofKind: Disk_entry.kind)
            WidgetCenter.shared.reloadTimelines(ofKind: "UnitedWidget")
        }
    }
    
    private func activityCallback(_ value: Disks) {
        guard self.enabled else { return }
        
        DispatchQueue.main.async(execute: {
            self.popupView.activityCallback(value)
            self.previewView.activityCallback(value)
        })
        
        guard let d = value.first(where: { $0.mediaName == self.selectedDisk }) ?? value.first(where: { $0.root }) else {
            return
        }
        
        self.portalView.activityCallback(d)
        
        self.menuBar.widgets.filter{ $0.isActive }.forEach { (w: SWidget) in
            switch w.item {
            case let widget as SpeedWidget:
                widget.setValue(input: d.activity.read, output: d.activity.write)
            case let widget as NetworkChart:
                widget.setValue(upload: Double(d.activity.write), download: Double(d.activity.read))
                if self.capacityReader?.interval != 1 {
                    self.settingsView.setUpdateInterval(value: 1)
                }
            default: break
            }
        }
    }
}
