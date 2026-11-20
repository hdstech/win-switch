import AppKit
import ApplicationServices

struct WindowItem: Identifiable, Equatable {
    let id: CGWindowID
    let title: String
    let appName: String
    let pid: pid_t
    let isOnscreen: Bool
    var isMinimized: Bool
    var spaceID: UInt64
    var icon: NSImage?
    var thumbnail: NSImage?

    var displayTitle: String { title.isEmpty ? appName : title }
}

enum WindowManager {
    static func currentSpace() -> UInt64 {
        SkyLight.getActiveSpace?(SkyLight.cid) ?? 0
    }

    static func space(forWindow wid: CGWindowID) -> UInt64 {
        let cid = SkyLight.cid
        if let f = SkyLight.getWindowWorkspace {
            var space: UInt64 = 0
            if f(cid, wid, &space) == 0 { return space }
        }
        return SkyLight.windowCopyWorkspaceID?(cid, wid) ?? 0
    }

    /// All normal-layer windows across every space, including minimized ones.
    /// `.optionAll` (i.e. *not* `onScreenOnly`) is what makes cross-space + minimized
    /// enumeration work; SkyLight then tells us which space each window belongs to.
    static func enumerate() -> [WindowItem] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let axTrusted = AXIsProcessTrusted()
        var axMapCache: [pid_t: [CGWindowID: AXUIElement]] = [:]
        var items: [WindowItem] = []

        for dict in list {
            guard let wid = dict[kCGWindowNumber as String] as? CGWindowID,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  pid != myPID,
                  let layer = dict[kCGWindowLayer as String] as? Int, layer == 0
            else { continue }

            var bounds = CGRect.zero
            if let b = dict[kCGWindowBounds as String] as? [String: Any] {
                bounds = CGRect(dictionaryRepresentation: b as CFDictionary) ?? .zero
            }
            guard bounds.width >= 50, bounds.height >= 50 else { continue }

            if let alpha = dict[kCGWindowAlpha as String] as? Double, alpha == 0 { continue }

            let appName = dict[kCGWindowOwnerName as String] as? String ?? "Unknown"
            if appName == "Window Server" { continue }

            // Only apps that live in the Dock — this filters out background
            // services and UIElement agents that own layer-0 windows.
            guard let running = NSRunningApplication(processIdentifier: pid),
                  running.activationPolicy == .regular else { continue }

            let title = dict[kCGWindowName as String] as? String ?? ""
            let onscreen = dict[kCGWindowIsOnscreen as String] as? Bool ?? false
            let space = space(forWindow: wid)

            var minimized = false
            if !onscreen && axTrusted {
                if axMapCache[pid] == nil { axMapCache[pid] = axWindowMap(pid: pid) }
                if let el = axMapCache[pid]?[wid], isMinimized(el) { minimized = true }
            }

            items.append(WindowItem(
                id: wid,
                title: title,
                appName: appName,
                pid: pid,
                isOnscreen: onscreen,
                isMinimized: minimized,
                spaceID: space,
                icon: running.icon,
                thumbnail: nil
            ))
        }

