import Foundation
import SwiftData

/// A representative invoice for the settings preview. It lives in its own
/// in-memory container so it never touches the real numbering or store.
@MainActor
final class SampleInvoice {
    let container: ModelContainer
    let invoice: Invoice

    init(matching profile: BusinessProfile) throws {
        container = try ModelContainer(
            for: Invoice.self, InvoiceLine.self, Client.self, BusinessProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        // The sample is previewed on the printed invoice, so it reads in the
        // document's language, not the interface's.
        let client = Client(name: DocumentText.string("Sample Company Ltd."))
        client.street = DocumentText.string("1 Sample Street")
        client.postalCode = "1000"
        client.city = "Ljubljana"
        client.taxNumber = "12345678"
        context.insert(client)

        let calendar = Calendar.current
        let today = Date()
        let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfThisMonth) ?? today
        let endOfLastMonth = calendar.date(byAdding: .day, value: -1, to: startOfThisMonth) ?? today
        let year = calendar.component(.year, from: today)

        invoice = Invoice(
            number: InvoiceNumbering.format(year: year, sequence: 8),
            year: year, sequence: 8,
            issueDate: today, serviceDate: startOfLastMonth,
            dueDate: calendar.date(byAdding: .day, value: profile.defaultPaymentTermDays, to: today) ?? today
        )
        invoice.serviceDateEnd = endOfLastMonth
        invoice.status = .issued
        invoice.client = client
        invoice.placeOfIssue = profile.city.isEmpty ? "Ljubljana" : profile.city
        invoice.paymentReference = "SI00 \(invoice.number)"
        context.insert(invoice)

        let items: [(String, Decimal, Decimal)] = [
            (DocumentText.string("Software development"), 1, 1075),
            (DocumentText.string("Consulting and support"), 4, 60),
        ]
        for (index, item) in items.enumerated() {
            let line = InvoiceLine(
                itemDescription: item.0, quantity: item.1, unitPrice: item.2,
                vatRate: profile.defaultVatRate, sortIndex: index
            )
            line.invoice = invoice
            context.insert(line)
        }
    }
}
