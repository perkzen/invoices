import SwiftUI

/// Everything on the printed invoice that is the business's own: logo, tagline,
/// the three sentences, and the signature.
struct InvoiceTemplateForm: View {
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
                                caption: "The name under the signature is “Full name” from Settings › My business.")
                    }
                    Text("Header")
                        .padding(.top, 16)
                }
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
        }
        .formStyle(.grouped)
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
