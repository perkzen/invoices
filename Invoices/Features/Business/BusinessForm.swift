import SwiftUI

/// Everything about the business that ends up on an invoice, on one page:
/// the artwork and wording it is printed with, and the details — name,
/// address, tax status, bank — it is printed from. They were two places
/// before, a Settings page and an "Invoice template" section, both editing
/// the same profile and both previewing the same sample invoice.
///
/// The form fills the middle column and the preview the right one, so a
/// change is seen where it lands without a split inside a single column.
struct BusinessForm: View {
    @Bindable var profile: BusinessProfile

    var body: some View {
        Form {
            // The artwork sits above the wording, in the first section's
            // header: never boxed, on the sections' own left edge.
            Section {
                TextField("Line of business", text: $profile.activityLine,
                          prompt: Text("e.g. IT SERVICES AND CONSULTING"))
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 32) {
                        artwork("Logo", data: $profile.logoData, symbol: "photo.badge.plus",
                                caption: "Printed top left on every invoice.")
                        artwork("Signature", data: $profile.signatureData, symbol: "signature",
                                caption: "The name under the signature is “Full name” below.")
                    }
                    Text("Header")
                        .padding(.top, 16)
                }
            }
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
            Section {
                TextField("Intro sentence", text: $profile.introTemplate, axis: .vertical)
                    .lineLimit(1...3)
                TextField("Payment instruction", text: $profile.paymentNoteTemplate, axis: .vertical)
                    .lineLimit(1...3)
                TextField("Closing sentence", text: $profile.closingNote, axis: .vertical)
                    .lineLimit(1...3)
                DisclosureGroup("Placeholders filled in automatically") {
                    ForEach(InvoiceTemplate.Placeholder.allCases, id: \.self) { placeholder in
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
                TextField("Email subject", text: $profile.emailSubjectTemplate)
                TextField("Email message", text: $profile.emailBodyTemplate, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("Email")
            } footer: {
                Text("The message an invoice is sent with, the PDF attached. The placeholders above apply here too; add your name where the message signs off.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("On the invoice") {
                TextField("Registration (e.g. AJPES)", text: $profile.registrationNote)
                TextField("Footer note", text: $profile.invoiceFooter, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("My business")
    }

    private func artwork(
        _ title: LocalizedStringKey, data: Binding<Data?>, symbol: String, caption: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            ImageWell(data: data, symbol: symbol)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 200, alignment: .leading)
        }
    }
}

/// The sample invoice, printed with whatever the form currently holds.
/// Built in `body`, so every edit to the profile — the VAT toggle included —
/// re-renders it.
struct BusinessPreview: View {
    let profile: BusinessProfile

    var body: some View {
        VStack(spacing: 0) {
            Text("Preview on a sample invoice")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(6)
            InvoicePreview(printed: PrintedInvoice.sample(matching: profile), fitsPage: true)
        }
    }
}
