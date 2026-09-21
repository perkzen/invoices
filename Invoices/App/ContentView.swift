import SwiftUI

struct ContentView: View {
    @State private var section: AppSection? = .invoices
    @State private var isImporting = false

    private var importSpreadsheet: ImportSpreadsheetAction {
        ImportSpreadsheetAction { isImporting = true }
    }

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
        // One flow per window; the sections and the File menu only ask for it.
        // What was recorded shows up in the Overview, so the window goes there.
        .spreadsheetImport(isPresented: $isImporting) { _ in section = .overview }
        .environment(\.importSpreadsheet, importSpreadsheet)
        .focusedSceneValue(\.importSpreadsheet, importSpreadsheet)
    }
}
