import SwiftData
import SwiftUI

/// Overview — one year at a glance, then every issued invoice of that year
/// in one table, the way a bookkeeper keeps it in a spreadsheet, and the
/// same table exported as .xlsx for the accountant.
struct YearOverviewView: View {
    /// `nil` until the year list has a year to offer.
    let year: Int?

    @Environment(\.modelContext) private var context
    @Environment(\.importSpreadsheet) private var importSpreadsheet
    @Query(sort: [SortDescriptor(\Invoice.sequence)]) private var invoices: [Invoice]

    @State private var export: FileExport?
    /// The number of the row picked in the table; numbers are unique within
    /// the year the table shows.
    @State private var selectedNumber: String?

    private var profile: BusinessProfile { Ledger(context).profile }

    private var overview: YearOverview? {
        year.map { YearOverview.make(year: $0, invoices: invoices, profile: profile) }
    }

    private var selectedInvoice: Invoice? {
        invoices.first { $0.year == year && $0.number == selectedNumber }
    }

    var body: some View {
        Group {
            if let overview {
                content(for: overview)
                    .onChange(of: year) { selectedNumber = nil }
                    .navigationTitle(overview.title)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Export XLSX", systemImage: "square.and.arrow.up") {
                                exportSheet(overview)
                            }
                            .help("Save the overview as an Excel spreadsheet")
                        }
                    }
            } else {
                ContentUnavailableView {
                    Label("No invoices issued", systemImage: "tablecells")
                } description: {
                    Text("Issue your first invoice and the year's numbers appear here. Invoices issued before you started using the app can be brought in from a spreadsheet.")
                } actions: {
                    if let importSpreadsheet {
                        Button("Import from a spreadsheet…") { importSpreadsheet() }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Import XLSX", systemImage: "tray.and.arrow.down") { importSpreadsheet?() }
                    .help("Record invoices from a spreadsheet of issued invoices")
                    .disabled(importSpreadsheet == nil)
            }
        }
        .fileExport($export)
    }

    /// Picking a row opens its invoice beside the table, the way the editor
    /// shows the page: the number in the table is the printed document.
    @ViewBuilder
    private func content(for overview: YearOverview) -> some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                OverviewHeadline(overview: overview)
                Divider()
                IssuerHeader(overview: overview)
                Divider()
                OverviewTable(
                    rows: overview.rows, currencyCode: overview.currencyCode,
                    selection: $selectedNumber
                )
            }
            .frame(minWidth: 520)
            if let invoice = selectedInvoice {
                OverviewPreviewPane(
                    invoice: invoice,
                    printed: PrintedInvoice.make(invoice: invoice, profile: profile)
                )
                .frame(minWidth: 300, idealWidth: 360)
            }
        }
        .animation(nil, value: selectedNumber)
    }

    private func exportSheet(_ overview: YearOverview) {
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
            // Detail titles are not shown in a three-column window, so the
            // sheet's own heading stays here where it mirrors the export.
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
    @Binding var selection: String?

    var body: some View {
        Table(rows, selection: $selection) {
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
                    .strikethrough(row.isCancelled)
                    .sensitiveValue()
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
                .sensitiveValue()
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 120, alignment: .leading)
    }
}

/// The picked invoice as its printed page, with who and what above it.
private struct OverviewPreviewPane: View {
    let invoice: Invoice
    let printed: PrintedInvoice

    @State private var export: FileExport?
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ClientAvatar(client: invoice.client, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(invoice.number)
                        .font(.headline)
                        .monospacedDigit()
                    Text(invoice.client?.displayName ?? String(localized: "No client"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                InvoiceStatusBadge(invoice: invoice)
                // The page is right here; so is the way to keep a copy.
                Button("Export PDF", systemImage: "square.and.arrow.down", action: exportPDF)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Save the invoice as a PDF")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            InvoicePreview(printed: printed)
        }
        .fileExport($export)
        .errorAlert("Export failed", message: $exportError)
    }

    private func exportPDF() {
        guard let data = InvoicePDF.render(printed) else {
            exportError = String(localized: "The invoice could not be rendered.")
            return
        }
        export = .pdf(data, named: printed.suggestedFilename)
    }
}
