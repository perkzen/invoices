import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The ⌘, window. The same content also lives in the sidebar under
/// Nastavitve, so nobody has to know the shortcut to find it.
struct SettingsView: View {
    var body: some View {
        SettingsContent()
            .frame(width: 1040, height: 720)
    }
}

/// Nastavitve: the s.p. details and the invoice template, with a live
/// preview of a sample invoice so every change is seen where it lands.
struct SettingsContent: View {
    @Environment(\.modelContext) private var context
    @State private var profile: BusinessProfile?
    @State private var sample: SampleInvoice?

    var body: some View {
        Group {
            if let profile, let sample {
                HStack(spacing: 0) {
                    TabView {
                        Tab("Moj s.p.", systemImage: "building.2") {
                            BusinessProfileForm(profile: profile)
                        }
                        Tab("Predloga računa", systemImage: "doc.richtext") {
                            InvoiceTemplateForm(profile: profile)
                        }
                    }
                    .frame(width: 470)
                    Divider()
                    VStack(spacing: 0) {
                        Text("Predogled na vzorčnem računu")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(6)
                        InvoicePreview(invoice: sample.invoice, profile: profile)
                    }
                    .frame(minWidth: 400)
                }
                // The sample's lines carry the profile's default VAT rate, so
                // flipping the DDV toggle rebuilds it with the right rate.
                .onChange(of: profile.isVatRegistered) {
                    self.sample = try? SampleInvoice(matching: profile)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            if profile == nil {
                let current = BusinessProfile.current(in: context)
                profile = current
                sample = try? SampleInvoice(matching: current)
            }
        }
    }
}

private struct BusinessProfileForm: View {
    @Bindable var profile: BusinessProfile

    var body: some View {
        Form {
            Section {
                TextField("Naziv s.p.", text: $profile.name, prompt: Text("npr. Domen Perko, s.p."))
                TextField("Ime in priimek", text: $profile.signerName, prompt: Text("nosilec dejavnosti"))
                TextField("E-pošta", text: $profile.email)
                TextField("Telefon", text: $profile.phone)
            } header: {
                Text("Moj s.p.")
            } footer: {
                Text("Naziv se natisne v glavi računa, ime in priimek pod »Račun izdal«.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Naslov") {
                TextField("Ulica in hišna številka", text: $profile.street)
                TextField("Poštna številka", text: $profile.postalCode)
                TextField("Kraj", text: $profile.city)
                TextField("Država (ISO)", text: $profile.countryCode)
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
            Section("Bančni račun") {
                TextField("IBAN (TRR)", text: $profile.iban)
                TextField("Banka", text: $profile.bankName)
                TextField("BIC / SWIFT", text: $profile.bic)
                Stepper(
                    "Privzeti rok plačila: \(profile.defaultPaymentTermDays) dni",
                    value: $profile.defaultPaymentTermDays,
                    in: 0...120
                )
            }
            Section("Na računu") {
                TextField("Registracija (npr. AJPES)", text: $profile.registrationNote)
                TextField("Opomba v nogi", text: $profile.invoiceFooter, axis: .vertical)
                    .lineLimit(2...5)
            }
            LanguageSection()
        }
        .formStyle(.grouped)
    }
}

/// App language. macOS reads `AppleLanguages` once at launch, so a change
/// takes effect after a relaunch; the invoice PDF itself stays Slovenian.
private struct LanguageSection: View {
    @AppStorage("appLanguage") private var language = "system"
    @State private var needsRelaunch = false

    var body: some View {
        Section {
            Picker("Jezik aplikacije", selection: $language) {
                Text("Kot sistem").tag("system")
                Text(verbatim: "Slovenščina").tag("sl")
                Text(verbatim: "English").tag("en")
            }
            .onChange(of: language) { _, newValue in
                if newValue == "system" {
                    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                } else {
                    UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                }
                needsRelaunch = true
            }
        } header: {
            Text("Jezik")
        } footer: {
            Text("Velja za vmesnik aplikacije. Računi so vedno v slovenščini.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .alert("Sprememba jezika velja po ponovnem zagonu", isPresented: $needsRelaunch) {
            Button("Zapri aplikacijo") { NSApp.terminate(nil) }
            Button("Pozneje", role: .cancel) {}
        } message: {
            Text("Zapri in znova odpri Invoices, da se vmesnik prikaže v izbranem jeziku.")
        }
    }
}

/// Everything on the printed invoice that is the s.p.'s own: logo, tagline,
/// the three sentences, and the signature.
private struct InvoiceTemplateForm: View {
    @Bindable var profile: BusinessProfile

    var body: some View {
        Form {
            Section("Glava") {
                ImageWell(title: "Logotip", data: $profile.logoData)
                TextField("Dejavnost", text: $profile.activityLine,
                          prompt: Text("npr. IT STORITVE IN SVETOVANJE"))
            }
            Section {
                TextField("Uvodni stavek", text: $profile.introTemplate, axis: .vertical)
                    .lineLimit(1...3)
                TextField("Navodilo za plačilo", text: $profile.paymentNoteTemplate, axis: .vertical)
                    .lineLimit(1...3)
                TextField("Zaključni stavek", text: $profile.closingNote, axis: .vertical)
                    .lineLimit(1...3)
                DisclosureGroup("Oznake, ki se izpolnijo samodejno") {
                    ForEach(InvoiceTemplate.placeholders, id: \.token) { placeholder in
                        HStack {
                            Text(verbatim: placeholder.token).monospaced()
                            Spacer()
                            Text(placeholder.meaning).foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            } header: {
                Text("Besedilo")
            } footer: {
                Text("Uvodni stavek lahko na posameznem računu prepišeš. Navodilo za plačilo se izpiše le, če je vpisan IBAN.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                ImageWell(title: "Podpis", data: $profile.signatureData)
            } header: {
                Text("Podpis")
            } footer: {
                Text("Ime pod podpisom je »Ime in priimek« z zavihka Moj s.p.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Thumbnail plus choose/remove buttons for a stored bitmap.
private struct ImageWell: View {
    let title: LocalizedStringKey
    @Binding var data: Data?

    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Group {
                    if let image = data.flatMap(NSImage.init(data:)) {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 72, height: 44)
                .background(.white, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))

                Button("Izberi…") { isImporting = true }
                if data != nil {
                    Button("Odstrani", role: .destructive) { data = nil }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image, .pdf]
        ) { result in
            switch result {
            case .success(let url):
                load(url)
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert(
            "Slike ni bilo mogoče naložiti",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("V redu", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private func load(_ url: URL) {
        // The app is sandboxed; a picked file is readable only inside this scope.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? Data(contentsOf: url), let png = ImageData.normalized(raw) else {
            importError = String(localized: "Datoteka ni slika, ki bi jo znal prebrati.")
            return
        }
        data = png
    }
}

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

        let client = Client(name: "Vzorčno podjetje d.o.o.")
        client.street = "Slovenska cesta 55B"
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
            ("Računalniško programiranje", 1, 1075),
            ("Svetovanje in podpora", 4, 60),
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
