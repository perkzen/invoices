import SwiftUI

/// Everything on the printed invoice that is the business's own: logo, tagline,
/// the three sentences, and the signature.
struct InvoiceTemplateForm: View {
    @Bindable var profile: BusinessProfile

    var body: some View {
        Form {
            Section("Header") {
                ImageWell(title: "Logo", data: $profile.logoData)
                TextField("Line of business", text: $profile.activityLine,
                          prompt: Text("e.g. IT SERVICES AND CONSULTING"))
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
                ImageWell(data: $profile.signatureData, symbol: "signature")
            } header: {
                Text("Signature")
            } footer: {
                Text("The name under the signature is “Full name” from Settings › My business.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
