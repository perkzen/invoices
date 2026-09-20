import Foundation

/// A spreadsheet read back in: a grid of plain values, with no idea yet of
/// what the columns mean. `InvoiceImport` gives them meaning.
///
/// Reads the two files a bookkeeper actually has — an .xlsx from Excel or
/// Numbers, or a .csv — by hand, like `XLSXWriter` writes them, so the app
/// stays dependency-free.
nonisolated enum Spreadsheet {
    enum Value: Equatable, Sendable {
        case empty
        case text(String)
        case number(Decimal)
    }

    /// Rows top to bottom, each row's cells from column A. Rows and columns
    /// keep their place in the file, so a row number here is the row number
    /// the user sees in Excel, less one.
    struct Grid: Equatable, Sendable {
        var rows: [[Value]] = []

        var columnCount: Int { rows.map(\.count).max() ?? 0 }

        subscript(row: Int, column: Int) -> Value {
            guard rows.indices.contains(row), rows[row].indices.contains(column) else { return .empty }
            return rows[row][column]
        }

        /// "A", "B", … — the column letters the user sees in the file.
        static func columnName(_ index: Int) -> String {
            XLSXWriter.columnName(index + 1)
        }
    }

    enum ReadError: Error, Equatable {
        case unsupportedType(String)
        case notASpreadsheet
        case noWorksheet
        case unreadableText
    }

    /// Reads a file by its extension — `xlsx`, or a delimited text file.
    static func grid(from data: Data, filenameExtension: String) throws -> Grid {
        switch filenameExtension.lowercased() {
        case "xlsx", "xlsm":
            return try XLSXReader.grid(from: data)
        case "csv", "tsv", "txt":
            return try CSVReader.grid(from: data)
        default:
            throw ReadError.unsupportedType(filenameExtension)
        }
    }
}

// MARK: - Reading a value

nonisolated extension Spreadsheet.Value {
    var isEmpty: Bool { text.isEmpty }

    /// The cell as the user would read it, trimmed; a number in plain
    /// decimal notation.
    var text: String {
        switch self {
        case .empty: ""
        case .text(let string): string.trimmingCharacters(in: .whitespacesAndNewlines)
        case .number(let value): "\(value)"
        }
    }

    /// A number, or a typed amount: "4.389,99 €", "4389.99", "1,000.50".
    var decimal: Decimal? {
        switch self {
        case .empty: nil
        case .number(let value): value
        case .text(let string): Spreadsheet.decimal(from: string)
        }
    }

    /// The first date in the cell: an Excel serial in a numeric cell, or a
    /// typed date in any of the shapes people and programs write.
    func date(calendar: Calendar = Formatting.calendar) -> Date? {
        dates(calendar: calendar).first
    }

    /// Every date in the cell, in order — a service period is two.
    func dates(calendar: Calendar = Formatting.calendar) -> [Date] {
        switch self {
        case .empty: []
        case .number(let serial): XLSXWriter.date(fromSerial: serial, calendar: calendar).map { [$0] } ?? []
        case .text(let string): Spreadsheet.dates(in: string, calendar: calendar)
        }
    }
}

