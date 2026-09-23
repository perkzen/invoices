import SwiftUI

/// Invoices › Install Command Line Tool…
///
/// The work is `CommandLineToolInstall`, which the Settings section runs too;
/// this is the menu item in front of it. Both are absent from Debug for the
/// reason given there.
#if !DEBUG

    struct CommandLineToolCommands: Commands {
        var body: some Commands {
            CommandGroup(after: .appSettings) {
                Button("Install Command Line Tool…") { CommandLineToolInstall.run() }
                    .disabled(!CommandLineTool.isPresent)
            }
        }
    }

#endif
