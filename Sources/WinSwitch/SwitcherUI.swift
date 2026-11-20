import AppKit
import SwiftUI

/// Computes a fixed (non-scrolling) layout. Two modes:
///   "bottom" — large preview on top, wrapping thumbnail grid below.
///   "side"   — large preview on the left, vertical thumbnail grid on the right.
struct GridLayout {
    let spacing: CGFloat = 12
    let padding: CGFloat = 22
    let columns: Int
    let cellWidth: CGFloat
    let thumbHeight: CGFloat
    let cellHeight: CGFloat
    let previewWidth: CGFloat
    let previewHeight: CGFloat
    let panelSize: NSSize

    init(count: Int, screen: NSRect, position: String) {
        if position == "side" {
            self.init(side: count, screen: screen)
        } else {
            self.init(bottom: count, screen: screen)
        }
    }

    private init(bottom count: Int, screen: NSRect) {
        let maxW = screen.width - 120
        let n = max(count, 1)
        var cols = min(n, max(4, Int(ceil(Double(n) / 4.0))))
        let baseCellW: CGFloat = 200
        let maxColsByWidth = max(1, Int((maxW - 2 * padding + spacing) / (baseCellW + spacing)))
        cols = max(1, min(cols, maxColsByWidth))
        columns = cols
        let rows = max(1, Int(ceil(Double(n) / Double(cols))))
        cellWidth = max(120, min(baseCellW,
            floor((maxW - 2 * padding - spacing * CGFloat(cols - 1)) / CGFloat(cols))))
        thumbHeight = cellWidth * 0.62
        cellHeight = thumbHeight + 26
        previewWidth = 0
        previewHeight = min(340, screen.height * 0.4)
        let w = 2 * padding + CGFloat(cols) * cellWidth + spacing * CGFloat(cols - 1)
        let gridH = CGFloat(rows) * cellHeight + spacing * CGFloat(rows - 1)
        let h = previewHeight + 34 + 12 + gridH + 2 * padding
        panelSize = NSSize(width: w, height: min(h, screen.height - 80))
    }

    private init(side count: Int, screen: NSRect) {
        let maxH = screen.height - 140
        let n = max(count, 1)
        let sideCols = n > 5 ? 2 : 1
        columns = sideCols
        let rows = max(1, Int(ceil(Double(n) / Double(sideCols))))

        let baseCellW: CGFloat = 180
        cellWidth = baseCellW
        // Shrink thumbnails vertically if needed so every row fits on screen.
        let availPerRow = (maxH - 2 * padding - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        thumbHeight = max(60, min(cellWidth * 0.62, availPerRow - 26))
        cellHeight = thumbHeight + 26

        let gridW = CGFloat(sideCols) * cellWidth + spacing * CGFloat(sideCols - 1)
        let gridH = CGFloat(rows) * cellHeight + spacing * CGFloat(rows - 1)

        previewWidth = min(560, (screen.width - 120) * 0.45)
        let contentH = max(gridH, 320)
        previewHeight = contentH
        panelSize = NSSize(
            width: 2 * padding + previewWidth + spacing + gridW,
            height: contentH + 34 + 2 * padding)
    }
}

final class SwitcherPanel: NSPanel {
    init(state: SwitcherState,
         onSelect: @escaping (Int) -> Void,
         onHover: @escaping (Int) -> Void) {
        let screen = NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1440, height: 900)
        let layout = GridLayout(count: state.windows.count,
                                screen: screen, position: state.gridPosition)
        state.gridColumns = layout.columns

        let size = layout.panelSize
        let rect = NSRect(x: screen.midX - size.width / 2,
                          y: screen.midY - size.height / 2,
                          width: size.width, height: size.height)

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
        acceptsMouseMovedEvents = true

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        contentView?.addSubview(effect)

        let hosting = NSHostingView(rootView: SwitcherRootView(
            state: state, layout: layout, onSelect: onSelect, onHover: onHover))
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
    }

    func present() { orderFrontRegardless() }
    func dismiss() { orderOut(nil) }
}

struct SwitcherRootView: View {
    @ObservedObject var state: SwitcherState
    let layout: GridLayout
    var onSelect: (Int) -> Void
    var onHover: (Int) -> Void

    private var selected: WindowItem? {
        state.windows.indices.contains(state.selectedIndex)
            ? state.windows[state.selectedIndex] : nil
    }

    var body: some View {
        Group {
            if state.gridPosition == "side" {
                HStack(alignment: .top, spacing: 12) {
                    preview
                        .frame(width: layout.previewWidth)
                    grid
                }
            } else {
                VStack(spacing: 12) {
                    preview
                    grid
                }
            }
        }
        .padding(layout.padding)
    }

    // MARK: Large preview of the selected window

    private var preview: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.45))
                if let img = previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                        .padding(4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: layout.previewHeight)

            HStack(spacing: 8) {
                if let icon = selected?.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Text(selected?.displayTitle ?? "")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(selected?.appName ?? "")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                if let item = selected {
                    if item.isMinimized {
                        badge("Minimized")
                    } else if !item.isOnscreen {
                        badge("Other Space")
                    }
                }
            }
            .frame(height: 26)
        }
    }

    private var previewImage: NSImage? {
        state.liveImage ?? selected?.thumbnail ?? selected?.icon
    }

    // MARK: Fixed grid of all windows

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(layout.cellWidth),
                                             spacing: layout.spacing),
                           count: layout.columns),
            spacing: layout.spacing
        ) {
            ForEach(Array(state.windows.enumerated()), id: \.element.id) { index, item in
                GridCell(item: item,
                         isSelected: index == state.selectedIndex,
                         iconsOnly: state.gridStyle == "icons",
                         width: layout.cellWidth,
                         thumbHeight: layout.thumbHeight)
                    .onTapGesture { onSelect(index) }
                    .onHover { inside in
                        if inside { onHover(index) }
                    }
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.65))
            .cornerRadius(4)
    }
}

struct GridCell: View {
    let item: WindowItem
    let isSelected: Bool
    let iconsOnly: Bool
    let width: CGFloat
    let thumbHeight: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.black.opacity(0.4))
                if iconsOnly {
                    if let icon = item.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: thumbHeight * 0.55)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if let img = item.thumbnail ?? item.icon {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(6)
                        .padding(2)
                }
                if !iconsOnly, let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .padding(2)
                        .background(.white.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }
            .frame(width: width, height: thumbHeight)

            Text(item.displayTitle)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: width)
        }
        .padding(5)
        .background(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
        )
        .cornerRadius(9)
    }
}
