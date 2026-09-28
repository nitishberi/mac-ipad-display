import AppKit
import Foundation

/// Minimal menu-bar UI: status, connect/disconnect, open config, quit.
@MainActor
final class MenuBarApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var supervisor: ConnectionSupervisor?
    private var supervisorQueue = DispatchQueue(label: "mac-ipad-display.supervisor")
    private var bridge: SidecarBridge?
    private var notify: NotifySink!
    private var prefs = Preferences.load()
    private var statusTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.setup()
        notify = NotifySink(prefs: { Preferences.load() })

        do {
            bridge = try SidecarBridge()
        } catch {
            Log.error("SidecarBridge init failed: \(error)")
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "iPad"
            button.toolTip = "MacIPadDisplay"
        }
        rebuildMenu()

        statusTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatusTitle() }
        }

        startSupervisorIfNeeded()
        refreshStatusTitle()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Status: …", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Connect Now", action: #selector(connectNow), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Disconnect", action: #selector(disconnectNow), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Start / Restart Supervisor", action: #selector(restartSupervisor), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Stop Supervisor", action: #selector(stopSupervisor), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Config…", action: #selector(openConfig), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Open Log…", action: #selector(openLog), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Send Test Notification", action: #selector(testNotify), keyEquivalent: "t"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func refreshStatusTitle() {
        prefs = Preferences.load()
        let connected = bridge?.isConnected(nameQuery: prefs.iPadName) ?? false
        let monitor = DisplayMonitor.hasPhysicalMonitor()
        if let button = statusItem.button {
            if connected {
                button.title = "iPad●"
            } else if monitor {
                button.title = "iPad—"
            } else {
                button.title = "iPad○"
            }
        }
        if let statusItem = statusItem.menu?.items.first {
            let state = connected ? "connected" : "not connected"
            let mon = monitor ? "monitor present (standing aside)" : "headless"
            statusItem.title = "\(prefs.iPadName): \(state) · \(mon)"
        }
    }

    private func startSupervisorIfNeeded() {
        guard let bridge else { return }
        supervisor?.requestStop()
        let prefs = Preferences.load()
        let sup = ConnectionSupervisor(bridge: bridge, notify: notify, prefs: prefs)
        supervisor = sup
        supervisorQueue.async {
            sup.runLoop()
        }
    }

    @objc private func connectNow() {
        guard let bridge else { return }
        prefs = Preferences.load()
        let options = SidecarBridge.ConnectOptions(
            wired: prefs.wiredFirst,
            noSidebar: prefs.noSidebar,
            noTouchbar: prefs.noTouchbar
        )
        DispatchQueue.global().async {
            do {
                _ = try bridge.connect(nameQuery: self.prefs.iPadName, options: options)
                self.notify.notify(
                    event: .sidecarConnected,
                    title: "Mac mini — iPad connected",
                    body: "Manual connect to \(self.prefs.iPadName).",
                    priority: .high
                )
            } catch {
                Log.error("manual connect failed: \(error)")
            }
            DispatchQueue.main.async { self.refreshStatusTitle() }
        }
    }

    @objc private func disconnectNow() {
        guard let bridge else { return }
        prefs = Preferences.load()
        DispatchQueue.global().async {
            do {
                try bridge.disconnect(nameQuery: self.prefs.iPadName)
                self.notify.notify(
                    event: .sidecarDisconnected,
                    title: "Mac mini — iPad disconnected",
                    body: "Manual disconnect of \(self.prefs.iPadName).",
                    priority: .high
                )
            } catch {
                Log.error("manual disconnect failed: \(error)")
            }
            DispatchQueue.main.async { self.refreshStatusTitle() }
        }
    }

    @objc private func restartSupervisor() {
        startSupervisorIfNeeded()
    }

    @objc private func stopSupervisor() {
        supervisor?.requestStop()
        supervisor = nil
    }

    @objc private func openConfig() {
        prefs = Preferences.load()
        try? prefs.save()
        NSWorkspace.shared.open(Preferences.configURL)
    }

    @objc private func openLog() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MacIPadDisplay/mac-ipad-display.log")
        NSWorkspace.shared.open(url)
    }

    @objc private func testNotify() {
        notify.notify(
            event: .sessionStart,
            title: "MacIPadDisplay test",
            body: "If you see this on your iPhone, notify is configured.",
            priority: .high
        )
    }

    @objc private func quit() {
        supervisor?.requestStop()
        NSApp.terminate(nil)
    }
}
