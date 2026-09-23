import AppKit
import SwiftUI

/// Installing the command-line tool, from wherever the user asks for it: the
/// Invoices menu and the Settings section both run this.
///
/// The tool is already inside the app, so this is only the symlink that puts
/// it on the PATH — and that is the one part the app cannot do by itself. It
/// is sandboxed, and every directory worth linking into lies outside its
/// container. The open panel is what grants the access: the directory the
/// user chooses becomes writable under
/// `com.apple.security.files.user-selected.read-write`, and nothing else does.
///
/// Debug is left out for the reason it has no updater — it is a separate app,
/// built into `build/`, and linking its helper would leave the user with a
/// link into a directory the next clean build empties.
#if !DEBUG

    @MainActor
    enum CommandLineToolInstall {
        /// Asks for the directory, links the tool into it, and says what
        /// happened either way.
        static func run() {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            // Every part of ~/.local/bin is hidden, so without this the panel
            // cannot show the user the directory it just suggested.
            panel.showsHiddenFiles = true
            panel.directoryURL = CommandLineTool.suggestedDirectory
            panel.prompt = String(localized: "Install")
            panel.message = String(localized: "Choose a folder that is on your PATH. The tool is linked into it as “invoices”.")
            guard panel.runModal() == .OK, let directory = panel.url else { return }

            // Sandboxed: the chosen directory is writable inside this scope.
            let scoped = directory.startAccessingSecurityScopedResource()
            defer { if scoped { directory.stopAccessingSecurityScopedResource() } }

            do {
                let link = try CommandLineTool.install(in: directory).path(percentEncoded: false)
                report(
                    String(localized: "The command line tool is installed"),
                    String(localized: "\(link) points to the tool inside this app, and an update keeps it current.\n\nIf that folder is not on your PATH, add it. To teach Claude Code the tool, run: invoices skill > ~/.claude/skills/invoices/SKILL.md")
                )
            } catch CommandLineTool.InstallError.occupied(let link) {
                failed(String(localized: "Something that is not a link to this app is already called “invoices” in that folder. Choose another folder, or remove \(link.path(percentEncoded: false)) yourself."))
            } catch {
                // /usr/local/bin is the one users reach for, and it belongs to
                // root: the app is refused there whatever the sandbox allows,
                // so the way through is the Terminal.
                failed(String(localized: "\(error.localizedDescription)\n\nA folder that belongs to the system, such as /usr/local/bin, cannot be written by the app. From the Terminal:\n\nsudo ln -sfn \(CommandLineTool.helperURL.path(percentEncoded: false)) /usr/local/bin/invoices"))
            }
        }

        private static func failed(_ message: String) {
            report(String(localized: "The command line tool could not be installed"), message, style: .warning)
        }

        private static func report(_ title: String, _ message: String, style: NSAlert.Style = .informational) {
            let alert = NSAlert()
            alert.alertStyle = style
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
        }
    }

#endif
