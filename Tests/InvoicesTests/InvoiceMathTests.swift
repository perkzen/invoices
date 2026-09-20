import Foundation
import Testing
@testable import Invoices

@Suite("Line arithmetic")
struct InvoiceMathTests {
    @Test func `line without discount adds 22 % VAT`() {
        let amounts = InvoiceMath.lineAmounts(
            quantity: 10, unitPrice: 50, discountPercent: 0, vatPercentage: 22
        )
        #expect(amounts.net == 500)
        #expect(amounts.vat == 110)
        #expect(amounts.gross == 610)
    }

    @Test func `discount applies before VAT`() {
        let amounts = InvoiceMath.lineAmounts(
            quantity: 2, unitPrice: 100, discountPercent: 10, vatPercentage: 22
        )
        #expect(amounts.net == 180)
        #expect(amounts.vat == Decimal(string: "39.60"))
    }

    @Test func `an s p that is not a VAT payer charges no VAT`() {
        let amounts = InvoiceMath.lineAmounts(
            quantity: 7, unitPrice: 45, discountPercent: 0,
            vatPercentage: VatRate.exempt.percentage
        )
        #expect(amounts.net == 315)
        #expect(amounts.vat == 0)
        #expect(amounts.gross == 315)
    }

    @Test func `amounts are rounded to cents per line`() {
        let amounts = InvoiceMath.lineAmounts(
            quantity: 3, unitPrice: Decimal(string: "33.333")!,
            discountPercent: 0, vatPercentage: Decimal(string: "9.5")!
        )
        #expect(amounts.net == Decimal(string: "100.00"))
        #expect(amounts.vat == Decimal(string: "9.50"))
    }

    @Test func `totals sum every line`() {
        let lines = [
            InvoiceMath.lineAmounts(quantity: 1, unitPrice: 100, discountPercent: 0, vatPercentage: 22),
            InvoiceMath.lineAmounts(quantity: 2, unitPrice: 50, discountPercent: 0, vatPercentage: 22)
        ]
        let total = InvoiceMath.total(of: lines)
        #expect(total.net == 200)
        #expect(total.vat == 44)
    }

    @Test func `VAT recap groups lines by rate`() {
        let entries: [(rate: VatRate, amounts: Amounts)] = [
            (.standard, Amounts(net: 100, vat: 22)),
            (.reduced, Amounts(net: 200, vat: 19)),
            (.standard, Amounts(net: 50, vat: 11))
        ]
        let recap = InvoiceMath.vatBreakdown(entries)
        #expect(recap.count == 2)
        #expect(recap.first?.rate == .standard)
        #expect(recap.first?.amounts.net == 150)
        #expect(recap.first?.amounts.vat == 33)
    }
}

@Suite("Invoice numbering")
struct InvoiceNumberingTests {
    @Test func `number is year and zero padded sequence`() {
        #expect(InvoiceNumbering.format(year: 2026, sequence: 1) == "2026-001")
        #expect(InvoiceNumbering.format(year: 2026, sequence: 142) == "2026-142")
    }
}
