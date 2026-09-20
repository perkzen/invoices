import SwiftData
import SwiftUI

/// Resolves the list's selection to a client for the editor; see
/// `InvoiceDetailColumn` for why it goes through an identifier.
struct ClientDetailColumn: View {
    let selection: PersistentIdentifier?
    @Query private var clients: [Client]

    var body: some View {
        if let client = clients.first(where: { $0.persistentModelID == selection }) {
            ClientDetailView(client: client)
                .id(client.persistentModelID)
        } else {
            ContentUnavailableView {
                Label("No client selected", systemImage: "person.2")
            } description: {
                Text("Choose a client from the list, or add a new one.")
            }
            // With no toolbar of its own the empty detail would pull the
            // list's buttons over to the window's far edge.
            .toolbar { ToolbarSpacer(.flexible) }
        }
    }
}
