import SwiftData
import SwiftUI

/// Pregled — every issued invoice of one year in one table, the way a
/// bookkeeper keeps it in a spreadsheet, and the same table exported as
/// .xlsx for the accountant.
struct YearOverviewView: View {
    /// `nil` until the year list has a year to offer.
    let year: Int?

    @Query(sort: [SortDescriptor(\Invoice.sequence)]) private var invoices: [Invoice]
    @Query private var profiles: [BusinessProfile]

    @State private var exportedSheet: XLSXFile?
    @State private var isExporting = false
    @State private var exportError: String?

    private var overview: YearOverview? {
        year.map { YearOverview.make(year: $0, invoices: invoices, profile: profiles.first) }
    }

    var body: some View {
        Group {
            if let overview {
                content(for: overview)
                    .navigationTitle(overview.title)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Export XLSX", systemImage: "tablecells.badge.ellipsis") {
                                exportSheet(overview)
                            }
                            .help("Save the overview as an Excel spreadsheet")
                        }
                    }
            } else {
                ContentUnavailableView {
                    Label("No invoices issued", systemImage: "tablecells")
                } description: {
                    Text("Issue your first invoice and the year's numbers appear here.")
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportedSheet,
            contentType: XLSXFile.contentType,
            defaultFilename: overview.map(YearOverviewXLSX.suggestedFilename) ?? ""
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            }
        }
        .alert(
            "Export failed",
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
        ) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    @ViewBuilder
    private func content(for overview: YearOverview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OverviewHeadline(overview: overview)
            Divider()
            IssuerHeader(overview: overview)
            Divider()
            OverviewTable(rows: overview.rows, currencyCode: overview.currencyCode)
        }
    }

    private func exportSheet(_ overview: YearOverview) {
        exportedSheet = XLSXFile(data: YearOverviewXLSX.data(for: overview))
        // Present on the next turn so the document is committed first —
        // setting both in one frame can hand the exporter a nil document.
        Task { isExporting = true }
    }
}

private struct IssuerHeader: View {
    let overview: YearOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(overview.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
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
            .width(min: 140, ideal: 170)

            TableColumn("Invoice no.") { row in
                Text(row.number).monospacedDigit()
            }
            .width(min: 70, ideal: 76)

            TableColumn("Date") { row in
                Text(Formatting.date(row.issueDate)).monospacedDigit()
            }
            .width(min: 75, ideal: 80)

            TableColumn("Due date") { row in
                Text(Formatting.date(row.dueDate)).monospacedDigit()
            }
            .width(min: 75, ideal: 80)

            TableColumn("Date of service") { row in
                Text(row.servicePeriod).monospacedDigit()
            }
            .width(min: 140, ideal: 150)

            TableColumn("Amount in \(currencyCode)") { row in
                Text(Formatting.money(row.amount, currencyCode: row.currencyCode))
                    .monospacedDigit()
                    .strikethrough(row.isCancelled)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .sensitiveValue()
            }
            .width(min: 90, ideal: 100)
            .alignment(.trailing)

            TableColumn("Payment received") { row in
                Text(row.paymentNote.isEmpty ? String(localized: "Unpaid") : row.paymentNote)
                    .monospacedDigit()
                    .foregroundStyle(row.isPaid ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .width(min: 90, ideal: 100)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }
}

/// The year at a glance: what went out, what came in, what is still owed,
/// and how much of that is late. The table below is the accountant's view;
/// this row is the owner's.
private struct OverviewHeadline: View {
    let overview: YearOverview

    private var overdue: [YearOverviewRow] { overview.overdueRows() }

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            figure("Invoiced", overview.total,
                   detail: Formatting.invoiceCount(overview.countedRows.count))
            figure("Paid", overview.paidTotal)
            figure("Outstanding", overview.outstandingTotal)
            figure("overview.overdue", overview.overdueTotal(),
                   detail: overdue.isEmpty ? nil : Formatting.invoiceCount(overdue.count),
                   tint: overdue.isEmpty ? .primary : .red)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private func figure(
        _ title: LocalizedStringKey, _ value: Decimal,
        detail: String? = nil, tint: Color = .primary
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Formatting.money(value, currencyCode: overview.currencyCode))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .sensitiveValue()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 120, alignment: .leading)
    }
}
