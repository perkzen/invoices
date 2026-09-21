import Foundation

/// The message an invoice goes out in: who it is for, the subject and body
/// resolved from the profile's templates, and the name of the PDF it
/// carries. A plain value, so the wording can be tested without a mail
/// client; `EmailComposer` is what hands it to one.
nonisolated struct InvoiceEmail: Hashable, Sendable {
    var recipient: String
    var subject: String
    var body: String
    /// The PDF's file name, extension included.
    var attachmentFilename: String

    init(
        recipient: String,
        subjectTemplate: String,
        bodyTemplate: String,
        context: InvoiceTemplate.Context,
        attachmentFilename: String
    ) {
        self.recipient = recipient
        // A subject is one line whatever the template says.
        self.subject = InvoiceTemplate.resolve(subjectTemplate, in: context)
            .replacingOccurrences(of: "\n", with: " ")
        self.body = InvoiceTemplate.resolve(bodyTemplate, in: context)
        self.attachmentFilename = attachmentFilename
    }
}

extension InvoiceEmail {
    /// The email for `invoice` as the models describe it right now,
    /// addressed to its client.
    static func make(invoice: Invoice, profile: BusinessProfile, printed: PrintedInvoice) -> InvoiceEmail {
        InvoiceEmail(
            recipient: invoice.client?.email.trimmingCharacters(in: .whitespaces) ?? "",
            subjectTemplate: profile.emailSubjectTemplate,
            bodyTemplate: profile.emailBodyTemplate,
            context: InvoiceTemplate.Context(invoice: invoice, profile: profile),
            attachmentFilename: printed.suggestedFilename + ".pdf"
        )
    }
}
