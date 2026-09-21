import AppKit
import SwiftData
import SwiftUI

/// The pages of Settings. They are rows in the middle column of the main
/// window and the sidebar of the ⌘, window, so both show the same forms.
/// The invoice template is not one of them: it has its own sidebar section.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case business

    var id: String { rawValue }

    var title: String {
        switch self {
        case .business: String(localized: "My business")
        case .general: String(localized: "General")
        }
    }

    var symbol: String {
        switch self {
        case .business: "building.2"
        case .general: "gearshape"
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
    @State private var page: SettingsPage? = .general

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

/// One settings page. The business details sit beside the sample preview,
/// since they are printed; the general preferences are not, so they stand
/// alone.
struct SettingsContent: View {
    let page: SettingsPage?

    var body: some View {
        Group {
            switch page {
            case .general, nil:
                GeneralSettingsForm()
            case .business:
                ProfilePreviewSplit { profile in
                    BusinessProfileForm(profile: profile)
                }
            }
        }
        .navigationTitle((page ?? .general).title)
    }
}

/// A form about the business profile beside a live preview of a sample
/// invoice, so every change is seen where it lands. Shared by the business
/// page and the invoice template.
struct ProfilePreviewSplit<Content: View>: View {
    @ViewBuilder let form: (BusinessProfile) -> Content

    @Environment(\.modelContext) private var context

    var body: some View {
        let profile = Ledger(context).profile

        HStack(spacing: 0) {
            form(profile)
                .frame(width: 470)
            Divider()
            VStack(spacing: 0) {
                Text("Preview on a sample invoice")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(6)
                // Built in `body`, so every edit to the profile — the VAT
                // toggle included — re-renders the sample.
                InvoicePreview(printed: PrintedInvoice.sample(matching: profile))
            }
            .frame(minWidth: 400)
        }
    }
}

/// Preferences about the app rather than the business: private mode and
/// the interface language.
private struct GeneralSettingsForm: View {
    var body: some View {
        Form {
            PrivacySection()
            LanguageSection()
        }
        .formStyle(.grouped)
    }
}

private struct BusinessProfileForm: View {
    @Bindable var profile: BusinessProfile

    var body: some View {
        Form {
            Section {
                TextField("Business name", text: $profile.name, prompt: Text("e.g. Domen Perko, sole trader"))
                TextField("Full name", text: $profile.signerName, prompt: Text("the business owner"))
                TextField("Email", text: $profile.email)
                TextField("Phone", text: $profile.phone)
            } header: {
                Text("My business")
            } footer: {
                Text("The business name is printed in the invoice header, the full name under “Issued by”.")
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
                SensitiveField("Tax number", text: $profile.taxNumber)
                Toggle("VAT registered", isOn: $profile.isVatRegistered)
                if profile.isVatRegistered {
                    SensitiveField("VAT ID", text: $profile.vatID)
                }
                Toggle("Flat-rate expenses", isOn: $profile.isFlatRate)
            } header: {
                Text("Tax status")
            } footer: {
                Text(profile.isVatRegistered
                     ? "Invoices show VAT rates and a breakdown per rate."
                     : "Invoices charge no VAT and carry the exemption clause under Article 94 of the VAT Act (ZDDV-1). Turn this on once you register for VAT.")
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
        }
        .formStyle(.grouped)
    }
}

/// Private mode, the same switch as View › Hide sensitive values.
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
                Text(verbatim: Self.nativeName(of: "sl")).tag("sl")
                Text(verbatim: Self.nativeName(of: "en")).tag("en")
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

    /// A language is offered under its own name — the way its speakers spell
    /// it, whatever language the rest of the picker is in.
    private static func nativeName(of code: String) -> String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? code
    }
}
