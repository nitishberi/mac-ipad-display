import Foundation
import CoreGraphics

/// Headless iPad-only supervisor: wait → connect → watch → reconnect; stand aside for monitors.
final class ConnectionSupervisor {
    private let bridge: SidecarBridge
    private let notify: NotifySink
    private var prefs: Preferences
    private var stopRequested = false
    private var didLockAfterConnect = false
    private var consecutiveFailures = 0
    private var wasConnected = false
    private var lastHadPhysicalMonitor: Bool?
    private var displayCallbackRegistered = false

    init(bridge: SidecarBridge, notify: NotifySink, prefs: Preferences) {
        self.bridge = bridge
        self.notify = notify
        self.prefs = prefs
    }

    func updatePrefs(_ prefs: Preferences) {
        self.prefs = prefs
    }

    func requestStop() {
        stopRequested = true
    }

    func runLoop() {
        registerDisplayCallback()
        Log.info("supervisor started (iPad=\(prefs.iPadName), wiredFirst=\(prefs.wiredFirst))")

        if prefs.notifyOnSessionStart {
            notify.notify(
                event: .sessionStart,
                title: "Mac mini — session started",
                body: "MacIPadDisplay agent is running. Watching for \(prefs.iPadName).",
                priority: .high
            )
        }

        while !stopRequested {
            prefs = Preferences.load()
            let hasMonitor = DisplayMonitor.hasPhysicalMonitor()
            handleMonitorTransition(hasMonitor)

            if hasMonitor && prefs.autoConnectWhenHeadless {
                // Stand aside: do not force Sidecar while a real monitor is present.
                sleepInterval(prefs.stablePollSeconds)
                continue
            }

            if !prefs.autoConnectWhenHeadless {
                sleepInterval(prefs.stablePollSeconds)
                continue
            }

            let connected = bridge.isConnected(nameQuery: prefs.iPadName)
            if connected {
                if !wasConnected {
                    onConnected()
                }
                wasConnected = true
                consecutiveFailures = 0
                sleepInterval(prefs.stablePollSeconds)
                continue
            }

            if wasConnected {
                onDisconnected()
                wasConnected = false
            }

            attemptConnect()
            sleepInterval(prefs.waitingPollSeconds)
        }

        Log.info("supervisor stopped")
    }

    private func attemptConnect() {
        if prefs.maxConsecutiveFailures > 0 && consecutiveFailures >= prefs.maxConsecutiveFailures {
            notify.notify(
                event: .reconnectExhausted,
                title: "Mac mini — Sidecar gave up",
                body: "Failed to connect to \(prefs.iPadName) \(consecutiveFailures) times.",
                priority: .urgent
            )
            // Back off harder so we don't spam.
            sleepInterval(max(10, prefs.stablePollSeconds * 5))
            return
        }

        var options = SidecarBridge.ConnectOptions(
            wired: false,
            noSidebar: prefs.noSidebar,
            noTouchbar: prefs.noTouchbar
        )

        // Wait briefly for the device to appear (iPad may be waking).
        if bridge.waitForDevice(nameQuery: prefs.iPadName, timeout: prefs.waitingPollSeconds * 2) == nil {
            // Still missing — keep waiting silently.
            return
        }

        do {
            if prefs.wiredFirst {
                options.wired = true
                do {
                    _ = try bridge.connect(nameQuery: prefs.iPadName, options: options)
                    onConnected()
                    wasConnected = true
                    consecutiveFailures = 0
                    return
                } catch {
                    Log.info("wired connect failed, trying wireless: \(error)")
                    options.wired = false
                }
            }
            _ = try bridge.connect(nameQuery: prefs.iPadName, options: options)
            onConnected()
            wasConnected = true
            consecutiveFailures = 0
        } catch {
            consecutiveFailures += 1
            Log.warn("connect attempt failed (\(consecutiveFailures)): \(error)")
        }
    }

    private func onConnected() {
        Log.info("Sidecar connected to \(prefs.iPadName)")
        notify.notify(
            event: .sidecarConnected,
            title: "Mac mini — iPad connected",
            body: "Sidecar linked to \(prefs.iPadName) at \(Self.stamp()).",
            priority: .high
        )
        if prefs.lockAfterFirstConnect && !didLockAfterConnect {
            didLockAfterConnect = true
            // Small delay so the display finishes attaching before lock.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                LockScreen.lockNow()
            }
        }
    }

    private func onDisconnected() {
        Log.info("Sidecar disconnected from \(prefs.iPadName)")
        notify.notify(
            event: .sidecarDisconnected,
            title: "Mac mini — iPad disconnected",
            body: "Sidecar dropped at \(Self.stamp()). Reconnecting…",
            priority: .high
        )
    }

    private func handleMonitorTransition(_ hasMonitor: Bool) {
        defer { lastHadPhysicalMonitor = hasMonitor }
        guard let last = lastHadPhysicalMonitor, last != hasMonitor else { return }
        if hasMonitor {
            Log.info("physical monitor attached — standing aside")
            notify.notify(
                event: .monitorStandAside,
                title: "Mac mini — monitor attached",
                body: "Standing aside; Sidecar auto-connect paused.",
                priority: .low
            )
        } else {
            Log.info("physical monitor removed — resuming iPad auto-connect")
            notify.notify(
                event: .monitorResume,
                title: "Mac mini — monitor removed",
                body: "Resuming iPad Sidecar auto-connect.",
                priority: .default
            )
        }
    }

    private func sleepInterval(_ seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        while !stopRequested && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
    }

    private static func stamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    // MARK: - Display hotplug

    private func registerDisplayCallback() {
        guard !displayCallbackRegistered else { return }
        let err = CGDisplayRegisterReconfigurationCallback({ _, _, _ in
            // Wakes interest only; supervisor re-queries displays on the next loop tick.
        }, nil)
        if err == .success {
            displayCallbackRegistered = true
            Log.info("registered CGDisplay reconfiguration callback")
        } else {
            Log.warn("CGDisplayRegisterReconfigurationCallback failed: \(err.rawValue)")
        }
    }
}
