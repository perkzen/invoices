import SwiftUI

/// A list row that can be deleted from a trash button under the pointer and
/// from its context menu. When `blocker` is set the button is disabled and
/// both explain why. The row never decides the rule itself — the caller
/// asks the ledger and passes the answer in.
///
/// The trash only appears under the pointer: a permanently visible
/// destructive control on every row is louder than the action deserves.
struct DeletableRow<Content: View>: View {
    let title: LocalizedStringKey
    let blocker: String?
    let onDelete: () -> Void
    let content: Content

    @State private var isHovering = false

    init(
        _ title: LocalizedStringKey,
        blocker: String?,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.blocker = blocker
        self.onDelete = onDelete
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            content

            Button(title, systemImage: "trash", action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .tint(.red)
                .disabled(blocker != nil)
                .help(blocker.map { Text(verbatim: $0) } ?? Text(title))
                .opacity(isHovering ? 1 : 0)
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            if let blocker {
                Text(verbatim: blocker)
            } else {
                Button(title, systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
    }
}

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