nonisolated extension Spreadsheet {
    /// Dates typed as text: "31.3.2026", "31. 3. 2026", "2026-03-31",
    /// "31/3/2026", and any of those twice for a period. Day comes before
    /// month, as it does everywhere the app's documents go.
    static func dates(in text: String, calendar: Calendar = Formatting.calendar) -> [Date] {
        text.matches(of: /(\d{1,4})[.\/-]\s*(\d{1,2})[.\/-]\s*(\d{1,4})/).compactMap { match in
            let first = Int(match.1) ?? 0
            let middle = Int(match.2) ?? 0
            let last = Int(match.3) ?? 0
            var year: Int, month: Int, day: Int
            if match.1.count == 4 {
                (year, month, day) = (first, middle, last)
            } else {
                (day, month, year) = (first, middle, last)
            }
            if year < 100 { year += 2000 }
            guard (1...12).contains(month), (1...31).contains(day), year >= 1900 else { return nil }
            let parts = DateComponents(year: year, month: month, day: day)
            guard let date = calendar.date(from: parts),
                  calendar.dateComponents([.year, .month, .day], from: date) == parts
            else { return nil }
            return date
        }
    }

    /// An amount typed as text. Whichever of comma and dot comes last is the
    /// decimal separator; on its own a comma is decimal (the Slovenian way)
    /// and a dot is decimal unless exactly three digits follow it.
    static func decimal(from text: String) -> Decimal? {
        var kept = text.filter { $0.isNumber || $0 == "," || $0 == "." || $0 == "-" }
        guard kept.contains(where: \.isNumber) else { return nil }
        let lastComma = kept.lastIndex(of: ",")
        let lastDot = kept.lastIndex(of: ".")
        switch (lastComma, lastDot) {
        case (let comma?, let dot?):
            let decimalSeparator: Character = comma > dot ? "," : "."
            kept.removeAll { $0 == (decimalSeparator == "," ? "." : ",") }
            kept = kept.replacingOccurrences(of: ",", with: ".")
        case (.some, nil):
            kept = kept.replacingOccurrences(of: ",", with: ".")
        case (nil, let dot?):
            let fraction = kept.distance(from: kept.index(after: dot), to: kept.endIndex)
            if fraction == 3 || kept.filter({ $0 == "." }).count > 1 {
                kept.removeAll { $0 == "." }
            }
        case (nil, nil):
            break
        }
        if kept.filter({ $0 == "." }).count > 1 { kept.removeAll { $0 == "." } }
        return Decimal(string: kept, locale: Locale(identifier: "en_US_POSIX"))
    }
}

// MARK: - .xlsx

/// Reads the first worksheet of a workbook: the ZIP, the shared strings,
/// then the cells by their own addresses, so a sparse sheet keeps its shape.
nonisolated enum XLSXReader {
    static func grid(from data: Data) throws -> Spreadsheet.Grid {
        guard let entries = try? ZIPArchive.entries(in: data) else { throw Spreadsheet.ReadError.notASpreadsheet }
        let parts = Dictionary(entries.map { ($0.path, $0.data) }, uniquingKeysWith: { first, _ in first })
        guard let worksheet = parts[firstWorksheetPath(in: parts)] else { throw Spreadsheet.ReadError.noWorksheet }

        let sharedStrings = parts["xl/sharedStrings.xml"].map(sharedStrings(in:)) ?? []
        guard let document = try? XMLDocument(data: worksheet) else { throw Spreadsheet.ReadError.notASpreadsheet }

        var rows: [[Spreadsheet.Value]] = []
        for cell in nodes(document, "//*[local-name()='sheetData']/*[local-name()='row']/*[local-name()='c']") {
            guard let reference = attribute("r", of: cell),
                  let (row, column) = coordinates(of: reference)
            else { continue }
            let value = self.value(of: cell, sharedStrings: sharedStrings)
            guard value != .empty else { continue }
            while rows.count <= row { rows.append([]) }
            while rows[row].count <= column { rows[row].append(.empty) }
            rows[row][column] = value
        }
        return Spreadsheet.Grid(rows: rows)
    }

    /// The sheet listed first in the workbook, resolved through its
    /// relationships; the conventional path when either part is missing.
    private static func firstWorksheetPath(in parts: [String: Data]) -> String {
        let fallback = "xl/worksheets/sheet1.xml"
        guard let workbook = parts["xl/workbook.xml"].flatMap({ try? XMLDocument(data: $0) }),
              let sheet = nodes(workbook, "//*[local-name()='sheets']/*[local-name()='sheet']").first,
              let relationship = (sheet as? XMLElement)?.attributes?.first(where: { $0.localName == "id" })?.stringValue,
              let rels = parts["xl/_rels/workbook.xml.rels"].flatMap({ try? XMLDocument(data: $0) }),
              let target = nodes(rels, "//*[local-name()='Relationship'][@Id='\(relationship)']").first
                  .flatMap({ attribute("Target", of: $0) })
        else { return fallback }
        return target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
    }

    /// Each shared string as one text, rich-text runs joined.
    private static func sharedStrings(in data: Data) -> [String] {
        guard let document = try? XMLDocument(data: data) else { return [] }
        return nodes(document, "//*[local-name()='sst']/*[local-name()='si']").map { item in
            nodes(item, ".//*[local-name()='t'][not(ancestor::*[local-name()='rPh'])]")
                .compactMap(\.stringValue)
                .joined()
        }
    }

    private static func value(of cell: XMLNode, sharedStrings: [String]) -> Spreadsheet.Value {
        let type = attribute("t", of: cell) ?? "n"
        let raw = nodes(cell, "./*[local-name()='v']").first?.stringValue ?? ""
        switch type {
        case "s":
            guard let index = Int(raw), sharedStrings.indices.contains(index) else { return .empty }
            return text(sharedStrings[index])
        case "inlineStr":
            return text(nodes(cell, ".//*[local-name()='t']").compactMap(\.stringValue).joined())
        case "str":
            return text(raw)
        case "b":
            return text(raw == "1" ? "TRUE" : "FALSE")
        case "e":
            return .empty
        default:
            guard let number = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { return text(raw) }
            return .number(number)
        }
    }

    private static func text(_ string: String) -> Spreadsheet.Value {
        string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .text(string)
    }

    /// "B9" → row 8, column 1 — both zero-based.
    static func coordinates(of reference: String) -> (row: Int, column: Int)? {
        let letters = reference.prefix { $0.isLetter }
        guard !letters.isEmpty, let row = Int(reference.dropFirst(letters.count)), row >= 1 else { return nil }
        let column = letters.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 }
        return (row - 1, column - 1)
    }

    private static func nodes(_ node: XMLNode, _ xpath: String) -> [XMLNode] {
        (try? node.nodes(forXPath: xpath)) ?? []
    }

    private static func attribute(_ name: String, of node: XMLNode) -> String? {
        (node as? XMLElement)?.attribute(forName: name)?.stringValue
    }
}

