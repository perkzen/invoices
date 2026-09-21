import SwiftUI

/// What the import will write, row by row, and what it will leave out and
/// why. The one thing the sheet cannot supply — what the line item says —
/// is asked for underneath.
struct ImportReviewStep: View {
    @Bindable var session: ImportSession

    private var plan: InvoiceImport.Plan { session.plan }

    var body: some View {
        VStack(spacing: 0) {
            Summary(plan: plan, newClientCount: session.newClients.count)
            Divider()
            CandidateTable(candidates: plan.candidates, newClients: session.newClients, currencyCode: plan.currencyCode)
            Divider()
            Form {
                Section {
                    TextField("Line item description", text: $session.lineDescription)
                } footer: {
                    Text("The file lists one amount per invoice, so each is recorded with a single line item carrying this description. The invoices land issued, paid or cancelled as the file says, and cannot be edited afterwards.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(height: 118)
            .scrollDisabled(true)
        }
    }
}

/// The counts that decide whether to press Import.
private struct Summary: View {
    let plan: InvoiceImport.Plan
    let newClientCount: Int

    var body: some View {
        HStack(spacing: 20) {
            if plan.rows.isEmpty {
                Label("Nothing in the file can be recorded", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else {
                Label(Formatting.invoiceCount(plan.rows.count), systemImage: "doc.text")
                Label(years, systemImage: "calendar")
                if newClientCount > 0 {
                    Label("\(newClientCount) new clients", systemImage: "person.badge.plus")
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("TOTAL")
                        .foregroundStyle(.secondary)
                    Text(Formatting.money(plan.total, currencyCode: plan.currencyCode))
                        .sensitiveValue()
                        .monospacedDigit()
                }
                .font(.headline)
            }
            if !plan.skipped.isEmpty {
                if plan.rows.isEmpty { Spacer() }
                Label("\(plan.skipped.count) rows skipped", systemImage: "minus.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var years: String {
        plan.years.map(String.init).joined(separator: ", ")
    }
}

private struct CandidateTable: View {
    let candidates: [InvoiceImport.Candidate]
    let newClients: [InvoiceImport.NewClient]
    let currencyCode: String

    var body: some View {
        Table(candidates) {
            TableColumn("Row") { candidate in
                Text(verbatim: String(candidate.sourceRow))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 34, ideal: 38)
            .alignment(.trailing)

            TableColumn("Invoice no.") { candidate in
                Text(candidate.number.isEmpty ? "—" : candidate.number)
                    .monospacedDigit()
                    .fontWeight(candidate.row == nil ? .regular : .medium)
                    .foregroundStyle(candidate.row == nil ? .secondary : .primary)
            }
            .width(min: 76, ideal: 84)

            TableColumn("Client") { candidate in
                HStack(spacing: 6) {
                    Text(candidate.clientName.isEmpty ? "—" : candidate.clientName)
                        .foregroundStyle(candidate.row == nil ? .secondary : .primary)
                    if isNew(candidate) {
                        Text("new")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            .width(min: 130, ideal: 170)

            TableColumn("Date") { candidate in
                Text(candidate.row.map { Formatting.date($0.issueDate) } ?? "")
                    .monospacedDigit()
            }
            .width(min: 76, ideal: 84)

            TableColumn("Date of service") { candidate in
                Text(candidate.row.map { Formatting.period($0.serviceDate, to: $0.serviceDateEnd) } ?? "")
                    .monospacedDigit()
            }
            .width(min: 120, ideal: 160)

            TableColumn("Amount") { candidate in
                Text(candidate.row.map { Formatting.money($0.amount, currencyCode: currencyCode) } ?? "")
                    .sensitiveValue()
                    .monospacedDigit()
                    .strikethrough(candidate.row?.isCancelled ?? false)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 90, ideal: 104)
            .alignment(.trailing)

            TableColumn("Outcome") { candidate in
                outcome(of: candidate)
                    .lineLimit(1)
            }
            .width(min: 150, ideal: 190)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func isNew(_ candidate: InvoiceImport.Candidate) -> Bool {
        candidate.row != nil
            && newClients.contains { $0.id == InvoiceImport.normalized(candidate.clientName) }
    }

    /// One line per row saying what happens to it. Recorded rows name the
    /// status they land in; skipped rows name the reason.
    @ViewBuilder
    private func outcome(of candidate: InvoiceImport.Candidate) -> some View {
        switch candidate.outcome {
        case .imports(let row):
            switch row.status {
            case .paid:
                Label(String(localized: "Paid \(Formatting.date(row.paidDate ?? row.issueDate))"), systemImage: InvoiceStatus.paid.symbol)
            case .cancelled:
                Label(InvoiceStatus.cancelled.label, systemImage: InvoiceStatus.cancelled.symbol)
                    .foregroundStyle(.secondary)
            case .issued, .draft:
                Label("Issued, unpaid", systemImage: InvoiceStatus.issued.symbol)
            }
        case .skipped(let problem):
            Label(problem.message, systemImage: "minus.circle")
                .foregroundStyle(.secondary)
        }
    }
}
