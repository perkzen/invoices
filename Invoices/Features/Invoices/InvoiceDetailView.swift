import SwiftData
import SwiftUI

struct InvoiceDetailView: View {
    @Bindable var invoice: Invoice

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: [SortDescriptor(\Client.name)]) private var clients: [Client]

    @State private var export: FileExport?
    @State private var exportError: String?
    @State private var emailError: String?
    @State private var showsPreview = true
    @State private var isConfirmingCancel = false
    @State private var isMarkingPaid = false
    @State private var isOfferingEmail = false
    @AppStorage(EmailComposer.Client.storageKey) private var emailClient = EmailComposer.Client.appleMail

    private var ledger: Ledger { Ledger(context) }
    private var isLocked: Bool { !invoice.status.isEditable }
    private var issueProblem: Ledger.IssueProblem? { ledger.issueProblem(for: invoice) }
    /// Why the invoice cannot go out by email right now, or nil when it can.
    private var emailProblem: String? {
        if invoice.status.isEditable { return String(localized: "Issue the invoice before sending it") }
        if clientEmail.isEmpty { return String(localized: "The client has no email address") }
        return nil
    }
    private var clientEmail: String {
        invoice.client?.email.trimmingCharacters(in: .whitespaces) ?? ""
    }
    private var title: String {
        invoice.number.isEmpty ? String(localized: "Draft invoice") : invoice.number
    }

    /// Pick the status, and the ledger's questions — the payment date, the
    /// cancellation warning — are asked before it changes.
    private var statusPicker: some View {
        Picker("Status", selection: requestedStatus) {
            ForEach(reachableStatuses) { status in
                Image(nsImage: StatusCapsuleImage.image(for: status, in: colorScheme))
                    .tag(status)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Change the status of the invoice")
    }

    /// The states the pop-up offers from where the invoice stands. Paid
    /// goes back to issued, never straight to cancelled; cancelled is final.
    private var reachableStatuses: [InvoiceStatus] {
        switch invoice.status {
        case .issued: [.issued, .paid, .cancelled]
        case .paid: [.issued, .paid]
        case .draft, .cancelled: [invoice.status]
        }
    }

    /// The pop-up's selection. Reading it is the invoice's status; choosing
    /// a status asks the ledger for the change, or asks the user first. The
    /// status itself moves only once that is answered, so a dismissed sheet
    /// leaves the pop-up where it was.
    private var requestedStatus: Binding<InvoiceStatus> {
        Binding(
            get: { invoice.status },
            set: { status in
                switch (invoice.status, status) {
                case (.issued, .paid): isMarkingPaid = true
                case (.issued, .cancelled): isConfirmingCancel = true
                case (.paid, .issued): ledger.markUnpaid(invoice)
                default: break
                }
            }
        )
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

        form(printed)
        // The rendered page in an inspector: a pane of the window with the
        // toolbar broken at its edge, the way Pages and Xcode hang theirs,
        // rather than a split view drawing its seam up through the toolbar
        // between the title and the tools.
        .inspector(isPresented: $showsPreview) {
            InvoicePreview(printed: printed)
                .inspectorColumnWidth(min: 280, ideal: 340, max: 520)
        }
        .navigationTitle(title)
        .toolbar {
            // A three-column window shows only the list's title, so the
            // editor names its own invoice here. The status is the first
            // row of the form, not repeated up here.
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.headline)
                    .monospacedDigit()
            }
            // A title, not a button: no glass capsule around it.
            .sharedBackgroundVisibility(.hidden)
            ToolbarItemGroup(placement: .primaryAction) {
                // Issuing is the one change with reasons it may be blocked,
                // so it is a button that can be disabled and say why, among
                // the tools. The other changes of status are the pop-up at
                // the top of the form.
                if invoice.status == .draft {
                    // The seal: the paper plane is sending, which comes after.
                    Button("Issue invoice", systemImage: "checkmark.seal", action: issue)
                        .disabled(issueProblem != nil)
                        .help(issueProblem.map { Text(verbatim: $0.message) }
                              ?? Text("Issue the invoice: assign the next number and lock it"))
                }
                Button("Export PDF", systemImage: "square.and.arrow.up") { exportPDF(printed) }
                    .help("Save the invoice as a PDF")
                Button("Send by email", systemImage: "paperplane", action: sendEmail)
                    .disabled(emailProblem != nil)
                    .help(emailProblem.map { Text(verbatim: $0) }
                          ?? Text("Open a new email to the client with the invoice PDF attached"))
                Toggle("Preview", systemImage: "sidebar.trailing", isOn: $showsPreview)
                    .help("Show or hide the invoice preview")
            }
        }
        .sheet(isPresented: $isMarkingPaid) {
            PaymentDateSheet { date in ledger.markPaid(invoice, on: date) }
        }
        .confirmationDialog("Cancel this invoice?", isPresented: $isConfirmingCancel) {
            Button("Cancel invoice", role: .destructive) { ledger.cancel(invoice) }
            Button("Keep invoice", role: .cancel) {}
        } message: {
            Text("The number stays in the sequence and the invoice is listed as cancelled. This cannot be undone.")
        }
        // Offered once, right after issuing — the moment the invoice is
        // final and the client is waiting for it. "Later" is the toolbar button.
        .confirmationDialog("Send the invoice by email?", isPresented: $isOfferingEmail) {
            Button("Send now", action: sendEmail)
            Button("Later", role: .cancel) {}
        } message: {
            Text("The invoice is issued. You can send it to \(clientEmail) now, or later with the Send by email button.")
        }
        .fileExport($export)
        .errorAlert("Export failed", message: $exportError)
        .errorAlert("The email could not be prepared", message: $emailError)
    }

    private func form(_ printed: PrintedInvoice) -> some View {
        Form {
            // Once issued, the state comes first: it is the one thing left
            // to change on a locked invoice. A draft has nothing to say
            // here; its way forward is the toolbar's button.
            if invoice.status != .draft {
                Section {
                    LabeledContent("Status") {
                        if invoice.status == .cancelled {
                            InvoiceStatusBadge(invoice: invoice)
                        } else {
                            // Overdue is the badge's own word, not a state
                            // the pop-up can offer, so it stands beside it.
                            if invoice.isOverdue {
                                InvoiceStatusBadge(invoice: invoice)
                            }
                            statusPicker
                        }
                    }
                    if invoice.status == .paid, let paidDate = invoice.paidDate {
                        LabeledContent("Paid on", value: Formatting.date(paidDate))
                    }
                }
            }

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
        guard (try? ledger.issue(invoice)) != nil else { return }
        // Nothing to offer without an address; the button's help says why.
        if !clientEmail.isEmpty { isOfferingEmail = true }
    }

    /// Built from the models here rather than handed the `printed` the body
    /// made: the dialog's "Send now" fires after issuing changed the number.
    private func sendEmail() {
        let profile = ledger.profile
        let printed = PrintedInvoice.make(invoice: invoice, profile: profile)
        guard let data = InvoicePDF.render(printed) else {
            emailError = String(localized: "The invoice could not be rendered.")
            return
        }
        let email = InvoiceEmail.make(invoice: invoice, profile: profile, printed: printed)
        do {
            try EmailComposer.compose(email, attachment: data, via: emailClient)
        } catch {
            emailError = error.message
        }
    }
}

/// Asks when the payment arrived before the invoice is marked paid. The
/// date lives here, not in the editor, so every opening starts from today
/// instead of whatever was picked last time.
private struct PaymentDateSheet: View {
    let confirm: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mark as paid")
                .font(.headline)
            DatePicker("Paid on", selection: $date, in: ...Date(), displayedComponents: .date)
            Text("The date is listed in the year overview. Mark the invoice unpaid to change it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Mark as paid") {
                    confirm(date)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
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
