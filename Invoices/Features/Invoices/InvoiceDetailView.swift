import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct InvoiceDetailView: View {
    @Bindable var invoice: Invoice

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Client.name)]) private var clients: [Client]
    @Query private var profiles: [BusinessProfile]

    private var isLocked: Bool { !invoice.status.isEditable }
    /// A business that is not VAT registered never charges VAT, so the whole
    /// VAT apparatus stays out of the way until the toggle in Settings flips.
    private var chargesVat: Bool { profiles.first?.isVatRegistered ?? false }

    @State private var exportedPDF: PDFFile?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showsPreview = true

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
                ForEach(invoice.sortedLines) { line in
                    InvoiceLineEditor(line: line, showsVatRate: chargesVat) {
                        delete(line)
                    }
                }
                .onDelete(perform: deleteLines)

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
        .inspector(isPresented: $showsPreview) {
            Group {
                if let profile = profiles.first {
                    InvoicePreview(invoice: invoice, profile: profile)
                } else {
                    ProgressView()
                }
            }
            .inspectorColumnWidth(min: 340, ideal: 440, max: 760)
        }
        .task {
            // Guarantees the preview has a profile on a fresh install.
            _ = BusinessProfile.current(in: context)
        }
        .navigationTitle(invoice.number.isEmpty ? String(localized: "Draft invoice") : invoice.number)
        .toolbar {
            ToolbarItem(placement: .status) {
                Label(invoice.status.label, systemImage: invoice.status.symbol)
                    .foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Export PDF", systemImage: "square.and.arrow.down", action: exportPDF)
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
                case .issued:
                    Button("Mark as paid", action: markPaid)
                    Button("Cancel invoice", role: .destructive) { invoice.status = .cancelled }
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
        .alert(
            "Export failed",
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
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

    private func deleteLines(at offsets: IndexSet) {
        guard !isLocked else { return }
        let sorted = invoice.sortedLines
        for index in offsets {
            delete(sorted[index])
        }
    }

    private func issue() {
        InvoiceNumbering.assign(to: invoice, in: context)
        // The bank reference most sole traders use is the invoice number under the
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

private struct InvoiceLineEditor: View {
    @Bindable var line: InvoiceLine
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
                    Text(Formatting.money(line.amounts.gross))
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
