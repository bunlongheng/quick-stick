import Foundation

/// One cell of the grid. Mirrors the web app's Sticky exactly.
struct Sticky: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var title: String = ""
    var content: String = ""
    var color: String

    var isEmpty: Bool {
        title.trimmed.isEmpty && content.trimmed.isEmpty
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// The 12 sticky colours, in order. A slot owns its colour: moving a note moves
/// the writing, never the palette.
enum Palette {
    static let colors = [
        "#FF6B6B", "#FF8F6B", "#FFB84D", "#FFE066", "#E8EF7B", "#6DDC8C",
        "#4DD9D2", "#6CC4F0", "#5EA3FF", "#8B89E8", "#C47EEA", "#FF6B8A",
    ]
    static let max = 12

    static func blank() -> [Sticky] {
        (0..<max).map { Sticky(color: colors[$0 % colors.count]) }
    }
}
