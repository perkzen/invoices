import Foundation

/// Lays the year overview out as a spreadsheet: the issuer block, the table
/// of issued invoices, and the TOTAL line.
///
/// The total is written as a value rather than a `=SUM()` formula, because
/// cancelled invoices are listed (their numbers are part of the sequence) but
/// not counted — a formula over the column would silently disagree with the
/// app.
nonisolated enum YearOverviewXLSX {
    /// Resolved through `DocumentText`, like the printed invoice — the sheet
    /// goes to a Slovenian accountant whatever language the app is running in.
    static let columnHeaders: [String] = [
        DocumentText.string("Client"),
        DocumentText.string("Invoice no."),
        DocumentText.string("Date"),
        DocumentText.string("Due date"),
        DocumentText.string("Date of service"),
        DocumentText.string("Amount"),
        DocumentText.string("Payment received"),
    ]

    private static let columnWidths: [Double] = [34, 12, 12, 12, 28, 16, 16]

    static func suggestedFilename(for overview: YearOverview) -> String {
        DocumentText.string("Issued-invoices-\(String(overview.year))")
    }

    static func data(for overview: YearOverview) -> Data {
        XLSXWriter.data(for: sheet(for: overview))
    }

    static func sheet(for overview: YearOverview) -> XLSXWriter.Sheet {
        var rows: [[XLSXWriter.Cell]] = [
            [.text(DocumentText.string("INVOICES ISSUED IN \(String(overview.year))"), style: .bold)],
            [],
        ]

        let issuer = overview.issuer
        if !issuer.headline.isEmpty {
            rows.append([.text(issuer.headline)])
        }
        for line in issuer.addressLines {
            rows.append([.text(line)])
        }
        if !issuer.taxNumber.isEmpty {
            rows.append([.text(DocumentText.string("Tax number: \(issuer.taxNumber)"))])
        }
        rows.append([])

        var headers = columnHeaders
        headers[5] = DocumentText.string("Amount in \(overview.currencyCode)")
        rows.append(headers.map { .text($0, style: .header) })
        let frozenRows = rows.count

        for row in overview.rows {
            rows.append([
                .text(row.clientName ?? DocumentText.string("No client"), style: .cell),
                .text(row.number, style: .cell),
                XLSXWriter.Cell(.date(row.issueDate), style: .cellDate),
                XLSXWriter.Cell(.date(row.dueDate), style: .cellDate),
                .text(row.servicePeriod, style: .cell),
                XLSXWriter.Cell(.number(row.amount), style: .cellMoney),
                paymentCell(for: row),
            ])
        }

        rows.append([])
        var total: [XLSXWriter.Cell] = Array(
            repeating: XLSXWriter.Cell(.empty, style: .totalText), count: columnHeaders.count
        )
        total[0] = .text(DocumentText.string("TOTAL"), style: .totalText)
        total[5] = XLSXWriter.Cell(.number(overview.total), style: .totalMoney)
        rows.append(total)

        return XLSXWriter.Sheet(
            name: DocumentText.string("Invoices \(String(overview.year))"),
            rows: rows,
            columnWidths: columnWidths,
            frozenRows: frozenRows
        )
    }

    /// A real date when the invoice was paid, so the column stays sortable;
    /// otherwise the reason there is no date, or nothing at all.
    private static func paymentCell(for row: YearOverviewRow) -> XLSXWriter.Cell {
        if row.isCancelled { return .text(DocumentText.string("Cancelled"), style: .cell) }
        if let paidDate = row.paidDate {
            return XLSXWriter.Cell(.date(paidDate), style: .cellDate)
        }
        return .text("", style: .cell)
    }
}
