import Foundation
import AppKit

let programName = "mac-ipad-display"
let programVersion = "1.0.0"

@main
enum MacIPadDisplayMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty || args.first == "--menubar" || args.first == "menubar" {
            runMenuBar()
            return
        }
        let command = args[0]
        let rest = Array(args.dropFirst())
        do {
            try runCLI(command: command, args: rest)
        } catch {
            fputs("\(programName): \(error)\n", stderr)
            exit(1)
        }
    }
}

// MARK: - Menu bar

var retainedMenuBarDelegate: MenuBarApp?

func runMenuBar() {
    let app = NSApplication.shared
    let delegate = MenuBarApp()
    retainedMenuBarDelegate = delegate
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

// MARK: - CLI

func runCLI(command: String, args: [String]) throws {
    Log.setup()

    switch command {
    case "help", "--help", "-h":
        print(usage)
    case "version", "--version":
        print("\(programName) \(programVersion)")
    case "init-config":
        var prefs = Preferences.load()
        if let name = argValue(args, flag: "--ipad") { prefs.iPadName = name }
        if let ntfy = argValue(args, flag: "--ntfy") { prefs.ntfyURL = ntfy }
        if let token = argValue(args, flag: "--ntfy-token") { prefs.ntfyToken = token }
        if let bark = argValue(args, flag: "--bark") { prefs.barkURL = bark }
        if args.contains("--no-lock") { prefs.lockAfterFirstConnect = false }
        try prefs.save()
        print("Wrote \(Preferences.configURL.path)")
    case "config-path":
        print(Preferences.configURL.path)
    case "list":
        let bridge = try SidecarBridge()
        let devices = bridge.listDevices()
        if devices.isEmpty {
            print("No Sidecar devices found.")
        } else {
            for d in devices {
                print("  \(d.connected ? "●" : "○") \(d.name)  (\(d.identifier))")
            }
        }
    case "status":
        let bridge = try SidecarBridge()
        let prefs = Preferences.load()
        let query = args.first ?? prefs.iPadName
        if let s = bridge.status(nameQuery: query) {
            print("\(s.connected ? "●" : "○") \(s.name) — \(s.connected ? "connected" : "not connected")")
            exit(s.connected ? 0 : 3)
        } else {
            print("No matching Sidecar device.")
            exit(3)
        }
    case "connect":
        let bridge = try SidecarBridge()
        let prefs = Preferences.load()
        let query = args.first ?? prefs.iPadName
        let waitSecs = TimeInterval(argValue(args, flag: "--wait") ?? "30") ?? 30
        _ = bridge.waitForDevice(nameQuery: query, timeout: waitSecs)
        var options = SidecarBridge.ConnectOptions(
            wired: prefs.wiredFirst && !args.contains("--wireless"),
            noSidebar: prefs.noSidebar,
            noTouchbar: prefs.noTouchbar
        )
        if args.contains("--wired") { options.wired = true }
        let info = try bridge.connect(nameQuery: query, options: options)
        print("Connected to \(info.name)")
    case "disconnect":
        let bridge = try SidecarBridge()
        let prefs = Preferences.load()
        let query = args.first ?? prefs.iPadName
        try bridge.disconnect(nameQuery: query)
        print("Disconnected")
    case "watch", "agent":
        let bridge = try SidecarBridge()
        let notify = NotifySink(prefs: { Preferences.load() })
        let prefs = Preferences.load()
        let supervisor = ConnectionSupervisor(bridge: bridge, notify: notify, prefs: prefs)
        signal(SIGINT) { _ in exit(0) }
        signal(SIGTERM) { _ in exit(0) }
        supervisor.runLoop()
    case "notify-test":
        let notify = NotifySink(prefs: { Preferences.load() })
        let title = argValue(args, flag: "--title") ?? "MacIPadDisplay test"
        let body = argValue(args, flag: "--body") ?? "If you see this on your iPhone, notify is configured."
        notify.notify(event: .sessionStart, title: title, body: body, priority: .high)
        print("Sent test notification (check iPhone / logs).")
    case "notify":
        // Used by loginwatcher hooks: notify <event> <title> <body...>
        guard args.count >= 2 else {
            throw CLIError("usage: \(programName) notify <event> <title> [body]")
        }
        let event = NotifyEvent(rawValue: args[0]) ?? .sessionStart
        let title = args[1]
        let body = args.count > 2 ? args.dropFirst(2).joined(separator: " ") : title
        let priority: NotifyPriority = (event == .loginFailure || event == .reconnectExhausted) ? .urgent : .high
        NotifySink(prefs: { Preferences.load() }).notify(event: event, title: title, body: body, priority: priority)
    case "has-monitor":
        print(DisplayMonitor.hasPhysicalMonitor() ? "yes" : "no")
        exit(DisplayMonitor.hasPhysicalMonitor() ? 0 : 1)
    case "lock":
        LockScreen.lockNow()
    case "install-agent":
        try Installer.installAgent(menubar: args.contains("--menubar"))
    case "uninstall-agent":
        try Installer.uninstallAgent()
    default:
        fputs("Unknown command '\(command)'\n\n", stderr)
        print(usage)
        exit(2)
    }
}

enum CLIError: Error, CustomStringConvertible {
    case message(String)
    init(_ message: String) { self = .message(message) }
    var description: String {
        if case .message(let m) = self { return m }
        return "error"
    }
}

func argValue(_ args: [String], flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let usage = """
\(programName) \(programVersion) — personal Mac mini → iPad Sidecar automation

USAGE:
  \(programName) [--menubar]           Start menu-bar app + supervisor (default)
  \(programName) <command> [options]

COMMANDS:
  list                         List Sidecar devices
  status [name]                Connection status (exit 0=connected, 3=not)
  connect [name] [--wait N] [--wired|--wireless]
  disconnect [name]
  watch | agent                Run headless supervisor (login agent)
  init-config [--ipad NAME] [--ntfy URL] [--ntfy-token T] [--bark URL] [--no-lock]
  config-path                  Print config.json path
  notify-test                  Send a test push to your iPhone
  notify <event> <title> [body]  Used by loginwatcher hooks
  has-monitor                  Exit 0 if a physical monitor is attached
  lock                         Lock the Mac now
  install-agent [--menubar]    Install LaunchAgent at login
  uninstall-agent              Remove LaunchAgent
  help | version

CONFIG:
  ~/Library/Application Support/MacIPadDisplay/config.json
LOG:
  ~/Library/Logs/MacIPadDisplay/mac-ipad-display.log

See docs/SETUP.md for FileVault/auto-login and ntfy/Bark setup.
"""

// MARK: - LaunchAgent installer

enum Installer {
    static var label: String { "com.personal.mac-ipad-display" }
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func resolveBinary() throws -> String {
        let argv0 = CommandLine.arguments[0]
        if argv0.hasPrefix("/") { return argv0 }
        var real = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(argv0).standardizedFileURL.path
        if FileManager.default.isExecutableFile(atPath: real) { return real }
        // Prefer installed location
        let homeBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/mac-ipad-display").path
        if FileManager.default.isExecutableFile(atPath: homeBin) { return homeBin }
        throw CLIError("could not resolve binary path; run from build product or install first")
    }

    static func installAgent(menubar: Bool) throws {
        let bin = try resolveBinary()
        let args: [String] = menubar ? [bin, "--menubar"] : [bin, "watch"]
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MacIPadDisplay", isDirectory: true)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": args,
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 5,
            "StandardOutPath": logDir.appendingPathComponent("launchd.out.log").path,
            "StandardErrorPath": logDir.appendingPathComponent("launchd.err.log").path
        ]
        let dir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)

        let uid = getuid()
        let bootout = Process()
        bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootout.arguments = ["bootout", "gui/\(uid)/\(label)"]
        try? bootout.run()
        bootout.waitUntilExit()

        let bootstrap = Process()
        bootstrap.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootstrap.arguments = ["bootstrap", "gui/\(uid)", plistURL.path]
        try bootstrap.run()
        bootstrap.waitUntilExit()
        if bootstrap.terminationStatus != 0 {
            // Older macOS fallback
            let load = Process()
            load.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            load.arguments = ["load", "-w", plistURL.path]
            try load.run()
            load.waitUntilExit()
        }
        print("Installed LaunchAgent \(label)")
        print("Plist: \(plistURL.path)")
        print("Binary: \(bin)")
    }

    static func uninstallAgent() throws {
        let uid = getuid()
        let bootout = Process()
        bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootout.arguments = ["bootout", "gui/\(uid)/\(label)"]
        try? bootout.run()
        bootout.waitUntilExit()

        let unload = Process()
        unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        unload.arguments = ["unload", "-w", plistURL.path]
        try? unload.run()
        unload.waitUntilExit()

        try? FileManager.default.removeItem(at: plistURL)
        print("Removed LaunchAgent \(label)")
    }
}
