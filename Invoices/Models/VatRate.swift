import Foundation

/// Slovenian VAT rates. `exempt` covers a small business that is not a DDV
/// zavezanec — the invoice must then carry the exemption clause instead of
/// a VAT amount.
nonisolated enum VatRate: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard      // 22 %
    case reduced       // 9,5 %
    case superReduced  // 5 %
    case zero          // 0 %
    case exempt        // ni obračunan DDV

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

    /// Text that must appear on the invoice when no VAT is charged.
    var exemptionClause: String? {
        switch self {
        case .exempt:
            "DDV ni obračunan na podlagi 1. odstavka 94. člena ZDDV-1."
        case .zero:
            "Obrnjena davčna obveznost / oproščeno po ZDDV-1."
        default:
            nil
        }
    }
}
