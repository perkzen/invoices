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
            fatalError("Baze ni bilo mogoče odpreti: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        .defaultSize(width: 1120, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .modelContainer(container)
        }
    }
}
