import Foundation

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
    /// Apprise URL(s), one per line, e.g. ntfys://ntfy.sh/my-secret-topic
    var appriseURLs: [String] = []
    /// Direct ntfy URL (used if appriseURLs empty), e.g. https://ntfy.sh/my-secret-topic
    var ntfyURL: String = ""
    /// Optional ntfy access token (Bearer / basic).
    var ntfyToken: String = ""
    /// Direct Bark base+key URL, e.g. https://api.day.app/YOURKEY
    var barkURL: String = ""
    /// Coalesce identical notify events within this window (seconds).
    var notifyDedupeSeconds: Double = 30

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
    }
}
