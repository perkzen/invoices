import Foundation

/// Everything the printed račun shows, as plain values — the way
/// `YearOverviewRow` is the plain value behind the year overview. Built once
/// from the models, then consumed by the page layout, the pagination budget,
/// the live preview and the settings sample alike.
///
/// The rules about *what* is printed live here, not on the page: whether the
/// ID za DDV appears, which optional columns show, what the Vrednost column
/// holds, which clauses go under the total. The page only decides where.
///
/// Being `Hashable` is what drives the preview: SwiftUI builds the value in a
/// `body`, hands it to `.task(id:)`, and re-renders when it changes. There is
/// no list of watched properties to keep in step with the page.
nonisolated struct PrintedInvoice: Hashable, Sendable {
    /// The s.p. as printed in the header and the signature block.
    struct Issuer: Hashable, Sendable {
        var name = ""
        var activityLine = ""
        var addressLines: [String] = []
        var taxNumber = ""
        var vatID = ""
        var iban = ""
        var bankName = ""
        var registrationNote = ""
        var logo: Data?
        var signerName = ""
        var signature: Data?
        var footer = ""
        var closingNote = ""
    }

    /// The stranka as printed opposite the invoice data.
    struct Customer: Hashable, Sendable {
        var name = ""
        var addressLines: [String] = []
        var taxNumber = ""
        var vatID = ""
    }

    /// One row of the item table. `index` is the row's position on the
    /// invoice, one-based, so numbering carries on across pages.
    struct Line: Hashable, Sendable, Identifiable {
        var index: Int
        var description = ""
        var quantity: Decimal = 1
        var unit = ""
        var unitPrice: Decimal = 0
        var discountPercent: Decimal = 0
        var vatRate: VatRate = .exempt

        var id: Int { index }

        var amounts: Amounts {
            InvoiceMath.lineAmounts(
                quantity: quantity,
                unitPrice: unitPrice,
                discountPercent: discountPercent,
                vatPercentage: vatRate.percentage
            )
        }
    }

    /// Empty for a draft; the OSNUTEK watermark follows `isDraft`.
    var number = ""
    var isDraft = true
    var issueDate: Date
    var serviceDate: Date
    var serviceDateEnd: Date?
    var dueDate: Date
    var placeOfIssue = ""
    var paymentReference = ""
    var currencyCode = "EUR"
    /// The issuer is a DDV zavezanec: the table gets a VAT column and the
    /// summary a breakdown per rate. Otherwise the exemption clauses print.
    var chargesVat = false
    var issuer = Issuer()
    var customer: Customer?
    var lines: [Line] = []
    /// The intro and payment sentences with their placeholders resolved.
    var intro = ""
    var paymentNote = ""
    var notes = ""

    // MARK: What the page derives

    var servicePeriod: String { Formatting.period(serviceDate, to: serviceDateEnd) }

    var totals: Amounts { InvoiceMath.total(of: lines.map(\.amounts)) }

    /// The "obračun DDV" block: one row per rate that actually charged something.
    var vatBreakdown: [(rate: VatRate, amounts: Amounts)] {
        InvoiceMath.vatBreakdown(lines.map { ($0.vatRate, $0.amounts) })
            .filter { $0.amounts.vat != 0 }
    }

    /// Clauses that must be printed when no VAT is charged. A zavezanec's
    /// invoice carries the breakdown instead.
    var exemptionClauses: [String] {
        guard !chargesVat else { return [] }
        return Array(Set(lines.compactMap { $0.vatRate.exemptionClause })).sorted()
    }

    /// A non-zavezanec must not print an ID za DDV, even a stored one.
    var issuerVatID: String? {
        chargesVat && !issuer.vatID.isEmpty ? issuer.vatID : nil
    }

    /// Printed under "Račun izdal:". Falls back to the business name.
    var signerName: String { issuer.signerName.isEmpty ? issuer.name : issuer.signerName }

    // Optional columns are decided per invoice, not per page, so a
    // continuation page lines up with the first one.
    var showsUnit: Bool { lines.contains { !$0.unit.isEmpty } }
    var showsDiscount: Bool { lines.contains { $0.discountPercent != 0 } }

    /// With VAT the Vrednost column is the net value and the tax is summed
    /// below; without VAT the two are the same number.
    func columnAmount(of line: Line) -> Decimal {
        chargesVat ? line.amounts.net : line.amounts.gross
    }

    var suggestedFilename: String {
        number.isEmpty ? "Osnutek-racuna" : "Racun-\(number)"
    }
}

extension PrintedInvoice {
    /// The invoice as the models describe it right now.
    static func make(invoice: Invoice, profile: BusinessProfile) -> PrintedInvoice {
        let context = InvoiceTemplate.Context(
            serviceDate: invoice.serviceDateEnd ?? invoice.serviceDate,
            clientName: invoice.client?.displayName ?? "",
            number: invoice.number,
            iban: profile.iban,
            reference: invoice.paymentReference.isEmpty
                ? InvoiceNumbering.defaultReference(number: invoice.number)
                : invoice.paymentReference,
            dueDate: invoice.dueDate
        )
        let introTemplate = invoice.introOverride.isEmpty ? profile.introTemplate : invoice.introOverride

        return PrintedInvoice(
            number: invoice.number,
            isDraft: invoice.status.isEditable,
            issueDate: invoice.issueDate,
            serviceDate: invoice.serviceDate,
            serviceDateEnd: invoice.serviceDateEnd,
            dueDate: invoice.dueDate,
            placeOfIssue: invoice.placeOfIssue,
            paymentReference: invoice.paymentReference,
            currencyCode: invoice.currencyCode,
            chargesVat: profile.isVatRegistered,
            issuer: Issuer(profile),
            customer: invoice.client.map(Customer.init),
            lines: invoice.sortedLines.enumerated().map { offset, line in
                Line(
                    index: offset + 1,
                    description: line.itemDescription,
                    quantity: line.quantity,
                    unit: line.unit,
                    unitPrice: line.unitPrice,
                    discountPercent: line.discountPercent,
                    vatRate: line.vatRate
                )
            },
            intro: InvoiceTemplate.resolve(introTemplate, in: context),
            // The payment instruction only makes sense with an account to pay into.
            paymentNote: profile.iban.isEmpty ? "" : InvoiceTemplate.resolve(profile.paymentNoteTemplate, in: context),
            notes: invoice.notes
        )
    }
}

extension PrintedInvoice.Issuer {
    init(_ profile: BusinessProfile) {
        self.init(
            name: profile.name,
            activityLine: profile.activityLine,
            addressLines: profile.addressLines,
            taxNumber: profile.taxNumber,
            vatID: profile.vatID,
            iban: profile.iban,
            bankName: profile.bankName,
            registrationNote: profile.registrationNote,
            logo: profile.logoData,
            signerName: profile.signerName,
            signature: profile.signatureData,
            footer: profile.invoiceFooter,
            closingNote: profile.closingNote
        )
    }
}

extension PrintedInvoice.Customer {
    init(_ client: Client) {
        self.init(
            name: client.displayName,
            addressLines: client.addressLines,
            taxNumber: client.taxNumber,
            vatID: client.vatID
        )
    }
}
