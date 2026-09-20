import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Invoices

@Suite("XLSX writer")
struct XLSXWriterTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func `CRC32 matches the reference vector`() {
        #expect(ZIPArchive.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(ZIPArchive.crc32(Data()) == 0)
    }

    @Test func `the archive carries the ZIP signatures and every entry`() {
        let archive = ZIPArchive.archive([
            .init(path: "a.xml", data: Data("<a/>".utf8)),
            .init(path: "b/c.xml", data: Data("<c/>".utf8)),
        ])
        #expect(archive.starts(with: [0x50, 0x4B, 0x03, 0x04]))
        // End of central directory: two entries on the only disk.
        let eocd = archive.range(of: Data([0x50, 0x4B, 0x05, 0x06]))
        #expect(eocd != nil)
        let text = String(decoding: archive, as: UTF8.self)
        // Each name appears twice: local header and central directory.
        #expect(text.components(separatedBy: "b/c.xml").count == 3)
    }

    @Test func `column names run past Z`() {
        #expect(XLSXWriter.columnName(1) == "A")
        #expect(XLSXWriter.columnName(7) == "G")
        #expect(XLSXWriter.columnName(26) == "Z")
        #expect(XLSXWriter.columnName(27) == "AA")
        #expect(XLSXWriter.columnName(28) == "AB")
    }

    /// The serials Excel itself shows for these days — including the one
    /// that predates its phantom 29 February 1900.
    @Test func `dates become Excel serials`() {
        #expect(XLSXWriter.serial(for: date(2026, 3, 31)) == 46112)
        #expect(XLSXWriter.serial(for: date(1970, 1, 1)) == 25569)
        #expect(XLSXWriter.serial(for: date(2000, 1, 1)) == 36526)
        #expect(XLSXWriter.serial(for: date(2024, 2, 29)) == 45351)
        #expect(XLSXWriter.serial(for: date(1900, 1, 1)) == 1)
        #expect(XLSXWriter.serial(for: date(1900, 3, 1)) == 61)
    }

    /// A date is a day, not an instant — the serial must not slip when the
    /// clock is on the other side of midnight UTC.
    @Test func `the serial does not depend on the time of day`() {
        var components = DateComponents(year: 2026, month: 3, day: 31, hour: 23, minute: 59)
        let lateEvening = Calendar.current.date(from: components)!
        components.hour = 0
        components.minute = 1
        let earlyMorning = Calendar.current.date(from: components)!
        #expect(XLSXWriter.serial(for: lateEvening) == XLSXWriter.serial(for: earlyMorning))
    }

    @Test func `text is XML escaped`() {
        #expect(XLSXWriter.escape("Tables & Chairs Ltd.") == "Tables &amp; Chairs Ltd.")
        #expect(XLSXWriter.escape("<b>\"x\"</b>") == "&lt;b&gt;&quot;x&quot;&lt;/b&gt;")
        #expect(XLSXWriter.escape("Ljubljana") == "Ljubljana")
    }

    @Test func `cells are written as numbers and dates, not as text`() {
        let sheet = XLSXWriter.Sheet(
            name: "Test",
            rows: [[
                .text("Client & Son"),
                XLSXWriter.Cell(.number(Decimal(string: "4389.99")!), style: .cellMoney),
                XLSXWriter.Cell(.date(date(2026, 3, 31)), style: .cellDate),
            ]]
        )
        let xml = worksheet(in: XLSXWriter.data(for: sheet))
        #expect(xml.contains("<c r=\"A1\" t=\"inlineStr\">"))
        #expect(xml.contains("Client &amp; Son"))
        // Decimals are written with a dot whatever the locale says.
        #expect(xml.contains("<c r=\"B1\" s=\"4\"><v>4389.99</v></c>"))
        #expect(xml.contains("<c r=\"C1\" s=\"3\"><v>46112</v></c>"))
    }

    @Test func `an unstyled empty cell is left out of the row`() {
        let sheet = XLSXWriter.Sheet(
            name: "Test",
            rows: [[XLSXWriter.Cell(.empty), .text("B")]]
        )
        let xml = worksheet(in: XLSXWriter.data(for: sheet))
        #expect(!xml.contains("r=\"A1\""))
        #expect(xml.contains("r=\"B1\""))
    }

    @Test func `the workbook contains the parts Excel opens`() throws {
        let data = XLSXWriter.data(for: XLSXWriter.Sheet(name: "Overview", rows: [[.text("A")]]))
        let text = String(decoding: data, as: UTF8.self)
        for part in [
            "[Content_Types].xml", "_rels/.rels", "xl/workbook.xml",
            "xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/worksheets/sheet1.xml",
        ] {
            #expect(text.contains(part), "manjka del \(part)")
        }
        #expect(text.contains("<sheet name=\"Overview\""))
    }

    @Test func `the exported document declares the xlsx type`() {
        #expect(UTType.xlsx.preferredFilenameExtension == "xlsx")
    }

    /// The parts are stored uncompressed, so the sheet XML can be read
    /// straight out of the archive bytes.
    private func worksheet(in archive: Data) -> String {
        String(decoding: archive, as: UTF8.self)
    }
}
