import Foundation
import SwiftData

@Model
final class InvoiceLine {
    var itemDescription: String = ""
    var quantity: Decimal = 1
    /// Unit of measure — "ura", "kos", "dan", "mesec". Empty hides the
    /// column on the printed invoice.
    var unit: String = ""
    var unitPrice: Decimal = 0
    var discountPercent: Decimal = 0
    var vatRate: VatRate = VatRate.exempt
    var sortIndex: Int = 0

    var invoice: Invoice?

    init(
        itemDescription: String = "",
        quantity: Decimal = 1,
        unit: String = "",
        unitPrice: Decimal = 0,
        discountPercent: Decimal = 0,
        vatRate: VatRate = .exempt,
        sortIndex: Int = 0
    ) {
        self.itemDescription = itemDescription
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.discountPercent = discountPercent
        self.vatRate = vatRate
        self.sortIndex = sortIndex
    }

    var amounts: Amounts {
        InvoiceMath.lineAmounts(
            quantity: quantity,
            unitPrice: unitPrice,
            discountPercent: discountPercent,
            vatPercentage: vatRate.percentage
        )
    }
}
