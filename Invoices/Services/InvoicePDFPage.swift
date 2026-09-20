import AppKit
import SwiftUI

/// One A4 page of a rendered invoice, laid out like the s.p.'s existing
/// invoices: logo and issuer top-left, customer left / invoice data right,
/// an intro sentence, the item table, a single total line, italic clauses,
/// and "Račun izdal" with a signature. Laid out at exactly
/// `InvoicePDF.pageSize` so `ImageRenderer` can hand it to a PDF context.
///
/// Every string here is `verbatim`: the invoice is a Slovenian legal
/// document and must not change language with the app's UI.
struct InvoicePDFPage: View {
    let invoice: Invoice
    let profile: BusinessProfile
    let lines: [InvoiceLine]
    let pageNumber: Int
    let pageCount: Int
    /// Totals, clauses and the signature only appear on the last page.
    let showsSummary: Bool
    let chargesVat: Bool

    private let margin: CGFloat = 44
    private let bodySize: CGFloat = 9.5

    // Optional columns are decided per invoice, not per page, so a
    // continuation page lines up with the first one.
    private var showsUnit: Bool { invoice.lines.contains { !$0.unit.isEmpty } }
    private var showsDiscount: Bool { invoice.lines.contains { $0.discountPercent != 0 } }

    var body: some View {
        ZStack {
            Color.white
            if invoice.status.isEditable {
                draftWatermark
            }
            VStack(alignment: .leading, spacing: 0) {
                if pageNumber == 1 {
                    issuer
                    gap(28)
                    parties
                    gap(30)
                    intro
                } else {
                    continuationHeader
                    gap(16)
                }
                table
                if showsSummary {
                    totals
                    gap(24)
                    clauses
                    gap(44)
                    signature
                }
                Spacer(minLength: 0)
                footer
            }
            .padding(margin)
        }
        .frame(width: InvoicePDF.pageSize.width, height: InvoicePDF.pageSize.height)
        .font(.system(size: bodySize))
        .foregroundStyle(.black)
        .environment(\.colorScheme, .light)
    }

    private func gap(_ height: CGFloat) -> some View {
        Spacer().frame(height: height)
    }

    private var draftWatermark: some View {
        Text(verbatim: "OSNUTEK")
            .font(.system(size: 110, weight: .bold))
            .foregroundStyle(.red.opacity(0.12))
            .rotationEffect(.degrees(-30))
    }

    // MARK: Page 1 header