        // Front-to-back (CGWindowList order) for onscreen windows first,
        // then offscreen windows (other spaces / minimized).
        let onscreen = items.filter { $0.isOnscreen }
        let offscreen = items.filter { !$0.isOnscreen }
        return onscreen + offscreen
    }

    /// Lightweight id-only scan used by the thumbnail cache (no AX/icon work).
    static func enumerateIDs() -> [CGWindowID] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let myPID = ProcessInfo.processInfo.processIdentifier
        var ids: [CGWindowID] = []
        for dict in list {
            guard let wid = dict[kCGWindowNumber as String] as? CGWindowID,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  pid != myPID,
                  let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let b = dict[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: b as CFDictionary),
                  bounds.width >= 50, bounds.height >= 50,
                  let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular
            else { continue }
            if let alpha = dict[kCGWindowAlpha as String] as? Double, alpha == 0 { continue }
            ids.append(wid)
        }
        return ids
    }

    // MARK: - Activation

    static func activate(_ w: WindowItem) {
        let cid = SkyLight.cid
        unminimize(w)

        let targetSpace = w.spaceID != 0 ? w.spaceID : space(forWindow: w.id)
        let current = currentSpace()
        NSLog("WinSwitch activate: wid=%u space=%llu current=%llu", w.id, targetSpace, current)

        var jumpedToSpace = false
        var movedWindow = false
        if targetSpace != 0 && targetSpace != current {
            if let uuid = displayUUID(forSpace: targetSpace),
               let setSpace = SkyLight.managedDisplaySetCurrentSpace {
                let err = setSpace(cid, uuid as CFString, targetSpace)
                NSLog("WinSwitch: CGSManagedDisplaySetCurrentSpace(uuid=%@) -> %d", uuid, err)
                jumpedToSpace = (err == 0)
            } else {
                NSLog("WinSwitch: no display UUID for space %llu or symbol missing",
                      targetSpace)
            }
            if !jumpedToSpace {
                // Fallback: pull the window onto the current space instead.
                movedWindow = moveWindow(w.id, to: current)
            }
        }

        // Give the space-switch animation a beat, then activate + raise.
        let delay: TimeInterval = jumpedToSpace ? 0.15 : 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            activateApp(pid: w.pid)
            raiseWindow(w)
            // A second raise covers slow space transitions / apps that resist.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { raiseWindow(w) }
        }

        // Rescue: if the space jump didn't take, pull the window to us.
        if targetSpace != 0 && targetSpace != current && !movedWindow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let now = space(forWindow: w.id)
                let cur = currentSpace()
                if now != 0 && now != cur {
                    NSLog("WinSwitch: space switch failed (window on %llu, current %llu) — moving window",
                          now, cur)
                    if moveWindow(w.id, to: cur) {
                        activateApp(pid: w.pid)
                        raiseWindow(w)
                    }
                }
            }
        }
    }

    /// Move a window onto a space via whichever private API is present.
    private static func moveWindow(_ wid: CGWindowID, to space: UInt64) -> Bool {
        let cid = SkyLight.cid
        let ids = [NSNumber(value: wid)] as CFArray
        if let f = SkyLight.moveWindowsToManagedSpace {
            let err = f(cid, ids, space)
            NSLog("WinSwitch: SLSMoveWindowsToManagedSpace -> %d", err)
            return err == 0
        }
        if let f = SkyLight.spaceAddWindowsAndRemoveFromSpaces {
            let err = f(cid, space, ids, ids)
            NSLog("WinSwitch: SLSSpaceAddWindowsAndRemoveFromSpaces -> %d", err)
            return err == 0
        }
        NSLog("WinSwitch: no space-move symbol available")
        return false
    }

    private static func activateApp(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private static func raiseWindow(_ w: WindowItem) {
        if let el = axWindowElement(for: w) {
            AXUIElementPerformAction(el, kAXRaiseAction as CFString)
            let appEl = AXUIElementCreateApplication(w.pid)
            AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        } else {
            _ = SkyLight.orderWindow?(SkyLight.cid, w.id, 1 /* kCGSOrderAbove */, 0)
        }
    }

    private static func unminimize(_ w: WindowItem) {
        guard w.isMinimized, let el = axWindowElement(for: w) else { return }
        AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }

    // MARK: - Spaces

    /// Find which display owns a space, returning that display's UUID string —
    /// the "Display Identifier" field inside CGSCopyManagedDisplaySpaces.
    static func displayUUID(forSpace space: UInt64) -> String? {
        guard let copy = SkyLight.copyManagedDisplaySpaces,
              let arr = copy(SkyLight.cid)?.takeRetainedValue() as? [[String: Any]]
        else { return nil }
        for display in arr {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            let ids = spaces.compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
            if ids.contains(space) {
                return display["Display Identifier"] as? String
            }
        }
        return nil
    }

    // MARK: - Accessibility helpers

    private static func axWindowMap(pid: pid_t) -> [CGWindowID: AXUIElement] {
        var map: [CGWindowID: AXUIElement] = [:]
        let appEl = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return map }
        for el in windows {
            var wid = CGWindowID(0)
            if let f = SkyLight.axGetWindow, f(el, &wid) == .success {
                map[wid] = el
            }
        }
        return map
    }

    private static func axWindowElement(for w: WindowItem) -> AXUIElement? {
        axWindowMap(pid: w.pid)[w.id]
    }

    private static func isMinimized(_ el: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXMinimizedAttribute as CFString, &value) == .success
        else { return false }
        return (value as? NSNumber)?.boolValue ?? false
    }
}
