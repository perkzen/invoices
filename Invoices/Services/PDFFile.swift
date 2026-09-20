import SwiftUI
import UniformTypeIdentifiers

/// Thin `FileDocument` wrapper so `.fileExporter` can write already-rendered
/// PDF bytes without an AppKit save panel.
nonisolated struct PDFFile: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]

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
