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
                    Label("Ni strank", systemImage: "person.2")
                } description: {
                    Text("Dodaj stranko, da ji lahko izdaš račun.")
                } actions: {
                    Button("Nova stranka", action: newClient)
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
        .navigationTitle("Stranke")
        .navigationDestination(for: Client.self) { ClientDetailView(client: $0) }
        .confirmationDialog(
            "Izbrišem stranko?",
            isPresented: isConfirming,
            presenting: pendingDelete
        ) { client in
            Button("Izbriši", role: .destructive) { delete(client) }
            Button("Prekliči", role: .cancel) {}
        } message: { client in
            Text("\(client.displayName) bo trajno izbrisana.")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: newClient) {
                    Label("Nova stranka", systemImage: "plus")
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
            Text("Ima izdane račune in je ni mogoče izbrisati")
        } else {
            Button("Izbriši stranko", systemImage: "trash", role: .destructive) {
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

            Button("Izbriši stranko", systemImage: "trash", action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .tint(.red)
                .disabled(isBlocked)
                .help(isBlocked ? "Ima izdane račune in je ni mogoče izbrisati" : "Izbriši stranko")
                .opacity(isHovering ? 1 : 0)
        }
        .onHover { isHovering = $0 }
    }
}
