import Foundation

/// Slovenian VAT rates. `exempt` covers a small business that is not VAT
/// registered — the invoice must then carry the exemption clause instead of
/// a VAT amount.
nonisolated enum VatRate: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard      // 22 %
    case reduced       // 9,5 %
    case superReduced  // 5 %
    case zero          // 0 %
    case exempt        // no VAT charged

    var id: String { rawValue }

    var percentage: Decimal {
        switch self {
        case .standard: 22
        case .reduced: 9.5
        case .superReduced: 5
        case .zero, .exempt: 0
        }
    }

    var label: String {
        switch self {
        case .standard: String(localized: "22 % (standard)")
        case .reduced: String(localized: "9.5 % (reduced)")
        case .superReduced: String(localized: "5 % (special reduced)")
        case .zero: String(localized: "0 %")
        case .exempt: String(localized: "Exempt / not VAT registered")
        }
    }

    /// For a narrow column, where the long label would not fit.
    var shortLabel: String {
        switch self {
        case .standard: "22 %"
        case .reduced: String(localized: "9.5 %")
        case .superReduced: "5 %"
        case .zero: "0 %"
        case .exempt: String(localized: "Exempt")
        }
    }

    /// Text that must appear on the invoice when no VAT is charged. It is
    /// part of the printed document, so it is Slovenian in every UI language.
    var exemptionClause: String? {
        switch self {
        case .exempt:
            DocumentText.string("VAT not charged under Article 94(1) of the VAT Act (ZDDV-1).")
        case .zero:
            DocumentText.string("Reverse charge / exempt under the VAT Act (ZDDV-1).")
        default:
            nil
        }
    }
}
