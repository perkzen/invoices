import SwiftUI

struct ClientDetailView: View {
    @Bindable var client: Client

    var body: some View {
        Form {
            Section {
                ImageWell(title: "Logo", data: $client.logoData)
            } header: {
                Text("Logo")
            } footer: {
                Text("Shown next to the client in lists. Invoices print your own logo, never the client's.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Details") {
                TextField("Name", text: $client.name)
                TextField("Address", text: $client.street)
                TextField("Postal code", text: $client.postalCode)
                TextField("City", text: $client.city)
                TextField("Country (ISO code)", text: $client.countryCode)
            }
            Section("Tax details") {
                SensitiveField("Tax number (davčna številka)", text: $client.taxNumber)
                SensitiveField("VAT ID", text: $client.vatID)
            }
            Section("Other") {
                TextField("Email", text: $client.email)
                Stepper(
                    "Payment term: \(client.defaultPaymentTermDays) days",
                    value: $client.defaultPaymentTermDays,
                    in: 0...120
                )
                TextField("Notes", text: $client.notes, axis: .vertical)
                    .lineLimit(3...8)
            }
            if !client.issuedInvoices.isEmpty {
                Section("Invoices") {
                    LabeledContent("Invoiced") {
                        Text(Formatting.invoiceCount(client.issuedInvoices.count))
                    }
                    LabeledContent("Outstanding") {
                        Text(Formatting.money(client.outstandingTotal))
                            .monospacedDigit()
                            .sensitiveValue()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(client.displayName)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    ClientAvatar(client: client, size: 22)
                    Text(client.displayName)
                        .font(.headline)
                }
            }
        }
    }
}
