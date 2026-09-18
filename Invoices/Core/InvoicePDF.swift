import CoreGraphics
import Foundation
import SwiftUI

/// Renders an invoice to a multi-page A4 PDF.
enum InvoicePDF {
    static let pageSize = CGSize(width: 595, height: 842)  // A4 at 72 dpi

    /// Page budgets are counted in layout units of roughly 8 pt. A row costs
    /// a fixed 2 units of padding plus 1 per wrapped text line, because the
    /// padding does not double when a description runs onto a second line.
    private static let maxDescriptionLines = 2
    /// Same budget, for the page view's `lineLimit`.
    static var maxDescriptionLinesForLayout: Int { maxDescriptionLines }
    private static let charactersPerDescriptionLine = 40

    private static func capacity(isFirstPage: Bool, withSummary: Bool, summaryExtra: Int) -> Int {
        // Sized for a first page with a logo and the intro sentence, and a
        // last page with the total, three clause lines and the signature
        // block. Checked by rendering, not derived — see the README.
        switch (isFirstPage, withSummary) {
        case (true, true): 22 - summaryExtra
        case (true, false): 40
        case (false, true): 54 - summaryExtra
        case (false, false): 72
        }
    }

    /// Units the last page loses to text the budget cannot assume: the
    /// invoice's own notes and the profile's footer line.
    static func summaryExtra(notes: String, footer: String) -> Int {
        let noteLines = notes.isEmpty ? 0 : notes.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .reduce(0) { $0 + max(1, ($1.count + 89) / 90) }
        return noteLines + (footer.isEmpty ? 0 : 2)
    }

    /// What one item costs against a page budget.
    static func cost(of line: InvoiceLine) -> Int {
        let text = line.itemDescription.isEmpty ? "—" : line.itemDescription
        let wrapped = (text.count + charactersPerDescriptionLine - 1) / charactersPerDescriptionLine
        return 2 + min(maxDescriptionLines, max(1, wrapped))
    }

    static func paginate(_ lines: [InvoiceLine], summaryExtra: Int = 0) -> [[InvoiceLine]] {
        var pages: [[InvoiceLine]] = []
        var remaining = lines[...]
        var isFirst = true

        while true {
            // The last page carries the summary, so it gets the smaller budget.
            if remaining.reduce(0, { $0 + cost(of: $1) })
                <= capacity(isFirstPage: isFirst, withSummary: true, summaryExtra: summaryExtra) {
                pages.append(Array(remaining))
                return pages
            }

            let budget = capacity(isFirstPage: isFirst, withSummary: false, summaryExtra: summaryExtra)
            var used = 0
            var taken = 0
            for line in remaining {
                let next = used + cost(of: line)
                if next > budget, taken > 0 { break }
                used = next
                taken += 1
            }
            pages.append(Array(remaining.prefix(taken)))
            remaining = remaining.dropFirst(taken)
            isFirst = false

            if remaining.isEmpty {
                // Every item fit, but this page had no room left for the
                // totals — they get a continuation page of their own.
                pages.append([])
                return pages
            }
        }
    }

    static func suggestedFilename(for invoice: Invoice) -> String {
        invoice.number.isEmpty ? "Osnutek-racuna" : "Racun-\(invoice.number)"
    }

    @MainActor
    static func render(invoice: Invoice, profile: BusinessProfile) -> Data? {
        let chunks = paginate(
            invoice.sortedLines,
            summaryExtra: summaryExtra(notes: invoice.notes, footer: profile.invoiceFooter)
        )
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return nil }

        for (index, chunk) in chunks.enumerated() {
            let page = InvoicePDFPage(
                invoice: invoice,
                profile: profile,
                lines: chunk,
                pageNumber: index + 1,
                pageCount: chunks.count,
                showsSummary: index == chunks.count - 1,
                chargesVat: profile.isVatRegistered
            )
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }

        context.closePDF()
        return data as Data
    }
}
