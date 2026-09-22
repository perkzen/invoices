import ArgumentParser
import Foundation

extension VatRate: ExpressibleByArgument {}
extension InvoiceStatus: ExpressibleByArgument {}

/// A number in a line's JSON: `49.9`, or `"49,90"` when the caller would
/// rather not trust a float.
struct DecimalValue: Decodable {
    let value: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            value = try Amount.parse(text)
        } else {
            value = try container.decode(Decimal.self)
        }
    }
}

/// One line item as the caller writes it: a JSON object naming only the
/// fields it wants to set. What it leaves out keeps the line's value — the
/// ledger's defaults on a new line, the current value on an existing one.
struct LineSpec: Decodable {
    static let help = """
        A line item as a JSON object. Keys: description, quantity (default 1), unit \
        (h, kos, dan…; empty hides the column), unitPrice, discountPercent, vatRate \
        (\(VatRate.allCases.map(\.rawValue).joined(separator: ", ")); default: the profile's). \
        Example: {"description": "Consulting", "quantity": 10, "unit": "h", "unitPrice": 50}
        """

    var description: String?
    var quantity: DecimalValue?
    var unit: String?
    var unitPrice: DecimalValue?
    var discountPercent: DecimalValue?
    var vatRate: VatRate?

    static func parse(_ text: String) throws -> LineSpec {
        do {
            return try JSONDecoder().decode(LineSpec.self, from: Data(text.utf8))
        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError("Not a line item: \(text). \(help)")
        }
    }

    @MainActor func apply(to line: InvoiceLine) {
        if let description { line.itemDescription = description }
        if let quantity { line.quantity = quantity.value }
        if let unit { line.unit = unit }
        if let unitPrice { line.unitPrice = unitPrice.value }
        if let discountPercent { line.discountPercent = discountPercent.value }
        if let vatRate { line.vatRate = vatRate }
    }
}
