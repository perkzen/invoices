import SwiftData
import SwiftUI

@main
struct InvoicesApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: Invoice.self, InvoiceLine.self, Client.self, BusinessProfile.self
            )
        } catch {
            fatalError("Could not open the store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .privacyRedacted()
        }
        .modelContainer(container)
        .defaultSize(width: 1400, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            PrivacyCommands()
        }

        Settings {
            SettingsView()
                .modelContainer(container)
                .privacyRedacted()
        }
    }
}
