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

    /// Rewrites the legacy placeholder tokens in the stored sentences — the
    /// profile's three and every invoice's own intro — to their current
    /// spelling. Run once at launch; a store written before the rename would
    /// otherwise show Slovenian tokens beside a legend that lists English ones.
    func modernizeTemplates() {
        let profile = self.profile
        for keyPath in [\BusinessProfile.introTemplate, \.paymentNoteTemplate, \.closingNote] {
            let modern = InvoiceTemplate.modernized(profile[keyPath: keyPath])
            if modern != profile[keyPath: keyPath] { profile[keyPath: keyPath] = modern }
        }
        let invoices = (try? context.fetch(FetchDescriptor<Invoice>())) ?? []
        for invoice in invoices {
            let modern = InvoiceTemplate.modernized(invoice.introOverride)
            if modern != invoice.introOverride { invoice.introOverride = modern }
        }
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

    // MARK: Recording history

    /// What an import has to know about the book as it stands: the numbers
    /// already taken, the clients already known, and the payment term that
    /// fills in a missing due date.
    var recorded: InvoiceImport.Existing {
        let invoices = (try? context.fetch(FetchDescriptor<Invoice>())) ?? []
        let clients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        return InvoiceImport.Existing(
            numbers: Set(invoices.filter { $0.year > 0 }.map { .init(year: $0.year, sequence: $0.sequence) }),
            clientNames: clients.map(\.name),
            paymentTermDays: profile.defaultPaymentTermDays
        )
    }

    /// Records invoices that were issued before the ledger kept the book —
    /// the rows of the accountant's spreadsheet. This is not issuing: the
    /// numbers were given out long ago, on the documents the clients hold,
    /// so each row keeps its own number and lands locked, as issued, paid or
    /// cancelled. The sheet carries one amount per invoice, so each gets one
    /// line item for it. `InvoiceNumbering` carries on after the highest
    /// number recorded.
    ///
    /// Clients are matched by name; a name the book does not know becomes
    /// a new client, with whatever details `newClients` typed in for it.
    @discardableResult
    func record(
        _ rows: [InvoiceImport.Row],
        newClients: [InvoiceImport.NewClient] = [],
        lineDescription: String
    ) -> [Invoice] {
        let profile = self.profile
        let existing = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        var clients = Dictionary(
            existing.map { (InvoiceImport.normalized($0.name), $0) }, uniquingKeysWith: { first, _ in first }
        )
        let details = Dictionary(newClients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return rows.map { row in
            let key = InvoiceImport.normalized(row.clientName)
            let client = clients[key] ?? {
                let client = Client(name: row.clientName)
                if let typed = details[key] {
                    client.street = typed.street
                    client.postalCode = typed.postalCode
                    client.city = typed.city
                    client.countryCode = typed.countryCode.isEmpty ? "SI" : typed.countryCode
                    client.taxNumber = typed.taxNumber
                    client.vatID = typed.vatID
                }
                context.insert(client)
                clients[key] = client
                return client
            }()

            let invoice = Invoice(
                number: row.number,
                year: row.key.year,
                sequence: row.key.sequence,
                issueDate: row.issueDate,
                serviceDate: row.serviceDate,
                dueDate: row.dueDate
            )
            invoice.serviceDateEnd = row.serviceDateEnd
            invoice.status = row.status
            invoice.paidDate = row.status == .paid ? row.paidDate : nil
            invoice.placeOfIssue = profile.city
            invoice.paymentReference = InvoiceNumbering.defaultReference(number: row.number)
            invoice.client = client
            context.insert(invoice)

            // The sheet lists what the client paid, so under VAT the line's
            // price is the net that grosses up to it.
            let rate = profile.defaultVatRate
            let unitPrice = rate.percentage == 0
                ? row.amount
                : (row.amount / (1 + rate.percentage / 100)).rounded()
            let line = InvoiceLine(
                itemDescription: lineDescription, quantity: 1, unitPrice: unitPrice, vatRate: rate
            )
            line.invoice = invoice
            context.insert(line)
            return invoice
        }
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
