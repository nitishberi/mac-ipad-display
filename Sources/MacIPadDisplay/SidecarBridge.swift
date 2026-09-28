import Foundation
import Darwin

/// Runtime bridge to Apple's private SidecarCore framework.
/// Pattern adapted from sidecar-connect (MIT) and SidecarLauncher (wired transport).
final class SidecarBridge {
    enum BridgeError: Error, CustomStringConvertible {
        case frameworkLoad(String)
        case classMissing(String)
        case managerMissing
        case timeout(String)
        case connectFailed(String)
        case disconnectFailed(String)
        case noDevice

        var description: String {
            switch self {
            case .frameworkLoad(let s): return "SidecarCore load failed: \(s)"
            case .classMissing(let s): return "\(s) not found (private API may have changed)"
            case .managerMissing: return "could not obtain SidecarDisplayManager.sharedManager"
            case .timeout(let s): return "timed out: \(s)"
            case .connectFailed(let s): return "connect failed: \(s)"
            case .disconnectFailed(let s): return "disconnect failed: \(s)"
            case .noDevice: return "no matching Sidecar device"
            }
        }
    }

    struct DeviceInfo: Equatable {
        let name: String
        let identifier: String
        let connected: Bool
    }

    struct ConnectOptions {
        var wired: Bool = false
        var noSidebar: Bool = false
        var noTouchbar: Bool = false
        var timeout: TimeInterval = 20
    }

    @objc private protocol SCDevice {
        func name() -> String?
        func identifier() -> AnyObject?
    }

    @objc private protocol SCConfig {
        func setShowSideBar(_ value: Bool)
        func setShowTouchBar(_ value: Bool)
    }

    @objc private protocol SCManager {
        func devices() -> [AnyObject]
        func connectedDevices() -> [AnyObject]
        @objc(connectToDevice:completion:)
        func connect(toDevice device: AnyObject, completion: @escaping (NSError?) -> Void)
        @objc(connectToDevice:withConfig:completion:)
        func connect(toDevice device: AnyObject, withConfig config: AnyObject, completion: @escaping (NSError?) -> Void)
        @objc(configForDevice:)
        func config(forDevice device: AnyObject) -> AnyObject?
        @objc(disconnectFromDevice:completion:)
        func disconnect(fromDevice device: AnyObject, completion: @escaping (NSError?) -> Void)
    }

    private let manager: SCManager

    init() throws {
        let path = "/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore"
        guard dlopen(path, RTLD_NOW) != nil else {
            throw BridgeError.frameworkLoad(String(cString: dlerror()))
        }
        guard let mgrClass = NSClassFromString("SidecarDisplayManager") else {
            throw BridgeError.classMissing("SidecarDisplayManager")
        }
        guard let mgrAny = (mgrClass as AnyObject).perform(Selector(("sharedManager")))?.takeUnretainedValue() else {
            throw BridgeError.managerMissing
        }
        manager = unsafeBitCast(mgrAny, to: SCManager.self)
    }

    func listDevices() -> [DeviceInfo] {
        callLock.lock()
        defer { callLock.unlock() }
        let available = manager.devices()
        let connected = manager.connectedDevices()
        let connectedIDs = Set(connected.map(Self.deviceID))
        var seen = Set<String>()
        var all: [AnyObject] = []
        for d in available + connected where seen.insert(Self.deviceID(d)).inserted {
            all.append(d)
        }
        return all.map {
            DeviceInfo(
                name: Self.deviceName($0),
                identifier: Self.deviceID($0),
                connected: connectedIDs.contains(Self.deviceID($0))
            )
        }
    }

    func isConnected(nameQuery: String?) -> Bool {
        callLock.lock()
        defer { callLock.unlock() }
        return firstMatch(in: manager.connectedDevices(), query: nameQuery) != nil
    }

    func status(nameQuery: String?) -> DeviceInfo? {
        callLock.lock()
        defer { callLock.unlock() }
        if let d = firstMatch(in: manager.connectedDevices(), query: nameQuery) {
            return DeviceInfo(name: Self.deviceName(d), identifier: Self.deviceID(d), connected: true)
        }
        if let d = firstMatch(in: manager.devices(), query: nameQuery) {
            return DeviceInfo(name: Self.deviceName(d), identifier: Self.deviceID(d), connected: false)
        }
        return nil
    }

