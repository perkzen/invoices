import Foundation
import SwiftData
import Testing
@testable import Invoices

@Suite("Printed invoice")
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
            issuer: .init(name: "Domen Perko", taxNumber: "12345678", vatID: "SI12345678"),
            lines: lines
        )
    }

    private func line(_ index: Int, price: Decimal = 100, unit: String = "", discount: Decimal = 0, rate: VatRate = .exempt) -> PrintedInvoice.Line {
        PrintedInvoice.Line(index: index, description: "Work", quantity: 1, unit: unit, unitPrice: price, discountPercent: discount, vatRate: rate)
    }

    @Test func `totals add up the lines`() {
        let printed = printed(chargesVat: true, lines: [line(1, rate: .standard), line(2, price: 50, rate: .reduced)])
        #expect(printed.totals.net == 150)
        #expect(printed.totals.vat == Decimal(string: "26.75"))
        #expect(printed.vatBreakdown.map(\.rate) == [.standard, .reduced])
    }

    @Test func `the VAT ID is printed only for a VAT registered business`() {
        #expect(printed(chargesVat: false, lines: [line(1)]).issuerVatID == nil)
        #expect(printed(chargesVat: true, lines: [line(1)]).issuerVatID == "SI12345678")
    }

    @Test func `exemption clauses print only when no VAT is charged`() {
        let exempt = printed(chargesVat: false, lines: [line(1), line(2)])
        #expect(exempt.exemptionClauses == [VatRate.exempt.exemptionClause!])
        #expect(printed(chargesVat: true, lines: [line(1, rate: .standard)]).exemptionClauses.isEmpty)
    }

    @Test func `the amount column is net with VAT and gross without`() {
        let item = line(1, rate: .standard)
        #expect(printed(chargesVat: true, lines: [item]).columnAmount(of: item) == 100)
        #expect(printed(chargesVat: false, lines: [item]).columnAmount(of: item) == 122)
    }

    @Test func `optional columns follow the lines`() {
        #expect(!printed(lines: [line(1)]).showsUnit)
        #expect(printed(lines: [line(1), line(2, unit: "ura")]).showsUnit)
        #expect(printed(lines: [line(1, discount: 10)]).showsDiscount)
    }

    @Test func `the service period follows the value`() {
        var printed = printed(lines: [line(1)])
        #expect(printed.servicePeriod.contains("–"))
        printed.serviceDateEnd = nil
        #expect(!printed.servicePeriod.contains("–"))
    }

    @Test func `the signer falls back to the business name`() {
        var printed = printed(lines: [])
        #expect(printed.signerName == "Domen Perko")
        printed.issuer.signerName = "D. Perko"
        #expect(printed.signerName == "D. Perko")
    }
}

@MainActor
@Suite("Printed invoice from the store")
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
        profile.name = "Domen Perko"
        profile.iban = "SI56 1910 0000 1234 567"
        profile.vatID = "SI12345678"

        let client = Client(name: "PARAKEET AI Ltd.")
        client.street = "Slovenska cesta 1"
        client.postalCode = "1000"
        client.city = "Ljubljana"
        ledger.context.insert(client)

        let invoice = ledger.newDraft()
        invoice.client = client
        invoice.serviceDate = date(2026, 8, 1)
        invoice.serviceDateEnd = date(2026, 8, 31)
        invoice.issueDate = date(2026, 9, 1)
        invoice.sortedLines[0].itemDescription = "First"
        let second = try #require(ledger.addLine(to: invoice))
        second.itemDescription = "Second"

        let printed = PrintedInvoice.make(invoice: invoice, profile: profile)
        #expect(printed.isDraft)
        #expect(printed.number.isEmpty)
        #expect(printed.customer?.name == "PARAKEET AI Ltd.")
        #expect(printed.customer?.addressLines == ["Slovenska cesta 1", "1000 Ljubljana"])
        #expect(printed.lines.map(\.index) == [1, 2])
        #expect(printed.lines.map(\.description) == ["First", "Second"])
        // The month is the one the service ended in, from the default template.
        let expectedIntro = InvoiceTemplate.defaultIntro
            .replacingOccurrences(of: "{MONTH}", with: InvoiceTemplate.upperMonthName(of: date(2026, 8, 31)))
            .replacingOccurrences(of: "{year}", with: "2026")
        #expect(printed.intro == expectedIntro)
        #expect(printed.intro.contains("2026"))
        // A draft has no number yet, so the reference says what will be filled in.
        #expect(printed.paymentNote.contains(DocumentText.string("SI00 (invoice number)")))
        #expect(printed.issuerVatID == nil)
    }

    @Test func `an invoice's own intro overrides the template`() throws {
        let ledger = try makeLedger()
        let invoice = ledger.newDraft()
        invoice.introOverride = "For {client}:"
        invoice.client = Client(name: "Client Ltd.")
        ledger.context.insert(invoice.client!)

        #expect(PrintedInvoice.make(invoice: invoice, profile: ledger.profile).intro == "For Client Ltd.:")
    }

    @Test func `an issued invoice prints its number and reference`() throws {
        let ledger = try makeLedger()
        let client = Client(name: "Client Ltd.")
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
        profile.introTemplate = "For {client}, {MONTH}:"
        profile.isVatRegistered = true

        let sample = PrintedInvoice.sample(matching: profile)
        #expect(!sample.isDraft)
        #expect(sample.lines.count == 2)
        #expect(sample.intro.hasPrefix("For \(DocumentText.string("Sample Company Ltd.")), "))
        #expect(sample.chargesVat)
        #expect(sample.lines.allSatisfy { $0.vatRate == .standard })
    }
}
