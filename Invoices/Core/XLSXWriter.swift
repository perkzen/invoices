import Foundation

/// Builds a single-sheet .xlsx workbook by hand — the OOXML parts plus a
/// stored ZIP around them (`ZIPArchive`). Hand-rolling it keeps the app
/// dependency-free, and the format only has to cover what a year overview
/// needs: text, dates, money and a handful of styles.
///
/// Values are written as real numbers and real dates rather than strings, so
/// the exported sheet can be sorted, summed and re-formatted in Excel instead
/// of being a picture of a table.
nonisolated enum XLSXWriter {
    // MARK: Cell model

    enum Value: Equatable {
        case empty
        case text(String)
        case number(Decimal)
        case date(Date)
    }

    /// Indexes into the `cellXfs` list written by `stylesXML` — the only
    /// styles a year overview uses.
    enum Style: Int {
        case plain = 0
        case bold = 1
        case cell = 2        // bordered text
        case cellDate = 3    // bordered d. m. yyyy
        case cellMoney = 4   // bordered #,##0.00 €
        case header = 5      // bold, filled, bordered
        case totalText = 6   // bold, filled, bordered
        case totalMoney = 7  // bold, filled, bordered, money
    }

    struct Cell {
        var value: Value
        var style: Style

        init(_ value: Value, style: Style = .plain) {
            self.value = value
            self.style = style
        }

        static func text(_ string: String, style: Style = .plain) -> Cell {
            Cell(.text(string), style: style)
        }
    }

    struct Sheet {
        var name: String
        /// Rows top to bottom; each row's cells start at column A.
        var rows: [[Cell]]
        /// Character widths, column A first.
        var columnWidths: [Double] = []
        /// Number of leading rows to freeze, so the table header stays put.
        var frozenRows: Int = 0
    }

    // MARK: Building

    static func data(for sheet: Sheet) -> Data {
        ZIPArchive.archive([
            .init(path: "[Content_Types].xml", data: Data(contentTypesXML.utf8)),
            .init(path: "_rels/.rels", data: Data(rootRelsXML.utf8)),
            .init(path: "xl/workbook.xml", data: Data(workbookXML(name: sheet.name).utf8)),
            .init(path: "xl/_rels/workbook.xml.rels", data: Data(workbookRelsXML.utf8)),
            .init(path: "xl/styles.xml", data: Data(stylesXML.utf8)),
            .init(path: "xl/worksheets/sheet1.xml", data: Data(worksheetXML(sheet).utf8)),
        ])
    }

    /// "A", "B", … "Z", "AA". One-based.
    static func columnName(_ index: Int) -> String {
        var index = index
        var name = ""
        while index > 0 {
            let remainder = (index - 1) % 26
            name = String(UnicodeScalar(UInt8(65 + remainder))) + name
            index = (index - 1) / 26
        }
        return name
    }

    /// Excel stores a date as the number of days since 1899-12-30. The serial
    /// is derived from the calendar components, not from a time interval, so a
    /// timezone offset cannot push a date onto the previous day.
    static func serial(for date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return 0 }
        let serial = daysSinceEpoch(year: year, month: month, day: day) + 25_569
        // Excel keeps Lotus 1-2-3's phantom 29 February 1900; every serial up
        // to that day is one higher than the real elapsed count. Invoices
        // never reach back there, but the arithmetic may as well be right.
        return serial <= 60 ? serial - 1 : serial
    }

    /// Days from 1970-01-01 to the given proleptic Gregorian date.
    private static func daysSinceEpoch(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = year - (month <= 2 ? 1 : 0)
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func escape(_ string: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(string.count)
        for character in string {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&apos;"
            // Control characters are not representable in XML 1.0.
            case let other where other.unicodeScalars.contains(where: {
                $0.value < 0x20 && $0.value != 0x09 && $0.value != 0x0A
            }):
                escaped += " "
            case let other: escaped.append(other)
            }
        }
        return escaped
    }

    // MARK: Parts

    private static func worksheetXML(_ sheet: Sheet) -> String {
        let columnCount = sheet.rows.map(\.count).max() ?? 1
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <dimension ref="A1:\(columnName(max(columnCount, 1)))\(max(sheet.rows.count, 1))"/>
        <sheetViews><sheetView tabSelected="1" workbookViewId="0">
        """
        if sheet.frozenRows > 0 {
            xml += """
            <pane ySplit="\(sheet.frozenRows)" topLeftCell="A\(sheet.frozenRows + 1)" \
            activePane="bottomLeft" state="frozen"/>
            """
        }
        xml += "</sheetView></sheetViews>"

        if !sheet.columnWidths.isEmpty {
            xml += "<cols>"
            for (index, width) in sheet.columnWidths.enumerated() {
                xml += "<col min=\"\(index + 1)\" max=\"\(index + 1)\" width=\"\(width)\" customWidth=\"1\"/>"
            }
            xml += "</cols>"
        }

        xml += "<sheetData>"
        for (rowIndex, cells) in sheet.rows.enumerated() {
            let rowNumber = rowIndex + 1
            let body = cells.enumerated()
                .compactMap { cellXML($0.element, reference: "\(columnName($0.offset + 1))\(rowNumber)") }
                .joined()
            guard !body.isEmpty else { continue }
            xml += "<row r=\"\(rowNumber)\">\(body)</row>"
        }
        xml += "</sheetData></worksheet>"
        return xml
    }

    /// Returns nil for a cell that carries neither content nor styling —
    /// leaving it out of the file entirely is what Excel itself does.
    private static func cellXML(_ cell: Cell, reference: String) -> String? {
        let style = cell.style == .plain ? "" : " s=\"\(cell.style.rawValue)\""
        switch cell.value {
        case .empty:
            return cell.style == .plain ? nil : "<c r=\"\(reference)\"\(style)/>"
        case .text(let string):
            guard !string.isEmpty else {
                return cell.style == .plain ? nil : "<c r=\"\(reference)\"\(style)/>"
            }
            // Inline strings keep the workbook to one sheet part — no
            // sharedStrings.xml to keep in sync.
            return "<c r=\"\(reference)\"\(style) t=\"inlineStr\"><is><t xml:space=\"preserve\">"
                + escape(string) + "</t></is></c>"
        case .number(let value):
            return "<c r=\"\(reference)\"\(style)><v>\(value)</v></c>"
        case .date(let date):
            return "<c r=\"\(reference)\"\(style)><v>\(serial(for: date))</v></c>"
        }
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
    """

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static let workbookRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    private static func workbookXML(name: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="\(escape(name))" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
        """
    }

    /// Excel repairs a workbook whose style table is incomplete, so the
    /// mandatory built-ins (the `none` and `gray125` fills, one border, one
    /// `cellStyleXfs` entry) are all present even though nothing uses them.
    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <numFmts count="2">
    <numFmt numFmtId="164" formatCode="d\\.\\ m\\.\\ yyyy"/>
    <numFmt numFmtId="165" formatCode="#,##0.00\\ &quot;€&quot;"/>
    </numFmts>
    <fonts count="2">
    <font><sz val="11"/><color theme="1"/><name val="Calibri"/><family val="2"/></font>
    <font><b/><sz val="11"/><color theme="1"/><name val="Calibri"/><family val="2"/></font>
    </fonts>
    <fills count="3">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFB4C7E7"/><bgColor indexed="64"/></patternFill></fill>
    </fills>
    <borders count="2">
    <border><left/><right/><top/><bottom/><diagonal/></border>
    <border>
    <left style="thin"><color indexed="64"/></left><right style="thin"><color indexed="64"/></right>
    <top style="thin"><color indexed="64"/></top><bottom style="thin"><color indexed="64"/></bottom>
    <diagonal/></border>
    </borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="8">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>
    <xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
    <xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
    <xf numFmtId="165" fontId="1" fillId="2" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>
    </cellXfs>
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    <dxfs count="0"/>
    <tableStyles count="0" defaultTableStyle="TableStyleMedium2" defaultPivotStyle="PivotStyleLight16"/>
    </styleSheet>
    """
}
