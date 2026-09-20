import Foundation
import Testing
@testable import Invoices

@Suite("Predloga računa")
struct InvoiceTemplateTests {
    @Test func `placeholders are replaced and the rest is left alone`() {
        let text = InvoiceTemplate.resolve(
            "Zaračunavam za {MESEC} {leto}, {stranka}!",
            with: ["{MESEC}": "AVGUST", "{leto}": "2026", "{stranka}": "Parakeet"]
        )
        #expect(text == "Zaračunavam za AVGUST 2026, Parakeet!")
    }

    @Test func `an unknown token stays visible rather than vanishing`() {
        #expect(InvoiceTemplate.resolve("x {neznano} y", with: [:]) == "x {neznano} y")
    }

    @Test func `month names come out in Slovenian`() {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 31
        let date = Calendar(identifier: .gregorian).date(from: components)!
        #expect(InvoiceTemplate.monthName(of: date) == "avgust")
        #expect(InvoiceTemplate.upperMonthName(of: date) == "AVGUST")
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
        #expect(InvoiceTemplate.resolve(InvoiceTemplate.defaultIntro, in: context)
                == "Zaračunavam vam storitev za mesec AVGUST 2026:")
        #expect(InvoiceTemplate.resolve(InvoiceTemplate.defaultPaymentNote, in: context)
                == "Pri plačilu na TRR: SI56 1910 0000 1234 567 navedite sklic: SI00 2026-001.")
        #expect(InvoiceTemplate.resolve("{stranka} do {valuta}", in: context) == "Parakeet do 9. 9. 2026")
    }

    /// The editor lists `Placeholder.allCases`; the resolver must fill every
    /// one of them, or a token would print literally on a legal document.
    @Test func `every placeholder the editor lists is filled by the resolver`() {
        let filled = Set(InvoiceTemplate.values(for: context).keys)
        #expect(filled == Set(InvoiceTemplate.Placeholder.allCases))
        #expect(InvoiceTemplate.Placeholder.allCases.allSatisfy { !$0.meaning.isEmpty })
    }
}
