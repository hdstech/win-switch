import AppKit

/// Keeps fresh thumbnails for every candidate window in memory, so the
/// switcher UI pops up instantly without waiting for captures.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var cache: [CGWindowID: NSImage] = [:]
    private var timer: Timer?
    private let queue = DispatchQueue(label: "winswitch.thumbnails", qos: .userInitiated)

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func image(for wid: CGWindowID) -> NSImage? {
        cache[wid]
    }

    private func refresh() {
        let ids = WindowManager.enumerateIDs()
        queue.async { [weak self] in
            var fresh: [CGWindowID: NSImage] = [:]
            for wid in ids {
                if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, wid,
                                                    [.boundsIgnoreFraming, .bestResolution]) {
                    fresh[wid] = NSImage(cgImage: cg,
                                         size: NSSize(width: cg.width, height: cg.height))
                }
            }
            DispatchQueue.main.async { self?.cache = fresh }
        }
    }
}
