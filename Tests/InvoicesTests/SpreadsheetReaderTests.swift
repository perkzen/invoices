import Foundation
import Testing
@testable import Invoices

@Suite("Spreadsheet reader")
struct SpreadsheetReaderTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Formatting.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: ZIP

    @Test func `a stored archive reads back what was written`() throws {
        let archive = ZIPArchive.archive([
            .init(path: "a.xml", data: Data("<a/>".utf8)),
            .init(path: "b/c.xml", data: Data("<c>Dvořák</c>".utf8)),
        ])
        let entries = try ZIPArchive.entries(in: archive)
        #expect(entries.map(\.path) == ["a.xml", "b/c.xml"])
        #expect(entries[1].data == Data("<c>Dvořák</c>".utf8))
    }

    /// Excel deflates every part; the reader has to inflate it.
    @Test func `a deflated archive is inflated`() throws {
        let text = String(repeating: "<row><c>x</c></row>", count: 200)
        let entries = try ZIPArchive.entries(in: deflatedArchive(["sheet.xml": Data(text.utf8)]))
        #expect(entries.count == 1)
        #expect(String(decoding: entries[0].data, as: UTF8.self) == text)
    }

    @Test func `bytes that are not an archive are refused`() {
        #expect(throws: ZIPArchive.ReadError.notAnArchive) {
            try ZIPArchive.entries(in: Data("PK, but not really".utf8))
        }
    }

    // MARK: Serials

    /// The inverse of `serial(for:)`, over the days `XLSXWriterTests` pins.
    @Test func `Excel serials become the days they name`() {
        for (year, month, day) in [(2026, 3, 31), (1970, 1, 1), (2000, 1, 1), (2024, 2, 29), (1900, 1, 1), (1900, 3, 1)] {
            let day = date(year, month, day)
            #expect(XLSXWriter.date(fromSerial: Decimal(XLSXWriter.serial(for: day))) == day)
        }
        // A time of day rides along on a fraction and is ignored.
        #expect(XLSXWriter.date(fromSerial: Decimal(string: "46112.75")!) == date(2026, 3, 31))
        #expect(XLSXWriter.date(fromSerial: 0) == nil)
    }

    // MARK: .xlsx

    /// The app's own export: inline strings, serial dates, stored parts.
    @Test func `the year overview export reads back as a grid`() throws {
        let row = YearOverviewRow(
            number: "2026-001", clientName: "Client & Son", issueDate: date(2026, 3, 31),
            dueDate: date(2026, 4, 8), serviceDate: date(2026, 3, 1), serviceDateEnd: date(2026, 3, 31),
            amount: Decimal(string: "4389.99")!, paidDate: date(2026, 4, 2)
        )
        let overview = YearOverview(year: 2026, issuer: .init(name: "Me"), rows: [row])
        let grid = try Spreadsheet.grid(from: YearOverviewXLSX.data(for: overview), filenameExtension: "xlsx")

        let sheet = YearOverviewXLSX.sheet(for: overview)
        let data = grid.rows[sheet.frozenRows]
        #expect(data[0] == .text("Client & Son"))
        #expect(data[1] == .text("2026-001"))
        #expect(data[2] == .number(Decimal(XLSXWriter.serial(for: date(2026, 3, 31)))))
        #expect(data[4] == .text(Formatting.period(date(2026, 3, 1), to: date(2026, 3, 31))))
        #expect(data[5] == .number(Decimal(string: "4389.99")!))
    }

    /// What Excel writes: shared strings with rich-text runs, cells placed by
    /// address with rows missing in between, a formula cell, and everything
    /// deflated.
    @Test func `an Excel workbook reads back by cell address`() throws {
        let grid = try Spreadsheet.grid(from: excelWorkbook(), filenameExtension: "xlsx")
        #expect(grid.rows.count == 5)
        #expect(grid[0, 0] == .text("Title"))
        #expect(grid.rows[1].isEmpty)
        #expect(grid[2, 1] == .text("Invoice no. "))
        #expect(grid[2, 2] == .text("Rich text"))
        #expect(grid[3, 0] == .text("Client"))
        #expect(grid[3, 5] == .number(Decimal(string: "4389.99")!))
        #expect(grid[3, 6] == .text("31.3.2026"))
        // The formula's cached value is the number, not the formula.
        #expect(grid[4, 5] == .number(5075))
        #expect(grid[9, 9] == .empty)
    }

    @Test func `a workbook without a worksheet is refused`() {
        let archive = ZIPArchive.archive([.init(path: "xl/workbook.xml", data: Data("<workbook/>".utf8))])
        #expect(throws: Spreadsheet.ReadError.noWorksheet) {
            try Spreadsheet.grid(from: archive, filenameExtension: "xlsx")
        }
    }

    @Test func `cell addresses map to rows and columns`() {
        #expect(XLSXReader.coordinates(of: "A1")! == (0, 0))
        #expect(XLSXReader.coordinates(of: "G9")! == (8, 6))
        #expect(XLSXReader.coordinates(of: "AA10")! == (9, 26))
        #expect(XLSXReader.coordinates(of: "9") == nil)
    }

    // MARK: .csv

    @Test func `a semicolon CSV with quoted fields reads back`() throws {
        let csv = "Client;Invoice no.;Amount\r\n\"Tables; Chairs \"\"Ltd\"\"\";2026-001;4.389,99 €\r\n\r\n"
        let grid = try Spreadsheet.grid(from: Data(csv.utf8), filenameExtension: "csv")
        #expect(grid.rows.count == 3)
        #expect(grid[0, 1] == .text("Invoice no."))
        #expect(grid[1, 0] == .text("Tables; Chairs \"Ltd\""))
        #expect(grid[1, 2] == .text("4.389,99 €"))
        #expect(grid.rows[2].isEmpty)
    }

    @Test func `a comma CSV in a Central European encoding reads back`() throws {
        let data = "Client,Amount\nDvořák Ltd.,\"1,000.50\"\n".data(using: .windowsCP1250)!
        let grid = try Spreadsheet.grid(from: data, filenameExtension: "csv")
        #expect(grid[1, 0] == .text("Dvořák Ltd."))
        #expect(grid[1, 1].decimal == Decimal(string: "1000.50"))
    }

    @Test func `other file types are refused`() {
        #expect(throws: Spreadsheet.ReadError.unsupportedType("numbers")) {
            try Spreadsheet.grid(from: Data(), filenameExtension: "numbers")
        }
    }

    // MARK: Values

    @Test func `dates are read in every shape people type`() {
        for text in ["31.3.2026", "31. 3. 2026", "2026-03-31", "31/3/2026", " 31.03.2026 "] {
            #expect(Spreadsheet.Value.text(text).date() == date(2026, 3, 31), "\(text)")
        }
        #expect(Spreadsheet.Value.text("31.3.26").date() == date(2026, 3, 31))
        #expect(Spreadsheet.Value.text("2026-001").date() == nil)
        #expect(Spreadsheet.Value.text("31.13.2026").date() == nil)
        #expect(Spreadsheet.Value.text("31.4.2026").date() == nil)
        #expect(Spreadsheet.Value.text("soon").date() == nil)
        #expect(Spreadsheet.Value.number(46112).date() == date(2026, 3, 31))
    }

    @Test func `a period is two dates, however it is joined`() {
        let expected = [date(2026, 3, 1), date(2026, 3, 31)]
        #expect(Spreadsheet.Value.text("01.03.2026 - 31.03.2026").dates() == expected)
        #expect(Spreadsheet.Value.text("01.03.2026-31.03.2026").dates() == expected)
        #expect(Spreadsheet.Value.text("1. 3. 2026 – 31. 3. 2026").dates() == expected)
        #expect(Spreadsheet.Value.text("2026-03-01 to 2026-03-31").dates() == expected)
        #expect(Spreadsheet.Value.text("31.3.2026").dates() == [date(2026, 3, 31)])
    }

    @Test func `amounts are read with either separator`() {
        #expect(Spreadsheet.decimal(from: "4.389,99 €") == Decimal(string: "4389.99"))
        #expect(Spreadsheet.decimal(from: "4,389.99") == Decimal(string: "4389.99"))
        #expect(Spreadsheet.decimal(from: "4389.99") == Decimal(string: "4389.99"))
        #expect(Spreadsheet.decimal(from: "4389,99") == Decimal(string: "4389.99"))
        #expect(Spreadsheet.decimal(from: "1.000") == 1000)
        #expect(Spreadsheet.decimal(from: "1.234.567") == 1_234_567)
        #expect(Spreadsheet.decimal(from: "12,5") == Decimal(string: "12.5"))
        #expect(Spreadsheet.decimal(from: "-50") == -50)
        #expect(Spreadsheet.decimal(from: "EUR") == nil)
        #expect(Spreadsheet.Value.number(1000).decimal == 1000)
    }

    // MARK: Fixtures

    /// A ZIP the way Excel writes one: every entry deflated.
    private func deflatedArchive(_ parts: [String: Data]) -> Data {
        var payload = Data()
        var directory = Data()
        for (path, data) in parts.sorted(by: { $0.key < $1.key }) {
            let name = Data(path.utf8)
            let deflated = try! (data as NSData).compressed(using: .zlib) as Data
            let crc = ZIPArchive.crc32(data)
            let offset = UInt32(payload.count)
            payload.append(le32: 0x0403_4B50); payload.append(le16: 20); payload.append(le16: 0x0800)
            payload.append(le16: 8); payload.append(le16: 0); payload.append(le16: 0x0021)
            payload.append(le32: crc); payload.append(le32: UInt32(deflated.count)); payload.append(le32: UInt32(data.count))
            payload.append(le16: UInt16(name.count)); payload.append(le16: 0)
            payload.append(name); payload.append(deflated)

            directory.append(le32: 0x0201_4B50); directory.append(le16: 20); directory.append(le16: 20)
            directory.append(le16: 0x0800); directory.append(le16: 8); directory.append(le16: 0); directory.append(le16: 0x0021)
            directory.append(le32: crc); directory.append(le32: UInt32(deflated.count)); directory.append(le32: UInt32(data.count))
            directory.append(le16: UInt16(name.count)); directory.append(le16: 0); directory.append(le16: 0)
            directory.append(le16: 0); directory.append(le16: 0); directory.append(le32: 0); directory.append(le32: offset)
            directory.append(name)
        }
        var archive = payload
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.append(le32: 0x0605_4B50); archive.append(le16: 0); archive.append(le16: 0)
        archive.append(le16: UInt16(parts.count)); archive.append(le16: UInt16(parts.count))
        archive.append(le32: UInt32(directory.count)); archive.append(le32: directoryOffset); archive.append(le16: 0)
        return archive
    }

    /// The shapes Excel itself produces, cut down: a shared-string table with
    /// a rich-text entry and a heading with a trailing space, a merged title, an empty row,
    /// a formula cell, and a sheet found through the workbook's relationships.
    private func excelWorkbook() -> Data {
        let ns = "xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\""
        let rns = "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\""
        return deflatedArchive([
            "xl/workbook.xml": Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <workbook \(ns) \(rns)><sheets><sheet name="List1" sheetId="1" r:id="rId7"/></sheets></workbook>
            """.utf8),
            "xl/_rels/workbook.xml.rels": Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId7" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/data.xml"/>
            </Relationships>
            """.utf8),
            "xl/sharedStrings.xml": Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <sst \(ns) count="4" uniqueCount="4"><si><t>Title</t></si><si><t xml:space="preserve">Invoice no. </t></si>
            <si><r><t>Rich</t></r><r><rPr><b/></rPr><t xml:space="preserve"> text</t></r></si><si><t>Client</t></si><si><t>31.3.2026</t></si></sst>
            """.utf8),
            "xl/worksheets/data.xml": Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet \(ns)><dimension ref="A1:G5"/><sheetData>
            <row r="1"><c r="A1" s="14" t="s"><v>0</v></c><c r="B1" s="14"/></row>
            <row r="3"><c r="B3" t="s"><v>1</v></c><c r="C3" t="s"><v>2</v></c></row>
            <row r="4"><c r="A4" t="s"><v>3</v></c><c r="F4" s="5"><v>4389.99</v></c><c r="G4" t="s"><v>4</v></c></row>
            <row r="5"><c r="F5" s="12"><f>SUM(F4:F4)</f><v>5075</v></c><c r="G5" t="e"><v>#REF!</v></c></row>
            </sheetData><mergeCells count="1"><mergeCell ref="A1:B1"/></mergeCells></worksheet>
            """.utf8),
        ])
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func append(le32 value: UInt32) {
        append(contentsOf: (0..<4).map { UInt8((value >> (8 * $0)) & 0xFF) })
    }
}
