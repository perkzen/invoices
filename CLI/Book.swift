import AppKit
import ArgumentParser
import Foundation
import SwiftData

/// The options every command takes to say which store it means.
struct StoreOptions: ParsableArguments {
    @Flag(help: "Open the development build's store (Invoices Dev) instead of the installed app's.")
    var dev = false

    @Option(
        help: ArgumentHelp(
            "Open this store file instead of the app's; created when it does not exist. "
                + "The INVOICES_STORE environment variable does the same.",
            valueName: "path"
        )
    )
    var store: String?
}

/// A failure worded for the caller. `String(describing:)` is what ends up
/// in the error JSON.
struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Where the store is: the installed app's container, the development
/// build's, or a file named outright.
struct StoreLocation {
    static let releaseBundleID = "com.domenperko.Invoices"
    static let devBundleID = "com.domenperko.Invoices.dev"

    let url: URL
    /// The app whose container the store sits in; nil for a file named outright.
    let bundleIdentifier: String?

    var isNamedOutright: Bool { bundleIdentifier == nil }

    static let noAppMessage =
        "No copy of the app was found, and the tool takes the documents' Slovenian wording "
        + "and the skill from it. Run the tool from inside an installed Invoices.app "
        + "(Contents/Helpers/invoices), or point INVOICES_APP at one."

    static func resolve(_ options: StoreOptions) -> StoreLocation {
        if let path = options.store ?? (options.dev ? nil : ProcessInfo.processInfo.environment["INVOICES_STORE"]) {
            let expanded = (path as NSString).expandingTildeInPath
            return StoreLocation(url: URL(fileURLWithPath: expanded), bundleIdentifier: nil)
        }
        let bundleID = options.dev ? devBundleID : releaseBundleID
        // SwiftData's default store, inside the sandbox container the app
        // writes it to. The tool is not sandboxed, so the path is literal.
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/\(bundleID)/Data/Library/Application Support/default.store")
        return StoreLocation(url: url, bundleIdentifier: bundleID)
    }

    /// The app the documents take their Slovenian wording from, and the
    /// skill comes from: INVOICES_APP when set; else the app this executable
    /// ships inside, which is where an installed copy runs from (the symlink
    /// on the PATH points into `Contents/Helpers`); else whichever build
    /// Launch Services knows, the one this store belongs to first, for a
    /// build-tree binary run on its own.
    @MainActor func installedApp() -> Bundle? {
        if let path = ProcessInfo.processInfo.environment["INVOICES_APP"] {
            return Bundle(url: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        }
        if let own = Self.enclosingApp { return own }
        let candidates = [bundleIdentifier, Self.releaseBundleID, Self.devBundleID].compactMap { $0 }
        for identifier in candidates {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return nil
    }

    /// The `.app` this executable sits inside, when it does: the bundle
    /// above `Contents/Helpers/invoices`, with the app's resources in it.
    /// Read from the kernel's idea of the executable rather than `argv[0]`,
    /// which is whatever the shell typed, and through any symlink.
    static var enclosingApp: Bundle? {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size) + 1)
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return nil }
        var url = URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if url.pathExtension == "app" {
                guard let bundle = Bundle(url: url), bundle.path(forResource: "sl", ofType: "lproj") != nil else { return nil }
                return bundle
            }
        }
        return nil
    }
}

/// An open store: the container, the ledger over it, and the app the
/// documents are worded from. One per command invocation.
@MainActor
final class Book {
    let location: StoreLocation
    let container: ModelContainer
    let ledger: Ledger
    /// The installed app, when one was found; documents need it.
    let app: Bundle?

    var context: ModelContext { container.mainContext }

