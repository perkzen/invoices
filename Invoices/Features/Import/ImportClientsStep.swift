import SwiftUI

/// The clients the file names and the ledger does not know. The file only
/// carries a name, and an issued invoice has to show an address and a tax
/// number, so they are asked for here — every field optional, since the
/// same fields wait under Clients afterwards.
struct ImportClientsStep: View {
    @Bindable var session: ImportSession

    var body: some View {
        Form {
            Section {
                Text(summary)
                    .foregroundStyle(.secondary)
            }
            ForEach($session.newClients) { $client in
                Section {
                    TextField("Address", text: $client.street)
                    TextField("Postal code", text: $client.postalCode)
                    TextField("City", text: $client.city)
                    TextField("Country (ISO code)", text: $client.countryCode)
                    SensitiveField("Tax number", text: $client.taxNumber)
                    SensitiveField("VAT ID", text: $client.vatID)
                } header: {
                    Label(client.name, systemImage: "person.badge.plus")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var summary: String {
        let count = session.newClients.count
        let invoices = session.plan.rows.filter { row in
            session.newClients.contains { $0.id == InvoiceImport.normalized(row.clientName) }
        }.count
        let clients = String(localized: "\(count) new clients")
        return String(localized: "The file names clients the ledger does not know yet: \(clients), with \(Formatting.invoiceCount(invoices)) between them. The spreadsheet gives only the name; fill in what the invoice must show, or leave it for later under Clients.")
    }
}
