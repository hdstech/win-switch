import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestPermissions()
        hotkeyManager = HotkeyManager()
        setupStatusItem()
    }

    private func requestPermissions() {
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

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "WinSwitch")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Switch windows: ⌥⇥", action: nil, keyEquivalent: ""))
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

    @objc private func openAXSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openSRSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