    private var issuer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let logo = profile.logoData.flatMap(NSImage.init(data:)) {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 170, maxHeight: 64, alignment: .leading)
                gap(14)
            }
            Text(profile.name.isEmpty ? "—" : profile.name)
                .font(.system(size: 11, weight: .bold))
            if !profile.activityLine.isEmpty {
                Text(profile.activityLine).font(.system(size: bodySize, weight: .bold))
            }
            gap(10)
            ForEach(profile.addressLines, id: \.self) { Text($0) }
            Text(verbatim: "Davčna številka: \(profile.taxNumber)")
            // A non-zavezanec must not print an ID za DDV, even a stored one.
            if profile.isVatRegistered, !profile.vatID.isEmpty {
                Text(verbatim: "ID za DDV: \(profile.vatID)")
            }
            if !profile.iban.isEmpty {
                Text(verbatim: "TRR: \(profile.iban)")
            }
            if !profile.bankName.isEmpty {
                Text(profile.bankName)
            }
            if !profile.registrationNote.isEmpty {
                Text(profile.registrationNote).font(.system(size: 8.5)).foregroundStyle(.secondary)
            }
        }
    }

    private var parties: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(invoice.client?.displayName ?? "—")
                    .font(.system(size: bodySize, weight: .bold))
                ForEach(invoice.client?.addressLines ?? [], id: \.self) { Text($0) }
                if let tax = invoice.client?.taxNumber, !tax.isEmpty {
                    Text(verbatim: "Davčna številka: \(tax)")
                }
                if let vat = invoice.client?.vatID, !vat.isEmpty {
                    Text(verbatim: "ID za DDV: \(vat)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                metaLine("Račun", invoice.number.isEmpty ? "osnutek" : invoice.number)
                metaLine("Datum", Formatting.date(invoice.issueDate))
                metaLine("Valuta", Formatting.date(invoice.dueDate))
                metaLine("Kraj izdaje", invoice.placeOfIssue.isEmpty ? "—" : invoice.placeOfIssue)
                metaLine("Datum opr. storitve", InvoiceTemplate.servicePeriod(for: invoice))
                if !invoice.paymentReference.isEmpty {
                    metaLine("Referenčna številka", invoice.paymentReference)
                }
            }
            .frame(width: 240, alignment: .leading)
        }
    }

    private func metaLine(_ label: String, _ value: String) -> some View {
        (Text(verbatim: "\(label): ").fontWeight(.bold) + Text(verbatim: value))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var intro: some View {
        let text = InvoiceTemplate.intro(for: invoice, profile: profile)
        if !text.isEmpty {
            Text(text).fixedSize(horizontal: false, vertical: true)
            gap(8)
        }
    }

    /// Continuation pages carry only enough to identify the invoice — the full
    /// header block would not leave room for the rows the budget assumes.
    private var continuationHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(profile.name.isEmpty ? "—" : profile.name)
                .font(.system(size: 11, weight: .bold))
            Spacer()
            Text(verbatim: invoice.number.isEmpty
                 ? "Račun – nadaljevanje"
                 : "Račun št. \(invoice.number) – nadaljevanje")
        }
    }

    // MARK: Items

    private var table: some View {
        VStack(spacing: 0) {
            tableRow(
                index: "Z. št.", description: "Opis blaga ali storitev", quantity: "Količina",
                unit: "EM", price: "Cena", discount: "Popust", vat: "DDV", amount: "Vrednost",
                isHeader: true
            )
            Rectangle().fill(.black).frame(height: 0.8)
            ForEach(Array(lines.enumerated()), id: \.element.id) { offset, line in
                tableRow(
                    index: String(indexOfFirstLine + offset),
                    description: line.itemDescription.isEmpty ? "—" : line.itemDescription,
                    quantity: Formatting.number(line.quantity, fractionDigits: 2),
                    unit: line.unit,
                    price: Formatting.amount(line.unitPrice),
                    discount: line.discountPercent == 0 ? "" : Formatting.percent(line.discountPercent),
                    vat: Formatting.percent(line.vatRate.percentage),
                    // With VAT the column is the net value and the tax is
                    // summed below; without VAT the two are the same number.
                    amount: Formatting.amount(chargesVat ? line.amounts.net : line.amounts.gross),
                    isHeader: false
                )
                Rectangle().fill(.black.opacity(0.08)).frame(height: 0.5)
            }
        }
    }

    /// Numbering continues across pages — page 2 does not restart at 1.
    private var indexOfFirstLine: Int {
        guard let first = lines.first,
              let position = invoice.sortedLines.firstIndex(where: { $0.id == first.id })
        else { return 1 }
        return position + 1
    }

    private func tableRow(
        index: String, description: String, quantity: String, unit: String, price: String,
        discount: String, vat: String, amount: String, isHeader: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(index).frame(width: 34, alignment: .center)
            // Bounded height keeps the fixed lines-per-page maths honest.
            Text(description)
                .lineLimit(InvoicePDF.maxDescriptionLinesForLayout)
                // Without this SwiftUI squeezes the first rows to one line
                // when the page is near full, giving ragged row heights.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: isHeader ? .center : .leading)
            Text(quantity).frame(width: 56, alignment: isHeader ? .center : .trailing)
            if showsUnit {
                Text(unit).frame(width: 40, alignment: isHeader ? .center : .leading)
            }
            Text(price).frame(width: 70, alignment: isHeader ? .center : .trailing)
            if showsDiscount {
                Text(discount).frame(width: 50, alignment: isHeader ? .center : .trailing)
            }
            if chargesVat {
                Text(vat).frame(width: 46, alignment: isHeader ? .center : .trailing)
            }
            Text(amount).frame(width: 76, alignment: isHeader ? .center : .trailing)
        }
        .fontWeight(isHeader ? .bold : .regular)
        .monospacedDigit()
        .padding(.vertical, 5)
    }

    // MARK: Last page

    private var totals: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if chargesVat {
                totalRow("Skupaj brez DDV:", invoice.totals.net, bold: false)
                ForEach(invoice.vatBreakdown.filter { $0.amounts.vat != 0 }, id: \.rate) { entry in
                    totalRow("DDV \(Formatting.percent(entry.rate.percentage)):", entry.amounts.vat, bold: false)
                }
            }
            totalRow("SKUPAJ ZA PLAČILO \(invoice.currencyCode):", invoice.totals.gross, bold: true)
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// The amount sits in the Vrednost column, directly under the line values.
    private func totalRow(_ label: String, _ amount: Decimal, bold: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label)
            Text(Formatting.amount(amount)).frame(width: 76, alignment: .trailing)
        }
        .fontWeight(bold ? .bold : .regular)
        .monospacedDigit()
    }

    private var clauses: some View {
        VStack(alignment: .leading, spacing: 4) {
            // TODO: a registered zavezanec billing reverse charge needs its
            // own clause (25. člen ZDDV-1); it is not the 94. člen one.
            if !chargesVat {
                ForEach(invoice.exemptionClauses, id: \.self) { Text($0) }
            }
            let payment = InvoiceTemplate.paymentNote(for: invoice, profile: profile)
            if !payment.isEmpty { Text(payment) }
            if !profile.closingNote.isEmpty { Text(profile.closingNote) }
            if !invoice.notes.isEmpty { Text(invoice.notes) }
        }
        .italic()
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var signature: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "Račun izdal:")
                Text(profile.signerName.isEmpty ? profile.name : profile.signerName)
                if let image = profile.signatureData.flatMap(NSImage.init(data:)) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 140, maxHeight: 44, alignment: .leading)
                } else {
                    gap(44)
                }
            }
            .frame(width: 250, alignment: .leading)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if pageCount > 1 || !profile.invoiceFooter.isEmpty {
            HStack(alignment: .top) {
                Text(profile.invoiceFooter)
                Spacer()
                if pageCount > 1 {
                    Text(verbatim: "Stran \(pageNumber) / \(pageCount)")
                }
            }
            .font(.system(size: 8))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
    }
}
