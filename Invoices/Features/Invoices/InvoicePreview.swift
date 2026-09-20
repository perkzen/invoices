import PDFKit
import SwiftUI

/// The invoice exactly as "Izvozi PDF" will write it, re-rendered whenever
/// anything printed on it changes.
struct InvoicePreview: View {
    let invoice: Invoice
    let profile: BusinessProfile

    /// `.redacted(reason: .privacy)` stops at the edge of an AppKit view, so
    /// the rendered page cannot be blanked the way the rest of the interface
    /// is — it is blurred instead. It stays live while it is blurred, so the
    /// layout still answers whether a long invoice broke onto a second page.
    @AppStorage(PrivacyMode.storageKey) private var hidesSensitiveValues = false
    @State private var pdfData: Data?

    var body: some View {
        PDFDocumentView(data: pdfData)
            .blur(radius: hidesSensitiveValues ? 14 : 0)
            .overlay {
                if hidesSensitiveValues {
                    Label("Predogled je zakrit", systemImage: "eye.slash")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .animation(.default, value: hidesSensitiveValues)
            .task(id: renderKey) {
                // Coalesce a burst of keystrokes into one render.
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                pdfData = InvoicePDF.render(invoice: invoice, profile: profile)
            }
    }

    /// Reading every printed property inside `body` is what registers
    /// observation: when any of them changes SwiftUI re-evaluates the view,
    /// the key changes, and `.task(id:)` renders again.
    private var renderKey: Int {
        var hasher = Hasher()
        hasher.combine(invoice.number)
        hasher.combine(invoice.status)
        hasher.combine(invoice.issueDate)
        hasher.combine(invoice.serviceDate)
        hasher.combine(invoice.serviceDateEnd)
        hasher.combine(invoice.dueDate)
        hasher.combine(invoice.currencyCode)
        hasher.combine(invoice.placeOfIssue)
        hasher.combine(invoice.paymentReference)
        hasher.combine(invoice.notes)
        hasher.combine(invoice.introOverride)

        if let client = invoice.client {
            hasher.combine(client.name)
            hasher.combine(client.street)
            hasher.combine(client.postalCode)
            hasher.combine(client.city)
            hasher.combine(client.countryCode)
            hasher.combine(client.taxNumber)
            hasher.combine(client.vatID)
        }

        for line in invoice.sortedLines {
            hasher.combine(line.itemDescription)
            hasher.combine(line.quantity)
            hasher.combine(line.unit)
            hasher.combine(line.unitPrice)
            hasher.combine(line.discountPercent)
            hasher.combine(line.vatRate)
            hasher.combine(line.sortIndex)
        }

        hasher.combine(profile.name)
        hasher.combine(profile.activityLine)
        hasher.combine(profile.street)
        hasher.combine(profile.postalCode)
        hasher.combine(profile.city)
        hasher.combine(profile.taxNumber)
        hasher.combine(profile.vatID)
        hasher.combine(profile.isVatRegistered)
        hasher.combine(profile.iban)
        hasher.combine(profile.bankName)
        hasher.combine(profile.registrationNote)
        hasher.combine(profile.invoiceFooter)
        hasher.combine(profile.signerName)
        hasher.combine(profile.introTemplate)
        hasher.combine(profile.paymentNoteTemplate)
        hasher.combine(profile.closingNote)
        hasher.combine(profile.logoData)
        hasher.combine(profile.signatureData)
        return hasher.finalize()
    }
}

/// PDFKit viewer that swaps documents without losing the reader's zoom or
/// place on the page, so typing into a field does not jump the preview.
struct PDFDocumentView: NSViewRepresentable {
    let data: Data?

    final class Coordinator {
        var shownData: Data?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
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
