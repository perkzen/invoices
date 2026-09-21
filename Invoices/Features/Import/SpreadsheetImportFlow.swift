import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Import, from wherever it is asked for: the File menu, the Overview
/// toolbar, the empty invoice list. The window installs the one flow and
/// hands the action down; each surface only calls it.
struct ImportSpreadsheetAction {
    let run: @MainActor () -> Void

    @MainActor
    func callAsFunction() { run() }
}

extension EnvironmentValues {
    @Entry var importSpreadsheet: ImportSpreadsheetAction?
}

extension FocusedValues {
    @Entry var importSpreadsheet: ImportSpreadsheetAction?
}

/// File › Import Spreadsheet…, next to the export entries macOS groups
/// there. It reaches the frontmost window's flow through the focused value.
struct ImportCommands: Commands {
    @FocusedValue(\.importSpreadsheet) private var importSpreadsheet

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Import Spreadsheet…") { importSpreadsheet?() }
                .disabled(importSpreadsheet == nil)
        }
    }
}

extension View {
    /// The open panel, the reading of the file, and the import sheet.
    /// `onFinish` runs once the ledger has been written, with what was
    /// recorded.
    func spreadsheetImport(isPresented: Binding<Bool>, onFinish: @escaping ([Invoice]) -> Void) -> some View {
        modifier(SpreadsheetImportFlow(isPresented: isPresented, onFinish: onFinish))
    }
}

private struct SpreadsheetImportFlow: ViewModifier {
    @Binding var isPresented: Bool
    let onFinish: ([Invoice]) -> Void

    @Environment(\.modelContext) private var context
    @State private var file: SpreadsheetFile?
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [.xlsx, .commaSeparatedText, .tabSeparatedText]
            ) { result in
                switch result {
                case .success(let url): open(url)
                case .failure(let failure): error = failure.localizedDescription
                }
            }
            .sheet(item: $file) { file in
                SpreadsheetImportView(file: file, existing: Ledger(context).recorded, onFinish: onFinish)
            }
            .errorAlert("The spreadsheet could not be read", message: $error)
    }

    private func open(_ url: URL) {
        // The app is sandboxed; a picked file is readable only inside this scope.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let grid = try Spreadsheet.grid(from: data, filenameExtension: url.pathExtension)
            guard grid.rows.contains(where: { !$0.isEmpty }) else {
                error = String(localized: "The spreadsheet is empty.")
                return
            }
            file = SpreadsheetFile(name: url.lastPathComponent, grid: grid)
        } catch let problem as Spreadsheet.ReadError {
            error = Self.message(for: problem)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func message(for problem: Spreadsheet.ReadError) -> String {
        switch problem {
        case .unsupportedType:
            String(localized: "Choose an Excel workbook (.xlsx) or a CSV file. A Numbers document can be exported as either.")
        case .notASpreadsheet:
            String(localized: "The file is not an Excel workbook.")
        case .noWorksheet:
            String(localized: "The workbook has no worksheet.")
        case .unreadableText:
            String(localized: "The text in the file could not be decoded.")
        }
    }
}
