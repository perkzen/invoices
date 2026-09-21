import SwiftUI

/// An editable value that private mode blanks.
///
/// `.redacted(reason: .privacy)` blanks a text field's *label* and leaves the
/// value inside it legible — the field is an AppKit view and draws its own
/// text. So the field is swapped for the blanked value instead, which also
/// makes it read-only for as long as it is hidden: a number you cannot see
/// is not one to type over.
struct SensitiveValue<Field: View>: View {
    private let value: String
    private let field: Field

    @AppStorage(PrivacyMode.storageKey) private var hidesSensitiveValues = false

    init(_ value: String, @ViewBuilder field: () -> Field) {
        self.value = value
        self.field = field()
    }

    var body: some View {
        if hidesSensitiveValues {
            // The blanked value, so the bar is the width of what it hides,
            // like every other blanked value in the app.
            Text(value).sensitiveValue()
        } else {
            field
        }
    }
}

/// A labelled text field whose value private mode blanks. The label sits
/// outside the field, so a hidden section still reads as a list of named
/// values rather than grey rectangles with nothing naming them.
struct SensitiveField: View {
    let title: LocalizedStringKey
    @Binding var text: String

    init(_ title: LocalizedStringKey, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        LabeledContent(title) {
            SensitiveValue(text) {
                TextField(title, text: $text)
                    .labelsHidden()
            }
        }
    }
}
