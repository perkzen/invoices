import Foundation
import SwiftData

/// Slovenian rules require invoice numbers to run in an unbroken sequence
/// within a numbering period (here: the calendar year). Gaps have to be
/// explainable, so numbers are only assigned when an invoice is issued —
/// `Ledger.issue` is the one caller of `assign`.
enum InvoiceNumbering {
    nonisolated static func format(year: Int, sequence: Int) -> String {
        String(format: "%d-%03d", year, sequence)
    }

    /// The bank reference most s.p. use: the SI00 model over the invoice
    /// number. A draft has no number yet, so it shows what will be filled in.
    nonisolated static func defaultReference(number: String) -> String {
        number.isEmpty ? "SI00 (št. računa)" : "SI00 \(number)"
    }

    static func nextSequence(for year: Int, in context: ModelContext) -> Int {
        var descriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate { $0.year == year },
            sortBy: [SortDescriptor(\.sequence, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let highest = (try? context.fetch(descriptor))?.first?.sequence ?? 0
        return highest + 1
    }

    /// Assigns the next number in the year of `issueDate`. A draft keeps an
    /// empty number until this runs.
    static func assign(to invoice: Invoice, in context: ModelContext) {
        let year = Formatting.calendar.component(.year, from: invoice.issueDate)
        let sequence = nextSequence(for: year, in: context)
        invoice.year = year
        invoice.sequence = sequence
        invoice.number = format(year: year, sequence: sequence)
    }
}
