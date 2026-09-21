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
    @Environment(\.modelContext) private var context

    @State private var section: AppSection? = .overview
    @State private var invoiceSelection: PersistentIdentifier?
    @State private var clientSelection: PersistentIdentifier?
    @State private var overviewYear: Int?
    @State private var isImporting = false

    private var importSpreadsheet: ImportSpreadsheetAction {
        ImportSpreadsheetAction { isImporting = true }
    }

    var body: some View {
        // One fetch per pass, for the two columns My business fills. The
        // profile exists from the first launch on; reading it here never
        // inserts during a view update.
        let profile = Ledger(context).profile

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
            // My business and Settings are forms, not lists of things to
            // pick from: the form itself fills this column, and what it
            // changes — the printed invoice — fills the one beside it.
            case .business:
                BusinessForm(profile: profile)
                    .navigationSplitViewColumnWidth(min: 440, ideal: 480, max: 560)
            case .settings:
                // Two preferences and nothing to pick from: no middle column
                // at all, so the form has the width the other sections give
                // their detail.
                // The window title comes from this column, so it keeps the
                // one the section is called by.
                Color.clear
                    .navigationTitle("Settings")
                    .navigationSplitViewColumnWidth(0)
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
            case .business:
                BusinessPreview(profile: profile)
            case .settings:
                GeneralSettingsForm()
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
