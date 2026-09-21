import Foundation
import SwiftData

@Model
final class Client {
    var name: String = ""
    var street: String = ""
    var postalCode: String = ""
    var city: String = ""
    var countryCode: String = "SI"
    /// Tax number, without the SI prefix.
    var taxNumber: String = ""
    /// VAT ID — empty when the client is not VAT registered.
    var vatID: String = ""
    var email: String = ""
    var defaultPaymentTermDays: Int = 8
    var notes: String = ""
    var createdAt: Date = Date()
    /// Shown next to the client in lists; never printed on an invoice, which
    /// carries the issuer's logo only.
    @Attribute(.externalStorage) var logoData: Data?

    @Relationship(deleteRule: .nullify, inverse: \Invoice.client)
    var invoices: [Invoice] = []

    init(name: String = "") {
        self.name = name
        self.createdAt = Date()
    }

    var addressLines: [String] {
        let country = countryCode.uppercased() == "SI" ? "" : countryCode
        return [street, "\(postalCode) \(city)".trimmingCharacters(in: .whitespaces), country]
            .filter { !$0.isEmpty }
    }

    var displayName: String { name.isEmpty ? String(localized: "Unnamed client") : name }

    /// Up to two initials, for the avatar of a client without a logo.
    /// Uppercased with the Slovenian locale so č, š and ž keep their carons.
    var monogram: String {
        let words = name.split(whereSeparator: \.isWhitespace).prefix(2)
        return words.compactMap(\.first).map { String($0).uppercased(with: Formatting.locale) }.joined()
    }

    /// Invoices that went out: everything but drafts.
    var issuedInvoices: [Invoice] {
        invoices.filter { $0.status != .draft }
    }

    /// Invoices that went out and have not been paid or cancelled.
    var outstandingTotal: Decimal {
        invoices.filter { $0.status == .issued }.reduce(0) { $0 + $1.totals.gross }
    }
}
