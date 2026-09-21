import SwiftData
import SwiftUI

/// The invoice list column. Deleting is offered everywhere a Mac user looks
/// for it: the trash in the toolbar, the ⌫ key, and the context menu — and
/// always for the selected row, never for a row under the pointer. The rule
/// on what may go comes from the ledger; the list only asks.
struct InvoiceListView: View {
    @Binding var selection: PersistentIdentifier?

    @Environment(\.modelContext) private var context
    @Environment(\.importSpreadsheet) private var importSpreadsheet
    @Query(sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)])
    private var invoices: [Invoice]

    @State private var pendingDelete: Invoice?
    @State private var searchText = ""
    @State private var filter: StatusFilter = .all

    private var ledger: Ledger { Ledger(context) }

    private var selected: Invoice? {
        invoices.first { $0.persistentModelID == selection }
    }

    private var shown: [Invoice] {
        invoices.filter { filter.matches($0) && matchesSearch($0) }
    }

    var body: some View {
        Group {
            if invoices.isEmpty {
                ContentUnavailableView {
                    Label("No invoices", systemImage: "doc.text")
                } description: {
                    Text("Create your first draft invoice, or bring in the ones you issued before from a spreadsheet.")
                } actions: {
                    Button("New invoice", action: newInvoice)
                    if let importSpreadsheet {
                        Button("Import from a spreadsheet…") { importSpreadsheet() }
                    }
                }
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(selection: $selection) {
                    ForEach(shown) { invoice in
                        InvoiceRow(invoice: invoice)
                            .tag(invoice.persistentModelID)
                            .contextMenu { deleteMenu(for: invoice) }
                    }
                }
                .onDeleteCommand { requestDelete(selected) }
            }
        }
        .navigationTitle("Invoices")
        .searchable(text: $searchText, prompt: "Number or client")
        .deletionConfirmation("Delete draft?", item: $pendingDelete) { _ in
            Text("The draft and all of its line items will be permanently deleted.")
        } perform: { invoice in
            delete(invoice)
        }
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $filter) {
                    ForEach(StatusFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .help("Show only invoices in one state")
            }
            // The picker draws its own pop-up control, spaced like every
            // other pop-up; the toolbar's glass around it only crowded it.
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem {
                Button("Delete draft", systemImage: "trash") { requestDelete(selected) }
                    .disabled(selected.map { ledger.deletionProblem(for: $0) != nil } ?? true)
                    .help(Text(verbatim: deleteHelp))
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New invoice", systemImage: "plus", action: newInvoice)
                    .keyboardShortcut("n")
                    .help("New draft invoice")
            }
        }
    }

    private func matchesSearch(_ invoice: Invoice) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return invoice.number.localizedStandardContains(query)
            || (invoice.client?.name.localizedStandardContains(query) ?? false)
    }

    private var deleteHelp: String {
        guard let selected else { return String(localized: "Select a draft to delete it") }
        return ledger.deletionProblem(for: selected)?.message ?? String(localized: "Delete draft")
    }

    private func newInvoice() {
        let invoice = ledger.newDraft()
        // Save first: an unsaved model carries a temporary identifier that
        // autosave replaces, which would drop the selection a moment later.
        try? context.save()
        // A fresh draft is the one thing the user wants to look at next.
        filter = .all
        searchText = ""
        selection = invoice.persistentModelID
    }

    private func requestDelete(_ invoice: Invoice?) {
        guard let invoice, ledger.deletionProblem(for: invoice) == nil else { return }
        pendingDelete = invoice
    }

    @ViewBuilder
    private func deleteMenu(for invoice: Invoice) -> some View {
        if let problem = ledger.deletionProblem(for: invoice) {
            Text(verbatim: problem.message)
        } else {
            Button("Delete draft", systemImage: "trash", role: .destructive) {
                requestDelete(invoice)
            }
        }
    }

    private func delete(_ invoice: Invoice) {
        // Drop the selection first so the editor lets go of the model
        // before it is gone.
        if selection == invoice.persistentModelID { selection = nil }
        try? ledger.delete(invoice)
    }
}

/// The states the list can be narrowed to. "Open" is the money still out:
/// issued and not yet paid.
private enum StatusFilter: String, CaseIterable, Identifiable {
    case all, drafts, open, paid, cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All invoices")
        case .drafts: String(localized: "Drafts")
        case .open: String(localized: "Open")
        case .paid: String(localized: "invoiceFilter.paid", defaultValue: "Paid")
        case .cancelled: String(localized: "Cancelled")
        }
    }

    func matches(_ invoice: Invoice) -> Bool {
        switch self {
        case .all: true
        case .drafts: invoice.status == .draft
        case .open: invoice.status == .issued
        case .paid: invoice.status == .paid
        case .cancelled: invoice.status == .cancelled
        }
    }
}

private struct InvoiceRow: View {
    let invoice: Invoice

    var body: some View {
        HStack(spacing: 10) {
            ClientAvatar(client: invoice.client, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if invoice.number.isEmpty {
                        Text("Draft")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(invoice.number)
                            .font(.headline)
                            .monospacedDigit()
                        InvoiceStatusBadge(invoice: invoice)
                    }
                }
                Text(invoice.client?.displayName ?? String(localized: "No client"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(Formatting.money(invoice.totals.gross, currencyCode: invoice.currencyCode))
                    .sensitiveValue()
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .strikethrough(invoice.status == .cancelled)
                Text(Formatting.date(invoice.issueDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 3)
    }
}
