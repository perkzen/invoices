import Foundation
import Testing
@testable import Invoices

@Suite("Invoice email")
struct InvoiceEmailTests {
    private var context: InvoiceTemplate.Context {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 31
        let serviceEnd = Formatting.calendar.date(from: components)!
        components.month = 9; components.day = 9
        return InvoiceTemplate.Context(
            serviceDate: serviceEnd,
            clientName: "Parakeet",
            number: "2026-001",
            iban: "SI56 1910 0000 1234 567",
            reference: "SI00 2026-001",
            dueDate: Formatting.calendar.date(from: components)!
        )
    }

    @Test func `the default subject and body resolve with nothing left in braces`() {
        let email = InvoiceEmail(
            recipient: "billing@parakeet.example",
            subjectTemplate: InvoiceTemplate.defaultEmailSubject,
            bodyTemplate: InvoiceTemplate.defaultEmailBody,
            context: context,
            attachmentFilename: "Racun-2026-001.pdf"
        )
        #expect(email.subject.contains("2026-001"))
        #expect(!email.subject.contains("{"))
        #expect(email.body.contains("2026-001"))
        #expect(email.body.contains(InvoiceTemplate.monthName(of: context.serviceDate)))
        #expect(email.body.contains("9. 9. 2026"))
        #expect(!email.body.contains("{"))
        // The body keeps its paragraphs; the greeting and the sign-off are apart.
        #expect(email.body.contains("\n\n"))
    }

    /// A subject is one line whatever the template says, and the legacy
    /// tokens still resolve there too.
    @Test func `the subject is flattened to one line`() {
        let email = InvoiceEmail(
            recipient: "", subjectTemplate: "Račun\n{stevilka}", bodyTemplate: "",
            context: context, attachmentFilename: "x.pdf"
        )
        #expect(email.subject == "Račun 2026-001")
    }

    /// Gmail reads its compose URL like a form: a bare `+` is a space and
    /// `&` ends the field, so both have to be encoded, as do the newlines
    /// that separate the paragraphs.
    @Test func `the Gmail compose URL carries every field, encoded`() throws {
        let email = InvoiceEmail(
            recipient: "a+b@parakeet.example", subjectTemplate: "Račun {number} & co",
            bodyTemplate: "Pozdravljeni,\n\nrok {due}.", context: context, attachmentFilename: "x.pdf"
        )
        let url = try #require(EmailComposer.gmailComposeURL(for: email))
        #expect(url.host() == "mail.google.com")
        let query = try #require(url.query(percentEncoded: true))
        #expect(query.contains("view=cm"))
        #expect(query.contains("to=a%2Bb%40parakeet.example"))
        #expect(query.contains("su=Ra%C4%8Dun%202026-001%20%26%20co"))
        #expect(query.contains("body=Pozdravljeni%2C%0A%0Arok%209.%209.%202026."))
        #expect(!query.contains("+"))
    }

    @MainActor
    @Test func `a file already in Downloads is never overwritten`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InvoiceEmailTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = EmailComposer.availableURL(in: directory, named: "Racun-2026-001.pdf")
        #expect(first.lastPathComponent == "Racun-2026-001.pdf")
        try Data().write(to: first)
        let second = EmailComposer.availableURL(in: directory, named: "Racun-2026-001.pdf")
        #expect(second.lastPathComponent == "Racun-2026-001 2.pdf")
        try Data().write(to: second)
        #expect(EmailComposer.availableURL(in: directory, named: "Racun-2026-001.pdf").lastPathComponent
                == "Racun-2026-001 3.pdf")
    }
}
