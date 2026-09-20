import SwiftUI

/// The templates the invoices are printed with. There is one today, so the
/// list has one row; it is a list all the same, so a second template has a
/// place to appear.
struct TemplateListView: View {
    @Binding var selection: String?

    /// The only template so far.
    static let standard = "standard"

    var body: some View {
        List(selection: $selection) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Standard template")
                    .font(.headline)
                Text("Used on every invoice")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
            .tag(Self.standard)
        }
        .navigationTitle("Invoice template")
        .task {
            if selection == nil { selection = Self.standard }
        }
    }
}

/// The template's settings beside the sample preview.
struct TemplateDetailColumn: View {
    let selection: String?

    var body: some View {
        if selection == TemplateListView.standard {
            ProfilePreviewSplit { profile in
                InvoiceTemplateForm(profile: profile)
            }
        } else {
            ContentUnavailableView {
                Label("No template selected", systemImage: "doc.richtext")
            } description: {
                Text("Choose a template from the list.")
            }
        }
    }
}
