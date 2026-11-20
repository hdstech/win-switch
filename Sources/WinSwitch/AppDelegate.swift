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
