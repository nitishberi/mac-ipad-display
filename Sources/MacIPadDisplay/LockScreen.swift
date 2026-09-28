import Foundation

enum LockScreen {
    /// Locks the Mac immediately (shows lock screen). Safe to call headlessly.
    static func lockNow() {
        let script = """
        tell application "System Events" to keystroke "q" using {control down, command down}
        """
        // Prefer private login command when available (no Accessibility needed).
        let loginBin = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        if FileManager.default.isExecutableFile(atPath: loginBin) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: loginBin)
            proc.arguments = ["-suspend"]
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    Log.info("locked session via CGSession -suspend")
                    return
                }
            } catch {
                Log.warn("CGSession lock failed: \(error)")
            }
        }

        // Fallback: pmset or AppleScript Control+Cmd+Q
        let pm = Process()
        pm.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        pm.arguments = ["displaysleepnow"]
        do {
            try pm.run()
            pm.waitUntilExit()
            Log.info("requested display sleep via pmset")
        } catch {
            Log.warn("pmset displaysleepnow failed: \(error)")
            let osa = Process()
            osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            osa.arguments = ["-e", script]
            try? osa.run()
            osa.waitUntilExit()
        }
    }
}
