import Foundation
import SwiftData

/// The issuer — your s.p. There is exactly one of these; see `current(in:)`.
@Model
final class BusinessProfile {
    var name: String = ""
    var street: String = ""
    var postalCode: String = ""
    var city: String = ""
    var countryCode: String = "SI"
    var taxNumber: String = ""
    var vatID: String = ""
    /// A normiranec does not track actual expenses; a normalni s.p. does.
    var isFlatRate: Bool = true
    var isVatRegistered: Bool = false
    var iban: String = ""
    var bankName: String = ""
    var bic: String = ""
    var email: String = ""
    var phone: String = ""
    var registrationNote: String = ""
    var defaultPaymentTermDays: Int = 8
    var invoiceFooter: String = ""

    init() {}

    var defaultVatRate: VatRate { isVatRegistered ? .standard : .exempt }

    var addressLines: [String] {
        [street, "\(postalCode) \(city)".trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }
    }

    /// Fetches the single profile, creating it on first launch.
    static func current(in context: ModelContext) -> BusinessProfile {
        let existing = try? context.fetch(FetchDescriptor<BusinessProfile>())
        if let profile = existing?.first { return profile }
        let profile = BusinessProfile()
        context.insert(profile)
        return profile
    }
}
