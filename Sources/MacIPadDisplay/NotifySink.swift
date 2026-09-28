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

        // Log event type only — avoid writing alert bodies (may be sensitive) to disk.
        Log.info("notify \(event.rawValue)")

        let ntfyURL = Self.sanitizedNtfyEndpoint(prefs.ntfyURL, token: prefs.ntfyToken)
        let barkURL = Self.sanitizedEndpoint(prefs.barkURL)
        let appriseURLs = prefs.appriseURLs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && Self.sanitizedEndpoint($0) != nil }

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
            Log.warn("notify: no backend configured (set ntfyURL+ntfyToken, barkURL, or appriseURLs)")
        }
    }

    /// Validate CLI/hook auth for `notify` subcommand.
    static func authorizeNotifyCLI(provided: String?, prefs: Preferences) -> Bool {
        let expected = prefs.notifyAuthToken
        guard !expected.isEmpty else {
            // Unconfigured auth: refuse external notify to prevent local spam.
            return false
        }
        guard let provided, !provided.isEmpty else { return false }
        return constantTimeEquals(provided, expected)
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aa = Array(a.utf8)
        let bb = Array(b.utf8)
        guard aa.count == bb.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<aa.count { diff |= aa[i] ^ bb[i] }
        return diff == 0
    }

    // MARK: - Endpoint policy

    private static func sanitizedEndpoint(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        let lower = s.lowercased()
        if lower.contains("change-me") || lower.contains("your-private-topic") || lower.contains("yourkey") {
            return nil
        }
        if lower.hasPrefix("http://") {
            Log.warn("notify: refusing cleartext http:// endpoint (use https://)")
            return nil
        }
        if lower.hasPrefix("ntfy://") {
            Log.warn("notify: use https:// or ntfys:// (not cleartext ntfy://)")
            return nil
        }
        return s
    }

    private static func sanitizedNtfyEndpoint(_ raw: String, token: String) -> String? {
        guard let url = sanitizedEndpoint(raw) else { return nil }
        guard let parsed = URL(string: url), let host = parsed.host?.lowercased() else {
            Log.warn("notify: invalid ntfyURL")
            return nil
        }

        let path = parsed.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let topic = path.split(separator: "/").last.map(String.init) ?? ""
        if topic.count < 16 {
            Log.warn("notify: ntfy topic too short (<16 chars) — refusing guessable topic")
            return nil
        }

        // Public ntfy.sh requires a token so strangers cannot subscribe/publish freely.
        if (host == "ntfy.sh" || host.hasSuffix(".ntfy.sh")) && token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Log.warn("notify: ntfy.sh requires ntfyToken (create one at https://ntfy.sh/account)")
            return nil
        }
        return url
    }

    // MARK: - Backends

    private func sendApprise(urls: [String], title: String, body: String) -> Bool {
        let apprise = which("apprise") ?? "/usr/local/bin/apprise"
        guard FileManager.default.isExecutableFile(atPath: apprise) else {
            Log.warn("apprise not found on PATH")
            return false
        }
        var ok = false
        for url in urls {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: apprise)
            proc.arguments = ["-t", title, "-b", body, url]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 { ok = true }
                else { Log.warn("apprise exit \(proc.terminationStatus)") }
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

        return perform(request, label: "ntfy")
    }

    /// Bark POST JSON — title/body stay out of the URL path (avoids proxy/CDN path logs).
    private func sendBark(base: String, title: String, body: String) -> Bool {
        let trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let endpoint = URL(string: trimmed) else {
            Log.warn("invalid barkURL")
            return false
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "title": title,
            "body": body,
            "group": "MacIPadDisplay",
            "level": "active"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return perform(request, label: "bark")
    }

    private func perform(_ request: URLRequest, label: String) -> Bool {
        let sem = DispatchSemaphore(value: 0)
        var success = false
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            defer { sem.signal() }
            if let error {
                Log.warn("\(label) error: \(error.localizedDescription)")
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            success = (200..<300).contains(code)
            if !success { Log.warn("\(label) HTTP \(code)") }
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
