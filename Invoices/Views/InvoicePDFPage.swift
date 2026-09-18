import SwiftUI

/// One A4 page of a rendered invoice. Laid out at exactly `InvoicePDF.pageSize`
/// so `ImageRenderer` can hand it straight to a PDF context.
struct InvoicePDFPage: View {
    let invoice: Invoice
    let profile: BusinessProfile
    let lines: [InvoiceLine]
    let pageNumber: Int
    let pageCount: Int
    /// Totals, payment details and the footer only appear on the last page.
    let showsSummary: Bool
    let chargesVat: Bool

    private let margin: CGFloat = 44

    var body: some View {
        ZStack {
            Color.white
            if invoice.status.isEditable {
                draftWatermark
            }
            VStack(alignment: .leading, spacing: 18) {
                if pageNumber == 1 {
                    header
                    parties
                    metadata
                } else {
                    continuationHeader
                }
                table
                if showsSummary {
                    summary
                }
                Spacer(minLength: 0)
                footer
            }
            .padding(margin)
        }
        .frame(width: InvoicePDF.pageSize.width, height: InvoicePDF.pageSize.height)
        .foregroundStyle(.black)
        .environment(\.colorScheme, .light)
    }

    private var draftWatermark: some View {
        Text("OSNUTEK")
            .font(.system(size: 110, weight: .bold))
            .foregroundStyle(.red.opacity(0.12))
            .rotationEffect(.degrees(-30))
    }

