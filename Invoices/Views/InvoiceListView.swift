import SwiftData
import SwiftUI

struct InvoiceListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)])
    private var invoices: [Invoice]

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
                        NavigationLink(value: invoice) {
                            InvoiceRow(invoice: invoice)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Računi")
        .navigationDestination(for: Invoice.self) { InvoiceDetailView(invoice: $0) }
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

    /// Only drafts may be deleted. An issued number has to stay in the
    /// sequence — removing it would leave an unexplainable gap.
    private func delete(at offsets: IndexSet) {
        for index in offsets where invoices[index].status.isEditable {
            context.delete(invoices[index])
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
