import Foundation

/// The app formats money and dates the Slovenian way regardless of the
/// system locale, because that is what ends up on a printed račun.
nonisolated enum Formatting {
    static let locale = Locale(identifier: "sl_SI")

    static func money(_ amount: Decimal, currencyCode: String = "EUR") -> String {
        amount.formatted(.currency(code: currencyCode).locale(locale))
    }

    static func number(_ value: Decimal, fractionDigits: Int = 2) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0...fractionDigits))
                .locale(locale)
        )
    }

    /// Always two decimals — an invoice column shows 12,00, never 12.
    static func amount(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }

    static func percent(_ value: Decimal) -> String {
        number(value, fractionDigits: 1) + " %"
    }

    /// Slovenian counts in four forms — 1 račun, 2 računa, 3 računi,
    /// 5 računov — and the dual is not optional in writing. English has two.
    /// Both sets live in the catalog under each language's plural rules,
    /// which for `sl` are exactly the old hand-written `% 100` switch.
    static func invoiceCount(_ count: Int) -> String {
        String(localized: "\(count) invoices")
    }

    static func date(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(locale))
    }
}
