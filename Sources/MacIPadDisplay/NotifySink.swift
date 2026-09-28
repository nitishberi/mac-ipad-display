import Foundation

enum NotifyEvent: String {
    case sessionStart = "session_start"
    case loginSuccess = "login_success"
    case loginFailure = "login_failure"
    case sidecarConnected = "sidecar_connected"
    case sidecarDisconnected = "sidecar_disconnected"
    case monitorStandAside = "monitor_stand_aside"
    case monitorResume = "monitor_resume"
    case reconnectExhausted = "reconnect_exhausted"
}

enum NotifyPriority: String {
    case min, low, `default`, high, urgent
}

/// Sends safety alerts to iPhone via Apprise, ntfy, or Bark (no custom APNs app).
final class NotifySink {
    private let prefs: () -> Preferences
    private var lastSent: [String: Date] = [:]
    private let lock = NSLock()

    init(prefs: @escaping () -> Preferences) {
        self.prefs = prefs
    }

    func notify(event: NotifyEvent, title: String, body: String, priority: NotifyPriority = .high) {
        let prefs = prefs()
        let dedupeKey = "\(event.rawValue)|\(title)|\(body)"
        lock.lock()
        if let last = lastSent[dedupeKey],
           Date().timeIntervalSince(last) < prefs.notifyDedupeSeconds {
            lock.unlock()
            Log.info("notify deduped: \(event.rawValue)")
            return
        }
        lastSent[dedupeKey] = Date()
        lock.unlock()

        Log.info("notify \(event.rawValue): \(title) — \(body)")

        let ntfyURL = Self.sanitizedEndpoint(prefs.ntfyURL)
        let barkURL = Self.sanitizedEndpoint(prefs.barkURL)
        let appriseURLs = prefs.appriseURLs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        var sent = false
        if !appriseURLs.isEmpty {
            sent = sendApprise(urls: appriseURLs, title: title, body: body) || sent
        }
        if let ntfyURL {
            sent = sendNtfy(url: ntfyURL, token: prefs.ntfyToken, title: title, body: body, priority: priority) || sent
        }
        if let barkURL {
            sent = sendBark(base: barkURL, title: title, body: body) || sent
        }
        if !sent {
            Log.warn("notify: no backend configured (set ntfyURL, barkURL, or appriseURLs in config.json)")
        }
    }

    /// Reject empty / placeholder / cleartext endpoints so alerts cannot leak broadly.
    private static func sanitizedEndpoint(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        let lower = s.lowercased()
        if lower.contains("change-me") || lower.contains("your-private-topic") || lower.contains("yourkey") {
            return nil
        }
        // Require TLS for push backends (tokens/keys in transit).
        if lower.hasPrefix("http://") {
            Log.warn("notify: refusing cleartext http:// endpoint (use https://)")
            return nil
        }
        if lower.hasPrefix("ntfy://") {
            Log.warn("notify: use ntfys:// or https:// for ntfy (not cleartext ntfy://)")
            return nil
        }
        return s
    }

    // MARK: - Backends

    private func sendApprise(urls: [String], title: String, body: String) -> Bool {
        let apprise = which("apprise") ?? "/usr/local/bin/apprise"
        guard FileManager.default.isExecutableFile(atPath: apprise) else {
            Log.warn("apprise not found on PATH")
            return false
        }
        var ok = false
        for url in urls where !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: apprise)
            proc.arguments = ["-t", title, "-b", body, url]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 { ok = true }
                else { Log.warn("apprise exit \(proc.terminationStatus) for \(url)") }
            } catch {
                Log.warn("apprise launch failed: \(error)")
            }
        }
        return ok
    }

    private func sendNtfy(url: String, token: String, title: String, body: String, priority: NotifyPriority) -> Bool {
        guard let endpoint = URL(string: url) else {
            Log.warn("invalid ntfyURL")
            return false
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(title, forHTTPHeaderField: "Title")
        request.setValue(priority.rawValue, forHTTPHeaderField: "Priority")
        request.setValue("computer,ipad", forHTTPHeaderField: "Tags")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body.data(using: .utf8)

        let sem = DispatchSemaphore(value: 0)
        var success = false
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            defer { sem.signal() }
            if let error {
                Log.warn("ntfy error: \(error.localizedDescription)")
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            success = (200..<300).contains(code)
            if !success { Log.warn("ntfy HTTP \(code)") }
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 15)
        return success
    }

    private func sendBark(base: String, title: String, body: String) -> Bool {
        // Accept either https://api.day.app/KEY or https://api.day.app/KEY/ with path append
        var trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? body
        trimmed += "/\(encodedTitle)/\(encodedBody)"
        guard let endpoint = URL(string: trimmed) else {
            Log.warn("invalid barkURL")
            return false
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"

        let sem = DispatchSemaphore(value: 0)
        var success = false
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            defer { sem.signal() }
            if let error {
                Log.warn("bark error: \(error.localizedDescription)")
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            success = (200..<300).contains(code)
            if !success { Log.warn("bark HTTP \(code)") }
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 15)
        return success
    }

    private func which(_ name: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [name]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (path?.isEmpty == false) ? path : nil
        } catch {
            return nil
        }
    }
}
