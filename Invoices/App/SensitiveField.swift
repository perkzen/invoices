import SwiftUI

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
