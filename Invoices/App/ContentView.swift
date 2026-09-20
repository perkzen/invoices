import SwiftData
import SwiftUI

/// Sidebar, list, editor — the three columns of a Mac document-list app.
/// Every section fills the middle column with the things it is about
/// (invoices, clients, years, settings pages) and the right one with the
/// selected thing, so the list never disappears while something is edited.
///
/// Selection is kept per section, so switching to Clients and back lands on
/// the same invoice.
struct ContentView: View {
    @State private var section: AppSection? = .invoices
    @State private var invoiceSelection: PersistentIdentifier?
    @State private var clientSelection: PersistentIdentifier?
    @State private var overviewYear: Int?
    @State private var settingsPage: SettingsPage? = .business

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(AppSection.content) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
            // Settings is a destination one visits rarely, so it sits apart
            // at the foot of the sidebar, set off by the empty space above it
            // rather than a rule. A second list bound to the same selection
            // keeps the row looking and highlighting like the rest.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                List(selection: $section) {
                    Label(AppSection.settings.title, systemImage: AppSection.settings.symbol)
                        .tag(AppSection.settings)
                }
                .listStyle(.sidebar)
                .scrollDisabled(true)
                .frame(height: 44)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } content: {
            switch section {
            case .invoices:
                InvoiceListView(selection: $invoiceSelection)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 460)
            case .clients:
                ClientListView(selection: $clientSelection)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 420)
            case .overview:
                YearListView(selection: $overviewYear)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
            case .settings:
                SettingsPageList(selection: $settingsPage)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
            case nil:
                Color.clear
            }
        } detail: {
            switch section {
            case .invoices:
                InvoiceDetailColumn(selection: invoiceSelection)
            case .clients:
                ClientDetailColumn(selection: clientSelection)
            case .overview:
                YearOverviewView(year: overviewYear)
            case .settings:
                SettingsContent(page: settingsPage)
            case nil:
                ContentUnavailableView("Choose a section", systemImage: "sidebar.left")
            }
        }
        .frame(minWidth: 1100, minHeight: 600)
    }
}
