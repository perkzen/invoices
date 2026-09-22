import Foundation
import SwiftData
import Testing
@testable import Invoices

@MainActor
@Suite("Ledger")
struct LedgerTests {
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

    /// A draft that is ready to issue: a client and the starter line.
    @discardableResult
    private func readyDraft(in ledger: Ledger, issuedOn: Date = Date()) -> Invoice {
        let client = Client(name: "PARAKEET AI Ltd.")
        ledger.context.insert(client)
        let invoice = ledger.newDraft()
        invoice.client = client
        invoice.issueDate = issuedOn
        return invoice
    }

    // MARK: The issuer

    @Test func `the profile is created once and then reused`() throws {
        let ledger = try makeLedger()
        let first = ledger.profile
        let second = ledger.profile
        #expect(first === second)
        #expect(try ledger.context.fetch(FetchDescriptor<BusinessProfile>()).count == 1)
    }

    // MARK: Identity

    /// The command-line tool names an invoice or a client by this. A row
    /// written before the tool existed has none until the launch-time pass.
    @Test func `every invoice and client carries an identity, and old rows are given one`() throws {
        let ledger = try makeLedger()
        let client = Client(name: "PARAKEET AI Ltd.")
        ledger.context.insert(client)
        let draft = ledger.newDraft()
        #expect(client.uuid != nil)
        #expect(draft.uuid != nil)
        #expect(client.uuid != draft.uuid)

        client.uuid = nil
        draft.uuid = nil
        try ledger.context.save()
        ledger.assignIdentifiers()
        #expect(client.uuid != nil)
        #expect(draft.uuid != nil)
    }

    // MARK: Drafts

    @Test func `a new draft takes its defaults from the profile`() throws {
        let ledger = try makeLedger()
        ledger.profile.defaultPaymentTermDays = 15
        ledger.profile.city = "Benedikt"
        ledger.profile.isVatRegistered = true

        let draft = ledger.newDraft()
        #expect(draft.status == .draft)
        #expect(draft.number.isEmpty)
        #expect(draft.placeOfIssue == "Benedikt")
        #expect(draft.lines.count == 1)
        #expect(draft.lines.first?.vatRate == .standard)
        let term = Formatting.calendar.dateComponents([.day], from: draft.issueDate, to: draft.dueDate).day
        #expect(term == 15)
    }

    @Test func `a line item inherits the rate of the line above it`() throws {
        let ledger = try makeLedger()
        let draft = ledger.newDraft()
        draft.sortedLines.first?.vatRate = .reduced

        let line = ledger.addLine(to: draft)
        #expect(line?.vatRate == .reduced)
        #expect(line?.sortIndex == 1)
        #expect(draft.lines.count == 2)
    }

    @Test func `an issued invoice takes no more lines and loses none`() throws {
        let ledger = try makeLedger()
        let invoice = readyDraft(in: ledger)
        try ledger.issue(invoice)

        #expect(ledger.addLine(to: invoice) == nil)
        ledger.removeLine(invoice.sortedLines[0])
        #expect(invoice.lines.count == 1)
    }

    @Test func `a service period defaults to one month less a day`() {
        let end = Ledger.defaultPeriodEnd(from: date(2026, 8, 1))
        #expect(end == date(2026, 8, 31))
    }

    // MARK: Issuing

    @Test func `issuing numbers invoices in an unbroken sequence`() throws {
        let ledger = try makeLedger()
        let first = readyDraft(in: ledger, issuedOn: date(2026, 3, 31))
        try ledger.issue(first)
        let second = readyDraft(in: ledger, issuedOn: date(2026, 4, 30))
        try ledger.issue(second)

        #expect(first.number == "2026-001")
        #expect(second.number == "2026-002")
        #expect(second.status == .issued)
        #expect(second.year == 2026 && second.sequence == 2)
    }

    @Test func `the year of the number is the year of the issue date`() throws {
        let ledger = try makeLedger()
        let december = readyDraft(in: ledger, issuedOn: date(2025, 12, 31))
        try ledger.issue(december)
        let january = readyDraft(in: ledger, issuedOn: date(2026, 1, 2))
        try ledger.issue(january)

        #expect(december.number == "2025-001")
        #expect(january.number == "2026-001")
    }

    @Test func `a draft without a client cannot be issued`() throws {
        let ledger = try makeLedger()
        let draft = ledger.newDraft()

        #expect(ledger.issueProblem(for: draft) == .noClient)
        #expect(throws: Ledger.IssueProblem.noClient) { try ledger.issue(draft) }
        #expect(draft.number.isEmpty)
        #expect(draft.status == .draft)
    }

