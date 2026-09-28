import Foundation
import CoreGraphics

/// Detects whether a non-Sidecar (physical / built-in) display is attached.
enum DisplayMonitor {
    /// Returns true if at least one online display looks like a real monitor
    /// (not only Sidecar / virtual screen-sharing displays).
    static func hasPhysicalMonitor() -> Bool {
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        let err = CGGetOnlineDisplayList(16, &displays, &displayCount)
        guard err == .success else {
            // Fail open: if we can't query, assume no physical monitor so headless mode runs.
            return false
        }

        for i in 0..<Int(displayCount) {
            let id = displays[i]
            if CGDisplayIsOnline(id) == 0 { continue }
            if isLikelySidecarOrVirtual(id) { continue }
            // Built-in on MacBook/iMac counts as physical for stand-aside purposes.
            return true
        }
        return false
    }

    private static func isLikelySidecarOrVirtual(_ id: CGDirectDisplayID) -> Bool {
        // Sidecar / AirPlay / Screen Sharing virtual displays often report as
        // non-builtin and may lack a traditional vendor EDID. Heuristic:
        // treat builtin as physical; for externals, check localized name via NSScreen if available.
        if CGDisplayIsBuiltin(id) != 0 { return false }

        #if canImport(AppKit)
        // Deferred to AppKit helper to avoid hard link issues in pure CLI contexts.
        return AppKitDisplayNames.isSidecarLike(id)
        #else
        return false
        #endif
    }
}

#if canImport(AppKit)
import AppKit

enum AppKitDisplayNames {
    static func isSidecarLike(_ id: CGDirectDisplayID) -> Bool {
        for screen in NSScreen.screens {
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  CGDirectDisplayID(num.uint32Value) == id else { continue }
            let name = screen.localizedName.lowercased()
            if name.contains("sidecar")
                || name.contains("ipad")
                || name.contains("airplay")
                || name.contains("screen sharing")
                || name.contains("virtual") {
                return true
            }
        }
        return false
    }
}
#endif
