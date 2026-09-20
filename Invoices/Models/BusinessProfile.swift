import Foundation
import SwiftData

/// The issuer — your s.p. There is exactly one of these; see `Ledger.profile`.
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

    // MARK: Predloga računa — the parts of the printed invoice that are yours
    // to shape: logo, tagline, wording, signature. Placeholders in the text
    // templates are resolved by `InvoiceTemplate`.

    /// Line under the name, e.g. "IT STORITVE IN SVETOVANJE".
    var activityLine: String = ""
    @Attribute(.externalStorage) var logoData: Data?
    @Attribute(.externalStorage) var signatureData: Data?
    /// Printed under "Račun izdal:". Falls back to `name`.
    var signerName: String = ""
    var introTemplate: String = InvoiceTemplate.defaultIntro
    var paymentNoteTemplate: String = InvoiceTemplate.defaultPaymentNote
    var closingNote: String = InvoiceTemplate.defaultClosingNote

    init() {}

    var defaultVatRate: VatRate { isVatRegistered ? .standard : .exempt }

    var addressLines: [String] {
        [street, "\(postalCode) \(city)".trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }
    }
}
