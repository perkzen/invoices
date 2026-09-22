import Foundation

/// The `invoices` command-line tool that ships inside this app, and what it
/// takes to put it on the PATH.
///
/// The tool is at `Contents/Helpers/invoices`, so every copy of the app
/// carries its own. What goes on the PATH is a symlink into the bundle rather
/// than a copy of the binary: an update replaces the tool behind the link
/// along with the app, so the link is made once and stays current.
enum CommandLineTool {
    /// The tool inside the running app — whichever copy that is.
    static var helperURL: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/invoices")
    }

    static var isPresent: Bool {
        FileManager.default.isExecutableFile(atPath: helperURL.path(percentEncoded: false))
    }

    enum InstallError: Error {
        /// Something that is not one of our links already has the name.
        case occupied(URL)
    }

    /// Links `invoices` in `directory` to the tool, and says where the link
    /// went. Installing twice is the ordinary case — the second run replaces
    /// the first run's link.
    @discardableResult
    static func install(_ helper: URL = helperURL, in directory: URL) throws -> URL {
        let link = directory.appending(path: "invoices")
        let manager = FileManager.default

        // A link left by an earlier install is ours to replace. Anything else
        // is someone's own `invoices` — a poor thing for a menu item to
        // overwrite without saying so.
        if let type = try? manager.attributesOfItem(atPath: link.path(percentEncoded: false))[.type]
            as? FileAttributeType
        {
            guard type == .typeSymbolicLink else { throw InstallError.occupied(link) }
            try manager.removeItem(at: link)
        }
        try manager.createSymbolicLink(at: link, withDestinationURL: helper)
        return link
    }

    /// Where to open the panel. `~/.local/bin` is the conventional directory a
    /// user can write without `sudo`; `/usr/local/bin` is deliberately not
    /// offered, because it belongs to root and the write would fail only after
    /// the user had chosen it.
    static var suggestedDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let local = home.appending(path: ".local/bin")
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: local.path(percentEncoded: false), isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue ? local : home
    }
}
