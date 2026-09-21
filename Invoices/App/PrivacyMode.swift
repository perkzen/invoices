import SwiftUI

/// Private mode — one switch that hides the values a passer-by or a shared
/// screen should not read: the bank account, the tax numbers and every amount.
///
/// It is a view preference and not a fact about the business, so it lives in
/// `AppStorage` and never touches the store: the exported PDF, the spreadsheet
/// and the printed invoice carry the real values even while it is on.
enum PrivacyMode {
    static let storageKey = "hidesSensitiveValues"

    /// What stands in for a hidden value, in the interface and on the
    /// rendered page alike. One mask everywhere: a hidden value reads as a
    /// value withheld, and never as a blank where something failed to load.
    static let mask = "****"
}

extension View {
    /// Marks a value private mode hides, and hides it: the view is replaced
    /// by `PrivacyMode.mask` while the switch is on.
    ///
    /// It goes directly on the value, ahead of the font, the colour and the
    /// frame around it, so the mask is styled and placed exactly as the value
    /// it stands in for — but behind a strikethrough, which belongs to the
    /// value and not to the mask standing in for it. Put it on the field itself where the value is
    /// editable — the mask is read-only, which is the point: a number you
    /// cannot see is not one to type over.
    ///
    /// `.redacted(reason: .privacy)` is not what does this. It blanks a text
    /// field's *label* and leaves the value inside it legible, because the
    /// field is an AppKit view drawing its own text.
    func sensitiveValue() -> some View {
        modifier(SensitiveValue())
    }
}

private struct SensitiveValue: ViewModifier {
    @AppStorage(PrivacyMode.storageKey) private var hidesSensitiveValues = false

    func body(content: Content) -> some View {
        if hidesSensitiveValues {
            Text(PrivacyMode.mask)
        } else {
            content
        }
    }
}
