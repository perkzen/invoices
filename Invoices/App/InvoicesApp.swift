import AppKit
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
        // The one profile exists from the first launch on, so views can read
        // it inside `body` without ever inserting during a view update.
        let ledger = Ledger(container.mainContext)
        _ = ledger.profile
        ledger.modernizeTemplates()
        ledger.assignIdentifiers()
        // One window is the whole app; tabs would only offer a second copy
        // of it and put "Show Tab Bar" in the View menu.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        .defaultSize(width: 1400, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            ImportCommands()
            PrivacyCommands()
            #if !DEBUG
                UpdaterCommands()
                CommandLineToolCommands()
            #endif
        }

        Settings {
            SettingsView()
                .modelContainer(container)
        }
    }
}
