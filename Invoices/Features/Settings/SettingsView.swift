import AppKit
import SwiftData
import SwiftUI

/// The ⌘, window: the preferences that are about the app rather than the
/// business. What the invoice is printed from and printed with lives in the
/// sidebar's own section, beside a preview of the invoice it produces.
struct SettingsView: View {
    var body: some View {
        // Width only: the window takes its height from the form, so a
        // longer translation of a footer cannot be cut off.
        GeneralSettingsForm()
            .frame(width: 520)
    }
}

/// Private mode, the mail client and the interface language — the
/// preferences that are the app's own. Shown in the ⌘, window and in the
/// sidebar's Settings row.
struct GeneralSettingsForm: View {
    var body: some View {
        Form {
            PrivacySection()
            EmailSection()
            LanguageSection()
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
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

/// Which client "Send by email" composes in. The footer spells out the
/// difference, because only Mail can be handed the attachment.
private struct EmailSection: View {
    @AppStorage(EmailComposer.Client.storageKey) private var client = EmailComposer.Client.appleMail

    var body: some View {
        Section {
            Picker("Send invoices with", selection: $client) {
                ForEach(EmailComposer.Client.allCases) { client in
                    Text(client.label).tag(client)
                }
            }
        } header: {
            Text("Email")
        } footer: {
            Text(client.explanation)
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
