import Foundation

/// One line of the year overview — the same seven columns a Slovenian
/// bookkeeper keeps in a spreadsheet of issued invoices.
///
/// Plain values, not `Invoice`, so the overview and its .xlsx export can be
/// built and tested without a `ModelContainer`.
nonisolated struct YearOverviewRow: Identifiable, Sendable, Equatable {
    var number: String
    /// `nil` when the invoice has no client. Each surface words that case for
    /// itself — the screen follows the app language, the .xlsx stays Slovenian.
    var clientName: String?
    var issueDate: Date
    /// Valuta — the date the payment is due.
    var dueDate: Date
    var serviceDate: Date
    var serviceDateEnd: Date?
    var amount: Decimal
    var currencyCode: String = "EUR"
    var paidDate: Date?
    var isCancelled: Bool = false

    /// Numbers are unique within a year, which is what this table covers.
    var id: String { number }

    /// The name as the screen shows it.
    var clientLabel: String { clientName ?? String(localized: "No client") }

    /// "1. 8. 2026 – 31. 8. 2026", or the single date when the service did
    /// not span a period.
    var servicePeriod: String {
        guard let end = serviceDateEnd else { return Formatting.date(serviceDate) }
        return "\(Formatting.date(serviceDate)) – \(Formatting.date(end))"
    }

    /// A cancelled invoice keeps its number so the sequence stays unbroken;
    /// the payment column says why no money arrived. On screen only — the
    /// spreadsheet words its own cell, in Slovenian.
    var paymentNote: String {
        if isCancelled { return String(localized: "Cancelled") }
        guard let paidDate else { return "" }
        return Formatting.date(paidDate)
    }

    var isPaid: Bool { paidDate != nil && !isCancelled }
}

/// Every issued invoice of one calendar year, plus the issuer block that goes
/// above the table.
nonisolated struct YearOverview: Sendable {
    struct Issuer: Sendable, Equatable {
        var name: String = ""
        var activityLine: String = ""
        var addressLines: [String] = []
        var taxNumber: String = ""

        /// "Domen Perko s.p., IT storitve in svetovanje"
        var headline: String {
            [name, activityLine].filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    var year: Int
    var issuer: Issuer
    /// Ordered by invoice number, the order the numbers were issued in.
    var rows: [YearOverviewRow]

    var title: String { String(localized: "INVOICES ISSUED IN \(String(year))") }

    /// The app issues in EUR; a foreign currency would need converting before
    /// it could be summed, so the total below only claims one currency.
    var currencyCode: String { rows.first?.currencyCode ?? "EUR" }

    /// A cancelled invoice was never revenue, so it is listed but not summed.
    var total: Decimal { countedRows.reduce(0) { $0 + $1.amount } }

    var paidTotal: Decimal {
        countedRows.filter(\.isPaid).reduce(0) { $0 + $1.amount }
    }

    var outstandingTotal: Decimal { total - paidTotal }

    /// Unpaid rows whose due date has passed. `asOf` is a parameter so the
    /// tests do not depend on the day they run.
    func overdueRows(asOf now: Date = Date()) -> [YearOverviewRow] {
        countedRows.filter { !$0.isPaid && $0.dueDate < now }
    }

    func overdueTotal(asOf now: Date = Date()) -> Decimal {
        overdueRows(asOf: now).reduce(0) { $0 + $1.amount }
    }

    var countedRows: [YearOverviewRow] { rows.filter { !$0.isCancelled } }
}

extension YearOverview {
    /// Builds the overview for one year. Only numbered invoices appear:
    /// `year` is assigned when an invoice is issued, so drafts (year 0) drop
    /// out without having to reason about their status.
    static func make(year: Int, invoices: [Invoice], profile: BusinessProfile?) -> YearOverview {
        let rows = invoices
            .filter { $0.year == year }
            .sorted { $0.sequence < $1.sequence }
            .map { invoice in
                YearOverviewRow(
                    number: invoice.number,
                    clientName: invoice.client?.displayName,
                    issueDate: invoice.issueDate,
                    dueDate: invoice.dueDate,
                    serviceDate: invoice.serviceDate,
                    serviceDateEnd: invoice.serviceDateEnd,
                    amount: invoice.totals.gross,
                    currencyCode: invoice.currencyCode,
                    paidDate: invoice.paidDate,
                    isCancelled: invoice.status == .cancelled
                )
            }

        let issuer = profile.map {
            Issuer(
                name: $0.name,
                activityLine: $0.activityLine,
                addressLines: $0.addressLines,
                taxNumber: $0.taxNumber
            )
        }
        return YearOverview(year: year, issuer: issuer ?? Issuer(), rows: rows)
    }

    /// The years that have at least one issued invoice, newest first.
    static func availableYears(in invoices: [Invoice]) -> [Int] {
        Array(Set(invoices.map(\.year).filter { $0 > 0 })).sorted(by: >)
    }
}
