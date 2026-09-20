import SwiftData
import SwiftUI

/// The client list column. Deleting follows the same three routes as the
/// invoice list: toolbar trash, ⌫, context menu — all on the selected row.
struct ClientListView: View {
    @Binding var selection: PersistentIdentifier?

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Client.name)]) private var clients: [Client]

    @State private var pendingDelete: Client?
    @State private var searchText = ""

    private var selected: Client? {
        clients.first { $0.persistentModelID == selection }
    }

    private var shown: [Client] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return clients }
        return clients.filter {
            $0.name.localizedStandardContains(query) || $0.city.localizedStandardContains(query)
        }
    }

    var body: some View {
        Group {
            if clients.isEmpty {
                ContentUnavailableView {
                    Label("No clients", systemImage: "person.2")
                } description: {
                    Text("Add a client so you can invoice them.")
                } actions: {
                    Button("New client", action: newClient)
                }
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(selection: $selection) {
                    ForEach(shown) { client in
                        ClientRow(client: client)
                            .tag(client.persistentModelID)
                            .contextMenu { deleteMenu(for: client) }
                    }
                }
                .onDeleteCommand { requestDelete(selected) }
            }
        }
        .navigationTitle("Clients")
        .searchable(text: $searchText, prompt: "Name or city")
        .confirmationDialog(
            "Delete client?",
            isPresented: isConfirming,
            presenting: pendingDelete
        ) { client in
            Button("Delete", role: .destructive) { delete(client) }
            Button("Cancel", role: .cancel) {}
        } message: { client in
            Text("\(client.displayName) will be permanently deleted.")
        }
        .toolbar {
            ToolbarItem {
                Button("Delete client", systemImage: "trash") { requestDelete(selected) }
                    .disabled(selected.map(hasRecords) ?? true)
                    .help(deleteHelp)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New client", systemImage: "plus", action: newClient)
                    .keyboardShortcut("n")
                    .help("New client")
            }
        }
    }

    private func newClient() {
        let client = Client()
        context.insert(client)
        // Save first: an unsaved model carries a temporary identifier that
        // autosave replaces, which would drop the selection a moment later.
        try? context.save()
        searchText = ""
        selection = client.persistentModelID
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var deleteHelp: String {
        guard let selected else { return String(localized: "Select a client to delete it") }
        return hasRecords(selected)
            ? String(localized: "Has issued invoices and cannot be deleted")
            : String(localized: "Delete client")
    }

    /// An invoice keeps no copy of its counterparty — name, address and tax
    /// number live only on the Client — so deleting one would strip a
    /// mandatory field off a document that has already been sent out.
    private func hasRecords(_ client: Client) -> Bool {
        client.invoices.contains { $0.status != .draft }
    }

    private func requestDelete(_ client: Client?) {
        guard let client, !hasRecords(client) else { return }
        pendingDelete = client
    }

    @ViewBuilder
    private func deleteMenu(for client: Client) -> some View {
        if hasRecords(client) {
            Text("Has issued invoices and cannot be deleted")
        } else {
            Button("Delete client", systemImage: "trash", role: .destructive) {
                requestDelete(client)
            }
        }
    }

    private func delete(_ client: Client) {
        pendingDelete = nil
        guard !hasRecords(client) else { return }
        if selection == client.persistentModelID { selection = nil }
        context.delete(client)
    }
}

private struct ClientRow: View {
    let client: Client

    private var place: String {
        [client.city, client.countryCode.uppercased() == "SI" ? "" : client.countryCode]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 10) {
            ClientAvatar(client: client, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(client.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(place.isEmpty ? String(localized: "No address") : place)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !client.issuedInvoices.isEmpty {
                Text(Formatting.invoiceCount(client.issuedInvoices.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
