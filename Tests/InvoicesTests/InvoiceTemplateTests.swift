import Foundation
import Testing
@testable import Invoices

@Suite("Invoice template")
struct InvoiceTemplateTests {
    @Test func `placeholders are replaced and the rest is left alone`() {
        let text = InvoiceTemplate.resolve(
            "Invoicing you for {MONTH} {year}, {client}!",
            with: ["{MONTH}": "AUGUST", "{year}": "2026", "{client}": "Parakeet"]
        )
        #expect(text == "Invoicing you for AUGUST 2026, Parakeet!")
    }

    @Test func `an unknown token stays visible rather than vanishing`() {
        #expect(InvoiceTemplate.resolve("x {unknown} y", with: [:]) == "x {unknown} y")
    }

    /// Profiles saved before the placeholders were renamed still hold the
    /// old spellings, and every such template has to keep printing correctly.
    @Test func `the tokens templates were saved with before the rename still resolve`() {
        let values = Dictionary(uniqueKeysWithValues: InvoiceTemplate.placeholders.map { ($0.token, "<\($0.token)>") })
        for (legacy, token) in InvoiceTemplate.legacyTokens {
            #expect(InvoiceTemplate.resolve("a \(legacy) b", with: values) == "a <\(token)> b")
        }
        #expect(InvoiceTemplate.legacyTokens.count == InvoiceTemplate.placeholders.count)
    }

    @Test func `the default sentences use the current placeholders`() {
        let tokens = Set(InvoiceTemplate.placeholders.map(\.token))
        for sentence in [InvoiceTemplate.defaultIntro, InvoiceTemplate.defaultPaymentNote] {
            let used = sentence.matches(of: /\{[^}]+\}/).map { String($0.output) }
            #expect(!used.isEmpty)
            #expect(used.allSatisfy(tokens.contains), "\(sentence) uses a token the editor does not offer")
        }
    }

    @Test func `month names come out in Slovenian`() {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 31
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let slovene = Calendar(identifier: .gregorian)
        var calendar = slovene
        calendar.locale = Locale(identifier: "sl_SI")
        #expect(InvoiceTemplate.monthName(of: date) == calendar.standaloneMonthSymbols[7])
        #expect(InvoiceTemplate.upperMonthName(of: date) == calendar.standaloneMonthSymbols[7].uppercased())
        #expect(InvoiceTemplate.monthName(of: date) != "August")
    }

    private var context: InvoiceTemplate.Context {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 31
        let serviceEnd = Formatting.calendar.date(from: components)!
        components.month = 9; components.day = 9
        return InvoiceTemplate.Context(
            serviceDate: serviceEnd,
            clientName: "Parakeet",
            number: "2026-001",
            iban: "SI56 1910 0000 1234 567",
            reference: "SI00 2026-001",
            dueDate: Formatting.calendar.date(from: components)!
        )
    }

    @Test func `a template resolves against the invoice's facts`() {
        let month = InvoiceTemplate.upperMonthName(of: context.serviceDate)
        let intro = InvoiceTemplate.resolve(InvoiceTemplate.defaultIntro, in: context)
        #expect(intro.contains("\(month) 2026"))
        #expect(!intro.contains("{"))
        let payment = InvoiceTemplate.resolve(InvoiceTemplate.defaultPaymentNote, in: context)
        #expect(payment.contains("SI56 1910 0000 1234 567"))
        #expect(payment.contains("SI00 2026-001"))
        #expect(InvoiceTemplate.resolve("{client} until {due}", in: context) == "Parakeet until 9. 9. 2026")
        // A sentence saved before the rename resolves the same way.
        #expect(InvoiceTemplate.resolve("{stranka} until {valuta}", in: context) == "Parakeet until 9. 9. 2026")
    }

    /// The editor lists `Placeholder.allCases`; the resolver must fill every
    /// one of them, or a token would print literally on a legal document.
    @Test func `every placeholder the editor lists is filled by the resolver`() {
        let filled = Set(InvoiceTemplate.values(for: context).keys)
        #expect(filled == Set(InvoiceTemplate.Placeholder.allCases))
        #expect(InvoiceTemplate.Placeholder.allCases.allSatisfy { !$0.meaning.isEmpty })
    }
}
