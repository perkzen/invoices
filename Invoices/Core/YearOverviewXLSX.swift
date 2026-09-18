import Foundation

/// Lays the year overview out as a spreadsheet: the issuer block, the table
/// of issued invoices, and the SKUPAJ line.
///
/// The total is written as a value rather than a `=SUM()` formula, because
/// cancelled invoices are listed (their numbers are part of the sequence) but
/// not counted — a formula over the column would silently disagree with the
/// app.
nonisolated enum YearOverviewXLSX {
    static let columnHeaders: [String] = [
        String(localized: "Stranka"),
        String(localized: "Račun št."),
        String(localized: "Datum"),
        String(localized: "Valuta"),
        String(localized: "Datum opravljene storitve"),
        String(localized: "Vrednost"),
        String(localized: "Prejem plačila"),
    ]

    private static let columnWidths: [Double] = [34, 12, 12, 12, 28, 16, 16]

    static func suggestedFilename(for overview: YearOverview) -> String {
        "Izdani-racuni-\(overview.year)"
    }

    static func data(for overview: YearOverview) -> Data {
        XLSXWriter.data(for: sheet(for: overview))
    }

    static func sheet(for overview: YearOverview) -> XLSXWriter.Sheet {
        var rows: [[XLSXWriter.Cell]] = [
            [.text(overview.title, style: .bold)],
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
            rows.append([.text(String(localized: "Davčna številka: \(issuer.taxNumber)"))])
        }
        rows.append([])

        var headers = columnHeaders
        headers[5] = "\(headers[5]) v \(overview.currencyCode)"
        rows.append(headers.map { .text($0, style: .header) })
        let frozenRows = rows.count

        for row in overview.rows {
            rows.append([
                .text(row.clientName, style: .cell),
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
        total[0] = .text(String(localized: "SKUPAJ"), style: .totalText)
        total[5] = XLSXWriter.Cell(.number(overview.total), style: .totalMoney)
        rows.append(total)

        return XLSXWriter.Sheet(
            name: String(localized: "Računi \(String(overview.year))"),
            rows: rows,
            columnWidths: columnWidths,
            frozenRows: frozenRows
        )
    }

    /// A real date when the invoice was paid, so the column stays sortable;
    /// otherwise the reason there is no date, or nothing at all.
    private static func paymentCell(for row: YearOverviewRow) -> XLSXWriter.Cell {
        if let paidDate = row.paidDate, !row.isCancelled {
            return XLSXWriter.Cell(.date(paidDate), style: .cellDate)
        }
        return .text(row.paymentNote, style: .cell)
    }
}
