import ArgumentParser
import Foundation

/// The issuer: the one business profile.
nonisolated struct ProfileCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "profile",
            abstract: "The business profile — the issuer printed on every invoice.",
            subcommands: [Show.self, Update.self],
            defaultSubcommand: Show.self
        )
    }

    nonisolated struct Show: LedgerCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "show", abstract: "Print the profile.")
        }

        @OptionGroup var store: StoreOptions

        @MainActor func execute(_ book: Book) throws {
            Output.print(ProfileRecord(book.profile))
        }
    }

    nonisolated struct Update: LedgerCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "set",
                abstract: "Change profile fields. Only the options given are changed.",
                discussion: "The logo and the signature are images; set them in the app."
            )
        }

        @OptionGroup var store: StoreOptions

        @Option(help: "Business name.") var name: String?
        @Option(name: .customLong("activity-line"), help: "Line under the name, e.g. \"IT SERVICES AND CONSULTING\".")
        var activityLine: String?
        @Option(help: "Street and number.") var street: String?
        @Option(name: .customLong("postal-code")) var postalCode: String?
        @Option var city: String?
        @Option(name: .customLong("country-code"), help: "Two letters, e.g. SI.") var countryCode: String?
        @Option(name: .customLong("tax-number"), help: "Tax number, without the SI prefix.") var taxNumber: String?
        @Option(name: .customLong("vat-id"), help: "VAT ID, e.g. SI12345678.") var vatID: String?
        @Option(name: .customLong("vat-registered"), help: "true or false. Off, invoices charge no VAT and carry the exemption clause.")
        var vatRegistered: Bool?
        @Option(name: .customLong("flat-rate"), help: "true or false: flat-rate expenses.") var flatRate: Bool?
        @Option var iban: String?
        @Option(name: .customLong("bank-name")) var bankName: String?
        @Option var bic: String?
        @Option var email: String?
        @Option var phone: String?
        @Option(name: .customLong("registration-note"), help: "Registration details printed with the issuer.")
        var registrationNote: String?
        @Option(name: .customLong("payment-term"), help: "Default payment term in days; a new draft is due that many days after today.")
        var paymentTerm: Int?
        @Option(name: .customLong("signer-name"), help: "Printed under \"Issued by:\"; empty means the business name.")
        var signerName: String?
        @Option(name: .customLong("intro-template"), help: "The intro sentence; placeholders {month} {MONTH} {year} {client} {number} {iban} {reference} {due}.")
        var introTemplate: String?
        @Option(name: .customLong("payment-note-template"), help: "The payment sentence, same placeholders.")
        var paymentNoteTemplate: String?
        @Option(name: .customLong("closing-note")) var closingNote: String?
        @Option(name: .customLong("footer"), help: "Line at the foot of every page.") var invoiceFooter: String?
        @Option(name: .customLong("email-subject-template")) var emailSubjectTemplate: String?
        @Option(name: .customLong("email-body-template")) var emailBodyTemplate: String?

        @MainActor func execute(_ book: Book) throws {
            let profile = book.profile
            if let name { profile.name = name }
            if let activityLine { profile.activityLine = activityLine }
            if let street { profile.street = street }
            if let postalCode { profile.postalCode = postalCode }
            if let city { profile.city = city }
            if let countryCode { profile.countryCode = countryCode.uppercased() }
            if let taxNumber { profile.taxNumber = taxNumber }
            if let vatID { profile.vatID = vatID }
            if let vatRegistered { profile.isVatRegistered = vatRegistered }
            if let flatRate { profile.isFlatRate = flatRate }
            if let iban { profile.iban = iban }
            if let bankName { profile.bankName = bankName }
            if let bic { profile.bic = bic }
            if let email { profile.email = email }
            if let phone { profile.phone = phone }
            if let registrationNote { profile.registrationNote = registrationNote }
            if let paymentTerm {
                guard paymentTerm >= 0 else { throw ToolError("The payment term cannot be negative.") }
                profile.defaultPaymentTermDays = paymentTerm
            }
            if let signerName { profile.signerName = signerName }
            if let introTemplate { profile.introTemplate = introTemplate }
            if let paymentNoteTemplate { profile.paymentNoteTemplate = paymentNoteTemplate }
            if let closingNote { profile.closingNote = closingNote }
            if let invoiceFooter { profile.invoiceFooter = invoiceFooter }
            if let emailSubjectTemplate { profile.emailSubjectTemplate = emailSubjectTemplate }
            if let emailBodyTemplate { profile.emailBodyTemplate = emailBodyTemplate }
            Output.print(ProfileRecord(profile))
        }
    }
}
