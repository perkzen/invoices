import SwiftUI

struct ClientDetailView: View {
    @Bindable var client: Client

    var body: some View {
        Form {
            // The logo lives in the first section's header rather than in a
            // row: a grouped form boxes every row, and headers share the
            // sections' left edge, so the plate lines up with the form
            // without a frame around it.
            Section {
                TextField("Name", text: $client.name)
                TextField("Address", text: $client.street)
                TextField("Postal code", text: $client.postalCode)
                TextField("City", text: $client.city)
                TextField("Country (ISO code)", text: $client.countryCode)
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Logo")
                    ImageWell(data: $client.logoData)
                    Text("Shown next to the client in lists. Invoices print your own logo, never the client's.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Details")
                        .padding(.top, 16)
                }
            }
            Section("Tax details") {
                SensitiveField("Tax number", text: $client.taxNumber)
                SensitiveField("VAT ID", text: $client.vatID)
            }
            Section("Other") {
                TextField("Email", text: $client.email)
                Stepper(
                    "Payment term: \(client.defaultPaymentTermDays) days",
                    value: $client.defaultPaymentTermDays,
                    in: 0...120
                )
                MessageEditor("Notes", text: $client.notes, lines: 5)
            }
            if !client.issuedInvoices.isEmpty {
                Section("Invoices") {
                    LabeledContent("Invoiced") {
                        Text(Formatting.invoiceCount(client.issuedInvoices.count))
                    }
                    LabeledContent("Outstanding") {
                        Text(Formatting.money(client.outstandingTotal))
                            .sensitiveValue()
                            .monospacedDigit()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(client.displayName)
        .toolbar {
            // A three-column window shows only the list's title, so the
            // editor names its client here — text alone, like the invoice
            // editor's chip; the logo is already large at the top of the form.
            ToolbarItem(placement: .principal) {
                Text(client.displayName)
                    .font(.headline)
            }
            // A title, not a button: no glass capsule around it.
            .sharedBackgroundVisibility(.hidden)
        }
    }
}
