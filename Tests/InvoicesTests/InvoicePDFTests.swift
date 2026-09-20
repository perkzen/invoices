import Foundation
import Testing
@testable import Invoices

@MainActor
@Suite("Izvoz PDF")
struct InvoicePDFTests {
    /// A printed invoice with `lineCount` rows — no store, no models.
    private func printed(lineCount: Int = 1, isDraft: Bool = true) -> PrintedInvoice {
        PrintedInvoice(
            number: isDraft ? "" : "2026-001",
            isDraft: isDraft,
            issueDate: .now,
            serviceDate: .now,
            dueDate: .now,
            placeOfIssue: "Ljubljana",
            issuer: .init(
                name: "Domen Perko s.p.",
                addressLines: ["Trg svobode 4", "1000 Ljubljana"],
                taxNumber: "12345678",
                iban: "SI56 1910 0000 1234 567",
                bankName: "Deželna banka"
            ),
            customer: .init(
                name: "Čevljarstvo Žnidaršič d.o.o.",
                addressLines: ["Šmartinska cesta 152", "1000 Ljubljana"],
                taxNumber: "87654321"
            ),
            lines: (0..<lineCount).map { index in
                PrintedInvoice.Line(
                    index: index + 1,
                    description: "Razvoj programske opreme – šifra \(index + 1)",
                    quantity: 40, unit: "ura", unitPrice: 55, vatRate: .exempt
                )
            },
            intro: "Zaračunavam vam storitev za mesec AVGUST 2026:",
            paymentNote: "Pri plačilu na TRR: SI56 1910 0000 1234 567 navedite sklic: SI00 2026-001."
        )
    }

    @Test func `renders a valid single page PDF`() throws {
        let data = try #require(InvoicePDF.render(printed()))
        #expect(data.starts(with: Array("%PDF".utf8)))
        #expect(data.count > 1000)
    }

    @Test func `an issued invoice renders too`() throws {
        _ = try #require(InvoicePDF.render(printed(lineCount: 3, isDraft: false)))
    }

    @Test func `a long invoice spills onto more pages`() throws {
        let long = printed(lineCount: 30, isDraft: false)
        #expect(InvoicePDF.pages(of: long).count > 1)
        let data = try #require(InvoicePDF.render(long))
        #expect(data.starts(with: Array("%PDF".utf8)))
    }

    @Test(arguments: [1, 12, 13, 30, 97])
    func `pagination keeps every line exactly once and in order`(count: Int) {
        let lines = printed(lineCount: count).lines
        let paginated = InvoicePDF.paginate(lines).flatMap(\.self)
        #expect(paginated.map(\.index) == Array(1...count))
    }

    /// Row numbers carry on across pages: page 2 does not restart at 1.
    @Test func `row numbering continues onto the next page`() {
        let pages = InvoicePDF.paginate(printed(lineCount: 30).lines)
        #expect(pages.count > 1)
        #expect(pages[1].first?.index == pages[0].count + 1)
    }

    @Test func `a page never exceeds its own budget`() {
        let pages = InvoicePDF.paginate(printed(lineCount: 60).lines)
        // 76 is the most generous capacity any page is granted.
        for page in pages {
            #expect(page.reduce(0) { $0 + InvoicePDF.cost(of: $1) } <= 76)
        }
    }

    @Test func `notes and a footer cost the last page rows`() {
        var withNotes = printed(lineCount: 6)
        withNotes.notes = "Opomba"
        withNotes.issuer.footer = "AJPES"
        #expect(InvoicePDF.pages(of: withNotes).count >= InvoicePDF.pages(of: printed(lineCount: 6)).count)
        #expect(InvoicePDF.summaryExtra(notes: "Opomba", footer: "AJPES") == 3)
    }

    @Test func `pagination always yields at least one page`() {
        #expect(InvoicePDF.paginate([]).count == 1)
    }
}
