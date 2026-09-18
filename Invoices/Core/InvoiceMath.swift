import Foundation

/// Net / VAT / gross for a single amount. Plain values so the arithmetic
/// can be tested without a SwiftData container.
nonisolated struct Amounts: Equatable, Sendable {
    var net: Decimal = 0
    var vat: Decimal = 0

    var gross: Decimal { net + vat }

    static func + (lhs: Amounts, rhs: Amounts) -> Amounts {
        Amounts(net: lhs.net + rhs.net, vat: lhs.vat + rhs.vat)
    }
}

nonisolated enum InvoiceMath {
    /// Line total. Rounding happens once per line, then lines are summed —
    /// the same order a Slovenian accountant reconciles them in.
    static func lineAmounts(
        quantity: Decimal,
        unitPrice: Decimal,
        discountPercent: Decimal,
        vatPercentage: Decimal
    ) -> Amounts {
        let gross = quantity * unitPrice
        let discount = gross * discountPercent / 100
        let net = (gross - discount).rounded()
        let vat = (net * vatPercentage / 100).rounded()
        return Amounts(net: net, vat: vat)
    }

    static func total(of lines: [Amounts]) -> Amounts {
        lines.reduce(Amounts(), +)
    }

    /// VAT recap grouped by rate, for the "obračun DDV" block on the invoice.
    static func vatBreakdown(_ entries: [(rate: VatRate, amounts: Amounts)]) -> [(rate: VatRate, amounts: Amounts)] {
        var byRate: [VatRate: Amounts] = [:]
        for entry in entries {
            byRate[entry.rate, default: Amounts()] = byRate[entry.rate, default: Amounts()] + entry.amounts
        }
        return VatRate.allCases.compactMap { rate in
            byRate[rate].map { (rate, $0) }
        }
    }
}
