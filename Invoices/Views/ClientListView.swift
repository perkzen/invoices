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
                        NavigationLink(value: client) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(client.displayName).font(.headline)
                                Text(client.addressLines.joined(separator: ", "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
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
    @ViewBuilder
    private func deleteMenu(for client: Client) -> some View {
        if client.invoices.contains(where: { $0.status != .draft }) {
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

struct ClientDetailView: View {
    @Bindable var client: Client

    var body: some View {
        Form {
            Section("Podatki") {
                TextField("Naziv", text: $client.name)
                TextField("Naslov", text: $client.street)
                TextField("Poštna številka", text: $client.postalCode)
                TextField("Kraj", text: $client.city)
                TextField("Država (ISO)", text: $client.countryCode)
            }
            Section("Davčni podatki") {
                TextField("Davčna številka", text: $client.taxNumber)
                TextField("ID za DDV", text: $client.vatID)
            }
            Section("Ostalo") {
                TextField("E-pošta", text: $client.email)
                Stepper(
                    "Rok plačila: \(client.defaultPaymentTermDays) dni",
                    value: $client.defaultPaymentTermDays,
                    in: 0...120
                )
                TextField("Opombe", text: $client.notes, axis: .vertical)
                    .lineLimit(3...8)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(client.displayName)
    }
}
