import Foundation
import PDFKit
import Testing
@testable import Invoices

@MainActor
@Suite("PDF export")
struct InvoicePDFTests {
    /// A printed invoice with `lineCount` rows — no store, no models.
    /// Diacritics on purpose: the page has to render them intact.
    private func printed(lineCount: Int = 1, isDraft: Bool = true) -> PrintedInvoice {
        PrintedInvoice(
            number: isDraft ? "" : "2026-001",
            isDraft: isDraft,
            issueDate: .now,
            serviceDate: .now,
            dueDate: .now,
            placeOfIssue: "Ljubljana",
            issuer: .init(
                name: "Domen Perko",
                addressLines: ["Rue de la Paix 4", "1000 Ljubljana"],
                taxNumber: "12345678",
                iban: "SI56 1910 0000 1234 567",
                bankName: "Banque Générale"
            ),
            customer: .init(
                name: "Müller & Søn ApS",
                addressLines: ["Ærøvej 152", "1000 Ljubljana"],
                taxNumber: "87654321"
            ),
            lines: (0..<lineCount).map { index in
                PrintedInvoice.Line(
                    index: index + 1,
                    description: "Software development – item \(index + 1)",
                    quantity: 40, unit: "h", unitPrice: 55, vatRate: .exempt
                )
            },
            intro: "Invoicing you for AUGUST 2026:",
            paymentNote: "When paying to SI56 1910 0000 1234 567, quote SI00 2026-001."
        )
    }

    /// The account, the two tax numbers, a line amount and the total, spelled
    /// the way they come back out of the page — text extraction drops the
    /// thousands separator, so an amount reads 4400,00 and not 4.400,00.
    private static let secrets = ["SI56 1910 0000 1234 567", "12345678", "87654321", "2200,00", "4400,00"]

    private func text(of data: Data?) -> String? {
        data.flatMap(PDFDocument.init(data:))?.string
    }

    @Test func `renders a valid single page PDF`() throws {
        let data = try #require(InvoicePDF.render(printed()))
        #expect(data.starts(with: Array("%PDF".utf8)))
        #expect(data.count > 1000)
    }

    /// Private mode's preview: the same page, with the account, the tax
    /// numbers and the amounts masked — including the account named inside
    /// the payment sentence.
    @Test func `a masked render prints no sensitive value`() throws {
        let invoice = printed(lineCount: 2, isDraft: false)
        let masked = try #require(text(of: InvoicePDF.render(invoice, masksSensitiveValues: true)))

        #expect(masked.contains(PrivacyMode.mask))
        for secret in Self.secrets {
            #expect(!masked.contains(secret), "\(secret) printed on a masked page")
        }
        // What the page is for survives the mask.
        #expect(masked.contains("Software development – item 2"))
        #expect(masked.contains("2026-001"))
    }

    @Test func `an export prints the real values`() throws {
        let plain = try #require(text(of: InvoicePDF.render(printed(lineCount: 2, isDraft: false))))
        for value in Self.secrets {
            #expect(plain.contains(value))
        }
        #expect(!plain.contains(PrivacyMode.mask))
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
        withNotes.notes = "A note"
        withNotes.issuer.footer = "AJPES"
        #expect(InvoicePDF.pages(of: withNotes).count >= InvoicePDF.pages(of: printed(lineCount: 6)).count)
        #expect(InvoicePDF.summaryExtra(notes: "A note", footer: "AJPES") == 3)
    }

    @Test func `pagination always yields at least one page`() {
        #expect(InvoicePDF.paginate([]).count == 1)
    }

    /// Named in the document's language, and kept to ASCII so the file
    /// travels through any mail client and file system.
    @Test func `the filename follows the invoice number`() {
        let issued = printed(isDraft: false).suggestedFilename
        #expect(issued.hasSuffix("-2026-001"))
        #expect(issued.allSatisfy { $0.isASCII && !$0.isWhitespace })
        let draft = printed().suggestedFilename
        #expect(draft != issued)
        #expect(draft.allSatisfy { $0.isASCII && !$0.isWhitespace })
    }
}
