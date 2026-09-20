import Combine
import Sparkle
import SwiftUI

/// Invoices › Check for Updates…, and the Sparkle updater behind it.
///
/// Only the release build updates itself. Debug is a separate app with its own
/// bundle id, so installing a release over it would quietly replace the
/// development build with the production one — hence the `#if !DEBUG` around
/// both this file's contents and its use in `InvoicesApp`.
#if !DEBUG

    struct UpdaterCommands: Commands {
        @StateObject private var updater = Updater()

        var body: some Commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }
    }

    /// Owns the updater for as long as the app runs. Starting it also starts
    /// Sparkle's own schedule, which is what checks in the background;
    /// the menu item is only the manual path.
    ///
    /// `canCheckForUpdates` is KVO-observable on `SPUUpdater` but not published,
    /// so the menu item cannot bind to it directly. This republishes it.
    @MainActor
    private final class Updater: ObservableObject {
        @Published var canCheckForUpdates = false

        private let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        init() {
            controller.updater.publisher(for: \.canCheckForUpdates)
                .assign(to: &$canCheckForUpdates)
        }

        func checkForUpdates() {
            controller.updater.checkForUpdates()
        }
    }

#endif
