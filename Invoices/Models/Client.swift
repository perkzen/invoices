import Foundation
import SwiftData

@Model
final class Client {
    var name: String = ""
    var street: String = ""
    var postalCode: String = ""
    var city: String = ""
    var countryCode: String = "SI"
    /// Davčna številka, without the SI prefix.
    var taxNumber: String = ""
    /// ID za DDV — empty when the client is not a DDV zavezanec.
    var vatID: String = ""
    var email: String = ""
    var defaultPaymentTermDays: Int = 8
    var notes: String = ""
    var createdAt: Date = Date()

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

    var displayName: String { name.isEmpty ? String(localized: "Neimenovana stranka") : name }
}
