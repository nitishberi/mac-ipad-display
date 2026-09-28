import Foundation
import Security

struct Preferences: Codable, Equatable {
    /// Case-insensitive substring of the Sidecar device name (e.g. "iPad").
    var iPadName: String = "iPad"
    /// Auto-connect when no physical monitor is attached.
    var autoConnectWhenHeadless: Bool = true
    /// Prefer USB Sidecar when available; fall back to wireless.
    var wiredFirst: Bool = true
    /// Hide Sidecar sidebar when connecting.
    var noSidebar: Bool = false
    /// Hide Sidecar Touch Bar strip when connecting.
    var noTouchbar: Bool = false
    /// Poll interval while waiting for the iPad (seconds).
    var waitingPollSeconds: Double = 0.5
    /// Poll interval while connected / stable (seconds).
    var stablePollSeconds: Double = 2.0
    /// Give up reconnect attempts after this many consecutive failures (0 = never).
    var maxConsecutiveFailures: Int = 0
    /// Lock the Mac immediately after the first successful Sidecar connect this session.
    var lockAfterFirstConnect: Bool = true
    /// Emit session-started notification when the agent launches.
    var notifyOnSessionStart: Bool = true
    /// Apprise URL(s), e.g. ntfys://ntfy.sh/my-secret-topic
    var appriseURLs: [String] = []
    /// Direct ntfy URL, e.g. https://ntfy.sh/<long-random-topic>
    var ntfyURL: String = ""
    /// ntfy access token (required for ntfy.sh topics).
    var ntfyToken: String = ""
    /// Bark base+key URL, e.g. https://api.day.app/YOURKEY (POST body used, not path).
    var barkURL: String = ""
    /// Coalesce identical notify events within this window (seconds).
    var notifyDedupeSeconds: Double = 30
    /// Shared secret required for `notify` CLI / loginwatcher hooks (not needed for in-process alerts).
    var notifyAuthToken: String = ""
    /// LaunchAgent KeepAlive: restart only after crash (RecommendedExit=false), not after clean quit.
    var launchAgentKeepAliveOnCrashOnly: Bool = true

    static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacIPadDisplay", isDirectory: true)
    }

    static var configURL: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    static func load() -> Preferences {
        let url = configURL
        guard let data = try? Data(contentsOf: url),
              let prefs = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return Preferences()
        }
        return prefs
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.configDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: Self.configURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: Self.configURL.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: Self.configDirectory.path
        )
    }

    /// Ensure notifyAuthToken exists; generate a random one if empty. Returns updated prefs.
    mutating func ensureNotifyAuthToken() -> String {
        if notifyAuthToken.isEmpty {
            notifyAuthToken = Self.randomToken(bytes: 24)
        }
        return notifyAuthToken
    }

    static func randomToken(bytes: Int) -> String {
        var buf = [UInt8](repeating: 0, count: bytes)
        let status = SecRandomCopyBytes(nil, bytes, &buf)
        if status != errSecSuccess {
            buf = (0..<bytes).map { _ in UInt8.random(in: 0...255) }
        }
        return Data(buf).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func randomNtfyTopic() -> String {
        // 22 chars of url-safe entropy — hard to guess on public ntfy.sh
        return "mid-" + randomToken(bytes: 16)
    }
}
