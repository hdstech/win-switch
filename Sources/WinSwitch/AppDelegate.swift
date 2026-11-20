import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestPermissions()
        ThumbnailCache.shared.start()
        hotkeyManager = HotkeyManager()
        setupStatusItem()
    }

    private func requestPermissions() {
        print("WinSwitch perms: screenRecording=\(CGPreflightScreenCaptureAccess()) accessibility=\(AXIsProcessTrusted())")
        fflush(stdout)
        // Accessibility is needed to detect/unminimize/raise specific windows.
        _ = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        // Screen recording is needed for window titles + thumbnails/live capture.
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        // After the system prompt settles, warn if permissions are still
        // missing (e.g. a stale grant from a previous ad-hoc-signed build).
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.showPermissionNoticeIfNeeded()
        }
    }

    private func showPermissionNoticeIfNeeded() {
        var missing: [String] = []
        if !CGPreflightScreenCaptureAccess() {
            missing.append("• Screen Recording — needed for window previews and titles")
        }
        if !AXIsProcessTrusted() {
            missing.append("• Accessibility — needed to raise and un-minimize windows")
        }
        guard !missing.isEmpty else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "WinSwitch is missing permissions"
        alert.informativeText = missing.joined(separator: "\n")
            + "\n\nEnable them in System Settings → Privacy & Security, then quit and relaunch WinSwitch."
        alert.addButton(withTitle: "Open Screen Recording Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn { openSRSettings() }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "WinSwitch")
        }
        let state = SwitcherController.shared.state

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Switch windows: ⌥⇥", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let styleItem = NSMenuItem(title: "Grid thumbnails", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        styleMenu.addItem(radio("Previews", key: "gridStyle", value: "previews", current: state.gridStyle))
        styleMenu.addItem(radio("Icons only", key: "gridStyle", value: "icons", current: state.gridStyle))
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        let posItem = NSMenuItem(title: "Grid position", action: nil, keyEquivalent: "")
        let posMenu = NSMenu()
        posMenu.addItem(radio("Below preview", key: "gridPosition", value: "bottom", current: state.gridPosition))
        posMenu.addItem(radio("Side", key: "gridPosition", value: "side", current: state.gridPosition))
        posItem.submenu = posMenu
        menu.addItem(posItem)

        menu.addItem(.separator())
        let axItem = NSMenuItem(title: "Accessibility Settings…", action: #selector(openAXSettings), keyEquivalent: "")
        axItem.target = self
        menu.addItem(axItem)
        let srItem = NSMenuItem(title: "Screen Recording Settings…", action: #selector(openSRSettings), keyEquivalent: "")
        srItem.target = self
        menu.addItem(srItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit WinSwitch", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem?.menu = menu
    }

    private func radio(_ title: String, key: String, value: String, current: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(setPref(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = "\(key)|\(value)"
        item.state = value == current ? .on : .off
        return item
    }

    @objc private func setPref(_ item: NSMenuItem) {
        guard let spec = item.representedObject as? String,
              let sep = spec.firstIndex(of: "|") else { return }
        let key = String(spec[spec.startIndex..<sep])
        let value = String(spec[spec.index(after: sep)...])
        let state = SwitcherController.shared.state
        switch key {
        case "gridStyle": state.gridStyle = value
        case "gridPosition":
            state.gridPosition = value
            SwitcherController.shared.refreshLayout()
        default: break
        }
        item.menu?.items.forEach { $0.state = .off }
        item.state = .on
    }

    @objc private func openAXSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openSRSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
