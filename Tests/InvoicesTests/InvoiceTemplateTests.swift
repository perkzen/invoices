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
}
