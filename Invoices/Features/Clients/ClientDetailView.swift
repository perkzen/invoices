import SwiftUI

struct ClientDetailView: View {
    @Bindable var client: Client

    var body: some View {
        Form {
            Section("Podatki") {
                TextField("Naziv", text: $client.name)
                TextField("Naslov", text: $client.street)
                TextField("Poštna številka", text: $client.postalCode)
                TextField("Kraj", text: $client.city)
                TextField("Država (ISO)", text: $client.countryCode)
            }
            Section("Davčni podatki") {
                SensitiveField("Davčna številka", text: $client.taxNumber)
                SensitiveField("ID za DDV", text: $client.vatID)
            }
            Section("Ostalo") {
                TextField("E-pošta", text: $client.email)
                Stepper(
                    "Rok plačila: \(client.defaultPaymentTermDays) dni",
                    value: $client.defaultPaymentTermDays,
                    in: 0...120
                )
                TextField("Opombe", text: $client.notes, axis: .vertical)
                    .lineLimit(3...8)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(client.displayName)
    }
}
