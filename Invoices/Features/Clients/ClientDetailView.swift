import SwiftUI

struct ClientDetailView: View {
    @Bindable var client: Client

    var body: some View {
        VStack(spacing: 0) {
            // The logo sits above the form, not in it: a grouped form boxes
            // every row, and a plate in a box is a picture in a frame in a
            // frame.
            HStack(alignment: .top, spacing: 16) {
                ImageWell(data: $client.logoData)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Logo")
                        .font(.headline)
                    Text("Shown next to the client in lists. Invoices print your own logo, never the client's.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Form {
                Section("Details") {
                    TextField("Name", text: $client.name)
                    TextField("Address", text: $client.street)
                    TextField("Postal code", text: $client.postalCode)
                    TextField("City", text: $client.city)
                    TextField("Country (ISO code)", text: $client.countryCode)
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
        }
        .navigationTitle(client.displayName)
        .toolbar {
            // A three-column window shows only the list's title, so the
            // editor names its client here — text alone, like the invoice
            // editor's chip; the logo is already large above the form.
            ToolbarItem(placement: .principal) {
                Text(client.displayName)
                    .font(.headline)
            }
            // A title, not a button: no glass capsule around it.
            .sharedBackgroundVisibility(.hidden)
        }
    }
}
