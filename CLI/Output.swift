import Foundation

/// Every command answers in JSON. Keys are sorted so two runs diff cleanly;
/// dates are calendar days, amounts are numbers.
enum Output {
    static func print<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            fail("The result could not be encoded as JSON.")
            return
        }
        Swift.print(text)
    }

    static func fail(_ message: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = (try? encoder.encode(["error": message])) ?? Data()
        FileHandle.standardError.write(data + Data("\n".utf8))
    }
}

/// A calendar day as the tool reads and writes it: `2026-09-22`, on the
/// app's calendar so a date never lands in the wrong year.
enum Day {
    static func string(_ date: Date) -> String {
        let parts = Formatting.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func string(_ date: Date?) -> String? {
        guard let date else { return nil }
        return string(date)
    }

    static func parse(_ text: String) throws -> Date {
        if text.lowercased() == "today" { return Date() }
        let parts = text.split(separator: "-").map { Int($0) }
        guard parts.count == 3, let year = parts[0], let month = parts[1], let day = parts[2],
              let date = Formatting.calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { throw ToolError("\"\(text)\" is not a date; write it as YYYY-MM-DD.") }
        // A day that does not exist (2026-02-30) rolls over instead of failing.
        let back = Formatting.calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else {
            throw ToolError("\"\(text)\" is not a day on the calendar.")
        }
        return date
    }
}

/// An amount as typed on the command line: `49.90`, or `49,90` the
/// Slovenian way.
enum Amount {
    static func parse(_ text: String) throws -> Decimal {
        let normalized = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), !normalized.isEmpty else {
            throw ToolError("\"\(text)\" is not a number.")
        }
        return value
    }
}

// MARK: What the commands print

struct AmountsRecord: Encodable {
    var net: Decimal
    var vat: Decimal
    var gross: Decimal

    init(_ amounts: Amounts) {
        net = amounts.net
        vat = amounts.vat
        gross = amounts.gross
    }
}

struct ClientSummary: Encodable {
    var id: String?
    var name: String
}

struct ClientRecord: Encodable {
    var id: String?
    var name: String
    var street: String
    var postalCode: String
    var city: String
    var countryCode: String
    var taxNumber: String
    var vatID: String
    var email: String
    var defaultPaymentTermDays: Int
    var notes: String
    var invoiceCount: Int
    var outstanding: Decimal
    /// Only `client show` lists them.
    var invoices: [InvoiceSummary]?
}

struct LineRecord: Encodable {
    var index: Int
    var description: String
    var quantity: Decimal
    var unit: String
    var unitPrice: Decimal
    var discountPercent: Decimal
    var vatRate: String
    var amounts: AmountsRecord
}

struct InvoiceSummary: Encodable {
    var id: String?
    var number: String?
    var status: String
    var issueDate: String
    var dueDate: String
    var paidDate: String?
    var isOverdue: Bool
    var client: ClientSummary?
    var total: Decimal
    var currencyCode: String
}

struct InvoiceRecord: Encodable {
    var id: String?
    var number: String?
    var status: String
    var issueDate: String
    var serviceDate: String
    var serviceDateEnd: String?
    var dueDate: String
    var paidDate: String?
    var isOverdue: Bool
    var currencyCode: String
    var placeOfIssue: String
    var paymentReference: String
    var notes: String
    var introOverride: String
    var client: ClientSummary?
    var lines: [LineRecord]
    var totals: AmountsRecord
}

struct ProfileRecord: Encodable {
    var name: String
    var activityLine: String
    var street: String
    var postalCode: String
    var city: String
    var countryCode: String
    var taxNumber: String
    var vatID: String
    var isVatRegistered: Bool
    var isFlatRate: Bool
    var iban: String
    var bankName: String
    var bic: String
    var email: String
    var phone: String
    var registrationNote: String
    var defaultPaymentTermDays: Int
    var signerName: String
    var introTemplate: String
    var paymentNoteTemplate: String
    var closingNote: String
    var invoiceFooter: String
    var emailSubjectTemplate: String
    var emailBodyTemplate: String
    var hasLogo: Bool
    var hasSignature: Bool
}

