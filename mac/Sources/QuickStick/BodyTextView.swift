import AppKit
import SwiftUI

/// The body of a sticky. An NSTextView rather than a TextEditor because the
/// cell needs three things SwiftUI will not give up: the 1.55 line height the
/// web app sets, a fully transparent scroll view, and a dark scroller knob -
/// ink on the colour, the way the web scrollbar is drawn.
struct BodyTextView: NSViewRepresentable {
    /// Which cell this is, so Enter in that cell's title can jump down here.
    let index: Int
    @Binding var text: String
    /// Whether this cell is the one being edited. AppKit has already made the
    /// text view first responder by the time mouseDown arrives, so asking the
    /// window is no help; this is the same question the web app answers with
    /// document.activeElement.
    let isEditing: Bool
    var onFocus: (Bool) -> Void
    /// A drag that started on a cell nobody is editing. The point is in the
    /// window's content area with a top-left origin, which is the same space
    /// SwiftUI reports geometry in.
    var onDrag: (Int, CGPoint, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = CellTextView.scrollableCellTextView()
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.verticalScroller = InkScroller()
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.scrollerKnobStyle = .dark

        guard let view = scroll.documentView as? CellTextView else { return scroll }
        view.delegate = context.coordinator
        view.index = index
        view.onDrag = onDrag
        view.onFocusChange = onFocus
        view.isEditingCell = isEditing
        view.drawsBackground = false
        view.textColor = .black
        view.insertionPointColor = .black
        // The system blue fights every colour on the board; a wash of black sits in all of them.
        view.selectedTextAttributes = [.backgroundColor: NSColor.black.withAlphaComponent(0.22)]
        view.font = Fonts.nsFont(Fonts.bodyFamily, size: 16, weight: 400)
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isRichText = false
        view.allowsUndo = true
        view.defaultParagraphStyle = Self.paragraph
        view.typingAttributes = [
            .font: Fonts.nsFont(Fonts.bodyFamily, size: 16, weight: 400),
            .foregroundColor: NSColor.black,
            .paragraphStyle: Self.paragraph,
        ]
        view.string = text
        view.restyle()
        context.coordinator.attach(view, at: index)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let cell = scroll.documentView as? CellTextView {
            // SwiftUI reuses these views as the grid changes size, so the index
            // has to be refreshed every pass - a stale one moves the wrong cell.
            cell.index = index
            cell.onDrag = onDrag
            cell.onFocusChange = onFocus
            cell.isEditingCell = isEditing
        }
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text
        view.typingAttributes = [
            .font: Fonts.nsFont(Fonts.bodyFamily, size: 16, weight: 400),
            .foregroundColor: NSColor.black,
            .paragraphStyle: Self.paragraph,
        ]
        (view as? CellTextView)?.restyle()
    }

