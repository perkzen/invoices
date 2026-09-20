import SwiftUI

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
            case .overview:
                NavigationStack { YearOverviewView() }
            case .settings:
                NavigationStack {
                    SettingsContent()
                        .navigationTitle(AppSection.settings.title)
                }
            case nil:
                ContentUnavailableView("Choose a section", systemImage: "sidebar.left")
            }
        }
        .frame(minWidth: 1100, minHeight: 600)
    }
}
