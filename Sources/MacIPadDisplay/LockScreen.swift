import Foundation
import Darwin

enum LockScreen {
    /// Locks the Mac session (lock screen), not merely display sleep.
    static func lockNow() {
        // 1) Private login.framework API when available (no Accessibility prompt).
        if lockViaLoginFramework() {
            Log.info("locked session via SACLockScreenImmediate")
            return
        }

        // 2) Legacy CGSession -suspend (removed on many recent macOS builds).
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

        // 3) Control+Cmd+Q via System Events (may need Accessibility for osascript).
        let script = "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"
        let osa = Process()
        osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osa.arguments = ["-e", script]
        do {
            try osa.run()
            osa.waitUntilExit()
            if osa.terminationStatus == 0 {
                Log.info("locked session via Control+Cmd+Q")
                return
            }
        } catch {
            Log.warn("osascript lock failed: \(error)")
        }

        // Do NOT use `pmset displaysleepnow` — that only sleeps the display and is not a session lock.
        Log.warn("could not lock session; grant Accessibility to mac-ipad-display or lock manually")
    }

    private static func lockViaLoginFramework() -> Bool {
        let path = "/System/Library/PrivateFrameworks/login.framework/login"
        guard let handle = dlopen(path, RTLD_LAZY) else { return false }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "SACLockScreenImmediate") else { return false }
        let lockFn = unsafeBitCast(sym, to: (@convention(c) () -> Void).self)
        lockFn()
        return true
    }
}