    /// Wait until a matching device appears in the Sidecar device list.
    func waitForDevice(nameQuery: String?, timeout: TimeInterval, poll: TimeInterval = 0.5) -> DeviceInfo? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            callLock.lock()
            let match = firstMatch(in: manager.devices(), query: nameQuery)
                ?? firstMatch(in: manager.connectedDevices(), query: nameQuery)
            let info: DeviceInfo? = match.map {
                DeviceInfo(
                    name: Self.deviceName($0),
                    identifier: Self.deviceID($0),
                    connected: isConnectedObject($0)
                )
            }
            callLock.unlock()
            if let info { return info }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(poll))
        }
        return nil
    }

    private let callLock = NSLock()

    @discardableResult
    func connect(nameQuery: String?, options: ConnectOptions) throws -> DeviceInfo {
        callLock.lock()
        defer { callLock.unlock() }

        guard let device = firstMatch(in: manager.devices(), query: nameQuery)
            ?? firstMatch(in: manager.connectedDevices(), query: nameQuery) else {
            throw BridgeError.noDevice
        }
        if isConnectedObject(device) {
            return DeviceInfo(name: Self.deviceName(device), identifier: Self.deviceID(device), connected: true)
        }

        let state = CompletionState()
        let completion: (NSError?) -> Void = { err in state.finish(err) }

        if options.wired, let wiredConfig = makeWiredConfig() {
            applySidebarTouchBar(to: wiredConfig, options: options)
            manager.connect(toDevice: device, withConfig: wiredConfig, completion: completion)
        } else if let cfg = manager.config(forDevice: device), options.noSidebar || options.noTouchbar {
            applySidebarTouchBar(to: cfg, options: options)
            manager.connect(toDevice: device, withConfig: cfg, completion: completion)
        } else {
            manager.connect(toDevice: device, completion: completion)
        }

        wait(upTo: options.timeout) { state.isFinished }
        if !state.isFinished { throw BridgeError.timeout("connect") }
        if let e = state.failure { throw BridgeError.connectFailed(e.localizedDescription) }

        return DeviceInfo(name: Self.deviceName(device), identifier: Self.deviceID(device), connected: true)
    }

    func disconnect(nameQuery: String?, timeout: TimeInterval = 20) throws {
        callLock.lock()
        defer { callLock.unlock() }

        guard let device = firstMatch(in: manager.connectedDevices(), query: nameQuery)
            ?? firstMatch(in: manager.devices(), query: nameQuery) else {
            throw BridgeError.noDevice
        }
        let state = CompletionState()
        manager.disconnect(fromDevice: device) { err in state.finish(err) }
        wait(upTo: timeout) { state.isFinished }
        if !state.isFinished { throw BridgeError.timeout("disconnect") }
        if let e = state.failure { throw BridgeError.disconnectFailed(e.localizedDescription) }
    }

    /// Synchronizes SidecarCore completion callbacks with the waiting thread.
    private final class CompletionState: @unchecked Sendable {
        private let lock = NSLock()
        private var _finished = false
        private var _failure: NSError?

        var isFinished: Bool {
            lock.lock(); defer { lock.unlock() }
            return _finished
        }

        var failure: NSError? {
            lock.lock(); defer { lock.unlock() }
            return _failure
        }

        func finish(_ error: NSError?) {
            lock.lock()
            _failure = error
            _finished = true
            lock.unlock()
        }
    }

    // MARK: - Private helpers

    private static func deviceName(_ d: AnyObject) -> String {
        unsafeBitCast(d, to: SCDevice.self).name() ?? "(unknown)"
    }

    private static func deviceID(_ d: AnyObject) -> String {
        guard let id = unsafeBitCast(d, to: SCDevice.self).identifier() else {
            return deviceName(d)
        }
        if let uuid = id as? UUID { return uuid.uuidString }
        if let uuid = id as? NSUUID { return uuid.uuidString }
        return String(describing: id)
    }

    private func isConnectedObject(_ d: AnyObject) -> Bool {
        let id = Self.deviceID(d)
        return manager.connectedDevices().contains { Self.deviceID($0) == id }
    }

    private func firstMatch(in devices: [AnyObject], query: String?) -> AnyObject? {
        guard let q = query, !q.isEmpty else { return devices.first }
        let needle = q.lowercased()
        return devices.first { Self.deviceName($0).lowercased().contains(needle) }
    }

    private func wait(upTo seconds: TimeInterval, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done() && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    /// SidecarDisplayConfig with transport=2 (wired), from SidecarLauncher.
    private func makeWiredConfig() -> AnyObject? {
        guard let configClass = NSClassFromString("SidecarDisplayConfig") as? NSObject.Type else {
            return nil
        }
        let config = configClass.init()
        let setTransport = Selector(("setTransport:"))
        guard let imp = config.method(for: setTransport) else { return config }
        let fn = unsafeBitCast(imp, to: (@convention(c) (Any?, Selector, Int64) -> Void).self)
        fn(config, setTransport, 2)
        return config
    }

    private func applySidebarTouchBar(to config: AnyObject, options: ConnectOptions) {
        let scfg = unsafeBitCast(config, to: SCConfig.self)
        if options.noSidebar { scfg.setShowSideBar(false) }
        if options.noTouchbar { scfg.setShowTouchBar(false) }
    }
}
