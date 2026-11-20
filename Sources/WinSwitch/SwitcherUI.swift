import AppKit
import SwiftUI

private let cellWidth: CGFloat = 250
private let cellHeight: CGFloat = 158

final class SwitcherPanel: NSPanel {
    init(state: SwitcherState, onSelect: @escaping (Int) -> Void) {
        let screen = NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1440, height: 900)
        let width = min(CGFloat(state.windows.count) * (cellWidth + 14) + 40, screen.width - 120)
        let height = cellHeight + 96
        let rect = NSRect(x: screen.midX - width / 2, y: screen.midY - height / 2,
                          width: width, height: height)

        super.init(contentRect: rect,
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)

        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: rect.size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        contentView?.addSubview(effect)

        let hosting = NSHostingView(rootView: SwitcherRootView(state: state, onSelect: onSelect))
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
    }

    func present() {
        orderFrontRegardless()
    }

    func dismiss() {
        orderOut(nil)
    }
}

struct SwitcherRootView: View {
    @ObservedObject var state: SwitcherState
    var onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(state.windows.enumerated()), id: \.element.id) { index, item in
                        WindowCell(item: item,
                                   isSelected: index == state.selectedIndex,
                                   liveImage: state.liveImage)
                            .id(item.id)
                            .onTapGesture { onSelect(index) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onChange(of: state.selectedIndex) { _ in
                if let id = selectedID() {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onAppear {
                if let id = selectedID() { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func selectedID() -> CGWindowID? {
        state.windows.indices.contains(state.selectedIndex)
            ? state.windows[state.selectedIndex].id : nil
    }
}

struct WindowCell: View {
    let item: WindowItem
    let isSelected: Bool
    let liveImage: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.45))
                if let img = displayedImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(6)
                        .padding(3)
                }
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 22, height: 22)
                        .padding(3)
                        .background(.white.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .padding(6)
                }
                badgeView
            }
            .frame(width: cellWidth, height: cellHeight)

            Text(item.displayTitle)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(item.appName)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .cornerRadius(10)
    }

    private var displayedImage: NSImage? {
        if isSelected, let live = liveImage { return live }
        if let thumb = item.thumbnail { return thumb }
        return item.icon // fall back to the app icon when no capture is available
    }

    @ViewBuilder private var badgeView: some View {
        if item.isMinimized {
            badge("Minimized")
        } else if !item.isOnscreen {
            badge("Other Space")
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.7))
            .cornerRadius(4)
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}
