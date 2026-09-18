import SwiftData
import SwiftUI

/// Pregled — every issued invoice of one year in one table, the way a
/// bookkeeper keeps it in a spreadsheet, and the same table exported as
/// .xlsx for the accountant.
struct YearOverviewView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Invoice.sequence)]) private var invoices: [Invoice]
    @Query private var profiles: [BusinessProfile]

    @State private var selectedYear: Int?
    @State private var exportedSheet: XLSXFile?
    @State private var isExporting = false
    @State private var exportError: String?

    private var years: [Int] { YearOverview.availableYears(in: invoices) }

    /// The newest year with invoices, until one is picked. Falling back to
    /// the current year would show an empty table every January.
    private var year: Int {
        selectedYear.flatMap { years.contains($0) ? $0 : nil }
            ?? years.first
            ?? Calendar.current.component(.year, from: Date())
    }

    private var overview: YearOverview {
        YearOverview.make(year: year, invoices: invoices, profile: profiles.first)
    }

    var body: some View {
        Group {
            if years.isEmpty {
                ContentUnavailableView {
                    Label("Ni izdanih računov", systemImage: "tablecells")
                } description: {
                    Text("Pregled pokaže račune, ko je prvi od njih izdan.")
                }
            } else {
                content(for: overview)
            }
        }
        .navigationTitle("Pregled")
        .toolbar {
            if !years.isEmpty {
                ToolbarItem(placement: .principal) {
                    Picker("Leto", selection: Binding(get: { year }, set: { selectedYear = $0 })) {
                        ForEach(years, id: \.self) { year in
                            Text(verbatim: String(year)).tag(year)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 90)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Izvozi XLSX", systemImage: "tablecells.badge.ellipsis", action: exportSheet)
                        .help("Shrani pregled kot Excelovo preglednico")
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportedSheet,
            contentType: XLSXFile.contentType,
            defaultFilename: YearOverviewXLSX.suggestedFilename(for: overview)
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            }
        }
        .alert(
            "Izvoz ni uspel",
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
        ) {
            Button("V redu", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
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
                .padding(.bottom, 4)
            if !overview.issuer.headline.isEmpty {
                Text(overview.issuer.headline)
            }
            ForEach(overview.issuer.addressLines, id: \.self) { line in
                Text(line)
            }
            if !overview.issuer.taxNumber.isEmpty {
                Text("Davčna številka: \(overview.issuer.taxNumber)")
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
            TableColumn("Stranka") { row in
                Text(row.clientName).strikethrough(row.isCancelled)
            }
            .width(min: 160, ideal: 240)

            TableColumn("Račun št.") { row in
                Text(row.number).monospacedDigit()
            }
            .width(min: 80, ideal: 90)

            TableColumn("Datum") { row in
                Text(Formatting.date(row.issueDate)).monospacedDigit()
            }
            .width(min: 80, ideal: 95)

            TableColumn("Valuta") { row in
                Text(Formatting.date(row.dueDate)).monospacedDigit()
            }
            .width(min: 80, ideal: 95)

            TableColumn("Datum opravljene storitve") { row in
                Text(row.servicePeriod).monospacedDigit()
            }
            .width(min: 150, ideal: 200)

            TableColumn("Vrednost v \(currencyCode)") { row in
                Text(Formatting.money(row.amount, currencyCode: row.currencyCode))
                    .monospacedDigit()
                    .strikethrough(row.isCancelled)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 90, ideal: 120)
            .alignment(.trailing)

            TableColumn("Prejem plačila") { row in
                Text(row.paymentNote.isEmpty ? String(localized: "Neplačano") : row.paymentNote)
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
            amount("Plačano", overview.paidTotal, style: .secondary)
            amount("Odprto", overview.outstandingTotal, style: .secondary)
            amount("SKUPAJ", overview.total, style: .primary)
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
        }
    }
}
