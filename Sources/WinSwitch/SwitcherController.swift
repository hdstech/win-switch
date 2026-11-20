import AppKit
import CoreGraphics

final class SwitcherState: ObservableObject {
    @Published var windows: [WindowItem] = []
    @Published var selectedIndex = 0
    @Published var liveImage: NSImage?
    /// Bumped when the selection should be scrolled into view (keyboard nav
    /// only — mouse hover selects without scrolling).
    @Published var scrollRequest = 0
    // Preferences (persisted): "previews"|"icons", "bottom"|"side"
    @Published var gridStyle: String {
        didSet { UserDefaults.standard.set(gridStyle, forKey: "gridStyle") }
    }
    @Published var gridPosition: String {
        didSet { UserDefaults.standard.set(gridPosition, forKey: "gridPosition") }
    }
    var isOpen = false
    var gridColumns = 1

    init() {
        gridStyle = UserDefaults.standard.string(forKey: "gridStyle") ?? "previews"
        gridPosition = UserDefaults.standard.string(forKey: "gridPosition") ?? "bottom"
    }
}

/// State machine for the switcher UI. While open it polls CGEventSource for the
/// Option key, Escape and the arrow keys — polling works without Accessibility /
/// Input Monitoring permissions, unlike CGEventTap.
final class SwitcherController {
    static let shared = SwitcherController()

    let state = SwitcherState()
    private var panel: SwitcherPanel?
    private var pollTimer: Timer?
    private var keyHeld: [CGKeyCode: Bool] = [:]
    private var workspaceObserver: NSObjectProtocol?

    private init() {
        LiveCapture.shared.onFrame = { [weak self] img in
            self?.state.liveImage = img
        }
    }

    // Hotkey IDs: 1 = ⌥⇥ next, 2 = ⇧⌥⇥ previous
    func onHotKey(id: Int) {
        if state.isOpen {
            select(state.selectedIndex + (id == 2 ? -1 : 1), wrap: true, scroll: true)
        } else {
            open()
        }
    }

    func open() {
        state.windows = WindowManager.enumerate()
        guard !state.windows.isEmpty else { return }
        // Default to the previous window (index 0 is the frontmost window).
        state.selectedIndex = state.windows.count > 1 ? 1 : 0
        state.liveImage = nil

        // Instant thumbnails from the warm cache; async refresh fills in gaps.
        for i in state.windows.indices {
            state.windows[i].thumbnail =
                ThumbnailCache.shared.image(for: state.windows[i].id)
        }
        loadThumbnails()
        presentPanel()

        state.isOpen = true
        startPolling()
        startLiveCapture()

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // Something else took focus while the switcher was open — bail out.
            self?.cancel()
        }
    }

    private func presentPanel() {
        panel = SwitcherPanel(state: state,
                              onSelect: { [weak self] i in self?.commit(index: i) },
                              onHover: { [weak self] i in self?.select(i) })
        panel?.present()
    }

    /// Rebuild the panel when a layout-affecting preference changes.
    func refreshLayout() {
        guard state.isOpen else { return }
        panel?.dismiss()
        presentPanel()
    }

    func select(_ index: Int, wrap: Bool = false, scroll: Bool = false) {
        let count = state.windows.count
        guard count > 0 else { return }
        let next = wrap ? (index + count) % count : max(0, min(count - 1, index))
        guard next != state.selectedIndex else { return }
        state.selectedIndex = next
        state.liveImage = nil
        startLiveCapture()
        if scroll { state.scrollRequest += 1 }
    }

    private func commit(index: Int? = nil) {
        let i = index ?? state.selectedIndex
        let window = state.windows.indices.contains(i) ? state.windows[i] : nil
        close()
        if let window { WindowManager.activate(window) }
    }

    private func cancel() { close() }

    private func close() {
        state.isOpen = false
        pollTimer?.invalidate()
        pollTimer = nil
        keyHeld.removeAll()
        LiveCapture.shared.stop()
        panel?.dismiss()
        panel = nil
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            workspaceObserver = nil
        }
    }

    private func startLiveCapture() {
        guard state.windows.indices.contains(state.selectedIndex) else { return }
        LiveCapture.shared.start(windowID: state.windows[state.selectedIndex].id)
    }

    private func loadThumbnails() {
        let items = state.windows
        Task.detached { [weak self] in
            var thumbs: [CGWindowID: NSImage] = [:]
            for w in items {
                if let img = await Thumbnails.capture(w.id) { thumbs[w.id] = img }
            }
            await MainActor.run {
                guard let self, self.state.isOpen else { return }
                for i in self.state.windows.indices {
                    if let t = thumbs[self.state.windows[i].id] {
                        self.state.windows[i].thumbnail = t
                        ThumbnailCache.shared.set(self.state.windows[i].id, image: t)
                    }
                }
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        guard state.isOpen else { return }

        // Releasing Option commits the selection (classic ⌥⇥ semantics).
        let flags = CGEventSource.flagsState(.combinedSessionState)
        if !flags.contains(.maskAlternate) {
            commit()
            return
        }

        // Escape cancels; arrows navigate the grid. Edge-triggered so one
        // press = one move.
        checkKey(53) { [weak self] in self?.cancel() }
        checkKey(123) { [weak self] in self?.select((self?.state.selectedIndex ?? 0) - 1, wrap: true, scroll: true) }
        checkKey(124) { [weak self] in self?.select((self?.state.selectedIndex ?? 0) + 1, wrap: true, scroll: true) }
        checkKey(126) { [weak self] in
            guard let self else { return }
            self.select(self.state.selectedIndex - self.state.gridColumns, scroll: true)
        }
        checkKey(125) { [weak self] in
            guard let self else { return }
            self.select(self.state.selectedIndex + self.state.gridColumns, scroll: true)
        }
    }

    private func checkKey(_ code: CGKeyCode, _ action: () -> Void) {
        let pressed = CGEventSource.keyState(.combinedSessionState, key: code)
        if pressed && !(keyHeld[code] ?? false) { action() }
        keyHeld[code] = pressed
    }
}
