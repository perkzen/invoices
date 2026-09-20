import SwiftUI

/// A text field whose value private mode blanks. A redacted `TextField` takes
/// its own label with it, so the label sits outside it — otherwise a section
/// would be left as grey rectangles with nothing naming them.
struct SensitiveField: View {
    let title: LocalizedStringKey
    @Binding var text: String

    init(_ title: LocalizedStringKey, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text)
                .labelsHidden()
                .sensitiveValue()
        }
    }
}
