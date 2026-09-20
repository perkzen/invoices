import SwiftData
import SwiftUI

struct InvoiceListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)])
    private var invoices: [Invoice]
    @State private var pendingDelete: Invoice?

    private var ledger: Ledger { Ledger(context) }

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
            } else {
                List {
                    ForEach(invoices) { invoice in
                        DeletableRow(
                            "Delete draft",
                            blocker: ledger.deletionProblem(for: invoice)?.message,
                            onDelete: { pendingDelete = invoice }
                        ) {
                            NavigationLink(value: invoice) { InvoiceRow(invoice: invoice) }
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Invoices")
        .navigationDestination(for: Invoice.self) { InvoiceDetailView(invoice: $0) }
        .deletionConfirmation("Delete draft?", item: $pendingDelete) { _ in
            Text("The draft and all of its line items will be permanently deleted.")
        } perform: { invoice in
            try? ledger.delete(invoice)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: newInvoice) {
                    Label("New invoice", systemImage: "plus")
                }
                .keyboardShortcut("n")
            }
        }
    }

    private func newInvoice() {
        ledger.newDraft()
    }

    /// The swipe path asks no question, but the rule still holds: the
    /// ledger refuses an issued invoice.
    private func delete(at offsets: IndexSet) {
        for index in offsets {
            try? ledger.delete(invoices[index])
        }
    }
}

private struct InvoiceRow: View {
    let invoice: Invoice

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: invoice.status.symbol)
                .foregroundStyle(invoice.isOverdue ? .red : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.number.isEmpty ? String(localized: "Draft") : invoice.number)
                    .font(.headline)
                Text(invoice.client?.displayName ?? String(localized: "No client"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatting.money(invoice.totals.gross, currencyCode: invoice.currencyCode))
                    .monospacedDigit()
                    .sensitiveValue()
                Text(Formatting.date(invoice.issueDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