    /// Continuation pages carry only enough to identify the invoice — the full
    /// header block would not leave room for the rows the budget assumes.
    private var continuationHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(profile.name.isEmpty ? "—" : profile.name)
                .font(.system(size: 11, weight: .bold))
            Spacer()
            Text(invoice.number.isEmpty
                 ? "Račun – nadaljevanje"
                 : "Račun št. \(invoice.number) – nadaljevanje")
                .font(.system(size: 11))
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name.isEmpty ? "—" : profile.name)
                    .font(.system(size: 13, weight: .bold))
                ForEach(profile.addressLines, id: \.self) { Text($0).font(.system(size: 10)) }
                Text("Davčna številka: \(profile.taxNumber)").font(.system(size: 10))
                // A non-zavezanec must not print an ID za DDV, even a stored one.
                if profile.isVatRegistered, !profile.vatID.isEmpty {
                    Text("ID za DDV: \(profile.vatID)").font(.system(size: 10))
                }
                if !profile.registrationNote.isEmpty {
                    Text(profile.registrationNote).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("RAČUN").font(.system(size: 22, weight: .bold))
                Text(invoice.number.isEmpty ? "(številka ob izdaji)" : "št. \(invoice.number)")
                    .font(.system(size: 12))
            }
        }
    }

    private var parties: some View {
        HStack(alignment: .top) {
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("Kupec").font(.system(size: 9)).foregroundStyle(.secondary)
                Text(invoice.client?.displayName ?? "—")
                    .font(.system(size: 12, weight: .semibold))
                ForEach(invoice.client?.addressLines ?? [], id: \.self) {
                    Text($0).font(.system(size: 10))
                }
                if let tax = invoice.client?.taxNumber, !tax.isEmpty {
                    Text("Davčna številka: \(tax)").font(.system(size: 10))
                }
            }
            .frame(width: 230, alignment: .leading)
        }
    }

    private var metadata: some View {
        HStack(alignment: .top, spacing: 26) {
            metaColumn("Kraj izdaje", invoice.placeOfIssue.isEmpty ? "—" : invoice.placeOfIssue)
            metaColumn("Datum izdaje", Formatting.date(invoice.issueDate))
            metaColumn("Datum opravljene storitve", Formatting.date(invoice.serviceDate))
            metaColumn("Rok plačila", Formatting.date(invoice.dueDate))
        }
    }

    private func metaColumn(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 8)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 10))
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            tableRow(
                description: "Opis", quantity: "Kol.", unit: "EM",
                price: "Cena", discount: "Popust", vat: "DDV", amount: "Znesek",
                isHeader: true
            )
            Divider().overlay(.black)
            ForEach(lines) { line in
                tableRow(
                    description: line.itemDescription.isEmpty ? "—" : line.itemDescription,
                    quantity: Formatting.number(line.quantity, fractionDigits: 2),
                    unit: line.unit,
                    price: Formatting.amount(line.unitPrice),
                    discount: line.discountPercent == 0 ? "" : Formatting.percent(line.discountPercent),
                    vat: Formatting.percent(line.vatRate.percentage),
                    amount: Formatting.amount(line.amounts.gross),
                    isHeader: false
                )
                Divider().overlay(.black.opacity(0.15))
            }
        }
    }

    private func tableRow(
        description: String, quantity: String, unit: String, price: String,
        discount: String, vat: String, amount: String, isHeader: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            // Bounded height keeps the fixed lines-per-page maths honest.
            Text(description)
                .lineLimit(InvoicePDF.maxDescriptionLinesForLayout)
                // Without this SwiftUI squeezes the first rows to one line
                // when the page is near full, giving ragged row heights.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(quantity).frame(width: 46, alignment: .trailing)
            Text(unit).frame(width: 36, alignment: .leading)
            Text(price).frame(width: 66, alignment: .trailing)
            Text(discount).frame(width: 48, alignment: .trailing)
            if chargesVat {
                Text(vat).frame(width: 48, alignment: .trailing)
            }
            Text(amount).frame(width: 74, alignment: .trailing)
        }
        .font(.system(size: isHeader ? 9 : 10, weight: isHeader ? .semibold : .regular))
        .foregroundStyle(isHeader ? .secondary : .primary)
        .monospacedDigit()
        .padding(.vertical, 5)
    }

    private var summary: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if chargesVat {
                summaryRow("Neto", Formatting.money(invoice.totals.net, currencyCode: invoice.currencyCode))
                ForEach(invoice.vatBreakdown.filter { $0.amounts.vat != 0 }, id: \.rate) { entry in
                    summaryRow("DDV \(Formatting.percent(entry.rate.percentage))",
                               Formatting.money(entry.amounts.vat, currencyCode: invoice.currencyCode))
                }
            }
            Divider().frame(width: 250).overlay(.black)
            HStack {
                Text("Za plačilo").font(.system(size: 12, weight: .bold))
                Spacer()
                Text(Formatting.money(invoice.totals.gross, currencyCode: invoice.currencyCode))
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
            }
            .frame(width: 250)

            VStack(alignment: .leading, spacing: 3) {
                // TODO: a registered zavezanec billing reverse charge needs its
                // own clause (25. člen ZDDV-1); it is not the 94. člen one.
                if !chargesVat {
                    ForEach(invoice.exemptionClauses, id: \.self) {
                        Text($0).font(.system(size: 9))
                    }
                }
                if !profile.iban.isEmpty {
                    Text("Znesek nakažite na \(profile.iban)\(profile.bankName.isEmpty ? "" : " (\(profile.bankName))").")
                        .font(.system(size: 9))
                }
                if !invoice.paymentReference.isEmpty {
                    Text("Sklic: \(invoice.paymentReference)").font(.system(size: 9))
                }
                if !invoice.notes.isEmpty {
                    Text(invoice.notes).font(.system(size: 9))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 10))
        .frame(width: 250)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider().overlay(.black.opacity(0.2))
            HStack(alignment: .top) {
                Text(profile.invoiceFooter.isEmpty
                     ? "Račun je izdan v elektronski obliki in je veljaven brez žiga in podpisa."
                     : profile.invoiceFooter)
                Spacer()
                Text("Stran \(pageNumber) / \(pageCount)")
            }
            .font(.system(size: 8))
            .foregroundStyle(.secondary)
        }
    }
}
