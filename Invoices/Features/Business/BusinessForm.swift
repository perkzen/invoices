import SwiftUI

/// Everything about the business that ends up on an invoice, on three pages
/// over one form: the details it is printed from — name, address, tax
/// status, bank — the artwork and wording it is printed with, and the email
/// it is sent in. One profile behind all three; the pages only decide which
/// of it is in front.
///
/// The form fills the middle column and the preview the right one, so a
/// change is seen where it lands without a split inside a single column.
/// The page is the window's, not the form's: the preview beside it follows
/// the same value.
struct BusinessForm: View {
    @Bindable var profile: BusinessProfile
    @Binding var page: BusinessPage

    var body: some View {
        Form {
            switch page {
            case .details: details
            case .invoice: invoice
            case .email: email
            }
        }
        .formStyle(.grouped)
        // Each page starts at its top: a scroll position carried over from a
        // long page would open the next one somewhere in the middle.
        .id(page)
        .navigationTitle("My business")
        // The switch is pinned over the form, not put in the toolbar: on
        // macOS 26 a three-column window lays the middle column's toolbar
        // items out from the detail column's edge, which would hang the
        // pages over the preview.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                Picker("Page", selection: $page) {
                    ForEach(BusinessPage.allCases) { page in
                        Text(page.title).tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                Divider()
            }
            .background(.bar)
        }
    }

    // MARK: Details — what the invoice is printed from

    @ViewBuilder
    private var details: some View {
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
            TextField("Registration (e.g. AJPES)", text: $profile.registrationNote)
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
    }

    // MARK: Invoice — what it is printed with

    @ViewBuilder
    private var invoice: some View {
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
                            caption: "The name under the signature is the full name under Details.")
                }
                Text("Header")
                    .padding(.top, 16)
            }
        }
        Section {
            MessageEditor("Intro sentence", text: $profile.introTemplate, lines: 2)
            MessageEditor("Payment instruction", text: $profile.paymentNoteTemplate, lines: 2)
            MessageEditor("Closing sentence", text: $profile.closingNote, lines: 2)
            PlaceholderLegend()
        } header: {
            Text("Text")
        } footer: {
            Text("The intro sentence can be overridden on each invoice. The payment instruction is printed only when an IBAN is set.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        Section("Footer") {
            MessageEditor("Footer note", text: $profile.invoiceFooter, lines: 3)
        }
    }

    // MARK: Email — what it is sent in

    @ViewBuilder
    private var email: some View {
        Section {
            TextField("Subject", text: $profile.emailSubjectTemplate)
            MessageEditor("Message", text: $profile.emailBodyTemplate)
            PlaceholderLegend()
        } header: {
            Text("Email")
        } footer: {
            Text("Send by email opens this message in your mail client, addressed to the client, with the invoice PDF attached. Add your name where the message signs off.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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

/// The tokens a template may use, with what each stands for. Under the
/// invoice wording and under the email, which share them.
private struct PlaceholderLegend: View {
    var body: some View {
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
    }
}

/// What the page in front changes, shown on a sample invoice: the printed
/// page for the details and the wording, the email for the message. Built
/// in `body`, so every edit to the profile — the VAT toggle included —
/// re-renders it.
struct BusinessPreview: View {
    let profile: BusinessProfile
    let page: BusinessPage

    var body: some View {
        VStack(spacing: 0) {
            Text(page == .email ? "Preview of the email for a sample invoice" : "Preview on a sample invoice")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(6)
            switch page {
            case .details, .invoice:
                InvoicePreview(printed: PrintedInvoice.sample(matching: profile), fitsPage: true)
            case .email:
                EmailPreview(profile: profile)
            }
        }
    }
}

/// The message as Mail would open it: the header fields, the body and the
/// attached PDF, on the same backdrop the rendered page sits on so the two
/// previews swap without a jump.
///
/// Private mode: `{iban}` is the one placeholder that resolves to a value
/// the mode hides, so the sample is resolved with it masked — the same
/// mask the page beside it prints.
private struct EmailPreview: View {
    let profile: BusinessProfile

    @AppStorage(PrivacyMode.storageKey) private var hidesSensitiveValues = false

    var body: some View {
        let email = InvoiceEmail.sample(matching: profile, masksSensitiveValues: hidesSensitiveValues)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                    if !sender.isEmpty {
                        headerRow("From:", value: sender)
                    }
                    headerRow("To:", value: email.recipient)
                    headerRow("Subject:", value: email.subject)
                }
                .padding(.bottom, 14)
                Divider()
                Text(email.body)
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
                Label(email.attachmentFilename, systemImage: "doc.richtext")
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.top, 24)
            }
            .padding(24)
            .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: 560)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    /// The business as Mail names the sender: the name, and the address
    /// after it when there is one.
    private var sender: String {
        [profile.name, profile.email.isEmpty ? "" : "<\(profile.email)>"]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func headerRow(_ label: LocalizedStringKey, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
