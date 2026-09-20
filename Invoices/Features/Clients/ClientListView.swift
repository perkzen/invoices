import SwiftData
import SwiftUI

struct ClientListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Client.name)]) private var clients: [Client]
    @State private var pendingDelete: Client?

    private var ledger: Ledger { Ledger(context) }

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
            } else {
                List {
                    ForEach(clients) { client in
                        DeletableRow(
                            "Delete client",
                            blocker: ledger.deletionProblem(for: client)?.message,
                            onDelete: { pendingDelete = client }
                        ) {
                            NavigationLink(value: client) { ClientRow(client: client) }
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Clients")
        .navigationDestination(for: Client.self) { ClientDetailView(client: $0) }
        .deletionConfirmation("Delete client?", item: $pendingDelete) { client in
            Text("\(client.displayName) will be permanently deleted.")
        } perform: { client in
            try? ledger.delete(client)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: newClient) {
                    Label("New client", systemImage: "plus")
                }
            }
        }
    }

    private func newClient() {
        context.insert(Client())
    }

    /// The swipe path asks no question, but the rule still holds: the
    /// ledger refuses a client with issued invoices.
    private func delete(at offsets: IndexSet) {
        for index in offsets {
            try? ledger.delete(clients[index])
        }
    }
}

private struct ClientRow: View {
    let client: Client

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(client.displayName).font(.headline)
                Text(client.addressLines.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