    @Test func `a draft without line items cannot be issued`() throws {
        let ledger = try makeLedger()
        let draft = readyDraft(in: ledger)
        ledger.removeLine(draft.sortedLines[0])

        #expect(ledger.issueProblem(for: draft) == .noLines)
        #expect(throws: Ledger.IssueProblem.noLines) { try ledger.issue(draft) }
    }

    @Test func `issuing fills in the SI00 reference unless one was typed`() throws {
        let ledger = try makeLedger()
        let automatic = readyDraft(in: ledger, issuedOn: date(2026, 3, 31))
        try ledger.issue(automatic)
        #expect(automatic.paymentReference == "SI00 2026-001")

        let typed = readyDraft(in: ledger, issuedOn: date(2026, 3, 31))
        typed.paymentReference = "SI12 4444"
        try ledger.issue(typed)
        #expect(typed.paymentReference == "SI12 4444")
    }

    @Test func `an issued invoice is issued once`() throws {
        let ledger = try makeLedger()
        let invoice = readyDraft(in: ledger)
        try ledger.issue(invoice)
        #expect(ledger.issueProblem(for: invoice) == .notADraft)
        #expect(throws: Ledger.IssueProblem.notADraft) { try ledger.issue(invoice) }
    }

    // MARK: Payment and cancellation

    @Test func `marking paid records the date`() throws {
        let ledger = try makeLedger()
        let invoice = readyDraft(in: ledger)
        try ledger.issue(invoice)
        ledger.markPaid(invoice, on: date(2026, 4, 2))

        #expect(invoice.status == .paid)
        #expect(invoice.paidDate == date(2026, 4, 2))
    }

    @Test func `a cancelled invoice keeps its number`() throws {
        let ledger = try makeLedger()
        let invoice = readyDraft(in: ledger, issuedOn: date(2026, 3, 31))
        try ledger.issue(invoice)
        ledger.cancel(invoice)

        #expect(invoice.status == .cancelled)
        #expect(invoice.number == "2026-001")
        #expect(invoice.paidDate == nil)
        // The next invoice carries on after the cancelled number.
        let next = readyDraft(in: ledger, issuedOn: date(2026, 4, 1))
        try ledger.issue(next)
        #expect(next.number == "2026-002")
    }

    @Test func `marking unpaid puts the invoice back among the issued`() throws {
        let ledger = try makeLedger()
        let invoice = readyDraft(in: ledger)
        try ledger.issue(invoice)
        ledger.markPaid(invoice, on: date(2026, 4, 2))
        ledger.markUnpaid(invoice)

        #expect(invoice.status == .issued)
        #expect(invoice.paidDate == nil)
        // And the second time round, the payment is dated afresh.
        ledger.markPaid(invoice, on: date(2026, 4, 9))
        #expect(invoice.paidDate == date(2026, 4, 9))
    }

    @Test func `only a paid invoice can be marked unpaid`() throws {
        let ledger = try makeLedger()
        let draft = ledger.newDraft()
        ledger.markUnpaid(draft)
        #expect(draft.status == .draft)

        let cancelled = readyDraft(in: ledger)
        try ledger.issue(cancelled)
        ledger.cancel(cancelled)
        ledger.markUnpaid(cancelled)
        #expect(cancelled.status == .cancelled)
    }

    @Test func `only an issued invoice can be paid or cancelled`() throws {
        let ledger = try makeLedger()
        let draft = ledger.newDraft()
        ledger.markPaid(draft)
        #expect(draft.status == .draft)
        ledger.cancel(draft)
        #expect(draft.status == .draft)
    }

    // MARK: Deleting

    @Test func `a draft may be deleted, an issued invoice may not`() throws {
        let ledger = try makeLedger()
        let draft = ledger.newDraft()
        let issued = readyDraft(in: ledger)
        try ledger.issue(issued)

        #expect(ledger.deletionProblem(for: draft) == nil)
        try ledger.delete(draft)
        #expect(draft.isDeleted)

        #expect(ledger.deletionProblem(for: issued) == .invoiceIssued)
        #expect(throws: Ledger.DeletionProblem.invoiceIssued) { try ledger.delete(issued) }
        #expect(!issued.isDeleted)
    }

    @Test func `a client with issued invoices stays`() throws {
        let ledger = try makeLedger()
        let invoice = readyDraft(in: ledger)
        let client = try #require(invoice.client)
        try ledger.issue(invoice)

        #expect(ledger.deletionProblem(for: client) == .clientHasIssuedInvoices)
        #expect(throws: Ledger.DeletionProblem.clientHasIssuedInvoices) { try ledger.delete(client) }
        #expect(!client.isDeleted)
    }

    @Test func `a client with only drafts may go`() throws {
        let ledger = try makeLedger()
        let draft = readyDraft(in: ledger)
        let client = try #require(draft.client)

        #expect(ledger.deletionProblem(for: client) == nil)
        try ledger.delete(client)
        #expect(client.isDeleted)
    }
}
