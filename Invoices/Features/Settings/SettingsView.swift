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
                        Tab("My s.p.", systemImage: "building.2") {
                            BusinessProfileForm(profile: profile)
                        }
                        Tab("Invoice template", systemImage: "doc.richtext") {
                            InvoiceTemplateForm(profile: profile)
                        }
                    }
                    .frame(width: 470)
                    Divider()
                    VStack(spacing: 0) {
                        Text("Preview on a sample invoice")
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
                TextField("Business name", text: $profile.name, prompt: Text("e.g. Domen Perko, s.p."))
                TextField("Full name", text: $profile.signerName, prompt: Text("the business owner"))
                TextField("Email", text: $profile.email)
                TextField("Phone", text: $profile.phone)
            } header: {
                Text("My s.p.")
            } footer: {
                Text("The business name is printed in the invoice header, the full name under “Račun izdal” (issued by).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Address") {
                TextField("Street and number", text: $profile.street)
                TextField("Postal code", text: $profile.postalCode)
                TextField("City", text: $profile.city)
                TextField("Country (ISO code)", text: $profile.countryCode)
            }
            Section {
                SensitiveField("Tax number (davčna številka)", text: $profile.taxNumber)
                Toggle("VAT registered", isOn: $profile.isVatRegistered)
                if profile.isVatRegistered {
                    SensitiveField("VAT ID", text: $profile.vatID)
                }
                Toggle("Flat-rate expenses (normiranec)", isOn: $profile.isFlatRate)
            } header: {
                Text("Tax status")
            } footer: {
                Text(profile.isVatRegistered
                     ? "Invoices show VAT rates and a breakdown per rate."
                     : "Invoices charge no VAT and carry the exemption clause under 94. člen ZDDV-1. Turn this on once you register for VAT.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Section("Bank account") {
                SensitiveField("IBAN", text: $profile.iban)
                TextField("Bank", text: $profile.bankName)
                SensitiveField("BIC / SWIFT", text: $profile.bic)
                Stepper(
                    "Default payment term: \(profile.defaultPaymentTermDays) days",
                    value: $profile.defaultPaymentTermDays,
                    in: 0...120
                )
            }
            Section("On the invoice") {
                TextField("Registration (e.g. AJPES)", text: $profile.registrationNote)
                TextField("Footer note", text: $profile.invoiceFooter, axis: .vertical)
                    .lineLimit(2...5)
            }
            PrivacySection()
            LanguageSection()
        }
        .formStyle(.grouped)
    }
}

/// Private mode, the same switch as Pogled › Skrij občutljive podatke.
/// It is here so it can be found; it is used through ⇧⌘H.
private struct PrivacySection: View {
    @AppStorage(PrivacyMode.storageKey) private var hidesSensitiveValues = false

    var body: some View {
        Section {
            Toggle("Hide sensitive values", isOn: $hidesSensitiveValues)
        } header: {
            Text("Privacy")
        } footer: {
            Text("Blanks tax numbers, the IBAN and every amount in the interface — for screen sharing, or a look over your shoulder. The exported PDF, the spreadsheet and the printed invoice are unchanged. Shortcut: ⇧⌘H.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// App language. macOS reads `AppleLanguages` once at launch, so a change
/// takes effect after a relaunch; the invoice PDF itself stays Slovenian.
private struct LanguageSection: View {
    @AppStorage("appLanguage") private var language = "system"
    @State private var needsRelaunch = false

    var body: some View {
        Section {
            Picker("App language", selection: $language) {
                Text("Same as system").tag("system")
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
            Text("Language")
        } footer: {
            Text("Applies to the app interface. Invoices are always in Slovenian.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .alert("The language change takes effect after a relaunch", isPresented: $needsRelaunch) {
            Button("Quit app") { NSApp.terminate(nil) }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Quit and reopen Invoices to see the interface in the selected language.")
        }
    }
}

/// Everything on the printed invoice that is the s.p.'s own: logo, tagline,
/// the three sentences, and the signature.
private struct InvoiceTemplateForm: View {
    @Bindable var profile: BusinessProfile

    var body: some View {
        Form {
            Section("Header") {
                ImageWell(title: "Logo", data: $profile.logoData)
                TextField("Line of business", text: $profile.activityLine,
                          prompt: Text("e.g. IT STORITVE IN SVETOVANJE"))
            }
            Section {
                TextField("Intro sentence", text: $profile.introTemplate, axis: .vertical)
                    .lineLimit(1...3)
                TextField("Payment instruction", text: $profile.paymentNoteTemplate, axis: .vertical)
                    .lineLimit(1...3)
                TextField("Closing sentence", text: $profile.closingNote, axis: .vertical)
                    .lineLimit(1...3)
                DisclosureGroup("Placeholders filled in automatically") {
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
                Text("Text")
            } footer: {
                Text("The intro sentence can be overridden on each invoice. The payment instruction is printed only when an IBAN is set.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                ImageWell(title: "Signature", data: $profile.signatureData)
            } header: {
                Text("Signature")
            } footer: {
                Text("The name under the signature is “Full name” from the My s.p. tab.")
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

                Button("Choose…") { isImporting = true }
                if data != nil {
                    Button("Remove", role: .destructive) { data = nil }
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
            "The image could not be loaded",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private func load(_ url: URL) {
        // The app is sandboxed; a picked file is readable only inside this scope.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? Data(contentsOf: url), let png = ImageData.normalized(raw) else {
            importError = String(localized: "The file is not an image that can be read.")
            return
        }
        data = png
    }
}
