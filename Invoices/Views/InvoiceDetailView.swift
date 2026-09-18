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
            Section("Račun") {
                LabeledContent("Številka") {
                    Text(invoice.number.isEmpty ? String(localized: "dodeljena ob izdaji") : invoice.number)
                        .foregroundStyle(invoice.number.isEmpty ? .secondary : .primary)
                }
                Picker("Stranka", selection: $invoice.client) {
                    Text("Brez stranke").tag(Client?.none)
                    ForEach(clients) { client in
                        Text(client.displayName).tag(Client?.some(client))
                    }
                }
                DatePicker("Datum izdaje", selection: $invoice.issueDate, displayedComponents: .date)
                DatePicker(isPeriod.wrappedValue ? "Storitev od" : "Datum storitve",
                           selection: $invoice.serviceDate, displayedComponents: .date)
                Toggle("Storitev za obdobje", isOn: isPeriod)
                if invoice.serviceDateEnd != nil {
                    DatePicker(
                        "Storitev do",
                        selection: Binding(
                            get: { invoice.serviceDateEnd ?? invoice.serviceDate },
                            set: { invoice.serviceDateEnd = $0 }
                        ),
                        in: invoice.serviceDate...,
                        displayedComponents: .date
                    )
                }
                DatePicker("Rok plačila", selection: $invoice.dueDate, displayedComponents: .date)
                TextField("Kraj izdaje", text: $invoice.placeOfIssue)
                TextField("Sklic", text: $invoice.paymentReference,
                          prompt: Text(verbatim: InvoiceTemplate.defaultReference(for: invoice)))
            }
            .disabled(isLocked)

            Section("Postavke") {
                ForEach(invoice.sortedLines) { line in
                    InvoiceLineEditor(line: line, showsVatRate: chargesVat) {
                        delete(line)
                    }
                }
                .onDelete(perform: deleteLines)

                Button("Dodaj postavko", systemImage: "plus", action: addLine)
            }
            .disabled(isLocked)

            Section("Povzetek") {
                if chargesVat {
                    LabeledContent("Neto", value: Formatting.money(invoice.totals.net, currencyCode: invoice.currencyCode))
                    ForEach(invoice.vatBreakdown.filter { $0.amounts.vat != 0 }, id: \.rate) { entry in
                        LabeledContent("DDV \(entry.rate.label)", value: Formatting.money(entry.amounts.vat, currencyCode: invoice.currencyCode))
                    }
                }
                LabeledContent("Za plačilo") {
                    Text(Formatting.money(invoice.totals.gross, currencyCode: invoice.currencyCode))
                        .font(.headline)
                        .monospacedDigit()
                }
                ForEach(invoice.exemptionClauses, id: \.self) { clause in
                    Text(clause)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                TextField(
                    "Uvodni stavek",
                    text: $invoice.introOverride,
                    prompt: Text(profiles.first.map { InvoiceTemplate.intro(for: invoice, profile: $0) } ?? ""),
                    axis: .vertical
                )
                .lineLimit(1...3)
                TextField("Opombe", text: $invoice.notes, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("Besedilo")
            } footer: {
                Text("Prazen uvodni stavek uporabi predlogo iz Nastavitev. Opombe se natisnejo pod klavzulami.")
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
        .navigationTitle(invoice.number.isEmpty ? String(localized: "Osnutek računa") : invoice.number)
        .toolbar {
            ToolbarItem(placement: .status) {
                Label(invoice.status.label, systemImage: invoice.status.symbol)
                    .foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Izvozi PDF", systemImage: "square.and.arrow.down", action: exportPDF)
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle("Predogled", systemImage: "sidebar.trailing", isOn: $showsPreview)
                    .help("Pokaži ali skrij predogled računa")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                switch invoice.status {
                case .draft:
                    Button("Izdaj račun", action: issue)
                        .disabled(invoice.client == nil || invoice.lines.isEmpty)
                case .issued:
                    Button("Označi kot plačan", action: markPaid)
                    Button("Storniraj", role: .destructive) { invoice.status = .cancelled }
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
            "Izvoz ni uspel",
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
        ) {
            Button("V redu", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private func exportPDF() {
        let profile = BusinessProfile.current(in: context)
        guard let data = InvoicePDF.render(invoice: invoice, profile: profile) else {
            exportError = String(localized: "Računa ni bilo mogoče upodobiti.")
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

private struct InvoiceLineEditor: View {
    @Bindable var line: InvoiceLine
    let showsVatRate: Bool
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Opis storitve", text: $line.itemDescription)
                .labelsHidden()

            HStack(alignment: .bottom, spacing: 12) {
                Field("Količina", width: 70) {
                    TextField("", value: $line.quantity, format: .number)
                }
                Field("EM", width: 60) {
                    TextField("", text: $line.unit)
                }
                Field("Cena", width: 90) {
                    TextField("", value: $line.unitPrice, format: .number)
                }
                Field("Popust %", width: 70) {
                    TextField("", value: $line.discountPercent, format: .number)
                }
                if showsVatRate {
                    Field("DDV", width: 180) {
                        Picker("", selection: $line.vatRate) {
                            ForEach(VatRate.allCases) { rate in
                                Text(rate.label).tag(rate)
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Skupaj")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Formatting.money(line.amounts.gross))
                        .monospacedDigit()
                }
                Button("Odstrani postavko", systemImage: "trash", action: remove)
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
