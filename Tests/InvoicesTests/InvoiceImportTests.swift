import Foundation
import SwiftData
import Testing
@testable import Invoices

@MainActor
@Suite("Invoice import")
struct InvoiceImportTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Formatting.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeLedger() throws -> Ledger {
        let container = try ModelContainer(
            for: Invoice.self, InvoiceLine.self, Client.self, BusinessProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return Ledger(ModelContext(container))
    }

    /// The bookkeeper's sheet as it is kept by hand: a title block, the
    /// table under the document-language headings, text dates, a blank
    /// row and the TOTAL line.
    private func bookkeeperSheet(rows: [[Spreadsheet.Value]]) -> Spreadsheet.Grid {
        var grid: [[Spreadsheet.Value]] = [
            [.text("INVOICES ISSUED")],
            [],
            [.text("Me, sole trader")],
            [.text("Tax number: 12345678")],
            [],
            [
                .text(DocumentText.string("Client")), .text(DocumentText.string("Invoice no.") + " "),
                .text(DocumentText.string("Date")), .text(DocumentText.string("Due date")),
                .text(DocumentText.string("Date of service")), .text(DocumentText.string("Amount in \("EUR")")),
                .text(DocumentText.string("Payment received")),
            ],
        ]
        grid += rows
        grid += [[], [.text(DocumentText.string("TOTAL")), .empty, .empty, .empty, .empty, .number(9999)]]
        return Spreadsheet.Grid(rows: grid)
    }

    private let paidRow: [Spreadsheet.Value] = [
        .text("PARAKEET AI Ltd."), .text("2026-001"), .text("31.3.2026"), .text("8.4.2026"),
        .text("01.03.2026 - 31.03.2026"), .number(Decimal(string: "4389.99")!), .text("31.3.2026"),
    ]
    private let unpaidRow: [Spreadsheet.Value] = [
        .text("PARAKEET AI Ltd."), .text("2026-002"), .text("16.4.2026"), .text("24.4.2026"),
        .text("01.04.2026-30.04.2026"), .number(1000), .empty,
    ]

    // MARK: Columns

