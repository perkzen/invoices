import Foundation
import SwiftData
import Testing
@testable import Invoices

@Suite("Natisnjeni račun")
struct PrintedInvoiceTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Formatting.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func printed(chargesVat: Bool = false, lines: [PrintedInvoice.Line]) -> PrintedInvoice {
        PrintedInvoice(
            number: "2026-001",
            isDraft: false,
            issueDate: date(2026, 9, 1),
            serviceDate: date(2026, 8, 1),
            serviceDateEnd: date(2026, 8, 31),
            dueDate: date(2026, 9, 9),
            chargesVat: chargesVat,
            issuer: .init(name: "Domen Perko s.p.", taxNumber: "12345678", vatID: "SI12345678"),
            lines: lines
        )
    }

    private func line(_ index: Int, price: Decimal = 100, unit: String = "", discount: Decimal = 0, rate: VatRate = .exempt) -> PrintedInvoice.Line {
        PrintedInvoice.Line(index: index, description: "Delo", quantity: 1, unit: unit, unitPrice: price, discountPercent: discount, vatRate: rate)
    }

    @Test func `totals add up the lines`() {
        let printed = printed(chargesVat: true, lines: [line(1, rate: .standard), line(2, price: 50, rate: .reduced)])
        #expect(printed.totals.net == 150)
        #expect(printed.totals.vat == Decimal(string: "26.75"))
        #expect(printed.vatBreakdown.map(\.rate) == [.standard, .reduced])
    }

    @Test func `the VAT ID is printed only for a zavezanec`() {
        #expect(printed(chargesVat: false, lines: [line(1)]).issuerVatID == nil)
        #expect(printed(chargesVat: true, lines: [line(1)]).issuerVatID == "SI12345678")
    }

    @Test func `exemption clauses print only when no VAT is charged`() {
        let exempt = printed(chargesVat: false, lines: [line(1), line(2)])
        #expect(exempt.exemptionClauses == [VatRate.exempt.exemptionClause!])
        #expect(printed(chargesVat: true, lines: [line(1, rate: .standard)]).exemptionClauses.isEmpty)
    }

    @Test func `the Vrednost column is net with VAT and gross without`() {
        let item = line(1, rate: .standard)
        #expect(printed(chargesVat: true, lines: [item]).columnAmount(of: item) == 100)
        #expect(printed(chargesVat: false, lines: [item]).columnAmount(of: item) == 122)
    }

    @Test func `optional columns follow the lines`() {
        #expect(!printed(lines: [line(1)]).showsUnit)
        #expect(printed(lines: [line(1), line(2, unit: "ura")]).showsUnit)
        #expect(printed(lines: [line(1, discount: 10)]).showsDiscount)
    }

    @Test func `the service period and filename follow the value`() {
        var printed = printed(lines: [line(1)])
        #expect(printed.servicePeriod.contains("–"))
        #expect(printed.suggestedFilename == "Racun-2026-001")
        printed.number = ""
        #expect(printed.suggestedFilename == "Osnutek-racuna")
    }

    @Test func `the signer falls back to the business name`() {
        var printed = printed(lines: [])
        #expect(printed.signerName == "Domen Perko s.p.")
        printed.issuer.signerName = "Domen Perko"
        #expect(printed.signerName == "Domen Perko")
    }
}

@MainActor
@Suite("Natisnjeni račun iz shrambe")
struct PrintedInvoiceFromModelsTests {
    private func makeLedger() throws -> Ledger {
        let container = try ModelContainer(
            for: Invoice.self, InvoiceLine.self, Client.self, BusinessProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return Ledger(ModelContext(container))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Formatting.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func `the value carries what the models say`() throws {
        let ledger = try makeLedger()
        let profile = ledger.profile
        profile.name = "Domen Perko s.p."
        profile.iban = "SI56 1910 0000 1234 567"
        profile.vatID = "SI12345678"

        let client = Client(name: "PARAKEET AI d.o.o.")
        client.street = "Slovenska cesta 1"
        client.postalCode = "1000"
        client.city = "Ljubljana"
        ledger.context.insert(client)

        let invoice = ledger.newDraft()
        invoice.client = client
        invoice.serviceDate = date(2026, 8, 1)
        invoice.serviceDateEnd = date(2026, 8, 31)
        invoice.issueDate = date(2026, 9, 1)
        invoice.sortedLines[0].itemDescription = "Prva"
        let second = try #require(ledger.addLine(to: invoice))
        second.itemDescription = "Druga"

        let printed = PrintedInvoice.make(invoice: invoice, profile: profile)
        #expect(printed.isDraft)
        #expect(printed.number.isEmpty)
        #expect(printed.customer?.name == "PARAKEET AI d.o.o.")
        #expect(printed.customer?.addressLines == ["Slovenska cesta 1", "1000 Ljubljana"])
        #expect(printed.lines.map(\.index) == [1, 2])
        #expect(printed.lines.map(\.description) == ["Prva", "Druga"])
        // The month is the one the service ended in, from the default template.
        #expect(printed.intro == "Zaračunavam vam storitev za mesec AVGUST 2026:")
        // A draft has no number yet, so the reference says what will be filled in.
        #expect(printed.paymentNote.contains("SI00 (št. računa)"))
        #expect(printed.issuerVatID == nil)
    }

    @Test func `an invoice's own intro overrides the template`() throws {
        let ledger = try makeLedger()
        let invoice = ledger.newDraft()
        invoice.introOverride = "Za {stranka}:"
        invoice.client = Client(name: "Stranka d.o.o.")
        ledger.context.insert(invoice.client!)

        #expect(PrintedInvoice.make(invoice: invoice, profile: ledger.profile).intro == "Za Stranka d.o.o.:")
    }

    @Test func `an issued invoice prints its number and reference`() throws {
        let ledger = try makeLedger()
        let client = Client(name: "Stranka d.o.o.")
        ledger.context.insert(client)
        let invoice = ledger.newDraft()
        invoice.client = client
        invoice.issueDate = date(2026, 3, 31)
        try ledger.issue(invoice)

        let printed = PrintedInvoice.make(invoice: invoice, profile: ledger.profile)
        #expect(!printed.isDraft)
        #expect(printed.number == "2026-001")
        #expect(printed.paymentReference == "SI00 2026-001")
    }

    @Test func `the settings sample prints the profile's own wording and VAT status`() throws {
        let ledger = try makeLedger()
        let profile = ledger.profile
        profile.introTemplate = "Za {stranka}, {MESEC}:"
        profile.isVatRegistered = true

        let sample = PrintedInvoice.sample(matching: profile)
        #expect(!sample.isDraft)
        #expect(sample.lines.count == 2)
        #expect(sample.intro.hasPrefix("Za Vzorčno podjetje d.o.o., "))
        #expect(sample.chargesVat)
        #expect(sample.lines.allSatisfy { $0.vatRate == .standard })
    }
}
