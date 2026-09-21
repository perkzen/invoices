import SwiftUI
import UniformTypeIdentifiers

/// One file on its way to the save panel: the bytes, their type and the name
/// the panel suggests. A view sets one into a binding and `fileExport(_:)`
/// does the rest — the panel, the failure alert, and the clearing afterwards.
nonisolated struct FileExport: Equatable, Sendable {
    var data: Data
    var contentType: UTType
    var filename: String

    static func pdf(_ data: Data, named filename: String) -> FileExport {
        FileExport(data: data, contentType: .pdf, filename: filename)
    }

    static func xlsx(_ data: Data, named filename: String) -> FileExport {
        FileExport(data: data, contentType: .xlsx, filename: filename)
    }
}

extension UTType {
    /// The system declares the Office type; the extension lookup and `.data`
    /// are only there so a missing declaration cannot break the export.
    nonisolated static let xlsx: UTType =
        UTType("org.openxmlformats.spreadsheetml.sheet")
        ?? UTType(filenameExtension: "xlsx")
        ?? .data
}

extension View {
    /// Presents the save panel for `export` as soon as it is set, and clears
    /// it once the panel is gone, so the same file can be exported twice.
    func fileExport(_ export: Binding<FileExport?>) -> some View {
        modifier(FileExportModifier(export: export))
    }
}

private struct FileExportModifier: ViewModifier {
    @Binding var export: FileExport?

    @State private var isPresented = false
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: export) { _, export in
                guard export != nil else { return }
                // Present on the next turn so the document is committed first —
                // setting both in one frame can hand the exporter a nil document.
                Task { isPresented = true }
            }
            .fileExporter(
                isPresented: $isPresented,
                document: export.map(ExportedFile.init),
                contentType: export?.contentType ?? .data,
                defaultFilename: export?.filename
            ) { result in
                if case .failure(let failure) = result {
                    error = failure.localizedDescription
                }
            }
            // Saved or cancelled, the panel is gone: forget the file so the
            // same one can be exported again.
            .onChange(of: isPresented) { _, presented in
                if !presented { export = nil }
            }
            .errorAlert("Export failed", message: $error)
    }
}

/// Hands already-rendered bytes to `.fileExporter`, which insists on a
/// `FileDocument`.
nonisolated private struct ExportedFile: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf, .xlsx, .data]

    var data: Data

    init(_ export: FileExport) {
        data = export.data
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
