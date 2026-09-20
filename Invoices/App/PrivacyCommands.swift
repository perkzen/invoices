import SwiftUI

/// Pogled › Skrij občutljive podatke. Stikalo mora biti dosegljivo v eni
/// potezi — njegov trenutek je sekunda pred začetkom deljenja zaslona in
/// pot v Nastavitve je za to prepočasna.
struct PrivacyCommands: Commands {
    @AppStorage(PrivacyMode.storageKey) private var hidesSensitiveValues = false

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Toggle("Skrij občutljive podatke", isOn: $hidesSensitiveValues)
                .keyboardShortcut("h", modifiers: [.command, .shift])
        }
    }
}
