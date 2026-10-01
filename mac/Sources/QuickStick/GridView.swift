import AppKit
import Foundation
import SwiftUI

/// The board. A flat grid of colour with no chrome at all: the only control on
/// screen is one hairline disc in the corner.
struct GridView: View {
    @EnvironmentObject var state: AppState
    @FocusState private var focusedTitle: Int?
    @State private var focusedBody: Int?
    @State private var dragFrom: Int?
    @State private var dragOver: Int?

    private static let space = "grid"

    var body: some View {
        GeometryReader { geo in
            let cols = state.count == 12 ? 4 : 3
            let rows = Int(ceil(Double(state.count) / Double(cols)))
            let cell = CGSize(width: geo.size.width / CGFloat(cols),
                              height: geo.size.height / CGFloat(rows))

            let frame = geo.frame(in: .global)

            ZStack(alignment: .bottomTrailing) {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(0..<rows, id: \.self) { row in
                        GridRow {
                            ForEach(0..<cols, id: \.self) { col in
                                let i = row * cols + col
                                if i < state.count {
                                    cellView(i, size: cell, origin: frame.origin)
                                } else {
                                    Color.clear
                                }
                            }
                        }
                    }
                }
                SettingsCorner()
                    .padding(12)
            }
            .coordinateSpace(name: Self.space)
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncNow)) { _ in
            Task { await state.sync() }
        }
    }

    @ViewBuilder
    private func cellView(_ i: Int, size: CGSize, origin: CGPoint) -> some View {
        let focused = focusedTitle == i || focusedBody == i
        StickyCell(
            sticky: $state.stickies[i],
            index: i,
            focused: focused,
            focusedTitle: $focusedTitle,
            onBodyFocus: { focusedBody = $0 ? i : (focusedBody == i ? nil : focusedBody) },
            onBodyDrag: { from, point, ended in
                bodyDrag(from: from, at: CGPoint(x: point.x - origin.x, y: point.y - origin.y),
                         ended: ended, size: size)
            }
        )
        .frame(width: size.width, height: size.height)
        .opacity(dragFrom == i ? 0.55 : 1)
        .overlay {
            // The cell you are over is ruled with an inset line in the same
            // ink as everything else. Nothing is added that is not already there.
            if dragOver == i, let from = dragFrom, from != i {
                Rectangle()
                    .strokeBorder(Color.black.opacity(0.45), lineWidth: 3)
            }
        }
        .animation(.easeOut(duration: 0.14), value: dragFrom)
        .animation(.easeOut(duration: 0.14), value: dragOver)
        // The padding and the title pick the sticky up whether or not the
        // cell is being edited, as on the web. A press inside the body is
        // handled by the text view itself: selection while editing, a drag
        // otherwise, and AppKit's tracking loop keeps either from reaching here.
        .gesture(dragGesture(i, size: size))
    }

    /// The same move, driven from inside a cell's body rather than from its
    /// padding. AppKit has already decided this is a drag by the time it calls.
    private func bodyDrag(from: Int, at point: CGPoint, ended: Bool, size: CGSize) {
        if ended {
            let to = cellIndex(at: point, size: size)
            dragFrom = nil
            dragOver = nil
            if let to { state.move(from: from, to: to) }
            return
        }
        if dragFrom == nil { dragFrom = from }
        dragOver = cellIndex(at: point, size: size)
    }

    private func dragGesture(_ i: Int, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if dragFrom == nil {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    dragFrom = i
                }
                dragOver = cellIndex(at: value.location, size: size)
            }
            .onEnded { value in
                let from = dragFrom
                let to = cellIndex(at: value.location, size: size)
                dragFrom = nil
                dragOver = nil
                if let from, let to { state.move(from: from, to: to) }
            }
    }

    /// Uniform grid, so the slot under the cursor is arithmetic.
    private func cellIndex(at point: CGPoint, size: CGSize) -> Int? {
        let cols = state.count == 12 ? 4 : 3
        guard size.width > 0, size.height > 0, point.x >= 0, point.y >= 0 else { return nil }
        let col = Int(point.x / size.width), row = Int(point.y / size.height)
        guard col < cols else { return nil }
        let i = row * cols + col
        return i < state.count ? i : nil
    }
}

extension Notification.Name {
    static let syncNow = Notification.Name("quickstick.syncNow")
}
