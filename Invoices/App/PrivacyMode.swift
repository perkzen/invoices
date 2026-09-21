import SwiftUI

/// Private mode — one switch that blanks the values a passer-by or a shared
/// screen should not read: the bank account, the tax numbers and every amount.
///
/// It is a view preference and not a fact about the business, so it lives in
/// `AppStorage` and never touches the store: the exported PDF, the spreadsheet
/// and the printed invoice carry the real values even while it is on.
enum PrivacyMode {
    static let storageKey = "hidesSensitiveValues"

    /// What stands in for a hidden value where a grey bar cannot be drawn —
    /// the rendered PDF, which is an image of a document and has no views to
    /// redact.
    static let mask = "••••"
}

extension View {
    /// Marks a value that private mode blanks. On its own it does nothing —
    /// `privacyRedacted()` higher up the tree is what blanks it.
    func sensitiveValue() -> some View {
        privacySensitive()
    }

    /// Once per window, at the root. The `.privacy` reason redacts only the
    /// subviews marked `sensitiveValue()`, so the labels, dates and
    /// descriptions around them stay readable.
    func privacyRedacted() -> some View {
        modifier(PrivacyRedaction())
    }
}

private struct PrivacyRedaction: ViewModifier {
    @AppStorage(PrivacyMode.storageKey) private var hidesSensitiveValues = false

    func body(content: Content) -> some View {
        content.redacted(reason: hidesSensitiveValues ? .privacy : [])
    }
}
