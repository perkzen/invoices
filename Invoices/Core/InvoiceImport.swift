import Foundation

/// Reads a bookkeeper's spreadsheet of issued invoices — the seven columns
/// `YearOverviewXLSX` writes, or any sheet with the same information under
/// other headings — into invoices ready to be recorded in the ledger.
///
/// Pure values: the grid comes in, a `Plan` comes out, and every row that
/// cannot become an invoice says why. The ledger records the plan; the
/// import sheet shows it. Nothing here touches a `ModelContainer`.
nonisolated enum InvoiceImport {
    // MARK: Columns

    enum Field: String, CaseIterable, Identifiable, Sendable {
        case client
        case number
        case issueDate
        case dueDate
        case servicePeriod
        case amount
        case paidDate

        var id: String { rawValue }

        var title: String {
            switch self {
            case .client: String(localized: "Client")
            case .number: String(localized: "Invoice no.")
            case .issueDate: String(localized: "Date")
            case .dueDate: String(localized: "Due date")
            case .servicePeriod: String(localized: "Date of service")
            case .amount: String(localized: "Amount")
            case .paidDate: String(localized: "Payment received")
            }
        }

        /// Without these a row cannot become an issued invoice; the rest are
        /// filled in from the issue date and the payment term.
        var isRequired: Bool {
            switch self {
            case .client, .number, .issueDate, .amount: true
            case .dueDate, .servicePeriod, .paidDate: false
            }
        }

        /// What a heading for this column may say — in English, and in the
        /// document language through the same catalog keys the export uses,
        /// so the app's own spreadsheet always reads back.
        var headings: [String] {
            switch self {
            case .client:
                ["client", "customer", "buyer", DocumentText.string("Client")]
            case .number:
                ["invoice no", "invoice number", "number", DocumentText.string("Invoice no.")]
            case .issueDate:
                ["issue date", "issued", "date", DocumentText.string("Date")]
            case .dueDate:
                ["due", DocumentText.string("Due date")]
            case .servicePeriod:
                ["service", "period", DocumentText.string("Date of service")]
            case .amount:
                ["amount", "total", "value", "sum", DocumentText.string("Amount")]
            case .paidDate:
                ["paid", "payment received", "received", DocumentText.string("Payment received")]
            }
        }

        /// The specific headings claim their columns before the generic ones:
        /// "Date of service" and "Due date" both contain "date".
        static let matchingOrder: [Field] = [
            .servicePeriod, .dueDate, .paidDate, .number, .amount, .client, .issueDate,
        ]
    }

    /// Which column holds which field, and where the data starts.
    struct Mapping: Equatable, Sendable {
        /// The row of headings; data starts below it. `nil` when the sheet
        /// has none, and the data starts at the top.
        var headerRow: Int?
        var columns: [Field: Int] = [:]

        var firstDataRow: Int { headerRow.map { $0 + 1 } ?? 0 }

        var missingFields: [Field] {
            Field.allCases.filter { $0.isRequired && columns[$0] == nil }
        }

        var isComplete: Bool { missingFields.isEmpty }
    }

    /// Finds the heading row — the first with at least three known headings
    /// — and claims a column for every field whose heading it recognises.
    static func detectMapping(in grid: Spreadsheet.Grid) -> Mapping {
        for (index, row) in grid.rows.prefix(30).enumerated() {
            let headings = row.map { normalized($0.text) }
            var columns: [Field: Int] = [:]
            for field in Field.matchingOrder {
                let wanted = field.headings.map(normalized)
                let free = headings.indices.filter { !columns.values.contains($0) && !headings[$0].isEmpty }
                // A heading that is exactly the field's name beats one that
                // merely contains it: "Invoice no." over "Notes".
                let column = free.first { wanted.contains(headings[$0]) }
                    ?? free.first { column in wanted.contains { headings[column].contains($0) } }
                if let column { columns[field] = column }
            }
            if columns.count >= 3 {
                return Mapping(headerRow: index, columns: columns)
            }
        }
        return Mapping(headerRow: nil)
    }

    /// One column as the mapping step names it: its letter, its heading,
    /// and the first value under it.
    struct Column: Identifiable, Sendable, Equatable {
        var index: Int
        var heading: String
        var sample: String

        var id: Int { index }
        var letter: String { Spreadsheet.Grid.columnName(index) }
    }

    static func columns(of grid: Spreadsheet.Grid, mapping: Mapping) -> [Column] {
        (0..<grid.columnCount).map { column in
            let heading = mapping.headerRow.map { grid[$0, column].text } ?? ""
            let sample = (mapping.firstDataRow..<min(grid.rows.count, mapping.firstDataRow + 20))
                .lazy
                .map { grid[$0, column].text }
                .first { !$0.isEmpty } ?? ""
            return Column(index: column, heading: heading, sample: sample)
        }
    }

    // MARK: Rows

    /// The number as the ledger keys it, so a row can be checked against
    /// what is already recorded.
    struct Number: Hashable, Sendable {
        var year: Int
        var sequence: Int
    }

    /// One invoice as it will be recorded: issued on its date under its own
    /// number, with a single line item for the amount.
    struct Row: Identifiable, Sendable, Equatable {
        /// The row in the file, as Excel numbers it.
        var sourceRow: Int
        var number: String
        var key: Number
        var clientName: String
        var issueDate: Date
        var dueDate: Date
        var serviceDate: Date
        var serviceDateEnd: Date?
        var amount: Decimal
        var paidDate: Date?
        var isCancelled: Bool

        var id: Int { sourceRow }

        var status: InvoiceStatus {
            if isCancelled { return .cancelled }
            return paidDate == nil ? .issued : .paid
        }
    }

    enum Problem: Equatable, Sendable {
        case noNumber
        case unreadableNumber(String)
        case noClient
        case noIssueDate
        case unreadableDate(String)
        case noAmount
        case unreadableAmount(String)
        case duplicateInFile
        case alreadyRecorded

        var message: String {
            switch self {
            case .noNumber: String(localized: "No invoice number")
            case .unreadableNumber(let text): String(localized: "“\(text)” is not an invoice number")
            case .noClient: String(localized: "No client")
            case .noIssueDate: String(localized: "No date")
            case .unreadableDate(let text): String(localized: "“\(text)” is not a date")
            case .noAmount: String(localized: "No amount")
            case .unreadableAmount(let text): String(localized: "“\(text)” is not an amount")
            case .duplicateInFile: String(localized: "Appears twice in the file")
            case .alreadyRecorded: String(localized: "Already in the ledger")
            }
        }
    }

    /// A row of the file and what will become of it.
    struct Candidate: Identifiable, Sendable, Equatable {
        enum Outcome: Equatable, Sendable {
            case imports(Row)
            case skipped(Problem)
        }

        var sourceRow: Int
        var number: String
        var clientName: String
        var outcome: Outcome

        var id: Int { sourceRow }

        var row: Row? {
            if case .imports(let row) = outcome { return row }
            return nil
        }

        var problem: Problem? {
            if case .skipped(let problem) = outcome { return problem }
            return nil
        }
    }

    /// The whole file, sorted: what imports, what is skipped and why, and
    /// which clients the ledger does not know yet.
    struct Plan: Sendable, Equatable {
        var candidates: [Candidate] = []
        /// Names not matched to a client in the ledger, in order of first
        /// appearance, each once.
        var newClientNames: [String] = []

        var rows: [Row] { candidates.compactMap(\.row) }
        var skipped: [Candidate] { candidates.filter { $0.problem != nil } }

        var total: Decimal { rows.filter { !$0.isCancelled }.reduce(0) { $0 + $1.amount } }
        var years: [Int] { Array(Set(rows.map(\.key.year))).sorted() }
        var currencyCode: String { "EUR" }
    }

    /// What the ledger already holds, so the plan can leave it alone.
    struct Existing: Sendable {
        var numbers: Set<Number> = []
        var clientNames: [String] = []
        var paymentTermDays: Int = 8
    }

    static func plan(grid: Spreadsheet.Grid, mapping: Mapping, existing: Existing = Existing()) -> Plan {
        let cancelledLabels = ["cancelled", "canceled", "void", DocumentText.string("Cancelled")].map(normalized)
        let noClientLabels = ["no client", DocumentText.string("No client")].map(normalized)
        let totalLabels = ["total", DocumentText.string("TOTAL")].map(normalized)
        let knownClients = Set(existing.clientNames.map(normalized))

        var plan = Plan()
        var seen: Set<Number> = []
        var newClients: [String: String] = [:]  // normalized → as first written
        var newClientOrder: [String] = []

        for index in mapping.firstDataRow..<grid.rows.count {
            let row = grid.rows[index]
            guard row.contains(where: { !$0.isEmpty }) else { continue }
            func cell(_ field: Field) -> Spreadsheet.Value {
                mapping.columns[field].map { grid[index, $0] } ?? .empty
            }

            let numberText = cell(.number).text
            let clientName = cell(.client).text
            // The TOTAL line under the table is not an invoice.
            if numberText.isEmpty, let first = row.first(where: { !$0.isEmpty }),
               totalLabels.contains(normalized(first.text)) {
                continue
            }

            var candidate = Candidate(
                sourceRow: index + 1, number: numberText, clientName: clientName, outcome: .skipped(.noNumber)
            )
            defer { plan.candidates.append(candidate) }

            guard !numberText.isEmpty else { continue }
            guard let issueDate = cell(.issueDate).date() else {
                candidate.outcome = .skipped(cell(.issueDate).isEmpty ? .noIssueDate : .unreadableDate(cell(.issueDate).text))
                continue
            }
            guard let key = number(from: numberText, issueDate: issueDate) else {
                candidate.outcome = .skipped(.unreadableNumber(numberText))
                continue
            }
            guard !clientName.isEmpty, !noClientLabels.contains(normalized(clientName)) else {
                candidate.outcome = .skipped(.noClient)
                continue
            }
            guard let amount = cell(.amount).decimal else {
                candidate.outcome = .skipped(cell(.amount).isEmpty ? .noAmount : .unreadableAmount(cell(.amount).text))
                continue
            }
            guard !existing.numbers.contains(key) else {
                candidate.outcome = .skipped(.alreadyRecorded)
                continue
            }
            guard seen.insert(key).inserted else {
                candidate.outcome = .skipped(.duplicateInFile)
                continue
            }

            let service = cell(.servicePeriod).dates()
            let payment = cell(.paidDate)
            let dueDate = cell(.dueDate).date()
                ?? Formatting.calendar.date(byAdding: .day, value: existing.paymentTermDays, to: issueDate)
                ?? issueDate
            candidate.outcome = .imports(Row(
                sourceRow: index + 1,
                number: numberText,
                key: key,
                clientName: clientName,
                issueDate: issueDate,
                dueDate: dueDate,
                serviceDate: service.first ?? issueDate,
                serviceDateEnd: service.count > 1 ? service[1] : nil,
                amount: amount,
                paidDate: payment.date(),
                isCancelled: cancelledLabels.contains(normalized(payment.text))
            ))

            let name = normalized(clientName)
            if !knownClients.contains(name), newClients[name] == nil {
                newClients[name] = clientName
                newClientOrder.append(name)
            }
        }
        plan.newClientNames = newClientOrder.compactMap { newClients[$0] }
        return plan
    }

    /// "2026-001", "001/2026", "R-2026-12" or a bare "12": the four-digit
    /// group is the year, the other the sequence. A bare sequence takes the
    /// year of the issue date.
    static func number(from text: String, issueDate: Date) -> Number? {
        let groups = text.split { !$0.isNumber }.compactMap { Int($0) }
        guard !groups.isEmpty else { return nil }
        let yearIndex = groups.firstIndex { (1900...2999).contains($0) && String($0).count == 4 }
        let year = yearIndex.map { groups[$0] } ?? Formatting.calendar.component(.year, from: issueDate)
        let others = groups.enumerated().filter { $0.offset != yearIndex }.map(\.element)
        guard let sequence = others.first, sequence > 0 else { return nil }
        return Number(year: year, sequence: sequence)
    }

    /// Names and headings compared without case, accents, punctuation or
    /// stray spaces — "Invoice no. " and "invoice no" are the same heading.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }
}

// MARK: - New clients

nonisolated extension InvoiceImport {
    /// A client the spreadsheet names but the ledger does not know. The
    /// sheet only carries the name; the address and tax number an issued
    /// invoice has to show are typed in before the import, or later under
    /// Clients.
    struct NewClient: Identifiable, Sendable, Equatable {
        var name: String
        var street: String = ""
        var postalCode: String = ""
        var city: String = ""
        var countryCode: String = "SI"
        var taxNumber: String = ""
        var vatID: String = ""

        var id: String { InvoiceImport.normalized(name) }
    }
}
