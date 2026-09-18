import Foundation
import SwiftData
import Testing
@testable import Invoices

@MainActor
@Suite("Izvoz PDF")
struct InvoicePDFTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Invoice.self, InvoiceLine.self, Client.self, BusinessProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @discardableResult
    private func makeInvoice(
        in context: ModelContext,
        lineCount: Int = 1,
        status: InvoiceStatus = .draft
    ) -> (Invoice, BusinessProfile) {
        let profile = BusinessProfile.current(in: context)
        profile.name = "Domen Perko s.p."
        profile.street = "Trg svobode 4"
        profile.postalCode = "1000"
        profile.city = "Ljubljana"
        profile.taxNumber = "12345678"
        profile.iban = "SI56 1910 0000 1234 567"
        profile.bankName = "Deželna banka"

        let client = Client(name: "Čevljarstvo Žnidaršič d.o.o.")
        client.street = "Šmartinska cesta 152"
        client.postalCode = "1000"
        client.city = "Ljubljana"
        client.taxNumber = "87654321"
        context.insert(client)

        let invoice = Invoice(issueDate: .now, serviceDate: .now, dueDate: .now)
        invoice.client = client
        invoice.placeOfIssue = "Ljubljana"
        invoice.status = status
        if status != .draft {
            invoice.number = "2026-001"
            invoice.year = 2026
            invoice.sequence = 1
        }
        context.insert(invoice)

        for index in 0..<lineCount {
            let line = InvoiceLine(
                itemDescription: "Razvoj programske opreme – šifra \(index + 1)",
                quantity: 40, unit: "ura", unitPrice: 55, vatRate: .exempt, sortIndex: index
            )
            line.invoice = invoice
            context.insert(line)
        }
        return (invoice, profile)
    }

    @Test func `renders a valid single page PDF`() throws {
        let context = try makeContext()
        let (invoice, profile) = makeInvoice(in: context)
        let data = try #require(InvoicePDF.render(invoice: invoice, profile: profile))

        #expect(data.starts(with: Array("%PDF".utf8)))
        #expect(data.count > 1000)
    }

    @Test func `an issued invoice renders too`() throws {
        let context = try makeContext()
        let (invoice, profile) = makeInvoice(in: context, lineCount: 3, status: .issued)
        let data = try #require(InvoicePDF.render(invoice: invoice, profile: profile))
    }

    @Test func `a long invoice spills onto more pages`() throws {
        let context = try makeContext()
        let (invoice, profile) = makeInvoice(in: context, lineCount: 30, status: .issued)
        #expect(InvoicePDF.paginate(invoice.sortedLines).count > 1)
        let data = try #require(InvoicePDF.render(invoice: invoice, profile: profile))
        #expect(data.starts(with: Array("%PDF".utf8)))
    }

    @Test(arguments: [1, 12, 13, 30, 97])
    func `pagination keeps every line exactly once and in order`(count: Int) throws {
        let context = try makeContext()
        let (invoice, _) = makeInvoice(in: context, lineCount: count)
        let lines = invoice.sortedLines
        let paginated = InvoicePDF.paginate(lines).flatMap(\.self)
        #expect(paginated.map(\.sortIndex) == lines.map(\.sortIndex))
    }

    @Test func `a page never exceeds its own budget`() throws {
        let context = try makeContext()
        let (invoice, _) = makeInvoice(in: context, lineCount: 60)
        let pages = InvoicePDF.paginate(invoice.sortedLines)
        // 76 is the most generous capacity any page is granted.
        for page in pages {
            #expect(page.reduce(0) { $0 + InvoicePDF.cost(of: $1) } <= 76)
        }
    }

    @Test func `pagination always yields at least one page`() {
        #expect(InvoicePDF.paginate([]).count == 1)
    }

    @Test func `filename follows the invoice number`() throws {
        let context = try makeContext()
        let (invoice, _) = makeInvoice(in: context, status: .issued)
        #expect(InvoicePDF.suggestedFilename(for: invoice) == "Racun-2026-001")
    }
}
