import SwiftData
import SwiftUI

/// Overview — every issued invoice of one year in one table, the way a
/// bookkeeper keeps it in a spreadsheet, and the same table exported as
/// .xlsx for the accountant.
struct YearOverviewView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Invoice.sequence)]) private var invoices: [Invoice]

    @State private var selectedYear: Int?
    @State private var export: FileExport?

    private var years: [Int] { YearOverview.availableYears(in: invoices) }

    /// The newest year with invoices, until one is picked. Falling back to
    /// the current year would show an empty table every January.
    private var year: Int {
        selectedYear.flatMap { years.contains($0) ? $0 : nil }
            ?? years.first
            ?? Formatting.calendar.component(.year, from: Date())
    }

    private var overview: YearOverview {
        YearOverview.make(year: year, invoices: invoices, profile: Ledger(context).profile)
    }

    var body: some View {
        Group {
            if years.isEmpty {
                ContentUnavailableView {
                    Label("No invoices issued", systemImage: "tablecells")
                } description: {
                    Text("The overview lists invoices once the first one has been issued.")
                }
            } else {
                content(for: overview)
            }
        }
        .navigationTitle("Overview")
        .toolbar {
            if !years.isEmpty {
                ToolbarItem(placement: .principal) {
                    Picker("Year", selection: Binding(get: { year }, set: { selectedYear = $0 })) {
                        ForEach(years, id: \.self) { year in
                            Text(verbatim: String(year)).tag(year)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 90)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Export XLSX", systemImage: "tablecells.badge.ellipsis", action: exportSheet)
                        .help("Save the overview as an Excel spreadsheet")
                }
            }
        }
        .fileExport($export)
    }

    @ViewBuilder
    private func content(for overview: YearOverview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            IssuerHeader(overview: overview)
            Divider()
            OverviewTable(rows: overview.rows, currencyCode: overview.currencyCode)
            Divider()
            OverviewSummary(overview: overview)
        }
    }

    private func exportSheet() {
        export = .xlsx(
            YearOverviewXLSX.data(for: overview),
            named: YearOverviewXLSX.suggestedFilename(for: overview)
        )
    }
}

private struct IssuerHeader: View {
    let overview: YearOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(overview.title)
                .font(.title3.weight(.semibold))
                .padding(.bottom, 4)
            if !overview.issuer.headline.isEmpty {
                Text(overview.issuer.headline)
            }
            ForEach(overview.issuer.addressLines, id: \.self) { line in
                Text(line)
            }
            if !overview.issuer.taxNumber.isEmpty {
                HStack(spacing: 4) {
                    Text("Tax number:")
                    Text(overview.issuer.taxNumber).sensitiveValue()
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

private struct OverviewTable: View {
    let rows: [YearOverviewRow]
    let currencyCode: String

    var body: some View {
        Table(rows) {
            TableColumn("Client") { row in
                Text(row.clientLabel).strikethrough(row.isCancelled)
            }
            .width(min: 160, ideal: 240)

            TableColumn("Invoice no.") { row in
                Text(row.number).monospacedDigit()
            }
            .width(min: 80, ideal: 90)

            TableColumn("Date") { row in
                Text(Formatting.date(row.issueDate)).monospacedDigit()
            }
            .width(min: 80, ideal: 95)

            TableColumn("Due date") { row in
                Text(Formatting.date(row.dueDate)).monospacedDigit()
            }
            .width(min: 80, ideal: 95)

            TableColumn("Date of service") { row in
                Text(row.servicePeriod).monospacedDigit()
            }
            .width(min: 150, ideal: 200)

            TableColumn("Amount in \(currencyCode)") { row in
                Text(Formatting.money(row.amount, currencyCode: row.currencyCode))
                    .monospacedDigit()
                    .strikethrough(row.isCancelled)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .sensitiveValue()
            }
            .width(min: 90, ideal: 120)
            .alignment(.trailing)

            TableColumn("Payment received") { row in
                Text(row.paymentNote.isEmpty ? String(localized: "Unpaid") : row.paymentNote)
                    .monospacedDigit()
                    .foregroundStyle(row.isPaid ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .width(min: 100, ideal: 120)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }
}

private struct OverviewSummary: View {
    let overview: YearOverview

    var body: some View {
        HStack(spacing: 24) {
            Label(Formatting.invoiceCount(overview.countedRows.count), systemImage: "doc.text")
                .foregroundStyle(.secondary)
            Spacer()
            amount("Paid", overview.paidTotal, style: .secondary)
            amount("Outstanding", overview.outstandingTotal, style: .secondary)
            amount("TOTAL", overview.total, style: .primary)
                .font(.headline)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func amount(
        _ title: LocalizedStringKey, _ value: Decimal, style: HierarchicalShapeStyle
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(Formatting.money(value, currencyCode: overview.currencyCode))
                .monospacedDigit()
                .foregroundStyle(style)
                .sensitiveValue()
        }
    }
}
