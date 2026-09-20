import Foundation

/// The app formats money and dates the Slovenian way regardless of the
/// system locale, because that is what ends up on a printed invoice.
nonisolated enum Formatting {
    static let locale = Locale(identifier: "sl_SI")

    /// Every date calculation in the app runs on this calendar — the year an
    /// invoice is numbered in, a due date, the month a sentence names — so a
    /// Mac set to a non-Gregorian calendar cannot move an invoice into another
    /// year.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar
    }()

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

    /// Slovenian counts in four forms — one, two, few and other — and the
    /// dual is not optional in writing. English has two. Both sets live in
    /// the catalog under each language's plural rules, which for `sl` are
    /// exactly the old hand-written `% 100` switch.
    static func invoiceCount(_ count: Int) -> String {
        String(localized: "\(count) invoices")
    }

    static func date(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(locale))
    }

    /// "1. 8. 2026 – 31. 8. 2026", or just the one date when the service did
    /// not span a period.
    static func period(_ start: Date, to end: Date?) -> String {
        guard let end else { return date(start) }
        return "\(date(start)) – \(date(end))"
    }
}
