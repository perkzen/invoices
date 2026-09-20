import SwiftUI

struct ClientDetailView: View {
    @Bindable var client: Client

    var body: some View {
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
        }
        .formStyle(.grouped)
        .navigationTitle(client.displayName)
    }
}
