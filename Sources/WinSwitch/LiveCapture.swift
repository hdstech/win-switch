import AppKit
import ScreenCaptureKit
import CoreMedia

/// Streams live frames of a single window via ScreenCaptureKit, so a video
/// playing in the selected window plays live in the switcher preview.
final class LiveCapture: NSObject {
    static let shared = LiveCapture()

    private var stream: SCStream?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    var onFrame: ((NSImage) -> Void)?

    func start(windowID: CGWindowID) {
        stop()
        Task { [weak self] in
            do {
                let content: SCShareableContent
                if #available(macOS 14.0, *) {
                    content = try await SCShareableContent.current
                } else {
                    content = try await SCShareableContent
                        .excludingDesktopWindows(false, onScreenWindowsOnly: false)
                }
                guard let window = content.windows.first(where: { $0.windowID == windowID }) else { return }
                guard let self else { return }

                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                config.width = max(2, Int(window.frame.width * scale))
                config.height = max(2, Int(window.frame.height * scale))
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false
                config.queueDepth = 3
                config.capturesAudio = false

                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .screen,
                                           sampleHandlerQueue: DispatchQueue(label: "winswitch.capture"))
                try await stream.startCapture()
                self.stream = stream
            } catch {
                // Missing Screen Recording permission or window vanished — the
                // static thumbnail remains in place.
            }
        }
    }

    func stop() {
        let s = stream
        stream = nil
        if let s { Task { try? await s.stopCapture() } }
    }
}

extension LiveCapture: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        DispatchQueue.main.async { self.onFrame?(image) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            if self?.stream === stream { self?.stream = nil }
        }
    }
}
