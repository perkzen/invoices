import Foundation
import SwiftData

@Model
final class Invoice {
    /// Full human-readable number, e.g. "2026-001". Numbering must be
    /// unbroken and sequential within the year — see `InvoiceNumbering`.
    var number: String = ""
    var year: Int = 0
    var sequence: Int = 0

    var status: InvoiceStatus = InvoiceStatus.draft
    var issueDate: Date = Date()
    /// Datum opravljene storitve — mandatory on a Slovenian invoice and
    /// often different from the issue date.
    var serviceDate: Date = Date()
    /// Set when the service spans a period — the invoice then prints
    /// "1. 8. 2026 – 31. 8. 2026" instead of a single date.
    var serviceDateEnd: Date?
    var dueDate: Date = Date()
    var paidDate: Date?

    var currencyCode: String = "EUR"
    var placeOfIssue: String = ""
    var paymentReference: String = ""
    var notes: String = ""
    /// Overrides the profile's intro template for this invoice; empty means
    /// use the template.
    var introOverride: String = ""

    var client: Client?

    @Relationship(deleteRule: .cascade, inverse: \InvoiceLine.invoice)
    var lines: [InvoiceLine] = []

    init(
        number: String = "",
        year: Int = 0,
        sequence: Int = 0,
        issueDate: Date = Date(),
        serviceDate: Date = Date(),
        dueDate: Date = Date()
    ) {
        self.number = number
        self.year = year
        self.sequence = sequence
        self.issueDate = issueDate
        self.serviceDate = serviceDate
        self.dueDate = dueDate
    }

    var sortedLines: [InvoiceLine] {
        lines.sorted { $0.sortIndex < $1.sortIndex }
    }

    var totals: Amounts {
        InvoiceMath.total(of: lines.map(\.amounts))
    }

    var vatBreakdown: [(rate: VatRate, amounts: Amounts)] {
        InvoiceMath.vatBreakdown(lines.map { ($0.vatRate, $0.amounts) })
    }

    /// Clauses that must be printed when a rate charges no VAT.
    var exemptionClauses: [String] {
        Array(Set(lines.compactMap { $0.vatRate.exemptionClause })).sorted()
    }

    var isOverdue: Bool {
        status == .issued && dueDate < Date()
    }
}