    @Test func `the columns are found under the document headings`() {
        let mapping = InvoiceImport.detectMapping(in: bookkeeperSheet(rows: [paidRow]))
        #expect(mapping.headerRow == 5)
        #expect(mapping.isComplete)
        #expect(mapping.columns == [
            .client: 0, .number: 1, .issueDate: 2, .dueDate: 3, .servicePeriod: 4, .amount: 5, .paidDate: 6,
        ])
    }

    @Test func `the columns are found under English headings in another order`() {
        let grid = Spreadsheet.Grid(rows: [
            [.text("Notes"), .text("Invoice number"), .text("Customer"), .text("Total"), .text("Issue date"), .text("Paid")],
        ])
        let mapping = InvoiceImport.detectMapping(in: grid)
        #expect(mapping.columns == [.number: 1, .client: 2, .amount: 3, .issueDate: 4, .paidDate: 5])
        #expect(mapping.isComplete)
    }

    @Test func `the app's own export is recognised whole`() throws {
        let overview = YearOverview(year: 2026, issuer: .init(name: "Me"), rows: [
            YearOverviewRow(number: "2026-001", clientName: "Client", issueDate: date(2026, 3, 31),
                            dueDate: date(2026, 4, 8), serviceDate: date(2026, 3, 1), amount: 100),
        ])
        let grid = try Spreadsheet.grid(from: YearOverviewXLSX.data(for: overview), filenameExtension: "xlsx")
        let mapping = InvoiceImport.detectMapping(in: grid)
        #expect(mapping.isComplete)
        #expect(mapping.columns.count == 7)
        let plan = InvoiceImport.plan(grid: grid, mapping: mapping)
        #expect(plan.rows.map(\.number) == ["2026-001"])
        #expect(plan.rows.first?.issueDate == date(2026, 3, 31))
    }

    @Test func `a sheet with unknown headings is left for the user to map`() {
        let grid = Spreadsheet.Grid(rows: [[.text("A"), .text("B"), .text("C")], [.text("x"), .text("y"), .text("z")]])
        let mapping = InvoiceImport.detectMapping(in: grid)
        #expect(mapping.headerRow == nil)
        #expect(mapping.missingFields == [.client, .number, .issueDate, .amount])
        let columns = InvoiceImport.columns(of: grid, mapping: mapping)
        #expect(columns.map(\.letter) == ["A", "B", "C"])
        #expect(columns.map(\.sample) == ["A", "B", "C"])
    }

    // MARK: Rows

    @Test func `rows become invoices, the title block and the total do not`() {
        let grid = bookkeeperSheet(rows: [paidRow, unpaidRow])
        let plan = InvoiceImport.plan(grid: grid, mapping: InvoiceImport.detectMapping(in: grid))

        #expect(plan.skipped.isEmpty)
        #expect(plan.rows.count == 2)
        let paid = plan.rows[0]
        #expect(paid.sourceRow == 7)
        #expect(paid.number == "2026-001")
        #expect(paid.key == .init(year: 2026, sequence: 1))
        #expect(paid.clientName == "PARAKEET AI Ltd.")
        #expect(paid.issueDate == date(2026, 3, 31))
        #expect(paid.dueDate == date(2026, 4, 8))
        #expect(paid.serviceDate == date(2026, 3, 1))
        #expect(paid.serviceDateEnd == date(2026, 3, 31))
        #expect(paid.amount == Decimal(string: "4389.99"))
        #expect(paid.paidDate == date(2026, 3, 31))
        #expect(paid.status == .paid)

        let unpaid = plan.rows[1]
        #expect(unpaid.status == .issued)
        #expect(unpaid.paidDate == nil)
        #expect(unpaid.serviceDateEnd == date(2026, 4, 30))
        #expect(plan.total == Decimal(string: "5389.99"))
        #expect(plan.years == [2026])
        #expect(plan.newClientNames == ["PARAKEET AI Ltd."])
    }

    @Test func `a cancelled invoice is recorded as cancelled and not summed`() {
        var row = unpaidRow
        row[6] = .text(DocumentText.string("Cancelled"))
        let grid = bookkeeperSheet(rows: [paidRow, row])
        let plan = InvoiceImport.plan(grid: grid, mapping: InvoiceImport.detectMapping(in: grid))
        #expect(plan.rows[1].status == .cancelled)
        #expect(plan.total == Decimal(string: "4389.99"))
    }

    @Test func `missing dates are filled in from the issue date and the payment term`() {
        var row = unpaidRow
        row[3] = .empty
        row[4] = .empty
        let grid = bookkeeperSheet(rows: [row])
        let plan = InvoiceImport.plan(
            grid: grid, mapping: InvoiceImport.detectMapping(in: grid), existing: .init(paymentTermDays: 15)
        )
        let invoice = try! #require(plan.rows.first)
        #expect(invoice.dueDate == date(2026, 5, 1))
        #expect(invoice.serviceDate == date(2026, 4, 16))
        #expect(invoice.serviceDateEnd == nil)
    }

    @Test func `a row missing what an invoice needs is skipped with the reason`() {
        var noClient = unpaidRow; noClient[0] = .text(DocumentText.string("No client"))
        var noNumber = unpaidRow; noNumber[1] = .empty
        var badNumber = unpaidRow; badNumber[1] = .text("pending")
        var noDate = unpaidRow; noDate[2] = .empty
        var badDate = unpaidRow; badDate[2] = .text("soon")
        var noAmount = unpaidRow; noAmount[5] = .empty
        var badAmount = unpaidRow; badAmount[5] = .text("n/a")
        let grid = bookkeeperSheet(rows: [noClient, noNumber, badNumber, noDate, badDate, noAmount, badAmount])
        let plan = InvoiceImport.plan(grid: grid, mapping: InvoiceImport.detectMapping(in: grid))

        #expect(plan.rows.isEmpty)
        #expect(plan.candidates.map(\.problem) == [
            .noClient, .noNumber, .unreadableNumber("pending"), .noIssueDate, .unreadableDate("soon"),
            .noAmount, .unreadableAmount("n/a"),
        ])
        #expect(plan.newClientNames.isEmpty)
    }

    @Test func `a number already in the ledger, or twice in the file, is skipped`() {
        let grid = bookkeeperSheet(rows: [paidRow, paidRow, unpaidRow])
        let plan = InvoiceImport.plan(
            grid: grid, mapping: InvoiceImport.detectMapping(in: grid),
            existing: .init(numbers: [.init(year: 2026, sequence: 2)])
        )
        #expect(plan.rows.map(\.number) == ["2026-001"])
        #expect(plan.candidates[1].problem == .duplicateInFile)
        #expect(plan.candidates[2].problem == .alreadyRecorded)
    }

    @Test func `a client the ledger knows is matched whatever the spelling`() {
        let grid = bookkeeperSheet(rows: [paidRow])
        let plan = InvoiceImport.plan(
            grid: grid, mapping: InvoiceImport.detectMapping(in: grid),
            existing: .init(clientNames: ["parakeet  ai ltd"])
        )
        #expect(plan.newClientNames.isEmpty)
    }

    @Test func `numbers are read in the shapes bookkeepers write`() {
        let issued = date(2026, 3, 31)
        #expect(InvoiceImport.number(from: "2026-001", issueDate: issued) == .init(year: 2026, sequence: 1))
        #expect(InvoiceImport.number(from: "12/2025", issueDate: issued) == .init(year: 2025, sequence: 12))
        #expect(InvoiceImport.number(from: "R-2026-7", issueDate: issued) == .init(year: 2026, sequence: 7))
        #expect(InvoiceImport.number(from: "7", issueDate: issued) == .init(year: 2026, sequence: 7))
        #expect(InvoiceImport.number(from: "2026", issueDate: issued) == nil)
        #expect(InvoiceImport.number(from: "pending", issueDate: issued) == nil)
    }

    // MARK: Recording

    @Test func `recording writes issued invoices, their clients and one line each`() throws {
        let ledger = try makeLedger()
        ledger.profile.city = "Benedikt"
        let known = Client(name: "Parakeet AI Ltd.")
        known.city = "Ljubljana"
        ledger.context.insert(known)

        var otherRow = unpaidRow
        otherRow[0] = .text("Other Co.")
        otherRow[1] = .text("2026-003")
        let grid = bookkeeperSheet(rows: [paidRow, unpaidRow, otherRow])
        let plan = InvoiceImport.plan(grid: grid, mapping: InvoiceImport.detectMapping(in: grid), existing: ledger.recorded)
        #expect(plan.newClientNames == ["Other Co."])

        var other = InvoiceImport.NewClient(name: "Other Co.")
        other.street = "1 High Street"
        other.taxNumber = "87654321"
        let recorded = ledger.record(plan.rows, newClients: [other], lineDescription: "Services")

        #expect(recorded.count == 3)
        let first = recorded[0]
        #expect(first.number == "2026-001")
        #expect(first.year == 2026 && first.sequence == 1)
        #expect(first.status == .paid)
        #expect(first.paidDate == date(2026, 3, 31))
        #expect(first.client === known)
        #expect(first.placeOfIssue == "Benedikt")
        #expect(first.paymentReference == "SI00 2026-001")
        #expect(first.serviceDateEnd == date(2026, 3, 31))
        #expect(first.lines.count == 1)
        #expect(first.lines.first?.itemDescription == "Services")
        #expect(first.totals.gross == Decimal(string: "4389.99"))
        #expect(recorded[1].status == .issued)

        let created = try #require(recorded[2].client)
        #expect(created.name == "Other Co.")
        #expect(created.street == "1 High Street")
        #expect(created.taxNumber == "87654321")
        #expect(try ledger.context.fetch(FetchDescriptor<Client>()).count == 2)

        // The book carries on after what was recorded.
        let next = ledger.newDraft()
        next.client = known
        next.issueDate = date(2026, 5, 6)
        try ledger.issue(next)
        #expect(next.number == "2026-004")
        #expect(ledger.recorded.numbers.count == 4)
        #expect(ledger.deletionProblem(for: first) == .invoiceIssued)
    }

    @Test func `under VAT the sheet's amount is the gross`() throws {
        let ledger = try makeLedger()
        ledger.profile.isVatRegistered = true
        let grid = bookkeeperSheet(rows: [unpaidRow])
        let plan = InvoiceImport.plan(grid: grid, mapping: InvoiceImport.detectMapping(in: grid))
        let invoice = try #require(ledger.record(plan.rows, lineDescription: "Services").first)
        #expect(invoice.lines.first?.vatRate == .standard)
        #expect(invoice.lines.first?.unitPrice == Decimal(string: "819.67"))
        #expect(invoice.totals.gross == Decimal(string: "1000.00"))
    }
}
