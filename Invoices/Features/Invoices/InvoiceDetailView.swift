import SwiftData
import SwiftUI

struct InvoiceDetailView: View {
    @Bindable var invoice: Invoice

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Client.name)]) private var clients: [Client]

    @State private var export: FileExport?
    @State private var exportError: String?
    @State private var showsPreview = true
    @State private var isConfirmingCancel = false

    private var ledger: Ledger { Ledger(context) }
    private var isLocked: Bool { !invoice.status.isEditable }
    private var issueProblem: Ledger.IssueProblem? { ledger.issueProblem(for: invoice) }
    private var title: String {
        invoice.number.isEmpty ? String(localized: "Draft invoice") : invoice.number
    }

    /// `serviceDateEnd` as a toggle: on means the service spans a period.
    private var isPeriod: Binding<Bool> {
        Binding(
            get: { invoice.serviceDateEnd != nil },
            set: { on in
                invoice.serviceDateEnd = on ? Ledger.defaultPeriodEnd(from: invoice.serviceDate) : nil
            }
        )
    }

    var body: some View {
        // Built here, in `body`, so every printed property is read under
        // observation: a change anywhere on the invoice, its client or the
        // profile re-evaluates the view, and the summary and the preview
        // follow the same value the PDF will print.
        let printed = PrintedInvoice.make(invoice: invoice, profile: ledger.profile)

        HSplitView {
            form(printed)
                .frame(minWidth: 540, idealWidth: 600)
            if showsPreview {
                // The rendered page beside the form, the way the template
                // page shows its sample.
                InvoicePreview(printed: printed)
                    .frame(minWidth: 280, idealWidth: 320)
            }
        }
        .animation(nil, value: showsPreview)
        .navigationTitle(title)
        .toolbar {
            // A three-column window shows only the list's title, so the
            // editor names its own invoice here.
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .monospacedDigit()
                    // "Draft invoice" already says what a draft is.
                    if !invoice.number.isEmpty {
                        InvoiceStatusBadge(invoice: invoice)
                    }
                }
            }
            // A title, not a button: no glass capsule around it.
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) {
                Button("Export PDF", systemImage: "square.and.arrow.up") { exportPDF(printed) }
                    .help("Save the invoice as a PDF")
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle("Preview", systemImage: "sidebar.trailing", isOn: $showsPreview)
                    .help("Show or hide the invoice preview")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                switch invoice.status {
                case .draft:
                    Button("Issue invoice", action: issue)
                        .disabled(issueProblem != nil)
                        .help(issueProblem.map { Text(verbatim: $0.message) }
                              ?? Text("Assign the next number and lock the invoice"))
                case .issued:
                    Button("Mark as paid") { ledger.markPaid(invoice) }
                    Button("Cancel invoice", role: .destructive) { isConfirmingCancel = true }
                case .paid, .cancelled:
                    EmptyView()
                }
            }
        }
        .confirmationDialog("Cancel this invoice?", isPresented: $isConfirmingCancel) {
            Button("Cancel invoice", role: .destructive) { ledger.cancel(invoice) }
            Button("Keep invoice", role: .cancel) {}
        } message: {
            Text("The number stays in the sequence and the invoice is listed as cancelled. This cannot be undone.")
        }
        .fileExport($export)
        .errorAlert("Export failed", message: $exportError)
    }

    private func form(_ printed: PrintedInvoice) -> some View {
        Form {
            Section("Invoice") {
                LabeledContent("Number") {
                    Text(invoice.number.isEmpty ? String(localized: "assigned on issue") : invoice.number)
                        .foregroundStyle(invoice.number.isEmpty ? .secondary : .primary)
                }
                Picker("Client", selection: $invoice.client) {
                    Text("No client").tag(Client?.none)
                    ForEach(clients) { client in
                        Text(client.displayName).tag(Client?.some(client))
                    }
                }
                DatePicker("Issue date", selection: $invoice.issueDate, displayedComponents: .date)
                DatePicker(isPeriod.wrappedValue ? "Service from" : "Service date",
                           selection: $invoice.serviceDate, displayedComponents: .date)
                Toggle("Service covers a period", isOn: isPeriod)
                if invoice.serviceDateEnd != nil {
                    DatePicker(
                        "Service until",
                        selection: Binding(
                            get: { invoice.serviceDateEnd ?? invoice.serviceDate },
                            set: { invoice.serviceDateEnd = $0 }
                        ),
                        in: invoice.serviceDate...,
                        displayedComponents: .date
                    )
                }
                DatePicker("Payment due", selection: $invoice.dueDate, displayedComponents: .date)
                TextField("Place of issue", text: $invoice.placeOfIssue)
                TextField("Payment reference", text: $invoice.paymentReference,
                          prompt: Text(verbatim: InvoiceNumbering.defaultReference(number: invoice.number)))
            }
            .disabled(isLocked)

            Section("Line items") {
                InvoiceLinesEditor(
                    lines: invoice.sortedLines,
                    currencyCode: invoice.currencyCode,
                    showsVatRate: printed.chargesVat,
                    remove: ledger.removeLine
                )
                Button("Add line item", systemImage: "plus") { ledger.addLine(to: invoice) }
            }
            .disabled(isLocked)

            Section("Summary") {
                if printed.chargesVat {
                    LabeledContent("Net") {
                        Text(Formatting.money(printed.totals.net, currencyCode: printed.currencyCode))
                            .sensitiveValue()
                    }
                    ForEach(printed.vatBreakdown, id: \.rate) { entry in
                        LabeledContent("VAT \(entry.rate.label)") {
                            Text(Formatting.money(entry.amounts.vat, currencyCode: printed.currencyCode))
                                .sensitiveValue()
                        }
                    }
                }
                LabeledContent("Amount due") {
                    Text(Formatting.money(printed.totals.gross, currencyCode: printed.currencyCode))
                        .sensitiveValue()
                        .font(.headline)
                        .monospacedDigit()
                }
                ForEach(printed.exemptionClauses, id: \.self) { clause in
                    Text(clause)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                TextField(
                    "Intro sentence",
                    text: $invoice.introOverride,
                    prompt: Text(verbatim: printed.intro),
                    axis: .vertical
                )
                .lineLimit(1...3)
                TextField("Notes", text: $invoice.notes, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("Text")
            } footer: {
                Text("An empty intro sentence uses the template from My business. Notes are printed below the clauses.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .disabled(isLocked)
        }
        .formStyle(.grouped)
    }

    private func exportPDF(_ printed: PrintedInvoice) {
        guard let data = InvoicePDF.render(printed) else {
            exportError = String(localized: "The invoice could not be rendered.")
            return
        }
        export = .pdf(data, named: printed.suggestedFilename)
    }

    /// The button is disabled while the ledger has an objection, so the
    /// throw cannot reach here from the toolbar.
    private func issue() {
        try? ledger.issue(invoice)
    }
}

/// The line items, each as its description on one row and its numbers on
/// the next, under a single header that names the numeric columns. The
/// columns are fixed widths shared by header and rows, so they line up
/// without a grid having to negotiate width with the form.
private struct InvoiceLinesEditor: View {
    let lines: [InvoiceLine]
    let currencyCode: String
    let showsVatRate: Bool
    let remove: (InvoiceLine) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: LineColumns.spacing) {
                header("Qty", width: LineColumns.quantity)
                header("Unit", width: LineColumns.unit)
                header("Price", width: LineColumns.price)
                header("Discount %", width: LineColumns.discount)
                if showsVatRate {
                    header("VAT", width: LineColumns.vat)
                }
                Spacer(minLength: 0)
                Text("Total")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                if index > 0 {
                    Divider().padding(.vertical, 4)
                }
                InvoiceLineRows(line: line, currencyCode: currencyCode, showsVatRate: showsVatRate) {
                    remove(line)
                }
            }
        }
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .padding(.vertical, 2)
    }

    private func header(_ title: LocalizedStringKey, width: CGFloat) -> some View {
        Text(title)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
    }
}

