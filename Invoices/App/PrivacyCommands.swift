import SwiftUI

/// View › Hide sensitive values. The switch has to be reachable in one
/// stroke — its moment is the second before a screen share starts, and a trip
/// into Settings is too slow for that.
struct PrivacyCommands: Commands {
    @AppStorage(PrivacyMode.storageKey) private var hidesSensitiveValues = false

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Toggle("Hide sensitive values", isOn: $hidesSensitiveValues)
                .keyboardShortcut("h", modifiers: [.command, .shift])
        }
    }
}
