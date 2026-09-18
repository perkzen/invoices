import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var profile: BusinessProfile?

    var body: some View {
        Group {
            if let profile {
                BusinessProfileForm(profile: profile)
            } else {
                ProgressView()
            }
        }
        .task {
            if profile == nil {
                profile = BusinessProfile.current(in: context)
            }
        }
        .frame(width: 480, height: 520)
    }
}

private struct BusinessProfileForm: View {
    @Bindable var profile: BusinessProfile

    var body: some View {
        Form {
            Section("Moj s.p.") {
                TextField("Naziv", text: $profile.name)
                TextField("Naslov", text: $profile.street)
                TextField("Poštna številka", text: $profile.postalCode)
                TextField("Kraj", text: $profile.city)
            }
            Section {
                TextField("Davčna številka", text: $profile.taxNumber)
                Toggle("Zavezanec za DDV", isOn: $profile.isVatRegistered)
                if profile.isVatRegistered {
                    TextField("ID za DDV", text: $profile.vatID)
                }
                Toggle("Normiranec (normirani odhodki)", isOn: $profile.isFlatRate)
            } header: {
                Text("Davčni status")
            } footer: {
                Text(profile.isVatRegistered
                     ? "Računi prikazujejo stopnje DDV in obračun po stopnjah."
                     : "Računi ne obračunavajo DDV in nosijo klavzulo po 94. členu ZDDV-1. Vklopi stikalo, če se registriraš za DDV.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Section("Plačilo") {
                TextField("IBAN", text: $profile.iban)
                TextField("Banka", text: $profile.bankName)
                TextField("BIC / SWIFT", text: $profile.bic)
                Stepper(
                    "Privzeti rok plačila: \(profile.defaultPaymentTermDays) dni",
                    value: $profile.defaultPaymentTermDays,
                    in: 0...120
                )
            }
            Section("Na računu") {
                TextField("Opomba v nogi", text: $profile.invoiceFooter, axis: .vertical)
                    .lineLimit(2...5)
                TextField("Registracija (npr. AJPES)", text: $profile.registrationNote)
            }
        }
        .formStyle(.grouped)
    }
}