// MARK: - .csv

/// A delimited text file. The delimiter is whichever of semicolon, comma
/// and tab the first line uses most — Excel in a Slovenian locale writes
/// semicolons, everything else commas.
nonisolated enum CSVReader {
    static func grid(from data: Data) throws -> Spreadsheet.Grid {
        guard let text = decode(data) else { throw Spreadsheet.ReadError.unreadableText }
        let delimiter = self.delimiter(in: text)

        var rows: [[Spreadsheet.Value]] = []
        var row: [Spreadsheet.Value] = []
        var field = ""
        var quoted = false
        var index = text.startIndex

        func endField() {
            let trimmed = field.trimmingCharacters(in: .whitespaces)
            row.append(trimmed.isEmpty ? .empty : .text(trimmed))
            field = ""
        }
        func endRow() {
            endField()
            rows.append(row.contains { $0 != .empty } ? row : [])
            row = []
        }

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            switch character {
            case "\"":
                if quoted, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    quoted.toggle()
                }
            case delimiter where !quoted:
                endField()
            case "\r\n", "\n", "\r":
                if quoted { field.append(character) } else { endRow() }
            default:
                field.append(character)
            }
            index = next
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return Spreadsheet.Grid(rows: rows)
    }

    private static func delimiter(in text: String) -> Character {
        let firstLine = text.prefix { !$0.isNewline }
        let candidates: [Character] = [";", ",", "\t"]
        func count(_ delimiter: Character) -> Int { firstLine.filter { $0 == delimiter }.count }
        return candidates.max { count($0) < count($1) } ?? ","
    }

    /// UTF-8 first, then the Central European encodings an older Excel
    /// saves Slovenian text in.
    private static func decode(_ data: Data) -> String? {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        for encoding in [String.Encoding.utf8, .windowsCP1250, .isoLatin2, .isoLatin1] {
            if let text = String(data: bytes, encoding: encoding) { return text }
        }
        return nil
    }
}