/// Widths shared by the header and every line, so the columns line up.
private enum LineColumns {
    static let spacing: CGFloat = 6
    static let quantity: CGFloat = 46
    static let unit: CGFloat = 52
    static let price: CGFloat = 78
    static let discount: CGFloat = 64
    static let vat: CGFloat = 88
}

private struct InvoiceLineRows: View {
    @Bindable var line: InvoiceLine
    let currencyCode: String
    let showsVatRate: Bool
    let remove: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: LineColumns.spacing) {
                TextField("Description", text: $line.itemDescription, prompt: Text("Description"))
                Button("Remove line item", systemImage: "xmark.circle.fill", action: remove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tertiary)
                    .help("Remove line item")
            }
            HStack(spacing: LineColumns.spacing) {
                TextField("Qty", value: $line.quantity, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: LineColumns.quantity)
                TextField("Unit", text: $line.unit)
                    .frame(width: LineColumns.unit)
                TextField("Price", value: $line.unitPrice, format: .number)
                    .multilineTextAlignment(.trailing)
                    .sensitiveValue()
                    .frame(width: LineColumns.price, alignment: .trailing)
                TextField("Discount %", value: $line.discountPercent, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: LineColumns.discount)
                if showsVatRate {
                    Picker("VAT", selection: $line.vatRate) {
                        ForEach(VatRate.allCases) { rate in
                            Text(rate.shortLabel).tag(rate)
                        }
                    }
                    .frame(width: LineColumns.vat)
                }
                Spacer(minLength: 0)
                Text(Formatting.money(line.amounts.gross, currencyCode: currencyCode))
                    .sensitiveValue()
                    .monospacedDigit()
            }
        }
    }
}
