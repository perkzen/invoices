import SwiftUI

/// Zasebni način — en sam preklop, ki zakrije vrednosti, ki jih mimoidoči
/// ali deljen zaslon ne bi smela prebrati: bančni račun, davčne številke in
/// vse zneske.
///
/// To je nastavitev pogleda in ne podatek o poslovanju, zato živi v
/// `AppStorage` in se shrambe ne dotakne: izvožen PDF, preglednica in
/// natisnjen račun nosijo prave vrednosti tudi takrat, ko je vklopljen.
enum PrivacyMode {
    static let storageKey = "hidesSensitiveValues"
}

extension View {
    /// Označi vrednost, ki jo zasebni način zakrije. Sam po sebi ne naredi
    /// nič — zakrije jo šele `privacyRedacted()` na vrhu drevesa.
    func sensitiveValue() -> some View {
        privacySensitive()
    }

    /// Enkrat na okno, na korenu. Razlog `.privacy` zakrije le podpoglede,
    /// označene s `sensitiveValue()`, zato oznake, datumi in opisi okoli
    /// njih ostanejo berljivi.
    func privacyRedacted() -> some View {
        modifier(PrivacyRedaction())
    }
}

private struct PrivacyRedaction: ViewModifier {
    @AppStorage(PrivacyMode.storageKey) private var hidesSensitiveValues = false

    func body(content: Content) -> some View {
        content.redacted(reason: hidesSensitiveValues ? .privacy : [])
    }
}

/// Vnosno polje, katerega vrednost zasebni način zakrije. Zakriti `TextField`
/// vzame s sabo tudi svojo oznako, zato oznaka stoji zunaj njega — sicer bi
/// v razdelku ostali sami sivi pravokotniki brez imen.
struct SensitiveField: View {
    let title: LocalizedStringKey
    @Binding var text: String

    init(_ title: LocalizedStringKey, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text)
                .labelsHidden()
                .sensitiveValue()
        }
    }
}

/// Pogled › Skrij občutljive podatke. Stikalo mora biti dosegljivo v eni
/// potezi — njegov trenutek je sekunda pred začetkom deljenja zaslona in
/// pot v Nastavitve je za to prepočasna.
struct PrivacyCommands: Commands {
    @AppStorage(PrivacyMode.storageKey) private var hidesSensitiveValues = false

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Toggle("Skrij občutljive podatke", isOn: $hidesSensitiveValues)
                .keyboardShortcut("h", modifiers: [.command, .shift])
        }
    }
}
