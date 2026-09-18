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
}
