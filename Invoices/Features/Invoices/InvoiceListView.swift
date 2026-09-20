import SwiftData
import SwiftUI

struct InvoiceListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)])
    private var invoices: [Invoice]
    @State private var pendingDelete: Invoice?

    var body: some View {
        Group {
            if invoices.isEmpty {
                ContentUnavailableView {
                    Label("Ni računov", systemImage: "doc.text")
                } description: {
                    Text("Ustvari prvi osnutek računa.")
                } actions: {
                    Button("Nov račun", action: newInvoice)
                }
            } else {
                List {
                    ForEach(invoices) { invoice in
                        InvoiceRow(invoice: invoice) {
                            pendingDelete = invoice
                        }
                        .contextMenu { deleteMenu(for: invoice) }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Računi")
        .navigationDestination(for: Invoice.self) { InvoiceDetailView(invoice: $0) }
        .confirmationDialog(
            "Izbrišem osnutek?",
            isPresented: isConfirming,
            presenting: pendingDelete
        ) { invoice in
            Button("Izbriši", role: .destructive) { delete(invoice) }
            Button("Prekliči", role: .cancel) {}
        } message: { _ in
            Text("Osnutek in vse njegove postavke bodo trajno izbrisani.")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: newInvoice) {
                    Label("Nov račun", systemImage: "plus")
                }
                .keyboardShortcut("n")
            }
        }
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
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    @ViewBuilder
    private func deleteMenu(for invoice: Invoice) -> some View {
        if invoice.status.isEditable {
            Button("Izbriši osnutek", systemImage: "trash", role: .destructive) {
                pendingDelete = invoice
            }
        } else {
            Text("Izdanega računa ni mogoče izbrisati")
        }
    }

    private func delete(_ invoice: Invoice) {
        pendingDelete = nil
        if invoice.status.isEditable {
            context.delete(invoice)
        }
    }

    /// Only drafts may be deleted. An issued number has to stay in the
    /// sequence — removing it would leave an unexplainable gap.
    private func delete(at offsets: IndexSet) {
        for index in offsets where invoices[index].status.isEditable {
            context.delete(invoices[index])
        }
    }
}

/// The trash only appears under the pointer — a permanently visible destructive
/// control on every row is louder than the action deserves.
private struct InvoiceRow: View {
    let invoice: Invoice
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink(value: invoice) { content }

            Button("Izbriši osnutek", systemImage: "trash", action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .tint(.red)
                .disabled(!invoice.status.isEditable)
                .help(invoice.status.isEditable
                      ? "Izbriši osnutek"
                      : "Izdanega računa ni mogoče izbrisati")
                .opacity(isHovering ? 1 : 0)
        }
        .onHover { isHovering = $0 }
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: invoice.status.symbol)
                .foregroundStyle(invoice.isOverdue ? .red : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.number.isEmpty ? String(localized: "Osnutek") : invoice.number)
                    .font(.headline)
                Text(invoice.client?.displayName ?? String(localized: "Brez stranke"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatting.money(invoice.totals.gross, currencyCode: invoice.currencyCode))
                    .monospacedDigit()
                Text(Formatting.date(invoice.issueDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
