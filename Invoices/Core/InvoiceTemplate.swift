import Foundation

/// Text templates on the printed invoice. The profile stores sentences with
/// `{placeholder}` tokens; this resolves them against one invoice.
///
/// Resolution is a pure string operation so it can be tested without a
/// `ModelContainer`; `values(for:profile:)` is the only part that reads models.
nonisolated enum InvoiceTemplate {
    static let defaultIntro = "Zaračunavam vam storitev za mesec {MESEC} {leto}:"
    static let defaultPaymentNote = "Pri plačilu na TRR: {trr} navedite sklic: {sklic}."
    static let defaultClosingNote = "Prosim, da račun poravnate do valute plačila!"

    /// Every token a template may use, with the text shown in the editor.
    static var placeholders: [(token: String, meaning: String)] {
        [
            ("{mesec}", String(localized: "month of service, in Slovenian (avgust)")),
            ("{MESEC}", String(localized: "month of service, in Slovenian (AVGUST)")),
            ("{leto}", String(localized: "year of service")),
            ("{stranka}", String(localized: "client name")),
            ("{stevilka}", String(localized: "invoice number")),
            ("{trr}", String(localized: "your IBAN")),
            ("{sklic}", String(localized: "payment reference")),
            ("{valuta}", String(localized: "due date")),
        ]
    }

    static func resolve(_ template: String, with values: [String: String]) -> String {
        var result = template
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

    /// `{MESEC}` in Slovenian. `uppercased()` alone would turn "avgust" into
    /// "AVGUST" correctly, but the locale keeps č/š/ž right on every system.
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
            "{mesec}": monthName(of: serviceDate),
            "{MESEC}": upperMonthName(of: serviceDate),
            "{leto}": String(calendar.component(.year, from: serviceDate)),
            "{stranka}": invoice.client?.displayName ?? "",
            "{stevilka}": invoice.number,
            "{trr}": profile.iban,
            "{sklic}": invoice.paymentReference.isEmpty ? defaultReference(for: invoice) : invoice.paymentReference,
            "{valuta}": Formatting.date(invoice.dueDate),
        ]
    }

    /// The SI00 model over the invoice number — what `issue()` fills in when
    /// nothing was typed, and what a draft shows in its place.
    @MainActor
    static func defaultReference(for invoice: Invoice) -> String {
        invoice.number.isEmpty ? "SI00 (št. računa)" : "SI00 \(invoice.number)"
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
