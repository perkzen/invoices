import Foundation
import SwiftData
import Testing
@testable import Invoices

@MainActor
@Suite("Year overview")
struct YearOverviewTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Invoice.self, InvoiceLine.self, Client.self, BusinessProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @discardableResult
    private func makeInvoice(
        in context: ModelContext,
        year: Int,
        sequence: Int,
        amount: Decimal,
        status: InvoiceStatus = .issued,
        client: Client? = nil
    ) -> Invoice {
        let invoice = Invoice(
            number: InvoiceNumbering.format(year: year, sequence: sequence),
            year: year,
            sequence: sequence,
            issueDate: date(year, 3, 31),
            serviceDate: date(year, 3, 1),
            dueDate: date(year, 4, 8)
        )
        invoice.status = status
        invoice.client = client
        if status == .paid { invoice.paidDate = date(year, 4, 2) }
        context.insert(invoice)

        let line = InvoiceLine(quantity: 1, unitPrice: amount, vatRate: .exempt)
        line.invoice = invoice
        context.insert(line)
        return invoice
    }

    private func sampleRow(
        number: String = "2026-001",
        amount: Decimal = 100,
        paidDate: Date? = nil,
        isCancelled: Bool = false
    ) -> YearOverviewRow {
        YearOverviewRow(
            number: number,
            clientName: "PARAKEET AI Ltd.",
            issueDate: date(2026, 3, 31),
            dueDate: date(2026, 4, 8),
            serviceDate: date(2026, 3, 1),
            serviceDateEnd: nil,
            amount: amount,
            paidDate: paidDate,
            isCancelled: isCancelled
        )
    }

    // MARK: Rows

    @Test func `only invoices of the chosen year appear, in numbering order`() throws {
        let context = try makeContext()
        makeInvoice(in: context, year: 2026, sequence: 2, amount: 200)
        makeInvoice(in: context, year: 2026, sequence: 1, amount: 100)
        makeInvoice(in: context, year: 2025, sequence: 1, amount: 900)

        let overview = YearOverview.make(
            year: 2026, invoices: try context.fetch(FetchDescriptor<Invoice>()), profile: nil
        )
        #expect(overview.rows.map(\.number) == ["2026-001", "2026-002"])
        #expect(overview.total == 300)
    }

    /// A draft has no number and no year, so it cannot appear in a list of
    /// issued invoices — and cannot be summed into the year's revenue.
    @Test func `drafts are left out`() throws {
        let context = try makeContext()
        makeInvoice(in: context, year: 2026, sequence: 1, amount: 100)
        let draft = Invoice()
        draft.status = .draft
        context.insert(draft)

        let overview = YearOverview.make(
            year: 2026, invoices: try context.fetch(FetchDescriptor<Invoice>()), profile: nil
        )
        #expect(overview.rows.count == 1)
    }

    @Test func `an invoice without a client still has a name in the table`() throws {
        let context = try makeContext()
        makeInvoice(in: context, year: 2026, sequence: 1, amount: 100)
        let overview = YearOverview.make(
            year: 2026, invoices: try context.fetch(FetchDescriptor<Invoice>()), profile: nil
        )
        // The row itself holds no name; the screen and the sheet each word
        // the empty case, and the sheet words it in the document's language.
        #expect(overview.rows.first?.clientName == nil)
        let sheet = YearOverviewXLSX.sheet(for: overview)
        #expect(sheet.rows[sheet.frozenRows].first?.value == .text(DocumentText.string("No client")))
    }

    @Test func `the years offered are those that have issued invoices, newest first`() throws {
        let context = try makeContext()
        makeInvoice(in: context, year: 2025, sequence: 1, amount: 10)
        makeInvoice(in: context, year: 2026, sequence: 1, amount: 10)
        makeInvoice(in: context, year: 2026, sequence: 2, amount: 10)
        context.insert(Invoice())

        let years = YearOverview.availableYears(in: try context.fetch(FetchDescriptor<Invoice>()))
        #expect(years == [2026, 2025])
    }

    // MARK: Totals

    /// A cancelled invoice keeps its number — the sequence must stay
    /// unbroken — but it was never revenue, so it is listed and not summed.
    @Test func `a cancelled invoice is listed but not counted`() throws {
        let context = try makeContext()
        makeInvoice(in: context, year: 2026, sequence: 1, amount: 100)
        makeInvoice(in: context, year: 2026, sequence: 2, amount: 50, status: .cancelled)

        let overview = YearOverview.make(
            year: 2026, invoices: try context.fetch(FetchDescriptor<Invoice>()), profile: nil
        )
        #expect(overview.rows.count == 2)
        #expect(overview.total == 100)
        #expect(overview.countedRows.count == 1)
        // The payment column of the cancelled row, as the accountant reads it.
        let sheet = YearOverviewXLSX.sheet(for: overview)
        #expect(sheet.rows[sheet.frozenRows + 1][6].value == .text(DocumentText.string("Cancelled")))
    }

    @Test func `paid and outstanding split the total`() throws {
        let context = try makeContext()
        makeInvoice(in: context, year: 2026, sequence: 1, amount: 100, status: .paid)
        makeInvoice(in: context, year: 2026, sequence: 2, amount: 25)

        let overview = YearOverview.make(
            year: 2026, invoices: try context.fetch(FetchDescriptor<Invoice>()), profile: nil
        )
        #expect(overview.paidTotal == 100)
        #expect(overview.outstandingTotal == 25)
        #expect(overview.paidTotal + overview.outstandingTotal == overview.total)
    }

    @Test func `a service spanning a period prints both dates`() {
        var row = sampleRow()
        #expect(!row.servicePeriod.contains("–"))
        row.serviceDateEnd = date(2026, 3, 31)
        #expect(row.servicePeriod.contains("–"))
        #expect(row.servicePeriod.contains(Formatting.date(date(2026, 3, 31))))
    }

    /// English has one plural boundary. The Slovenian four are pinned in
    /// `LocalizationTests`, where the sl bundle can be asked directly.
    @Test func `the invoice count is written in the app's language`() {
        #expect(Formatting.invoiceCount(1) == "1 invoice")
        #expect(Formatting.invoiceCount(2) == "2 invoices")
        #expect(Formatting.invoiceCount(5) == "5 invoices")
        #expect(Formatting.invoiceCount(0) == "0 invoices")
    }

    @Test func `the issuer block joins the name and the activity line`() throws {
        let context = try makeContext()
        let profile = BusinessProfile.current(in: context)
        profile.name = "Domen Perko"
        profile.activityLine = "IT services and consulting"
        profile.street = "Ihova 51 a"
        profile.postalCode = "2234"
        profile.city = "Benedikt"
        profile.taxNumber = "13640887"

        let overview = YearOverview.make(year: 2026, invoices: [], profile: profile)
        #expect(overview.issuer.headline == "Domen Perko, IT services and consulting")
        #expect(overview.issuer.addressLines == ["Ihova 51 a", "2234 Benedikt"])
        #expect(overview.title.contains("2026"))
    }

    // MARK: Spreadsheet

    @Test func `the sheet has an issuer block, a header row and a TOTAL line`() {
        let overview = YearOverview(
            year: 2026,
            issuer: .init(
                name: "Domen Perko",
                activityLine: "IT services and consulting",
                addressLines: ["Ihova 51 a", "2234 Benedikt"],
                taxNumber: "13640887"
            ),
            rows: [
                sampleRow(number: "2026-001", amount: Decimal(string: "4389.99")!),
                sampleRow(number: "2026-002", amount: 1000, paidDate: date(2026, 4, 8)),
            ]
        )
        let sheet = YearOverviewXLSX.sheet(for: overview)

        // Title, blank, headline, two address lines, tax number, blank.
        #expect(sheet.frozenRows == 8)
        #expect(sheet.rows[sheet.frozenRows - 1].count == YearOverviewXLSX.columnHeaders.count)
        #expect(sheet.rows.last?.first?.value == .text(DocumentText.string("TOTAL")))
        #expect(sheet.rows.last?[5].value == .number(Decimal(string: "5389.99")!))
        #expect(YearOverviewXLSX.suggestedFilename(for: overview).hasSuffix("-2026"))
    }

    @Test func `the exported workbook holds the year's numbers`() {
        let overview = YearOverview(
            year: 2026,
            issuer: .init(name: "Domen Perko"),
            rows: [sampleRow(number: "2026-001", amount: Decimal(string: "4389.99")!)]
        )
        let text = String(decoding: YearOverviewXLSX.data(for: overview), as: UTF8.self)
        #expect(text.contains(XLSXWriter.escape(DocumentText.string("INVOICES ISSUED IN \(String(2026))"))))
        #expect(text.contains("PARAKEET AI Ltd."))
        #expect(text.contains("2026-001"))
        #expect(text.contains("<v>4389.99</v>"))
        #expect(text.contains("<v>46112</v>"))  // 31. 3. 2026
    }
}
