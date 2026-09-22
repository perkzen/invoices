import ArgumentParser
import Foundation

/// A command that works on the open store. It opens the store the options
/// name, runs `execute` on the main actor — the ledger and the models are
/// main-actor types — saves, and turns any failure into the error JSON.
///
/// `ParsableCommand.run()` is a nonisolated requirement, and the command
/// types are declared `nonisolated` to satisfy it; `main()` calls it on the
/// main thread, which is what lets `execute` assume the main actor.
nonisolated protocol LedgerCommand: ParsableCommand {
    var store: StoreOptions { get }
    @MainActor func execute(_ book: Book) throws
}

extension LedgerCommand {
    nonisolated func run() throws {
        let failure: String? = MainActor.assumeIsolated {
            do {
                let book = try Book.open(store)
                try execute(book)
                try book.save()
                return nil
            } catch let error as ToolError {
                return error.description
            } catch let problem as Ledger.IssueProblem {
                return problem.message
            } catch let problem as Ledger.DeletionProblem {
                return problem.message
            } catch {
                return error.localizedDescription
            }
        }
        if let failure {
            Output.fail(failure)
            throw ExitCode.failure
        }
    }
}
