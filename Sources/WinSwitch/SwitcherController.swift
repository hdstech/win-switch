import AppKit
import CoreGraphics

final class SwitcherState: ObservableObject {
    @Published var windows: [WindowItem] = []
    @Published var selectedIndex = 0
    @Published var liveImage: NSImage?
    var isOpen = false
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
            moveSelection(id == 2 ? -1 : 1)
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

        loadThumbnails()

        panel = SwitcherPanel(state: state) { [weak self] index in
            self?.commit(index: index)
        }
        panel?.present()
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

    private func moveSelection(_ delta: Int) {
        let count = state.windows.count
        guard count > 0 else { return }
        state.selectedIndex = (state.selectedIndex + delta + count) % count
        state.liveImage = nil
        startLiveCapture()
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var thumbs: [CGWindowID: NSImage] = [:]
            for w in items {
                if let img = Thumbnails.capture(w.id) { thumbs[w.id] = img }
            }
            DispatchQueue.main.async {
                guard let self, self.state.isOpen else { return }
                for i in self.state.windows.indices {
                    if let t = thumbs[self.state.windows[i].id] {
                        self.state.windows[i].thumbnail = t
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

        // Escape cancels; arrows navigate. Edge-triggered so one press = one move.
        checkKey(53) { [weak self] in self?.cancel() }
        checkKey(123) { [weak self] in self?.moveSelection(-1) }
        checkKey(124) { [weak self] in self?.moveSelection(1) }
    }

    private func checkKey(_ code: CGKeyCode, _ action: () -> Void) {
        let pressed = CGEventSource.keyState(.combinedSessionState, key: code)
        if pressed && !(keyHeld[code] ?? false) { action() }
        keyHeld[code] = pressed
    }
}
