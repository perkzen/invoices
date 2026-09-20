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
        let endOfLastMonth = calendar.date(byAdding: .day, value: -1, to: startOfThisMonth) ?? today
        let dueDate = calendar.date(byAdding: .day, value: profile.defaultPaymentTermDays, to: today) ?? today
        let number = InvoiceNumbering.format(year: calendar.component(.year, from: today), sequence: 8)
        let reference = InvoiceNumbering.defaultReference(number: number)

        let customer = Customer(
            name: DocumentText.string("Sample Company Ltd."),
            addressLines: [DocumentText.string("1 Sample Street"), "1000 Ljubljana"],
            taxNumber: "12345678"
        )
        let context = InvoiceTemplate.Context(
            serviceDate: endOfLastMonth,
            clientName: customer.name,
            number: number,
            iban: profile.iban,
            reference: reference,
            dueDate: dueDate
        )
        let items: [(String, Decimal, Decimal)] = [
            (DocumentText.string("Software development"), 1, 1075),
            (DocumentText.string("Consulting and support"), 4, 60),
        ]

        return PrintedInvoice(
            number: number,
            isDraft: false,
            issueDate: today,
            serviceDate: startOfLastMonth,
            serviceDateEnd: endOfLastMonth,
            dueDate: dueDate,
            placeOfIssue: profile.city.isEmpty ? "Ljubljana" : profile.city,
            paymentReference: reference,
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
