//
//  AppDelegate.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 28.05.2019.
//  Copyright © 2019 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import IOKit.ps

import Kit
import UserNotifications

import CPU
import RAM
import Disk
import Net
import Battery
import Sensors
import GPU
import Bluetooth
import Clock
import Remote

let updater = Updater(github: "exelban/stats", url: "https://api.mac-stats.com/release/latest")
var modules: [Module] = [
    CPU(),
    GPU(),
    RAM(),
    Disk(),
    Sensors(),
    Network(),
    Battery(),
    Bluetooth(),
    Clock(),
    Remote()
]

@main
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    internal var settingsWindow: SettingsWindow?
    internal var updateWindow: UpdateWindow?
    internal var setupWindow: SetupWindow?
    internal var supportWindow: SupportWindow?
    
    internal var menuBarItem: NSStatusItem? = nil
    internal var combinedView: CombinedView = CombinedView()
    
    internal let updateActivity = NSBackgroundActivityScheduler(identifier: "eu.exelban.Stats.updateCheck")
    internal let supportActivity = NSBackgroundActivityScheduler(identifier: "eu.exelban.Stats.support")
    
    internal var clickInNotification: Bool = false
    private var batterySaverNotificationID: String?
    private var powerSourceRunLoop: CFRunLoop?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    
    internal var pauseState: Bool {
        Store.shared.bool(key: "pause", defaultValue: false)
    }
    
    private var startTS: Date?
    private var launchStart: Date?
    
    static func main() {
        let launchStart = Date()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        delegate.launchStart = launchStart
        app.delegate = delegate
        app.run()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let startingPoint = self.launchStart ?? Date()
        
        self.parseArguments()
        self.parseVersion()
        SMCHelper.shared.checkForUpdate()
        self.setup {
            modules.reversed().forEach{ $0.mount() }
            self.showSettingsIfNoActiveWidgets()
        }
        self.defaultValues()
        self.icon()
        
        NotificationCenter.default.addObserver(self, selector: #selector(listenForAppPause), name: .pause, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleToggleSettings), name: .toggleSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRemoteAuthenticated), name: .remoteAuthenticated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRemoteUpdate), name: .remoteUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleBatterySaverModeDidChange), name: .batterySaverModeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePowerStateDidChange(_:)), name: ProcessInfo.powerStateDidChangeNotification, object: nil)
        self.startBatterySaverPowerSourceObserver()
        self.refreshPowerSource()
        self.refreshLowPowerMode()
        
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
        
        info("Stats started in \((startingPoint.timeIntervalSinceNow * -1).rounded(toPlaces: 4)) seconds")
        self.startTS = Date()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        self.stopBatterySaverPowerSourceObserver()
        modules.forEach{ $0.terminate() }
        SystemStats.shared.terminate()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if self.clickInNotification {
            self.clickInNotification = false
            return true
        }
        guard let startTS = self.startTS, Date().timeIntervalSince(startTS) > 2 else { return false }
        
        let window = self.ensureSettingsWindow()
        if flag {
            window.makeKeyAndOrderFront(self)
        } else {
            window.setIsVisible(true)
        }
        
        return true
    }
    
    @objc private func handleToggleSettings(_ notification: Notification) {
        let module = notification.userInfo?["module"] as? String
        self.ensureSettingsWindow().open(module: module)
    }
    
    @objc private func handleRemoteAuthenticated() {
        DispatchQueue.main.async {
            self.checkIfShouldShowSupportWindow()
        }
    }
    
    @objc private func handleRemoteUpdate() {
        DispatchQueue.main.async {
            self.checkForNewVersion(silent: true)
        }
    }
    
    private func showSettingsIfNoActiveWidgets() {
        if self.pauseState { return }
        let hasActive = modules.contains(where: { $0.enabled != false && $0.available != false && !$0.menuBar.widgets.filter({ $0.isActive }).isEmpty })
        if hasActive { return }
        self.ensureSettingsWindow().setIsVisible(true)
    }

    @objc private func handlePowerStateDidChange(_ notification: Notification) {
        self.refreshLowPowerMode()
    }

    private func startBatterySaverPowerSourceObserver() {
        guard self.powerSourceRunLoopSource == nil else { return }

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            appDelegate.refreshPowerSource()
        }, context).takeRetainedValue()

        let runLoop = CFRunLoopGetMain()
        self.powerSourceRunLoop = runLoop
        self.powerSourceRunLoopSource = source
        CFRunLoopAddSource(runLoop, source, .defaultMode)
    }

    private func stopBatterySaverPowerSourceObserver() {
        guard let runLoop = self.powerSourceRunLoop, let source = self.powerSourceRunLoopSource else { return }

        CFRunLoopRemoveSource(runLoop, source, .defaultMode)
        self.powerSourceRunLoop = nil
        self.powerSourceRunLoopSource = nil
    }

    private func refreshPowerSource() {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        let isBatteryPowered = sources.contains { source in
            guard let description = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any] else {
                return false
            }
            return description[kIOPSPowerSourceStateKey] as? String == "Battery Power"
        }
        BatterySaverPolicy.shared.updatePowerSource(isBatteryPowered: isBatteryPowered)
    }

    private func refreshLowPowerMode() {
        if #available(macOS 12.0, *) {
            BatterySaverPolicy.shared.updateLowPowerMode(isEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled)
        } else {
            BatterySaverPolicy.shared.updateLowPowerMode(isEnabled: false)
        }
    }

    @objc private func handleBatterySaverModeDidChange(_ notification: Notification) {
        guard let state = notification.userInfo?["state"] as? BatterySaverState else { return }

        if let id = self.batterySaverNotificationID {
            removeNotification(id)
            self.batterySaverNotificationID = nil
        }

        let title = state.active ? localizedString("Battery Saver Mode") : localizedString("Normal monitoring restored")
        let reason = state.isLowPowerModeEnabled ? localizedString("Low Power Mode is enabled") : localizedString("Mac is running on battery power")
        let subtitle = state.active ? "\(reason). \(localizedString("Stats is using fewer updates"))" : localizedString("Power adapter connected")
        let id = showNotification(title: title, subtitle: subtitle, delegate: self)
        self.batterySaverNotificationID = id

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            removeNotification(id)
            if self?.batterySaverNotificationID == id {
                self?.batterySaverNotificationID = nil
            }
        }
    }
    
    internal func ensureSettingsWindow() -> SettingsWindow {
        if let w = self.settingsWindow { return w }
        let w = SettingsWindow()
        w.onClose = { [weak self] in self?.settingsWindow = nil }
        self.settingsWindow = w
        return w
    }
    
    internal func ensureUpdateWindow() -> UpdateWindow {
        if let w = self.updateWindow { return w }
        let w = UpdateWindow()
        w.onClose = { [weak self] in self?.updateWindow = nil }
        self.updateWindow = w
        return w
    }
    
    internal func ensureSetupWindow() -> SetupWindow {
        if let w = self.setupWindow { return w }
        let w = SetupWindow()
        w.onClose = { [weak self] in self?.setupWindow = nil }
        self.setupWindow = w
        return w
    }
    
    internal func ensureSupportWindow() -> SupportWindow {
        if let w = self.supportWindow { return w }
        let w = SupportWindow()
        w.onClose = { [weak self] in self?.supportWindow = nil }
        self.supportWindow = w
        return w
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        self.clickInNotification = true
        
        if let uri = response.notification.request.content.userInfo["url"] as? String {
            debug("Downloading new version of app...")
            if let url = URL(string: uri) {
                updater.download(url, completion: { path in
                    updater.install(path: path) { error in
                        if let error {
                            showAlert("Error update Stats", error, .critical)
                        }
                    }
                })
            }
        }
        
        completionHandler()
    }
}
