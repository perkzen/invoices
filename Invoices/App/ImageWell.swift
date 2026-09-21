import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A stored bitmap as a Mac image well: a plate that takes a dropped file or
/// a click, with Choose and Remove beneath it. A logo or a signature is drawn
/// for paper, so once set it sits on a white plate whatever the appearance.
struct ImageWell: View {
    /// A row label, when the well shares a section with other rows. Left
    /// out when the section header already names it.
    let title: LocalizedStringKey?
    @Binding var data: Data?
    /// The glyph on the empty plate: what kind of picture belongs here.
    var symbol = "photo.badge.plus"

    @State private var isImporting = false
    @State private var isTargeted = false
    @State private var isHovering = false
    @State private var importError: String?

    init(title: LocalizedStringKey? = nil, data: Binding<Data?>, symbol: String = "photo.badge.plus") {
        self.title = title
        self._data = data
        self.symbol = symbol
    }

    private static let acceptedTypes: [UTType] = [.image, .pdf]
    private static let plateSize = CGSize(width: 200, height: 104)

    var body: some View {
        Group {
            if let title {
                LabeledContent(title) { well }
            } else {
                // Alone in its section, the plate is the row: no box around
                // it, the section header names it.
                well
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.acceptedTypes) { result in
            switch result {
            case .success(let url):
                load(url)
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .errorAlert("The image could not be loaded", message: $importError)
    }

    /// The plate does everything: click to choose, drop to replace, and a
    /// small ⓧ under the pointer to remove. The context menu repeats both.
    private var well: some View {
        Button { isImporting = true } label: { plate }
            .buttonStyle(.plain)
            .help(data == nil ? "Choose an image" : "Choose another image")
            .onDrop(of: [.fileURL, .image, .pdf], isTargeted: $isTargeted, perform: drop)
            .overlay(alignment: .topTrailing) {
                if data != nil, isHovering {
                    Button("Remove", systemImage: "xmark.circle.fill") { data = nil }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .font(.title3)
                        .foregroundStyle(.secondary, .regularMaterial)
                        .padding(6)
                        .help("Remove")
                }
            }
            .onHover { isHovering = $0 }
            .contextMenu {
                Button("Choose…") { isImporting = true }
                if data != nil {
                    Button("Remove", role: .destructive) { data = nil }
                }
            }
            .padding(.vertical, 4)
    }

    @ViewBuilder
    private var plate: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Group {
            if let image = data.flatMap(NSImage.init(data:)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .frame(width: Self.plateSize.width, height: Self.plateSize.height)
                    .background(.white, in: shape)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Drop an image here, or click to choose")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(8)
                .frame(width: Self.plateSize.width, height: Self.plateSize.height)
                .background(.quaternary.opacity(isTargeted ? 1 : 0.6), in: shape)
            }
        }
        .overlay {
            if isTargeted {
                shape.strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            } else {
                shape.strokeBorder(.separator)
            }
        }
        .contentShape(shape)
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }

    // MARK: Loading

    /// A file from the open panel or dragged in from the Finder.
    private func load(_ url: URL) {
        // The app is sandboxed; a picked file is readable only inside this scope.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? Data(contentsOf: url) else {
            importError = String(localized: "The file could not be read.")
            return
        }
        accept(raw)
    }

    /// Bytes from any source, re-encoded as a bounded PNG or refused.
    private func accept(_ raw: Data) {
        guard let png = ImageData.normalized(raw) else {
            importError = String(localized: "The file is not an image that can be read.")
            return
        }
        data = png
    }

    /// A Finder file comes as a URL; an image dragged out of another app
    /// comes as its bytes. The first provider that offers either wins.
    private func drop(_ providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            _ = provider.loadDataRepresentation(for: .fileURL) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in load(url) }
            }
            return true
        }
        for type in Self.acceptedTypes {
            if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type.identifier) }) {
                _ = provider.loadDataRepresentation(for: type) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in accept(data) }
                }
                return true
            }
        }
        return false
    }
}
