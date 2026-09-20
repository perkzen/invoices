import SwiftData
import SwiftUI

/// Resolves the list's selection to an invoice for the editor. The selection
/// is an identifier rather than the model, so a deleted invoice simply stops
/// resolving instead of leaving the editor bound to a dead object.
struct InvoiceDetailColumn: View {
    let selection: PersistentIdentifier?
    @Query private var invoices: [Invoice]

    var body: some View {
        if let invoice = invoices.first(where: { $0.persistentModelID == selection }) {
            InvoiceDetailView(invoice: invoice)
                .id(invoice.persistentModelID)
        } else {
            ContentUnavailableView {
                Label("No invoice selected", systemImage: "doc.text")
            } description: {
                Text("Choose an invoice from the list, or create a new one.")
            }
            // With no toolbar of its own the empty detail would pull the
            // list's buttons over to the window's far edge.
            .toolbar { ToolbarSpacer(.flexible) }
        }
    }
}
