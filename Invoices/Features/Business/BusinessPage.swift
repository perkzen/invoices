import Foundation

/// The three pages of My business, picked over the form: what the business
/// is, how its invoice is printed, and how the invoice is sent. Each page
/// changes one thing the column beside it shows — the sample invoice for the
/// first two, the sample email for the third — so the switch is over the
/// form, not the preview.
enum BusinessPage: String, CaseIterable, Identifiable, Hashable {
    case details
    case invoice
    case email

    var id: String { rawValue }

    var title: String {
        switch self {
        case .details: String(localized: "Details")
        case .invoice: String(localized: "Invoice")
        case .email: String(localized: "Email")
        }
    }
}
