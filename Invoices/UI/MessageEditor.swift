import AppKit
import SwiftUI

/// A form row for prose: a message, rather than a value on the right-hand
/// side of a label.
///
/// `TextField(axis: .vertical)` is the obvious way to write one and the
/// wrong one. On macOS the Return key ends its editing instead of breaking
/// the line, so text that is meant to have paragraphs — or even two lines —
/// cannot be typed into it at all. `TextEditor` is a text view, and takes
/// the Return.
///
/// The label goes above rather than beside, because a form row lays its
/// content out against the trailing edge, which leaves prose set to the
/// right a word or two per line. It is read from the left, the full width of
/// the row.
struct MessageEditor: View {
    let title: LocalizedStringKey
    @Binding var text: String
    /// What the field says when it is empty — the same part a `TextField`
    /// takes as its `prompt`. A text view has no such thing of its own.
    var prompt: String?
    /// How many lines the box shows. It does not grow with the text: past
    /// this much the editor scrolls, the way a mail window does.
    var lines: Int = 8

    @FocusState private var isFocused: Bool

    init(_ title: LocalizedStringKey, text: Binding<String>, prompt: String? = nil, lines: Int = 8) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.lines = lines
    }

    /// One line of body text, so `lines` counts what it says it counts.
    private static var lineHeight: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .body)
        return ceil(font.ascender - font.descender + font.leading)
    }

    private static let inset: CGFloat = 8

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .overlay(alignment: .topLeading) {
                    if let prompt, text.isEmpty {
                        Text(verbatim: prompt)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            // The prompt is what is under the cursor, not
                            // something to put a cursor in.
                            .allowsHitTesting(false)
                    }
                }
                .padding(Self.inset)
                .frame(height: CGFloat(lines) * Self.lineHeight + Self.inset * 2)
                .background(.quaternary.opacity(0.6), in: shape)
                // A text view on a plate of its own draws no focus ring, and
                // a field nobody can see the focus of is a field nobody can
                // tell is taking the typing.
                .overlay {
                    shape.strokeBorder(
                        isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                        lineWidth: isFocused ? 2 : 1
                    )
                }
        }
        .padding(.vertical, 4)
    }
}
