import Foundation

/// Text templates on the printed invoice. The profile stores sentences with
/// `{placeholder}` tokens; this resolves them against one invoice.
///
/// Resolution is a pure string operation so it can be tested without a
/// `ModelContainer`; `values(for:profile:)` is the only part that reads models.
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

    /// Every token a template may use, with the text shown in the editor.
    static var placeholders: [(token: String, meaning: String)] {
        [
            ("{month}", String(localized: "month of service (august)")),
            ("{MONTH}", String(localized: "month of service, in capitals (AUGUST)")),
            ("{year}", String(localized: "year of service")),
            ("{client}", String(localized: "client name")),
            ("{number}", String(localized: "invoice number")),
            ("{iban}", String(localized: "your IBAN")),
            ("{reference}", String(localized: "payment reference")),
            ("{due}", String(localized: "due date")),
        ]
    }

    /// The tokens as they were spelled before the placeholders were renamed.
    /// They sit inside sentences already saved in users' profiles and
    /// invoices, so a template written with them has to keep resolving.
    static let legacyTokens: [String: String] = [
        "{mesec}": "{month}",
        "{MESEC}": "{MONTH}",
        "{leto}": "{year}",
        "{stranka}": "{client}",
        "{stevilka}": "{number}",
        "{trr}": "{iban}",
        "{sklic}": "{reference}",
        "{valuta}": "{due}",
    ]

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
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Formatting.locale
        let month = calendar.component(.month, from: date)
        return calendar.standaloneMonthSymbols[month - 1]
    }

    /// `{MONTH}`. A plain `uppercased()` would usually be right, but the
    /// locale keeps the Slovenian letters with diacritics right on every system.
    static func upperMonthName(of date: Date) -> String {
        monthName(of: date).uppercased(with: Formatting.locale)
    }
}

extension InvoiceTemplate {
    @MainActor
    static func values(for invoice: Invoice, profile: BusinessProfile) -> [String: String] {
        // The month is the one the service ends in — a period "1.8.–31.8."
        // is August even when the invoice goes out in September.
        let serviceDate = invoice.serviceDateEnd ?? invoice.serviceDate
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Formatting.locale
        return [
            "{month}": monthName(of: serviceDate),
            "{MONTH}": upperMonthName(of: serviceDate),
            "{year}": String(calendar.component(.year, from: serviceDate)),
            "{client}": invoice.client?.displayName ?? "",
            "{number}": invoice.number,
            "{iban}": profile.iban,
            "{reference}": invoice.paymentReference.isEmpty ? defaultReference(for: invoice) : invoice.paymentReference,
            "{due}": Formatting.date(invoice.dueDate),
        ]
    }

    /// The SI00 model over the invoice number — what `issue()` fills in when
    /// nothing was typed, and what a draft shows in its place.
    @MainActor
    static func defaultReference(for invoice: Invoice) -> String {
        invoice.number.isEmpty ? DocumentText.string("SI00 (invoice number)") : "SI00 \(invoice.number)"
    }

    @MainActor
    static func intro(for invoice: Invoice, profile: BusinessProfile) -> String {
        let template = invoice.introOverride.isEmpty ? profile.introTemplate : invoice.introOverride
        return resolve(template, with: values(for: invoice, profile: profile))
    }

    @MainActor
    static func paymentNote(for invoice: Invoice, profile: BusinessProfile) -> String {
        guard !profile.iban.isEmpty else { return "" }
        return resolve(profile.paymentNoteTemplate, with: values(for: invoice, profile: profile))
    }

    /// "1. 8. 2026 – 31. 8. 2026", or just the one date.
    @MainActor
    static func servicePeriod(for invoice: Invoice) -> String {
        guard let end = invoice.serviceDateEnd else { return Formatting.date(invoice.serviceDate) }
        return "\(Formatting.date(invoice.serviceDate)) – \(Formatting.date(end))"
    }
}
