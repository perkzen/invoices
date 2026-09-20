import SwiftData
import SwiftUI

struct InvoiceDetailView: View {
    @Bindable var invoice: Invoice

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Client.name)]) private var clients: [Client]

    @State private var export: FileExport?
    @State private var exportError: String?
    @State private var showsPreview = true

    private var ledger: Ledger { Ledger(context) }
    private var isLocked: Bool { !invoice.status.isEditable }
    private var issueProblem: Ledger.IssueProblem? { ledger.issueProblem(for: invoice) }

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
                ForEach(invoice.sortedLines) { line in
                    InvoiceLineEditor(line: line, currencyCode: invoice.currencyCode, showsVatRate: printed.chargesVat) {
                        ledger.removeLine(line)
                    }
                }
                .onDelete(perform: removeLines)

                Button("Add line item", systemImage: "plus", action: addLine)
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
                        .font(.headline)
                        .monospacedDigit()
                        .sensitiveValue()
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
                Text("An empty intro sentence uses the template from Settings. Notes are printed below the clauses.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .disabled(isLocked)
        }
        .formStyle(.grouped)
        .inspector(isPresented: $showsPreview) {
            InvoicePreview(printed: printed)
                .inspectorColumnWidth(min: 340, ideal: 440, max: 760)
        }
        .navigationTitle(invoice.number.isEmpty ? String(localized: "Draft invoice") : invoice.number)
        .toolbar {
            ToolbarItem(placement: .status) {
                Label(invoice.status.label, systemImage: invoice.status.symbol)
                    .foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Export PDF", systemImage: "square.and.arrow.down") { exportPDF(printed) }
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
                        .help(issueProblem.map { Text(verbatim: $0.message) } ?? Text("Issue invoice"))
                case .issued:
                    Button("Mark as paid") { ledger.markPaid(invoice) }
                    Button("Cancel invoice", role: .destructive) { ledger.cancel(invoice) }
                case .paid, .cancelled:
                    EmptyView()
                }
            }
        }
        .fileExport($export)
        .errorAlert("Export failed", message: $exportError)
    }

    private func exportPDF(_ printed: PrintedInvoice) {
        guard let data = InvoicePDF.render(printed) else {
            exportError = String(localized: "The invoice could not be rendered.")
            return
        }
        export = .pdf(data, named: printed.suggestedFilename)
    }

    private func addLine() {
        ledger.addLine(to: invoice)
    }

    private func removeLines(at offsets: IndexSet) {
        let sorted = invoice.sortedLines
        for index in offsets {
            ledger.removeLine(sorted[index])
        }
    }

    /// The button is disabled while the ledger has an objection, so the
    /// throw cannot reach here from the toolbar.
    private func issue() {
        try? ledger.issue(invoice)
    }
}

private struct InvoiceLineEditor: View {
    @Bindable var line: InvoiceLine
    let currencyCode: String
    let showsVatRate: Bool
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Description", text: $line.itemDescription)
                .labelsHidden()

            HStack(alignment: .bottom, spacing: 12) {
                Field("Quantity", width: 70) {
                    TextField("", value: $line.quantity, format: .number)
                }
                Field("Unit", width: 60) {
                    TextField("", text: $line.unit)
                }
                Field("Price", width: 90) {
                    TextField("", value: $line.unitPrice, format: .number)
                        .sensitiveValue()
                }
                Field("Discount %", width: 70) {
                    TextField("", value: $line.discountPercent, format: .number)
                }
                if showsVatRate {
                    Field("VAT", width: 180) {
                        Picker("", selection: $line.vatRate) {
                            ForEach(VatRate.allCases) { rate in
                                Text(rate.label).tag(rate)
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Formatting.money(line.amounts.gross, currencyCode: currencyCode))
                        .monospacedDigit()
                        .sensitiveValue()
                }
                Button("Remove line item", systemImage: "trash", action: remove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 4)
    }

    /// A caption above the control, so the column stays readable instead of
    /// wrapping an inline Form label into two lines.
    private struct Field<Content: View>: View {
        let title: LocalizedStringKey
        let width: CGFloat
        @ViewBuilder let content: Content

        init(_ title: LocalizedStringKey, width: CGFloat, @ViewBuilder content: () -> Content) {
            self.title = title
            self.width = width
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                content
            }
            .frame(width: width)
        }
    }
}