extension ClientSummary {
    @MainActor init(_ client: Client) {
        id = client.uuid?.uuidString
        name = client.displayName
    }
}

extension ClientRecord {
    @MainActor init(_ client: Client, listingInvoices: Bool = false) {
        id = client.uuid?.uuidString
        name = client.name
        street = client.street
        postalCode = client.postalCode
        city = client.city
        countryCode = client.countryCode
        taxNumber = client.taxNumber
        vatID = client.vatID
        email = client.email
        defaultPaymentTermDays = client.defaultPaymentTermDays
        notes = client.notes
        invoiceCount = client.invoices.count
        outstanding = client.outstandingTotal
        invoices = listingInvoices
            ? client.invoices
                .sorted { ($0.year, $0.sequence, $0.issueDate) > ($1.year, $1.sequence, $1.issueDate) }
                .map { InvoiceSummary($0) }
            : nil
    }
}

extension LineRecord {
    @MainActor init(index: Int, _ line: InvoiceLine) {
        self.index = index
        description = line.itemDescription
        quantity = line.quantity
        unit = line.unit
        unitPrice = line.unitPrice
        discountPercent = line.discountPercent
        vatRate = line.vatRate.rawValue
        amounts = AmountsRecord(line.amounts)
    }
}

extension InvoiceSummary {
    @MainActor init(_ invoice: Invoice) {
        id = invoice.uuid?.uuidString
        number = invoice.number.isEmpty ? nil : invoice.number
        status = invoice.status.rawValue
        issueDate = Day.string(invoice.issueDate)
        dueDate = Day.string(invoice.dueDate)
        paidDate = Day.string(invoice.paidDate)
        isOverdue = invoice.isOverdue
        client = invoice.client.map { ClientSummary($0) }
        total = invoice.totals.gross
        currencyCode = invoice.currencyCode
    }
}

extension InvoiceRecord {
    @MainActor init(_ invoice: Invoice) {
        id = invoice.uuid?.uuidString
        number = invoice.number.isEmpty ? nil : invoice.number
        status = invoice.status.rawValue
        issueDate = Day.string(invoice.issueDate)
        serviceDate = Day.string(invoice.serviceDate)
        serviceDateEnd = Day.string(invoice.serviceDateEnd)
        dueDate = Day.string(invoice.dueDate)
        paidDate = Day.string(invoice.paidDate)
        isOverdue = invoice.isOverdue
        currencyCode = invoice.currencyCode
        placeOfIssue = invoice.placeOfIssue
        paymentReference = invoice.paymentReference
        notes = invoice.notes
        introOverride = invoice.introOverride
        client = invoice.client.map { ClientSummary($0) }
        lines = invoice.sortedLines.enumerated().map { LineRecord(index: $0.offset + 1, $0.element) }
        totals = AmountsRecord(invoice.totals)
    }
}

extension ProfileRecord {
    @MainActor init(_ profile: BusinessProfile) {
        name = profile.name
        activityLine = profile.activityLine
        street = profile.street
        postalCode = profile.postalCode
        city = profile.city
        countryCode = profile.countryCode
        taxNumber = profile.taxNumber
        vatID = profile.vatID
        isVatRegistered = profile.isVatRegistered
        isFlatRate = profile.isFlatRate
        iban = profile.iban
        bankName = profile.bankName
        bic = profile.bic
        email = profile.email
        phone = profile.phone
        registrationNote = profile.registrationNote
        defaultPaymentTermDays = profile.defaultPaymentTermDays
        signerName = profile.signerName
        introTemplate = profile.introTemplate
        paymentNoteTemplate = profile.paymentNoteTemplate
        closingNote = profile.closingNote
        invoiceFooter = profile.invoiceFooter
        emailSubjectTemplate = profile.emailSubjectTemplate
        emailBodyTemplate = profile.emailBodyTemplate
        hasLogo = profile.logoData != nil
        hasSignature = profile.signatureData != nil
    }
}
