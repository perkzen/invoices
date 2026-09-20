import SwiftData
import SwiftUI

/// The invoice list column. Deleting is offered everywhere a Mac user looks
/// for it: the trash in the toolbar, the ⌫ key, and the context menu — and
/// always for the selected row, never for a row under the pointer.
struct InvoiceListView: View {
    @Binding var selection: PersistentIdentifier?

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)])
    private var invoices: [Invoice]

    @State private var pendingDelete: Invoice?
    @State private var searchText = ""
    @State private var filter: StatusFilter = .all

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
                    Text("Create your first draft invoice.")
                } actions: {
                    Button("New invoice", action: newInvoice)
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
        .confirmationDialog(
            "Delete draft?",
            isPresented: isConfirming,
            presenting: pendingDelete
        ) { invoice in
            Button("Delete", role: .destructive) { delete(invoice) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The draft and all of its line items will be permanently deleted.")
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
            ToolbarItem {
                Button("Delete draft", systemImage: "trash") { requestDelete(selected) }
                    .disabled(!(selected?.status.isEditable ?? false))
                    .help(deleteHelp)
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
        return selected.status.isEditable
            ? String(localized: "Delete draft")
            : String(localized: "An issued invoice cannot be deleted")
    }

    private func newInvoice() {
        let profile = BusinessProfile.current(in: context)
        let today = Date()
        let due = Calendar.current.date(
            byAdding: .day, value: profile.defaultPaymentTermDays, to: today
        ) ?? today
        let invoice = Invoice(issueDate: today, serviceDate: today, dueDate: due)
        invoice.placeOfIssue = profile.city
        context.insert(invoice)

        let line = InvoiceLine(vatRate: profile.defaultVatRate)
        line.invoice = invoice
        context.insert(line)

        // Save first: an unsaved model carries a temporary identifier that
        // autosave replaces, which would drop the selection a moment later.
        try? context.save()
        // A fresh draft is the one thing the user wants to look at next.
        filter = .all
        searchText = ""
        selection = invoice.persistentModelID
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    /// Only drafts may be deleted. An issued number has to stay in the
    /// sequence — removing it would leave an unexplainable gap.
    private func requestDelete(_ invoice: Invoice?) {
        guard let invoice, invoice.status.isEditable else { return }
        pendingDelete = invoice
    }

    @ViewBuilder
    private func deleteMenu(for invoice: Invoice) -> some View {
        if invoice.status.isEditable {
            Button("Delete draft", systemImage: "trash", role: .destructive) {
                requestDelete(invoice)
            }
        } else {
            Text("An issued invoice cannot be deleted")
        }
    }

    private func delete(_ invoice: Invoice) {
        pendingDelete = nil
        guard invoice.status.isEditable else { return }
        // Drop the selection first so the editor lets go of the model
        // before it is gone.
        if selection == invoice.persistentModelID { selection = nil }
        context.delete(invoice)
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
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .strikethrough(invoice.status == .cancelled)
                    .sensitiveValue()
                Text(Formatting.date(invoice.issueDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 3)
    }
}
