import AppKit
import SwiftUI

/// One A4 page of a rendered invoice, laid out like the s.p.'s existing
/// invoices: logo and issuer top-left, customer left / invoice data right,
/// an intro sentence, the item table, a single total line, italic clauses,
/// and "Račun izdal" with a signature. Laid out at exactly
/// `InvoicePDF.pageSize` so `ImageRenderer` can hand it to a PDF context.
///
/// Every value it prints comes from `PrintedInvoice`, which has already
/// decided what appears; the page only decides where.
///
/// Every string here is `verbatim`: the invoice is a Slovenian legal
/// document and must not change language with the app's UI.
struct InvoicePDFPage: View {
    let printed: PrintedInvoice
    /// The rows this page carries — a slice of `printed.lines`.
    let lines: [PrintedInvoice.Line]
    let pageNumber: Int
    let pageCount: Int
    /// Totals, clauses and the signature only appear on the last page.
    let showsSummary: Bool

    private let margin: CGFloat = 44
    private let bodySize: CGFloat = 9.5

    private var issuer: PrintedInvoice.Issuer { printed.issuer }

    var body: some View {
        ZStack {
            Color.white
            if printed.isDraft {
                draftWatermark
            }
            VStack(alignment: .leading, spacing: 0) {
                if pageNumber == 1 {
                    issuerBlock
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

    private var issuerBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let logo = issuer.logo.flatMap(NSImage.init(data:)) {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 170, maxHeight: 64, alignment: .leading)
                gap(14)
            }
            Text(issuer.name.isEmpty ? "—" : issuer.name)
                .font(.system(size: 11, weight: .bold))
            if !issuer.activityLine.isEmpty {
                Text(issuer.activityLine).font(.system(size: bodySize, weight: .bold))
            }
            gap(10)
            ForEach(issuer.addressLines, id: \.self) { Text($0) }
            Text(verbatim: "Davčna številka: \(issuer.taxNumber)")
            if let vatID = printed.issuerVatID {
                Text(verbatim: "ID za DDV: \(vatID)")
            }
            if !issuer.iban.isEmpty {
                Text(verbatim: "TRR: \(issuer.iban)")
            }
            if !issuer.bankName.isEmpty {
                Text(issuer.bankName)
            }
            if !issuer.registrationNote.isEmpty {
                Text(issuer.registrationNote).font(.system(size: 8.5)).foregroundStyle(.secondary)
            }
        }
    }

    private var parties: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(printed.customer?.name ?? "—")
                    .font(.system(size: bodySize, weight: .bold))
                ForEach(printed.customer?.addressLines ?? [], id: \.self) { Text($0) }
                if let tax = printed.customer?.taxNumber, !tax.isEmpty {
                    Text(verbatim: "Davčna številka: \(tax)")
                }
                if let vat = printed.customer?.vatID, !vat.isEmpty {
                    Text(verbatim: "ID za DDV: \(vat)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                metaLine("Račun", printed.number.isEmpty ? "osnutek" : printed.number)
                metaLine("Datum", Formatting.date(printed.issueDate))
                metaLine("Valuta", Formatting.date(printed.dueDate))
                metaLine("Kraj izdaje", printed.placeOfIssue.isEmpty ? "—" : printed.placeOfIssue)
                metaLine("Datum opr. storitve", printed.servicePeriod)
                if !printed.paymentReference.isEmpty {
                    metaLine("Referenčna številka", printed.paymentReference)
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
        if !printed.intro.isEmpty {
            Text(printed.intro).fixedSize(horizontal: false, vertical: true)
            gap(8)
        }
    }

    /// Continuation pages carry only enough to identify the invoice — the full
    /// header block would not leave room for the rows the budget assumes.
    private var continuationHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(issuer.name.isEmpty ? "—" : issuer.name)
                .font(.system(size: 11, weight: .bold))
            Spacer()
            Text(verbatim: printed.number.isEmpty
                 ? "Račun – nadaljevanje"
                 : "Račun št. \(printed.number) – nadaljevanje")
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
            ForEach(lines) { line in
                tableRow(
                    index: String(line.index),
                    description: line.description.isEmpty ? "—" : line.description,
                    quantity: Formatting.number(line.quantity, fractionDigits: 2),
                    unit: line.unit,
                    price: Formatting.amount(line.unitPrice),
                    discount: line.discountPercent == 0 ? "" : Formatting.percent(line.discountPercent),
                    vat: Formatting.percent(line.vatRate.percentage),
                    amount: Formatting.amount(printed.columnAmount(of: line)),
                    isHeader: false
                )
                Rectangle().fill(.black.opacity(0.08)).frame(height: 0.5)
            }
        }
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
            if printed.showsUnit {
                Text(unit).frame(width: 40, alignment: isHeader ? .center : .leading)
            }
            Text(price).frame(width: 70, alignment: isHeader ? .center : .trailing)
            if printed.showsDiscount {
                Text(discount).frame(width: 50, alignment: isHeader ? .center : .trailing)
            }
            if printed.chargesVat {
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
            if printed.chargesVat {
                totalRow("Skupaj brez DDV:", printed.totals.net, bold: false)
                ForEach(printed.vatBreakdown, id: \.rate) { entry in
                    totalRow("DDV \(Formatting.percent(entry.rate.percentage)):", entry.amounts.vat, bold: false)
                }
            }
            totalRow("SKUPAJ ZA PLAČILO \(printed.currencyCode):", printed.totals.gross, bold: true)
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
            ForEach(printed.exemptionClauses, id: \.self) { Text($0) }
            if !printed.paymentNote.isEmpty { Text(printed.paymentNote) }
            if !issuer.closingNote.isEmpty { Text(issuer.closingNote) }
            if !printed.notes.isEmpty { Text(printed.notes) }
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
                Text(printed.signerName)
                if let image = issuer.signature.flatMap(NSImage.init(data:)) {
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
        if pageCount > 1 || !issuer.footer.isEmpty {
            HStack(alignment: .top) {
                Text(issuer.footer)
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
