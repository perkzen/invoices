import Foundation

/// Text templates on the printed invoice. The profile stores sentences with
/// `{placeholder}` tokens; this resolves them against one invoice's facts.
///
/// Everything here is a pure string operation over a `Context`, so the
/// wording can be tested without a `ModelContainer`. `PrintedInvoice` is
/// what builds the context from the models.
nonisolated enum InvoiceTemplate {
    /// The sentences a fresh profile starts with. They are printed on the
    /// invoice, so they come from `DocumentText` like every other label on it.
    static var defaultIntro: String {
        DocumentText.string("I am invoicing you for services in the month of {MONTH} {year}:")
    }
    static var defaultPaymentNote: String {
        DocumentText.string("When paying to bank account {iban}, quote the reference {reference}.")
    }
    static var defaultClosingNote: String {
        DocumentText.string("Please settle the invoice by the due date.")
    }

    /// Every token a template may use. The editor lists these and the
    /// resolver fills exactly these — one list, so the two cannot drift and
    /// advertise a token that would print literally on a legal document.
    enum Placeholder: String, CaseIterable, Sendable {
        case month = "{month}"
        case monthUppercased = "{MONTH}"
        case year = "{year}"
        case client = "{client}"
        case number = "{number}"
        case iban = "{iban}"
        case reference = "{reference}"
        case dueDate = "{due}"

        var token: String { rawValue }

        /// The text shown next to the token in the editor.
        var meaning: String {
            switch self {
            case .month: String(localized: "month of service (august)")
            case .monthUppercased: String(localized: "month of service, in capitals (AUGUST)")
            case .year: String(localized: "year of service")
            case .client: String(localized: "client name")
            case .number: String(localized: "invoice number")
            case .iban: String(localized: "your IBAN")
            case .reference: String(localized: "payment reference")
            case .dueDate: String(localized: "due date")
            }
        }
    }

    /// The tokens with the text shown in the editor, in the order it lists them.
    static var placeholders: [(token: String, meaning: String)] {
        Placeholder.allCases.map { ($0.token, $0.meaning) }
    }

    /// The tokens as they were spelled before the placeholders were renamed.
    /// They sit inside sentences already saved in users' profiles and
    /// invoices, so a template written with them has to keep resolving.
    static let legacyTokens: [String: String] = [
        "{mesec}": Placeholder.month.token,
        "{MESEC}": Placeholder.monthUppercased.token,
        "{leto}": Placeholder.year.token,
        "{stranka}": Placeholder.client.token,
        "{stevilka}": Placeholder.number.token,
        "{trr}": Placeholder.iban.token,
        "{sklic}": Placeholder.reference.token,
        "{valuta}": Placeholder.dueDate.token,
    ]

    /// The facts one invoice contributes to its sentences.
    struct Context: Hashable, Sendable {
        /// The day the service ended — a period spanning one month is that
        /// month even when the invoice goes out in the next.
        var serviceDate: Date
        var clientName: String
        var number: String
        var iban: String
        var reference: String
        var dueDate: Date
    }

    static func values(for context: Context) -> [Placeholder: String] {
        [
            .month: monthName(of: context.serviceDate),
            .monthUppercased: upperMonthName(of: context.serviceDate),
            .year: String(Formatting.calendar.component(.year, from: context.serviceDate)),
            .client: context.clientName,
            .number: context.number,
            .iban: context.iban,
            .reference: context.reference,
            .dueDate: Formatting.date(context.dueDate),
        ]
    }

    static func resolve(_ template: String, in context: Context) -> String {
        let values = values(for: context).map { ($0.key.token, $0.value) }
        return resolve(template, with: Dictionary(uniqueKeysWithValues: values))
    }

    static func resolve(_ template: String, with values: [String: String]) -> String {
        var result = template
        for (legacy, token) in legacyTokens {
            result = result.replacingOccurrences(of: legacy, with: token)
        }
        for (token, value) in values {
            result = result.replacingOccurrences(of: token, with: value)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func monthName(of date: Date) -> String {
        let month = Formatting.calendar.component(.month, from: date)
        return Formatting.calendar.standaloneMonthSymbols[month - 1]
    }

    /// `{MONTH}`. A plain `uppercased()` would usually be right, but the
    /// locale keeps the Slovenian letters with diacritics right on every system.
    static func upperMonthName(of date: Date) -> String {
        monthName(of: date).uppercased(with: Formatting.locale)
    }
}
