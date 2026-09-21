import Foundation
import Observation

/// One spreadsheet on its way into the ledger: the grid as read, the column
/// mapping the user may correct, the plan that follows from it, and what the
/// user types in along the way. The sheet's steps all edit this one object,
/// so a change on one step is seen on the next.
@Observable
@MainActor
final class ImportSession {
    /// The three things a user may have to do before the book is written.
    /// A step that has nothing to do is skipped on the way in and stays
    /// reachable on the way back.
    enum Step: Int, CaseIterable, Identifiable, Comparable {
        case columns
        case clients
        case review

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .columns: String(localized: "Columns")
            case .clients: String(localized: "New clients")
            case .review: String(localized: "Review")
            }
        }

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let filename: String
    let grid: Spreadsheet.Grid
    let existing: InvoiceImport.Existing

    var mapping: InvoiceImport.Mapping {
        didSet { replan() }
    }
    private(set) var plan: InvoiceImport.Plan
    private(set) var columns: [InvoiceImport.Column]

    /// One entry per client the ledger does not know, kept in step with the
    /// plan: a mapping change may add names or drop them, but what was
    /// typed for a name that stays is not lost.
    var newClients: [InvoiceImport.NewClient] = []

    /// The sheet only carries a total per invoice, so every recorded invoice
    /// gets one line item with this description. On the document, so in
    /// the document's language.
    var lineDescription = DocumentText.string("Services rendered")

    var step: Step

    init(filename: String, grid: Spreadsheet.Grid, existing: InvoiceImport.Existing) {
        self.filename = filename
        self.grid = grid
        self.existing = existing
        let mapping = InvoiceImport.detectMapping(in: grid)
        self.mapping = mapping
        self.plan = InvoiceImport.plan(grid: grid, mapping: mapping, existing: existing)
        self.columns = InvoiceImport.columns(of: grid, mapping: mapping)
        self.step = .review
        replan()
        step = steps.first { hasWork($0) } ?? .review
    }

    private func replan() {
        plan = InvoiceImport.plan(grid: grid, mapping: mapping, existing: existing)
        columns = InvoiceImport.columns(of: grid, mapping: mapping)
        let typed = Dictionary(newClients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        newClients = plan.newClientNames.map { name in
            typed[InvoiceImport.normalized(name)] ?? InvoiceImport.NewClient(name: name)
        }
    }

    // MARK: Steps

    /// The steps this file goes through — the client step only exists when
    /// there is a client to add.
    var steps: [Step] {
        Step.allCases.filter { $0 != .clients || !newClients.isEmpty }
    }

    /// Whether the step has something for the user to do, which is where the
    /// sheet opens.
    private func hasWork(_ step: Step) -> Bool {
        switch step {
        case .columns: !mapping.isComplete
        case .clients: !newClients.isEmpty
        case .review: true
        }
    }

    var previousStep: Step? { steps.last { $0 < step } }
    var nextStep: Step? { steps.first { $0 > step } }

    /// The current step is done and the next may be shown — or, on the
    /// last, the ledger may be written.
    var canProceed: Bool {
        switch step {
        case .columns: mapping.isComplete
        case .clients: true
        case .review: !plan.rows.isEmpty
        }
    }

    func goBack() {
        if let previousStep { step = previousStep }
    }

    func goForward() {
        if let nextStep, canProceed { step = nextStep }
    }

    // MARK: The file, for the columns step

    /// The heading row and the first rows under it, as the file shows them.
    struct PreviewRow: Identifiable {
        var id: Int
        var values: [String]
        var isHeader: Bool
    }

    var previewRows: [PreviewRow] {
        let start = mapping.headerRow ?? mapping.firstDataRow
        let end = min(grid.rows.count, mapping.firstDataRow + 5)
        guard start < end else { return [] }
        return (start..<end).map { row in
            PreviewRow(
                id: row,
                values: (0..<grid.columnCount).map { grid[row, $0].text },
                isHeader: row == mapping.headerRow
            )
        }
    }
}
