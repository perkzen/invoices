import Foundation

/// Once an invoice is issued its content is fixed — a mistake is corrected
/// with a storno or a dobropis, never by editing the original.
nonisolated enum InvoiceStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case draft
    case issued
    case paid
    case cancelled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draft: "Osnutek"
        case .issued: "Izdan"
        case .paid: "Plačan"
        case .cancelled: "Storniran"
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
