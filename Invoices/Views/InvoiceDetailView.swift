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

    var body: some View {
        Form {
            Section("Račun") {
                LabeledContent("Številka") {
                    Text(invoice.number.isEmpty ? "dodeljena ob izdaji" : invoice.number)
                        .foregroundStyle(invoice.number.isEmpty ? .secondary : .primary)
                }
                Picker("Stranka", selection: $invoice.client) {
                    Text("Brez stranke").tag(Client?.none)
                    ForEach(clients) { client in
                        Text(client.displayName).tag(Client?.some(client))
                    }
                }
                DatePicker("Datum izdaje", selection: $invoice.issueDate, displayedComponents: .date)
                DatePicker("Datum storitve", selection: $invoice.serviceDate, displayedComponents: .date)
                DatePicker("Rok plačila", selection: $invoice.dueDate, displayedComponents: .date)
                TextField("Kraj izdaje", text: $invoice.placeOfIssue)
                TextField("Sklic", text: $invoice.paymentReference)
            }
            .disabled(isLocked)

            Section("Postavke") {
                ForEach(invoice.sortedLines) { line in
                    InvoiceLineEditor(line: line, showsVatRate: chargesVat)
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

            Section("Opombe") {
                TextField("Opombe", text: $invoice.notes, axis: .vertical)
                    .lineLimit(3...8)
            }
            .disabled(isLocked)
        }
        .formStyle(.grouped)
        .navigationTitle(invoice.number.isEmpty ? "Osnutek računa" : invoice.number)
        .toolbar {
            ToolbarItem(placement: .status) {
                Label(invoice.status.label, systemImage: invoice.status.symbol)
                    .foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Izvozi PDF", systemImage: "square.and.arrow.down", action: exportPDF)
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
            exportError = "Računa ni bilo mogoče upodobiti."
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

    private func deleteLines(at offsets: IndexSet) {
        guard !isLocked else { return }
        let sorted = invoice.sortedLines
        for index in offsets {
            context.delete(sorted[index])
        }
    }

    private func issue() {
        InvoiceNumbering.assign(to: invoice, in: context)
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
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 4)
    }

    /// A caption above the control, so the column stays readable instead of
    /// wrapping an inline Form label into two lines.
    private struct Field<Content: View>: View {
        let title: String
        let width: CGFloat
        @ViewBuilder let content: Content

        init(_ title: String, width: CGFloat, @ViewBuilder content: () -> Content) {
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
