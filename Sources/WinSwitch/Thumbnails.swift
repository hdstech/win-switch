import AppKit
import ScreenCaptureKit

enum Thumbnails {
    /// Static per-window capture. Works for windows on other spaces and
    /// minimized windows (returns the window's backing store). Requires
    /// Screen Recording permission on modern macOS.
    static func capture(_ wid: CGWindowID) async -> NSImage? {
        if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, wid,
                                            [.boundsIgnoreFraming, .bestResolution]) {
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        // Fallback: ScreenCaptureKit one-shot capture (the modern replacement
        // for the deprecated CGWindowListCreateImage).
        if #available(macOS 14.0, *) {
            return await captureViaScreenCaptureKit(wid)
        }
        return nil
    }

    @available(macOS 14.0, *)
    private static func captureViaScreenCaptureKit(_ wid: CGWindowID) async -> NSImage? {
        do {
            let content = try await SCShareableContent.current
            guard let window = content.windows.first(where: { $0.windowID == wid }) else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            config.width = max(2, Int(window.frame.width * scale))
            config.height = max(2, Int(window.frame.height * scale))
            config.showsCursor = false
            let cg = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                configuration: config)
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        } catch {
            return nil
        }
    }
}
