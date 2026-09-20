import SwiftUI

extension View {
    /// An alert that shows while `message` holds text and clears it on OK,
    /// so a view keeps one optional string per failure rather than a flag
    /// and a text that have to agree.
    func errorAlert(_ title: LocalizedStringKey, message: Binding<String?>) -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
