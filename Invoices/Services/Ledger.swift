import Foundation
import SwiftData

/// The book of invoices and clients. Every step in an invoice's life goes
/// through here: drafting, issuing, payment, cancellation, and the rules on
/// what may be deleted. Views call it with the app's context; tests call it
/// with an in-memory container and get the same behaviour.
///
/// Slovenian rules require invoice numbers to run in an unbroken sequence
/// within the year. So a number is assigned only when a draft is issued, an
/// issued invoice is never deleted — it is cancelled and keeps its number —
/// and a client with issued invoices stays, because the invoice keeps no
/// copy of its counterparty.
@MainActor
struct Ledger {
    let context: ModelContext

    init(_ context: ModelContext) {
        self.context = context
    }

    // MARK: The issuer

    /// The single business profile, created on first use. The app touches
    /// it once at launch, so views can read it inside `body` without ever
    /// inserting during a view update.
    var profile: BusinessProfile {
        let existing = try? context.fetch(FetchDescriptor<BusinessProfile>())
        if let profile = existing?.first { return profile }
        let profile = BusinessProfile()
        context.insert(profile)
        return profile
    }

    // MARK: Drafts

    /// A new draft: today's dates, the profile's payment term and city, and
    /// one empty line item at the profile's default VAT rate.
    @discardableResult
    func newDraft() -> Invoice {
        let profile = self.profile
        let today = Date()
        let due = Formatting.calendar.date(
            byAdding: .day, value: profile.defaultPaymentTermDays, to: today
        ) ?? today
        let invoice = Invoice(issueDate: today, serviceDate: today, dueDate: due)
        invoice.placeOfIssue = profile.city
        context.insert(invoice)
        addLine(to: invoice)
        return invoice
    }

    /// Appends a line item. It inherits the VAT rate of the line above it,
    /// or the profile's default on an empty invoice.
    @discardableResult
    func addLine(to invoice: Invoice) -> InvoiceLine? {
        guard invoice.status.isEditable else { return nil }
        let last = invoice.sortedLines.last
        let line = InvoiceLine(
            vatRate: last?.vatRate ?? profile.defaultVatRate,
            sortIndex: (last?.sortIndex ?? -1) + 1
        )
        line.invoice = invoice
        context.insert(line)
        return line
    }

    /// Detaches before deleting: a `ForEach` driven by `invoice.lines` must
    /// not re-render an editor bound to a deleted model.
    func removeLine(_ line: InvoiceLine) {
        guard line.invoice?.status.isEditable ?? true else { return }
        line.invoice = nil
        context.delete(line)
    }

    /// The end of a service period that starts on `start`: one month, less
    /// a day — "1. 8." to "31. 8.".
    nonisolated static func defaultPeriodEnd(from start: Date) -> Date? {
        Formatting.calendar.date(byAdding: .month, value: 1, to: start)
            .flatMap { Formatting.calendar.date(byAdding: .day, value: -1, to: $0) }
    }

    // MARK: Issuing

    enum IssueProblem: Error, Equatable {
        case notADraft
        case noClient
        case noLines

        var message: String {
            switch self {
            case .notADraft: String(localized: "Only a draft can be issued")
            case .noClient: String(localized: "Choose a client before issuing the invoice")
            case .noLines: String(localized: "Add a line item before issuing the invoice")
            }
        }
    }

    /// Why `invoice` cannot be issued right now, or nil when it can.
    func issueProblem(for invoice: Invoice) -> IssueProblem? {
        guard invoice.status.isEditable else { return .notADraft }
        if invoice.client == nil { return .noClient }
        if invoice.lines.isEmpty { return .noLines }
        return nil
    }

    /// Assigns the next number in the year of the issue date, fills in the
    /// bank reference when nothing was typed by hand, and locks the invoice.
    func issue(_ invoice: Invoice) throws(IssueProblem) {
        if let problem = issueProblem(for: invoice) { throw problem }
        InvoiceNumbering.assign(to: invoice, in: context)
        if invoice.paymentReference.isEmpty {
            invoice.paymentReference = InvoiceNumbering.defaultReference(number: invoice.number)
        }
        invoice.status = .issued
    }

    func markPaid(_ invoice: Invoice, on date: Date = Date()) {
        guard invoice.status == .issued else { return }
        invoice.status = .paid
        invoice.paidDate = date
    }

    /// Cancellation. The invoice keeps its number so the sequence stays
    /// unbroken; the year overview lists it but does not count it.
    func cancel(_ invoice: Invoice) {
        guard invoice.status == .issued else { return }
        invoice.status = .cancelled
        invoice.paidDate = nil
    }

    // MARK: Deleting

    enum DeletionProblem: Error, Equatable {
        case invoiceIssued
        case clientHasIssuedInvoices

        var message: String {
            switch self {
            case .invoiceIssued: String(localized: "An issued invoice cannot be deleted")
            case .clientHasIssuedInvoices: String(localized: "Has issued invoices and cannot be deleted")
            }
        }
    }

    /// Only a draft may go. An issued number has to stay in the sequence —
    /// removing it would leave an unexplainable gap.
    func deletionProblem(for invoice: Invoice) -> DeletionProblem? {
        invoice.status.isEditable ? nil : .invoiceIssued
    }

    func delete(_ invoice: Invoice) throws(DeletionProblem) {
        if let problem = deletionProblem(for: invoice) { throw problem }
        context.delete(invoice)
    }

    /// An invoice keeps no copy of its counterparty — name, address and tax
    /// number live only on the Client — so deleting one would strip a
    /// mandatory field off a document that has already been sent out.
    func deletionProblem(for client: Client) -> DeletionProblem? {
        client.invoices.contains { !$0.status.isEditable } ? .clientHasIssuedInvoices : nil
    }

    func delete(_ client: Client) throws(DeletionProblem) {
        if let problem = deletionProblem(for: client) { throw problem }
        context.delete(client)
    }
}
