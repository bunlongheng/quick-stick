import CoreImage
import SwiftUI

/// One sticky. A flat block of colour with no chrome, so the only thing that
/// can announce "title here, body below" is the type itself: the title set in
/// the dot-matrix display face and ruled off with a hairline.
struct StickyCell: View {
    @Binding var sticky: Sticky
    let index: Int
    let focused: Bool
    @FocusState.Binding var focusedTitle: Int?
    var onBodyFocus: (Bool) -> Void
    var onBodyDrag: (Int, CGPoint, Bool) -> Void

    /// The web app sets the title in uppercase with a CSS transform, which
    /// AppKit has no equivalent of in an editable field. Uppercasing on the way
    /// out is the closest thing: what is stored is only ever what was typed.
    private var title: Binding<String> {
        Binding(get: { sticky.title.uppercased() }, set: { sticky.title = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("", text: title)
                    .textFieldStyle(.plain)
                    .font(Fonts.font(Fonts.displayFamily, size: 20, weight: 600))
                    .tracking(0.8)
                    .foregroundStyle(.black)
                    .focused($focusedTitle, equals: index)
                    .onSubmit { NotificationCenter.default.post(name: .focusBody, object: index) }
                Rectangle()
                    .fill(Color.black.opacity(ruleInk))
                    .frame(height: 1)
                    .animation(.easeOut(duration: 0.16), value: ruleInk)
            }
            BodyTextView(index: index, text: $sticky.content, isEditing: focused,
                         onFocus: onBodyFocus, onDrag: onBodyDrag)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: sticky.color, brightness: 0.7))
    }

    /// Faint at rest, ink-dark once the cell has focus. An empty cell drops it
    /// almost to nothing: a hint that the structure is there, not a line to read.
    private var ruleInk: Double {
        if focused { return 0.55 }
        return sticky.isEmpty ? 0.05 : 0.16
    }
}

/// The only control on the board. A hairline ring drawn in the same ink as the
/// rules inside the cells, so it sits in the colour rather than on top of it.
/// Press it and the sizes come out; press it again and the board is bare.
struct SettingsCorner: View {
    @EnvironmentObject var state: AppState
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if state.settingsOpen, let url = Config.lanURL {
                QRCard(url: url).transition(.scale(scale: 0.96, anchor: .bottomTrailing).combined(with: .opacity))
            }
            HStack(spacing: 8) {
                if state.settingsOpen { panel.transition(.scale(scale: 0.96, anchor: .trailing).combined(with: .opacity)) }
                disc
            }
        }
        .animation(.easeOut(duration: 0.16), value: state.settingsOpen)
    }

    private var disc: some View {
        Button {
            state.settingsOpen.toggle()
        } label: {
            Circle()
                .fill(state.settingsOpen ? Color.black.opacity(0.12) : .clear)
                .overlay(Circle().strokeBorder(Color.black.opacity(ringInk), lineWidth: 1))
                .overlay(Circle().fill(dotInk).frame(width: 4, height: 4))
                .frame(width: 20, height: 20)
                // The ring is a hairline and the fill is clear, so without this
                // the only thing you could press is the 1px stroke itself.
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.16), value: hovering)
    }

    private var ringInk: Double {
        state.settingsOpen ? 0.55 : hovering ? 0.5 : 0.22
    }

    /// The one time the board says something without being asked.
    private var dotInk: Color {
        if state.status == .error { return .red }
        return .black.opacity(state.settingsOpen ? 0.7 : hovering ? 0.55 : 0.3)
    }

    private var panel: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach([6, 9, 12], id: \.self) { n in
                    Button { state.count = n } label: {
                        Text("\(n)")
                            .font(.system(size: 11))
                            .foregroundStyle(state.count == n ? Color.white : Color.white.opacity(0.4))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(state.count == n ? Color.white.opacity(0.2) : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }

            if state.hidden > 0 || state.status == .saving || state.status == .error {
                Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 14)
            }

            // Silence is the success case. A write in flight or a write that
            // failed is the only thing worth a word.
            if state.status == .saving || state.status == .error {
                Text(state.status == .saving ? "saving" : (state.message.isEmpty ? "not saved" : state.message))
                    .font(.system(size: 11))
                    .foregroundStyle(state.status == .error ? Color.red.opacity(0.8) : Color.white.opacity(0.45))
            }

            if state.hidden > 0 {
                Text("\(state.hidden) hidden")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .help("\(state.hidden) filled notes hidden - switch to 12 to see them")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.6)))
    }
}

/// The board on a phone: scan, and the same web app opens over the LAN.
/// White because a QR code has to be; everything else stays in the ink.
struct QRCard: View {
    let url: String

    var body: some View {
        VStack(spacing: 6) {
            if let image = Self.code(for: url) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 112, height: 112)
            }
            Text(url)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.black.opacity(0.6))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
        .onTapGesture { if let u = URL(string: url) { NSWorkspace.shared.open(u) } }
    }

    static func code(for text: String) -> NSImage? {
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(Data(text.utf8), forKey: "inputMessage")
        filter?.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter?.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
