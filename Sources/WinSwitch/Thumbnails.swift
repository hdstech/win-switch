import AppKit

enum Thumbnails {
    /// Static per-window capture. Works for windows on other spaces and
    /// minimized windows (returns the window's backing store). Requires
    /// Screen Recording permission on modern macOS.
    static func capture(_ wid: CGWindowID) -> NSImage? {
        guard let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, wid,
                                               [.boundsIgnoreFraming, .bestResolution])
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
