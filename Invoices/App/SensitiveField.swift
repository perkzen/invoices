import SwiftUI

/// A labelled text field whose value private mode hides. The label sits
/// outside the field, so a hidden section still reads as a list of named
/// values rather than a column of masks with nothing naming them.
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
