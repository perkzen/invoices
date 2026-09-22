import ArgumentParser
import Foundation

/// Answers where the tool would look, without opening anything — the one
/// command that is safe to run before the app has ever been launched.
nonisolated struct StoreCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "store",
            abstract: "Where the store is, whether it exists, and which installed app the documents are worded from."
        )
    }

    @OptionGroup var store: StoreOptions

    nonisolated struct Record: Encodable {
        var path: String
        var exists: Bool
        var bundleIdentifier: String?
        var app: String?
    }

    nonisolated func run() throws {
        let location = StoreLocation.resolve(store)
        let app: String? = MainActor.assumeIsolated { location.installedApp()?.bundlePath }
        Output.print(
            Record(
                path: location.url.path,
                exists: FileManager.default.fileExists(atPath: location.url.path),
                bundleIdentifier: location.bundleIdentifier,
                app: app
            )
        )
    }
}
