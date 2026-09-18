import SwiftUI
import UniformTypeIdentifiers

/// Thin `FileDocument` wrapper so `.fileExporter` can write already-built
/// workbook bytes, mirroring `PDFFile`.
nonisolated struct XLSXFile: FileDocument {
    /// The system declares the Office type; the extension lookup and `.data`
    /// are only there so a missing declaration cannot break the export.
    static let contentType: UTType =
        UTType("org.openxmlformats.spreadsheetml.sheet")
        ?? UTType(filenameExtension: "xlsx")
        ?? .data

    static let readableContentTypes: [UTType] = [contentType]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
