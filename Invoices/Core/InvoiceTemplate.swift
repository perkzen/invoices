import Foundation

/// Text templates on the printed invoice. The profile stores sentences with
/// `{placeholder}` tokens; this resolves them against one invoice's facts.
///
/// Everything here is a pure string operation over a `Context`, so the
/// wording can be tested without a `ModelContainer`. `PrintedInvoice` is
/// what builds the context from the models.
nonisolated enum InvoiceTemplate {
    static let defaultIntro = "Zaračunavam vam storitev za mesec {MESEC} {leto}:"
    static let defaultPaymentNote = "Pri plačilu na TRR: {trr} navedite sklic: {sklic}."
    static let defaultClosingNote = "Prosim, da račun poravnate do valute plačila!"

    /// Every token a template may use. The editor lists these and the
    /// resolver fills exactly these — one list, so the two cannot drift and
    /// advertise a token that would print literally on a legal document.
    enum Placeholder: String, CaseIterable, Sendable {
        case month = "{mesec}"
        case monthUppercased = "{MESEC}"
        case year = "{leto}"
        case client = "{stranka}"
        case number = "{stevilka}"
        case iban = "{trr}"
        case reference = "{sklic}"
        case dueDate = "{valuta}"

        var token: String { rawValue }

        /// The text shown next to the token in the editor.
        var meaning: String {
            switch self {
            case .month: String(localized: "month of service, in Slovenian (avgust)")
            case .monthUppercased: String(localized: "month of service, in Slovenian (AVGUST)")
            case .year: String(localized: "year of service")
            case .client: String(localized: "client name")
            case .number: String(localized: "invoice number")
            case .iban: String(localized: "your IBAN")
            case .reference: String(localized: "payment reference")
            case .dueDate: String(localized: "due date")
            }
        }
    }

    /// The facts one invoice contributes to its sentences.
    struct Context: Hashable, Sendable {
        /// The day the service ended — a period "1.8.–31.8." is August even
        /// when the invoice goes out in September.
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
        for (token, value) in values {
            result = result.replacingOccurrences(of: token, with: value)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func monthName(of date: Date) -> String {
        let month = Formatting.calendar.component(.month, from: date)
        return Formatting.calendar.standaloneMonthSymbols[month - 1]
    }

    /// `{MESEC}` in Slovenian. `uppercased()` alone would turn "avgust" into
    /// "AVGUST" correctly, but the locale keeps č/š/ž right on every system.
    static func upperMonthName(of date: Date) -> String {
        monthName(of: date).uppercased(with: Formatting.locale)
    }
}
