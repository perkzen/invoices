import SwiftData
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case invoices
    case clients
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .invoices: String(localized: "Računi")
        case .clients: String(localized: "Stranke")
        case .settings: String(localized: "Nastavitve")
        }
    }

    var symbol: String {
        switch self {
        case .invoices: "doc.text"
        case .clients: "person.2"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var section: AppSection? = .invoices

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(AppSection.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            switch section {
            case .invoices:
                NavigationStack { InvoiceListView() }
            case .clients:
                NavigationStack { ClientListView() }
            case .settings:
                NavigationStack {
                    SettingsContent()
                        .navigationTitle(AppSection.settings.title)
                }
            case nil:
                ContentUnavailableView("Izberi razdelek", systemImage: "sidebar.left")
            }
        }
        .frame(minWidth: 1100, minHeight: 600)
    }
}
