import ArgumentParser
import Foundation

/// `invoices` — the app's ledger from the command line, for scripts and for
/// coding agents. It compiles the app's own models, rules and renderers, and
/// opens the app's own store, so nothing it does could disagree with the app.
///
/// Every command prints JSON on stdout. A failure prints `{"error": "…"}` on
/// stderr and exits with status 1, so a caller never has to parse prose.
@main
struct InvoicesCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "invoices",
            abstract: "The invoices and clients of the Invoices app, from the command line.",
            discussion: """
                Opens the store of the installed app (or the development build's with --dev) \
                and applies the app's rules: only a draft can be edited or deleted, issuing \
                assigns the next number of the year and locks the invoice, and an issued \
                invoice is cancelled, never removed. Every command prints JSON on stdout; a \
                failure prints {"error": "…"} on stderr and exits with status 1.

                An invoice is named by its number (2026-003), its id, or "draft" when there is \
                exactly one draft. A client is named by its id or by its name, or a unique part \
                of it. Dates are written YYYY-MM-DD; amounts as plain numbers (49.90).
                """,
            subcommands: [
                StoreCommand.self,
                ProfileCommand.self,
                ClientCommand.self,
                InvoiceCommand.self,
                OverviewCommand.self,
            ]
        )
    }
}
