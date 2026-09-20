import SwiftData
import SwiftUI

struct ClientListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Client.name)]) private var clients: [Client]
    @State private var pendingDelete: Client?

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
                        ClientRow(client: client, isBlocked: hasRecords(client)) {
                            pendingDelete = client
                        }
                        .contextMenu { deleteMenu(for: client) }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Clients")
        .navigationDestination(for: Client.self) { ClientDetailView(client: $0) }
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

    private var isConfirming: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    /// An invoice keeps no copy of its counterparty — name, address and tax
    /// number live only on the Client — so deleting one would strip a
    /// mandatory field off a document that has already been sent out.
    private func hasRecords(_ client: Client) -> Bool {
        client.invoices.contains { $0.status != .draft }
    }

    @ViewBuilder
    private func deleteMenu(for client: Client) -> some View {
        if hasRecords(client) {
            Text("Has issued invoices and cannot be deleted")
        } else {
            Button("Delete client", systemImage: "trash", role: .destructive) {
                pendingDelete = client
            }
        }
    }

    private func delete(_ client: Client) {
        pendingDelete = nil
        context.delete(client)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(clients[index])
        }
    }
}

/// The trash only appears under the pointer — a permanently visible destructive
/// control on every row is louder than the action deserves.
private struct ClientRow: View {
    let client: Client
    let isBlocked: Bool
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink(value: client) {
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

            Button("Delete client", systemImage: "trash", action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .tint(.red)
                .disabled(isBlocked)
                .help(isBlocked ? "Has issued invoices and cannot be deleted" : "Delete client")
                .opacity(isHovering ? 1 : 0)
        }
        .onHover { isHovering = $0 }
    }
}
