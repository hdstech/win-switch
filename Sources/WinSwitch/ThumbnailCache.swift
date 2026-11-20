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

    /// Called when a capture succeeds through another path (e.g. the
    /// SCScreenshotManager fallback) so the image persists across opens.
    func set(_ wid: CGWindowID, image: NSImage) {
        cache[wid] = image
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
            DispatchQueue.main.async {
                guard let self else { return }
                // Only overwrite with successful captures — a transient nil
                // must not knock a good image back to the icon fallback.
                for wid in ids {
                    if let img = fresh[wid] { self.cache[wid] = img }
                }
                // Drop windows that no longer exist.
                let alive = Set(ids)
                self.cache = self.cache.filter { alive.contains($0.key) }
            }
        }
    }
}
