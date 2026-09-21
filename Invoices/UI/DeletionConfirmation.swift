import SwiftUI

extension View {
    /// Asks before deleting `item`, then performs the deletion and clears it.
    func deletionConfirmation<Item>(
        _ title: LocalizedStringKey,
        item: Binding<Item?>,
        message: @escaping (Item) -> Text,
        perform: @escaping (Item) -> Void
    ) -> some View {
        confirmationDialog(
            title,
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            presenting: item.wrappedValue
        ) { pending in
            Button("Delete", role: .destructive) {
                item.wrappedValue = nil
                perform(pending)
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            message(pending)
        }
    }
}
