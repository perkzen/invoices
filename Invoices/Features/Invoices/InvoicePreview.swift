import PDFKit
import SwiftUI

/// The invoice exactly as "Export PDF" will write it, re-rendered whenever
/// the printed value changes.
///
/// The caller builds `printed` inside its own `body`, which is what registers
/// observation: any printed property that changes re-evaluates that view, the
/// value differs, and `.task(id:)` renders again. Nothing here lists what to
/// watch.
struct InvoicePreview: View {
    let printed: PrintedInvoice
    /// Scale the whole page into the view rather than to its width. The
    /// editor scrolls a preview that may run to a second page; the sample
    /// beside the business form is one page and should be seen at once,
    /// whatever the column's proportions.
    var fitsPage = false

    /// `.redacted(reason: .privacy)` stops at the edge of an AppKit view, so
    /// the rendered page cannot be blanked the way the rest of the interface
    /// is — it is rendered with the sensitive values masked instead. The page
    /// stays legible, so the preview still answers what it is for: how the
    /// invoice reads, and whether a long one broke onto a second page.
    @AppStorage(PrivacyMode.storageKey) private var hidesSensitiveValues = false
    @State private var pdfData: Data?

    /// What a render is of. Masking is part of it, or toggling private mode
    /// would leave the last render on screen.
    private struct Render: Hashable {
        var printed: PrintedInvoice
        var masksSensitiveValues: Bool
    }

    private var render: Render {
        Render(printed: printed, masksSensitiveValues: hidesSensitiveValues)
    }

    var body: some View {
        PDFDocumentView(data: pdfData, fitsPage: fitsPage)
            .task(id: render) {
                // Coalesce a burst of keystrokes into one render.
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                pdfData = InvoicePDF.render(render.printed, masksSensitiveValues: render.masksSensitiveValues)
            }
    }
}

/// PDFKit viewer that swaps documents without losing the reader's zoom or
/// place on the page, so typing into a field does not jump the preview.
struct PDFDocumentView: NSViewRepresentable {
    let data: Data?
    var fitsPage = false

    final class Coordinator {
        var shownData: Data?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        // .singlePage scales the page to fit the view in both directions;
        // .singlePageContinuous fits its width and scrolls.
        view.displayMode = fitsPage ? .singlePage : .singlePageContinuous
        view.displayDirection = .vertical
        view.pageShadowsEnabled = true
        view.backgroundColor = .underPageBackgroundColor
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard context.coordinator.shownData != data else { return }
        context.coordinator.shownData = data

        guard let data, let document = PDFDocument(data: data) else {
            view.document = nil
            return
        }

        let keepsAutoScale = view.autoScales
        let scale = view.scaleFactor
        let destination = view.currentDestination
        let pageIndex = destination?.page.flatMap { view.document?.index(for: $0) }

        view.document = document

        if !keepsAutoScale {
            view.scaleFactor = scale
        }
        if let destination, let pageIndex, let page = document.page(at: min(pageIndex, document.pageCount - 1)) {
            view.go(to: PDFDestination(page: page, at: destination.point))
        }
    }
}
