import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct InvoiceDetailView: View {
    @Bindable var invoice: Invoice

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Client.name)]) private var clients: [Client]
    @Query private var profiles: [BusinessProfile]

    private var isLocked: Bool { !invoice.status.isEditable }
    /// A s.p. that is not a DDV zavezanec never charges VAT, so the whole
    /// VAT apparatus stays out of the way until the toggle in Nastavitve flips.
    private var chargesVat: Bool { profiles.first?.isVatRegistered ?? false }

    @State private var exportedPDF: PDFFile?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showsPreview = true
    @State private var isConfirmingCancel = false

    /// `serviceDateEnd` as a toggle: on means the service spans a period.
    private var isPeriod: Binding<Bool> {
        Binding(
            get: { invoice.serviceDateEnd != nil },
            set: { on in
                invoice.serviceDateEnd = on
                    ? Calendar.current.date(byAdding: .month, value: 1, to: invoice.serviceDate)
                        .flatMap { Calendar.current.date(byAdding: .day, value: -1, to: $0) }
                    : nil
            }
        )
    }

    var body: some View {
        HSplitView {
            form
                .frame(minWidth: 540, idealWidth: 600)
            if showsPreview {
                previewPane
                    .frame(minWidth: 280, idealWidth: 320)
            }
        }
        .animation(nil, value: showsPreview)
        .task {
            // Guarantees the preview has a profile on a fresh install.
            _ = BusinessProfile.current(in: context)
        }
        .navigationTitle(invoice.number.isEmpty ? String(localized: "Draft invoice") : invoice.number)
        .toolbar {
            // A three-column window shows only the list's title, so the
            // editor names its own invoice here.
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Text(invoice.number.isEmpty ? String(localized: "Draft invoice") : invoice.number)
                        .font(.headline)
                        .monospacedDigit()
                    // "Draft invoice" already says what a draft is.
                    if !invoice.number.isEmpty {
                        InvoiceStatusBadge(invoice: invoice)
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Export PDF", systemImage: "square.and.arrow.down", action: exportPDF)
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
                        .disabled(invoice.client == nil || invoice.lines.isEmpty)
                        .help(invoice.client == nil
                              ? "Choose a client before issuing"
                              : "Assign the next number and lock the invoice")
                case .issued:
                    Button("Mark as paid", action: markPaid)
                    Button("Cancel invoice", role: .destructive) { isConfirmingCancel = true }
                case .paid, .cancelled:
                    EmptyView()
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportedPDF,
            contentType: .pdf,
            defaultFilename: InvoicePDF.suggestedFilename(for: invoice)
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            }
        }
        .confirmationDialog("Cancel this invoice?", isPresented: $isConfirmingCancel) {
            Button("Cancel invoice", role: .destructive) { invoice.status = .cancelled }
            Button("Keep invoice", role: .cancel) {}
        } message: {
            Text("The number stays in the sequence and the invoice is listed as cancelled. This cannot be undone.")
        }
        .alert(
            "Export failed",
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    /// The rendered page beside the form, the way Settings shows its sample.
    @ViewBuilder
    private var previewPane: some View {
        if let profile = profiles.first {
            InvoicePreview(invoice: invoice, profile: profile)
        } else {
            ProgressView()
        }
    }

    private var form: some View {
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
                          prompt: Text(verbatim: InvoiceTemplate.defaultReference(for: invoice)))
            }
            .disabled(isLocked)

            Section("Line items") {
                InvoiceLinesEditor(
                    lines: invoice.sortedLines,
                    showsVatRate: chargesVat,
                    remove: delete
                )
                Button("Add line item", systemImage: "plus", action: addLine)
            }
            .disabled(isLocked)

            Section("Summary") {
                if chargesVat {
                    LabeledContent("Net") {
                        Text(Formatting.money(invoice.totals.net, currencyCode: invoice.currencyCode))
                            .sensitiveValue()
                    }
                    ForEach(invoice.vatBreakdown.filter { $0.amounts.vat != 0 }, id: \.rate) { entry in
                        LabeledContent("VAT \(entry.rate.label)") {
                            Text(Formatting.money(entry.amounts.vat, currencyCode: invoice.currencyCode))
                                .sensitiveValue()
                        }
                    }
                }
                LabeledContent("Amount due") {
                    Text(Formatting.money(invoice.totals.gross, currencyCode: invoice.currencyCode))
                        .font(.headline)
                        .monospacedDigit()
                        .sensitiveValue()
                }
                ForEach(invoice.exemptionClauses, id: \.self) { clause in
                    Text(clause)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                TextField(
                    "Intro sentence",
                    text: $invoice.introOverride,
                    prompt: Text(profiles.first.map { InvoiceTemplate.intro(for: invoice, profile: $0) } ?? ""),
                    axis: .vertical
                )
                .lineLimit(1...3)
                TextField("Notes", text: $invoice.notes, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("Text")
            } footer: {
                Text("An empty intro sentence uses the template from Settings. Notes are printed below the clauses.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .disabled(isLocked)
        }
        .formStyle(.grouped)
    }

    private func exportPDF() {
        let profile = BusinessProfile.current(in: context)
        guard let data = InvoicePDF.render(invoice: invoice, profile: profile) else {
            exportError = String(localized: "The invoice could not be rendered.")
            return
        }
        exportedPDF = PDFFile(data: data)
        // Present on the next turn so the document is committed first —
        // setting both in one frame can hand the exporter a nil document.
        Task { isExporting = true }
    }

    private func addLine() {
        let profile = BusinessProfile.current(in: context)
        let line = InvoiceLine(
            vatRate: invoice.sortedLines.last?.vatRate ?? profile.defaultVatRate,
            sortIndex: (invoice.sortedLines.last?.sortIndex ?? -1) + 1
        )
        line.invoice = invoice
        context.insert(line)
    }

    /// Detach before deleting: the ForEach above is driven by `invoice.lines`,
    /// and it must not re-render an editor bound to a deleted model.
    private func delete(_ line: InvoiceLine) {
        guard !isLocked else { return }
        line.invoice = nil
        context.delete(line)
    }

    private func issue() {
        InvoiceNumbering.assign(to: invoice, in: context)
        // The bank reference most s.p. use is the invoice number under the
        // SI00 model; only fill it in when nothing was typed by hand.
        if invoice.paymentReference.isEmpty {
            invoice.paymentReference = InvoiceTemplate.defaultReference(for: invoice)
        }
        invoice.status = .issued
    }

    private func markPaid() {
        invoice.status = .paid
        invoice.paidDate = Date()
    }
}

/// The line items, each as its description on one row and its numbers on
/// the next, under a single header that names the numeric columns. The
/// columns are fixed widths shared by header and rows, so they line up
/// without a grid having to negotiate width with the form.
private struct InvoiceLinesEditor: View {
    let lines: [InvoiceLine]
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
                InvoiceLineRows(line: line, showsVatRate: showsVatRate) { remove(line) }
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
                TextField("Unit", text: $line.unit, prompt: Text(verbatim: "ura"))
                    .frame(width: LineColumns.unit)
                TextField("Price", value: $line.unitPrice, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: LineColumns.price)
                    .sensitiveValue()
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
                Text(Formatting.money(line.amounts.gross))
                    .monospacedDigit()
                    .sensitiveValue()
            }
        }
    }
}
