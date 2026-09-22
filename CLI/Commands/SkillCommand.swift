import ArgumentParser
import Foundation

/// Prints the agent skill that ships with the app, so an installed copy can
/// set up Claude Code without a checkout of the repository.
struct SkillCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "skill",
            abstract: "Print the agent skill (SKILL.md) that teaches Claude Code to use this tool.",
            discussion: """
                Markdown, not JSON — it is the one command that answers for a person setting \
                things up. Save it where the agent looks:

                    mkdir -p ~/.claude/skills/invoices && invoices skill > ~/.claude/skills/invoices/SKILL.md
                """
        )
    }

    @OptionGroup var store: StoreOptions

    func run() throws {
        let location = StoreLocation.resolve(store)
        let path: String? = MainActor.assumeIsolated {
            location.installedApp()?.path(forResource: "SKILL", ofType: "md")
        }
        guard let path, let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            Output.fail(StoreLocation.noAppMessage)
            throw ExitCode.failure
        }
        print(text, terminator: "")
    }
}
