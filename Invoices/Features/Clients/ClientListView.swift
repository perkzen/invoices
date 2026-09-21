import SwiftData
import SwiftUI

/// The client list column. Deleting follows the same three routes as the
/// invoice list: toolbar trash, ⌫, context menu — all on the selected row,
/// and always by the ledger's rule.
struct ClientListView: View {
    @Binding var selection: PersistentIdentifier?

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Client.name)]) private var clients: [Client]

    @State private var pendingDelete: Client?
    @State private var searchText = ""

    private var ledger: Ledger { Ledger(context) }

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
        .deletionConfirmation("Delete client?", item: $pendingDelete) { client in
            Text("\(client.displayName) will be permanently deleted.")
        } perform: { client in
            delete(client)
        }
        .toolbar {
            ToolbarItem {
                Button("Delete client", systemImage: "trash") { requestDelete(selected) }
                    .disabled(selected.map { ledger.deletionProblem(for: $0) != nil } ?? true)
                    .help(Text(verbatim: deleteHelp))
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

    private var deleteHelp: String {
        guard let selected else { return String(localized: "Select a client to delete it") }
        return ledger.deletionProblem(for: selected)?.message ?? String(localized: "Delete client")
    }

    private func requestDelete(_ client: Client?) {
        guard let client, ledger.deletionProblem(for: client) == nil else { return }
        pendingDelete = client
    }

    @ViewBuilder
    private func deleteMenu(for client: Client) -> some View {
        if let problem = ledger.deletionProblem(for: client) {
            Text(verbatim: problem.message)
        } else {
            Button("Delete client", systemImage: "trash", role: .destructive) {
                requestDelete(client)
            }
        }
    }

    private func delete(_ client: Client) {
        if selection == client.persistentModelID { selection = nil }
        try? ledger.delete(client)
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
