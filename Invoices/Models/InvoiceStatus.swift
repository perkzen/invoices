import Foundation

/// Once an invoice is issued its content is fixed — a mistake is corrected
/// with a cancellation or a credit note, never by editing the original.
nonisolated enum InvoiceStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case draft
    case issued
    case paid
    case cancelled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draft: String(localized: "Draft")
        case .issued: String(localized: "Issued")
        // Slovenian declines this differently from the year overview's
        // "paid total", which is also "Paid" in English — hence the key.
        case .paid: String(localized: "invoiceStatus.paid", defaultValue: "Paid")
        case .cancelled: String(localized: "Cancelled")
        }
    }

    var isEditable: Bool { self == .draft }

    var symbol: String {
        switch self {
        case .draft: "pencil.circle"
        case .issued: "paperplane.circle"
        case .paid: "checkmark.circle"
        case .cancelled: "xmark.circle"
        }
    }
}
