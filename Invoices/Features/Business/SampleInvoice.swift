import Foundation

extension PrintedInvoice {
    /// A representative invoice for the settings preview: last month's work
    /// for a made-up client, printed with the profile's own header, wording
    /// and VAT status. A plain value, so it never touches the store or the
    /// real numbering.
    ///
    /// The sample is previewed on the printed invoice, so its text reads in
    /// the document's language, not the interface's.
    static func sample(matching profile: BusinessProfile) -> PrintedInvoice {
        let calendar = Formatting.calendar
        let today = Date()
        let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfThisMonth) ?? today
        let context = InvoiceTemplate.Context.sample(matching: profile)
        let customer = Customer(
            name: context.clientName,
            addressLines: [DocumentText.string("1 Sample Street"), "1000 Ljubljana"],
            taxNumber: "12345678"
        )
        let items: [(String, Decimal, Decimal)] = [
            (DocumentText.string("Software development"), 1, 1075),
            (DocumentText.string("Consulting and support"), 4, 60),
        ]

        return PrintedInvoice(
            number: context.number,
            isDraft: false,
            issueDate: today,
            serviceDate: startOfLastMonth,
            serviceDateEnd: context.serviceDate,
            dueDate: context.dueDate,
            placeOfIssue: profile.city.isEmpty ? "Ljubljana" : profile.city,
            paymentReference: context.reference,
            chargesVat: profile.isVatRegistered,
            issuer: Issuer(profile),
            customer: customer,
            lines: items.enumerated().map { offset, item in
                Line(
                    index: offset + 1,
                    description: item.0,
                    quantity: item.1,
                    unitPrice: item.2,
                    vatRate: profile.defaultVatRate
                )
            },
            intro: InvoiceTemplate.resolve(profile.introTemplate, in: context),
            paymentNote: profile.iban.isEmpty ? "" : InvoiceTemplate.resolve(profile.paymentNoteTemplate, in: context)
        )
    }
}

extension InvoiceTemplate.Context {
    /// The facts the sample invoice is worded with: last month's service for
    /// the made-up client, numbered as this year's eighth, due after the
    /// profile's payment term. The printed sample and the sample email are
    /// both resolved from this one value, so they name the same invoice.
    static func sample(matching profile: BusinessProfile) -> InvoiceTemplate.Context {
        let calendar = Formatting.calendar
        let today = Date()
        let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let endOfLastMonth = calendar.date(byAdding: .day, value: -1, to: startOfThisMonth) ?? today
        let number = InvoiceNumbering.format(year: calendar.component(.year, from: today), sequence: 8)
        return InvoiceTemplate.Context(
            serviceDate: endOfLastMonth,
            clientName: DocumentText.string("Sample Company Ltd."),
            number: number,
            iban: profile.iban,
            reference: InvoiceNumbering.defaultReference(number: number),
            dueDate: calendar.date(byAdding: .day, value: profile.defaultPaymentTermDays, to: today) ?? today
        )
    }
}

extension InvoiceEmail {
    /// The email the sample invoice would go out in, through the same
    /// initializer `EmailComposer` is handed, so the preview cannot say
    /// anything the mail client would not.
    ///
    /// `masksSensitiveValues` is the preview's copy of private mode: the
    /// IBAN is the one placeholder value the mode hides, so it is resolved
    /// as the mask the rendered page prints.
    static func sample(matching profile: BusinessProfile, masksSensitiveValues: Bool = false) -> InvoiceEmail {
        var context = InvoiceTemplate.Context.sample(matching: profile)
        if masksSensitiveValues, !context.iban.isEmpty {
            context.iban = PrivacyMode.mask
        }
        return InvoiceEmail(
            recipient: "billing@sample.example",
            subjectTemplate: profile.emailSubjectTemplate,
            bodyTemplate: profile.emailBodyTemplate,
            context: context,
            attachmentFilename: PrintedInvoice.sample(matching: profile).suggestedFilename + ".pdf"
        )
    }
}
