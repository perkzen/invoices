import ArgumentParser
import Foundation

/// The year overview: what the accountant gets.
nonisolated struct OverviewCommand: LedgerCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "overview",
            abstract: "A year's issued invoices with the invoiced, paid, outstanding and overdue totals; optionally as the .xlsx the app exports."
        )
    }

    @OptionGroup var store: StoreOptions
    @Option(help: "The year; this year by default.") var year: Int?
    @Option(help: "Also write the year's spreadsheet to this path.") var xlsx: String?

    nonisolated struct Row: Encodable {
        var number: String
        var client: String?
        var issueDate: String
        var dueDate: String
        var serviceDate: String
        var serviceDateEnd: String?
        var amount: Decimal
        var paidDate: String?
        var isCancelled: Bool
        var isOverdue: Bool
    }

    nonisolated struct Record: Encodable {
        var year: Int
        /// Every year with at least one issued invoice, newest first.
        var years: [Int]
        var currencyCode: String
        var total: Decimal
        var paidTotal: Decimal
        var outstandingTotal: Decimal
        var overdueTotal: Decimal
        var invoices: [Row]
        var xlsx: String?
    }

    @MainActor func execute(_ book: Book) throws {
        let invoices = try book.invoices()
        let year = year ?? Formatting.calendar.component(.year, from: Date())
        let overview = YearOverview.make(year: year, invoices: invoices, profile: book.profile)
        let now = Date()
        let overdue = Set(overview.overdueRows(asOf: now).map(\.number))

        var path: String?
        if let xlsx {
            try book.requireApp()
            let url = URL(fileURLWithPath: (xlsx as NSString).expandingTildeInPath)
            try YearOverviewXLSX.data(for: overview).write(to: url)
            path = url.path
        }

        Output.print(
            Record(
                year: year,
                years: YearOverview.availableYears(in: invoices),
                currencyCode: overview.currencyCode,
                total: overview.total,
                paidTotal: overview.paidTotal,
                outstandingTotal: overview.outstandingTotal,
                overdueTotal: overview.overdueTotal(asOf: now),
                invoices: overview.rows.map { row in
                    Row(
                        number: row.number,
                        client: row.clientName,
                        issueDate: Day.string(row.issueDate),
                        dueDate: Day.string(row.dueDate),
                        serviceDate: Day.string(row.serviceDate),
                        serviceDateEnd: Day.string(row.serviceDateEnd),
                        amount: row.amount,
                        paidDate: Day.string(row.paidDate),
                        isCancelled: row.isCancelled,
                        isOverdue: overdue.contains(row.number)
                    )
                },
                xlsx: path
            )
        )
    }
}