    private static let paragraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.55
        return p
    }()

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BodyTextView
        private weak var textView: CellTextView?
        private var observer: Any?
        private var doneObserver: Any?

        init(_ parent: BodyTextView) { self.parent = parent }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            if let doneObserver { NotificationCenter.default.removeObserver(doneObserver) }
        }

        func attach(_ view: CellTextView, at index: Int) {
            textView = view
            observer = NotificationCenter.default.addObserver(
                forName: .focusBody, object: nil, queue: .main
            ) { [weak view] note in
                guard let wanted = note.object as? Int else { return }
                MainActor.assumeIsolated {
                    // The view's current index, not the one it was built with.
                    guard let view, view.index == wanted else { return }
                    view.window?.makeFirstResponder(view)
                    view.beginEditing()
                }
            }
            doneObserver = NotificationCenter.default.addObserver(
                forName: .markDone, object: nil, queue: .main
            ) { [weak view] _ in
                MainActor.assumeIsolated {
                    guard let view, view.window?.firstResponder === view else { return }
                    view.toggleDone()
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

/// A text view that is only as tall as its text leaves the rest of the cell
/// belonging to the clip view, where a click lands on nothing. Growing it to
/// the visible height on every layout keeps the whole cell live.
final class CellScrollView: NSScrollView {
    /// "Show scroll bars: Always" in System Settings turns every scroll view
    /// legacy, with a white rail. This one stays an overlay regardless.
    override var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }

    override func layout() {
        super.layout()
        guard let text = documentView as? NSTextView else { return }
        text.minSize = NSSize(width: 0, height: contentSize.height)
        if text.frame.height < contentSize.height {
            text.frame.size.height = contentSize.height
        }
        text.textContainer?.containerSize = NSSize(width: contentSize.width,
                                                   height: CGFloat.greatestFiniteMagnitude)
    }
}

/// The web scrollbar: a translucent black knob floating in the colour, no
/// rail. Drawn by hand so no system style, expanded or legacy, can paint a
/// white track under it.
final class InkScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat { 9 }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func draw(_ dirtyRect: NSRect) { drawKnob() }

    override func drawKnob() {
        let r = rect(for: .knob).insetBy(dx: 2, dy: 2)
        guard r.height > 0 else { return }
        NSColor.black.withAlphaComponent(0.26).setFill()
        NSBezierPath(roundedRect: r, xRadius: r.width / 2, yRadius: r.width / 2).fill()
    }
}

/// The body of a cell nobody is editing has to behave like the rest of the
/// cell: a press that travels picks the sticky up, and a press that does not
/// drops the caret where it landed. AppKit's own mouseDown starts selecting the
/// moment it is called, so the first gesture on an unfocused cell is tracked by
/// hand and only then handed to one behaviour or the other.
final class CellTextView: NSTextView {
    var index = 0
    var onDrag: ((Int, CGPoint, Bool) -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var isEditingCell = false

    /// Editing starts when a click lands, not on the first keystroke the way
    /// textDidBeginEditing reports it. Until then every drag in the cell was
    /// read as a move, and selecting text was impossible.
    func beginEditing() {
        guard !isEditingCell else { return }
        isEditingCell = true
        onFocusChange?(true)
    }

    // MARK: - Done lines

    /// A done line is stored with this prefix: a zero-width space, so the
    /// strike is the only thing that shows and the text still round-trips
    /// as plain text. Lines marked with the earlier check are still done.
    static let doneMark = "\u{200B}"
    private static let oldMark = "\u{2713} "

    static func isDone(_ line: String) -> Bool { line.hasPrefix(doneMark) || line.hasPrefix(oldMark) }
    /// Lines still wearing the old visible check are rewritten to the
    /// invisible mark, so the check never shows again anywhere.
    static func normalizeDone(_ text: String) -> String {
        guard text.contains(oldMark) else { return text }
        return text.components(separatedBy: "\n")
            .map { $0.hasPrefix(oldMark) ? doneMark + $0.dropFirst(oldMark.count) : $0 }
            .joined(separator: "\n")
    }
    static func undone(_ line: String) -> String {
        if line.hasPrefix(doneMark) { return String(line.dropFirst(doneMark.count)) }
        if line.hasPrefix(oldMark) { return String(line.dropFirst(oldMark.count)) }
        return line
    }

    /// Cmd+D. The caret's line, or every line the selection touches, is marked
    /// done and sent to the bottom: the first line finished sits lowest, each
    /// one after it stacks on top. On lines already done it is undone instead,
    /// and the line goes back to the foot of what is still open.
    func toggleDone() {
        let mark = Self.doneMark
        let ns = string as NSString
        let hit = ns.lineRange(for: selectedRange())
        let lines = string.components(separatedBy: "\n")

        var affected: [Int] = []
        var start = 0
        for (i, line) in lines.enumerated() {
            if start >= hit.location, start < NSMaxRange(hit) || (hit.length == 0 && start == hit.location) {
                affected.append(i)
            }
            start += (line as NSString).length + 1
        }
        let targets = affected.filter { !lines[$0].trimmed.isEmpty }
        guard !targets.isEmpty else { return }
        let undo = targets.allSatisfy { Self.isDone(lines[$0]) }

        var open: [String] = [], fresh: [String] = [], done: [String] = []
        for (i, line) in lines.enumerated() {
            if targets.contains(i) {
                if undo { open.append(Self.undone(line)) } else { fresh.append(mark + line) }
            } else if Self.isDone(line) {
                done.append(line)
            } else {
                open.append(line)
            }
        }
        let tail = fresh + done
        if !tail.isEmpty { while open.last?.trimmed.isEmpty == true { open.removeLast() } }
        let result = (open + tail).joined(separator: "\n")

        let full = NSRange(location: 0, length: ns.length)
        guard shouldChangeText(in: full, replacementString: result) else { return }
        textStorage?.replaceCharacters(in: full, with: result)
        didChangeText()

        // Leave the caret on the line that moved.
        let moved = undo ? open.count - 1 : open.count
        let offset = (open + tail).prefix(moved).reduce(0) { $0 + ($1 as NSString).length + 1 }
        setSelectedRange(NSRange(location: offset, length: 0))
    }

    /// Struck through and greyed. Temporary attributes draw over the plain text
    /// without touching what is stored or what the next keystroke inherits.
    func restyle() {
        guard let lm = layoutManager else { return }
        let ns = string as NSString
        let full = NSRange(location: 0, length: ns.length)
        lm.removeTemporaryAttribute(.strikethroughStyle, forCharacterRange: full)
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        ns.enumerateSubstrings(in: full, options: .byLines) { line, range, _, _ in
            guard let line, Self.isDone(line) else { return }
            lm.addTemporaryAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.black.withAlphaComponent(0.35),
            ], forCharacterRange: range)
        }
    }

    override func didChangeText() {
        super.didChangeText()
        restyle()
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, isEditingCell {
            isEditingCell = false
            onFocusChange?(false)
        }
        return resigned
    }

    static func scrollableCellTextView() -> NSScrollView {
        let scroll = CellScrollView()
        let text = CellTextView(frame: .zero)
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        return scroll
    }

    /// Window content coordinates, top-left origin, to match SwiftUI's. The
    /// hosting view is already flipped, so flipping it again puts the drop on
    /// the mirror image of the row it was dropped on.
    private func flipped(_ locationInWindow: NSPoint) -> CGPoint {
        guard let content = window?.contentView else { return locationInWindow }
        let p = content.convert(locationInWindow, from: nil)
        return content.isFlipped ? p : CGPoint(x: p.x, y: content.bounds.height - p.y)
    }

    private var press: NSPoint?
    private var moved = false

    override func mouseDown(with event: NSEvent) {
        // Already editing here: selection, exactly as AppKit does it.
        guard !isEditingCell else {
            super.mouseDown(with: event)
            return
        }
        // A double click wants the word under it, which only AppKit can give.
        if event.clickCount > 1 {
            beginEditing()
            super.mouseDown(with: event)
            return
        }
        // Hold the press instead of handing it to AppKit, which would start
        // selecting immediately and swallow the gesture.
        press = event.locationInWindow
        moved = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = press else {
            super.mouseDragged(with: event)
            return
        }
        let p = event.locationInWindow
        if !moved, hypot(p.x - start.x, p.y - start.y) < 8 { return }
        moved = true
        onDrag?(index, flipped(p), false)
    }

    override func mouseUp(with event: NSEvent) {
        guard press != nil else {
            super.mouseUp(with: event)
            return
        }
        press = nil

        if moved {
            onDrag?(index, flipped(event.locationInWindow), true)
            return
        }

        // A plain click: take focus and put the caret where it landed.
        window?.makeFirstResponder(self)
        let local = convert(event.locationInWindow, from: nil)
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: local), length: 0))
        beginEditing()
    }
}

extension Notification.Name {
    static let focusBody = Notification.Name("quickstick.focusBody")
    static let markDone = Notification.Name("quickstick.markDone")
}