    static func open(_ options: StoreOptions) throws -> Book {
        let location = StoreLocation.resolve(options)
        // A store named outright is a deliberate choice, so it may be new.
        // The app's own is not created here: an empty store in the
        // container would only hide that the app has never been launched.
        if !location.isNamedOutright, !FileManager.default.fileExists(atPath: location.url.path) {
            let hint = options.dev
                ? "Launch Invoices Dev once so it creates one."
                : "Launch the app once so it creates one, or pass --dev for the development build's store."
            throw ToolError("No store at \(location.url.path). \(hint)")
        }

        // The Slovenian document strings live in the app bundle. Point the
        // lookup there before anything reads a template or a label.
        let app = location.installedApp()
        if let app { DocumentText.resourceBundle = app }

        let container = try ModelContainer(
            for: Invoice.self, InvoiceLine.self, Client.self, BusinessProfile.self,
            configurations: ModelConfiguration(url: location.url)
        )
        let book = Book(location: location, container: container, app: app)
        // The same housekeeping the app does at launch, so a store the app
        // has not opened since the last update is still complete.
        _ = book.ledger.profile
        book.ledger.modernizeTemplates()
        book.ledger.assignIdentifiers()
        try book.save()
        return book
    }

    private init(location: StoreLocation, container: ModelContainer, app: Bundle?) {
        self.location = location
        self.container = container
        self.ledger = Ledger(container.mainContext)
        self.app = app
    }

    func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    /// Rendering a document needs the app's wording; without it the page
    /// would come out in English, which a Slovenian invoice must not.
    func requireApp() throws {
        guard app != nil else { throw ToolError(StoreLocation.noAppMessage) }
    }

    // MARK: Finding records

    func clients() throws -> [Client] {
        try context.fetch(FetchDescriptor<Client>(sortBy: [SortDescriptor(\.name)]))
    }

    /// Drafts first, newest on top; then the numbered invoices, newest first.
    func invoices() throws -> [Invoice] {
        let all = try context.fetch(FetchDescriptor<Invoice>())
        let drafts = all.filter { $0.status.isEditable }.sorted { $0.issueDate > $1.issueDate }
        let numbered = all.filter { !$0.status.isEditable }
            .sorted { ($0.year, $0.sequence) > ($1.year, $1.sequence) }
        return drafts + numbered
    }

    /// A client by id, by name, or by a part of the name that fits one
    /// client only. Names are compared the way the import matches them:
    /// case and diacritics aside.
    func client(_ reference: String) throws -> Client {
        let clients = try clients()
        if let uuid = UUID(uuidString: reference), let client = clients.first(where: { $0.uuid == uuid }) {
            return client
        }
        let key = InvoiceImport.normalized(reference)
        guard !key.isEmpty else { throw ToolError("Name a client by id or by name.") }
        let exact = clients.filter { InvoiceImport.normalized($0.name) == key }
        if exact.count == 1 { return exact[0] }
        let partial = exact.isEmpty ? clients.filter { InvoiceImport.normalized($0.name).contains(key) } : exact
        if partial.count == 1 { return partial[0] }
        if partial.isEmpty { throw ToolError("No client matches \"\(reference)\".") }
        let names = partial.map { "\($0.displayName) (\($0.uuid?.uuidString ?? "no id"))" }.joined(separator: ", ")
        throw ToolError("\"\(reference)\" matches several clients: \(names). Name one by id or by full name.")
    }

    /// An invoice by number (2026-003, or 2026-3), by id, or "draft" when
    /// exactly one draft exists.
    func invoice(_ reference: String) throws -> Invoice {
        let invoices = try invoices()
        if let uuid = UUID(uuidString: reference), let invoice = invoices.first(where: { $0.uuid == uuid }) {
            return invoice
        }
        if reference.lowercased() == "draft" {
            let drafts = invoices.filter { $0.status.isEditable }
            switch drafts.count {
            case 1: return drafts[0]
            case 0: throw ToolError("There is no draft.")
            default:
                let ids = drafts.map { $0.uuid?.uuidString ?? "no id" }.joined(separator: ", ")
                throw ToolError("There are \(drafts.count) drafts; name one by id: \(ids).")
            }
        }
        let parts = reference.split(separator: "-")
        if parts.count == 2, let year = Int(parts[0]), let sequence = Int(parts[1]) {
            let number = InvoiceNumbering.format(year: year, sequence: sequence)
            if let invoice = invoices.first(where: { $0.number == number }) { return invoice }
            throw ToolError("No invoice is numbered \(number).")
        }
        throw ToolError("\"\(reference)\" is not an invoice number, an id, or \"draft\".")
    }

    /// The one profile.
    var profile: BusinessProfile { ledger.profile }
}
