import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The two pages of Nastavitve. They are rows in the middle column of the
/// main window and the sidebar of the ⌘, window, so both show the same forms.
enum SettingsPage: String, CaseIterable, Identifiable {
    case business
    case template

    var id: String { rawValue }

    var title: String {
        switch self {
        case .business: String(localized: "My s.p.")
        case .template: String(localized: "Invoice template")
        }
    }

    var symbol: String {
        switch self {
        case .business: "building.2"
        case .template: "doc.richtext"
        }
    }
}

struct SettingsPageList: View {
    @Binding var selection: SettingsPage?

    var body: some View {
        List(selection: $selection) {
            ForEach(SettingsPage.allCases) { page in
                Label(page.title, systemImage: page.symbol)
                    .tag(page)
            }
        }
        .navigationTitle("Settings")
    }
}

/// The ⌘, window. The same pages also live in the sidebar under Settings,
/// so nobody has to know the shortcut to find them.
struct SettingsView: View {
    @State private var page: SettingsPage? = .business

    var body: some View {
        NavigationSplitView {
            SettingsPageList(selection: $page)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            SettingsContent(page: page)
        }
        .frame(width: 1240, height: 720)
    }
}

/// One settings page beside a live preview of a sample invoice, so every
/// change is seen where it lands.
struct SettingsContent: View {
    let page: SettingsPage?

    @Environment(\.modelContext) private var context
    @State private var profile: BusinessProfile?
    @State private var sample: SampleInvoice?

    var body: some View {
        Group {
            if let profile, let sample {
                HStack(spacing: 0) {
                    Group {
                        switch page {
                        case .business, nil:
                            BusinessProfileForm(profile: profile)
                        case .template:
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
        .navigationTitle((page ?? .business).title)
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
