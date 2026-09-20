import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Thumbnail plus choose/remove buttons for a stored bitmap.
struct ImageWell: View {
    let title: LocalizedStringKey
    @Binding var data: Data?

    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Group {
                    if let image = data.flatMap(NSImage.init(data:)) {
                        // Logos are drawn for paper: keep a white plate
                        // under them whatever the appearance.
                        Image(nsImage: image).resizable().scaledToFit()
                            .padding(3)
                            .background(.white, in: RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .frame(width: 72, height: 44)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))

                Button("Choose…") { isImporting = true }
                if data != nil {
                    Button("Remove", role: .destructive) { data = nil }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image, .pdf]
        ) { result in
            switch result {
            case .success(let url):
                load(url)
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .errorAlert("The image could not be loaded", message: $importError)
    }

    private func load(_ url: URL) {
        // The app is sandboxed; a picked file is readable only inside this scope.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? Data(contentsOf: url), let png = ImageData.normalized(raw) else {
            importError = String(localized: "The file is not an image that can be read.")
            return
        }
        data = png
    }
}
