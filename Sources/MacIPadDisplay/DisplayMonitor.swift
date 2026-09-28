import Foundation
import CoreGraphics

#if canImport(AppKit)
import AppKit
#endif

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

        let online = (0..<Int(displayCount)).map { displays[$0] }.filter { CGDisplayIsOnline($0) != 0 }
        if online.isEmpty { return false }

        let physical = online.filter { !isLikelySidecarOrVirtual($0, totalOnline: online.count) }
        return !physical.isEmpty
    }

    /// - Parameter totalOnline: when a lone non-builtin display has an unknown name on a
    ///   headless Mac mini, treat it as Sidecar/virtual so we do not "stand aside" forever.
    private static func isLikelySidecarOrVirtual(_ id: CGDirectDisplayID, totalOnline: Int) -> Bool {
        if CGDisplayIsBuiltin(id) != 0 { return false }

        #if canImport(AppKit)
        if let known = AppKitDisplayNames.sidecarLikeness(id) {
            return known
        }
        // Unknown non-builtin name: alone ⇒ assume Sidecar/virtual (Mac mini headless).
        // Multiple displays with an unnamed external ⇒ treat as physical to be safe.
        return totalOnline == 1
        #else
        return totalOnline == 1
        #endif
    }
}

#if canImport(AppKit)
enum AppKitDisplayNames {
    /// `true` / `false` when the screen name is conclusive; `nil` if not found / unknown.
    static func sidecarLikeness(_ id: CGDirectDisplayID) -> Bool? {
        for screen in NSScreen.screens {
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  CGDirectDisplayID(num.uint32Value) == id else { continue }
            let name = screen.localizedName.lowercased()
            if name.contains("sidecar")
                || name.contains("ipad")
                || name.contains("airplay")
                || name.contains("screen sharing")
                || name.contains("virtual")
                || name.contains("continuit") {
                return true
            }
            // Named external panel (e.g. "LG UltraFine", "DELL …") ⇒ physical.
            if !name.isEmpty { return false }
            return nil
        }
        return nil
    }
}
#endif
