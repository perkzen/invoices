import AppKit
import Foundation

/// Hands an invoice email to the mail client chosen in Settings. Nothing is
/// sent from here: Mail or Gmail opens with the message filled in, and the
/// user reads it over and presses Send there.
@MainActor
enum EmailComposer {
    /// Where "Send by email" composes the message. A preference of this Mac
    /// rather than of the business, so it lives in `UserDefaults`.
    enum Client: String, CaseIterable, Identifiable {
        case appleMail
        case gmail

        static let storageKey = "emailClient"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .appleMail: String(localized: "Apple Mail")
            case .gmail: String(localized: "Gmail in the browser")
            }
        }

        /// What happens when the button is pressed — shown under the picker,
        /// because the two routes end differently: Mail takes the attachment,
        /// a browser cannot.
        var explanation: String {
            switch self {
            case .appleMail:
                String(localized: "Send by email opens a new message in Mail, addressed to the client, with the invoice PDF attached. Nothing is sent until you press Send.")
            case .gmail:
                String(localized: "Send by email opens a new Gmail message in your browser, addressed to the client and filled in. A browser cannot take the attachment from the app, so the PDF is saved to Downloads and copied to the clipboard: paste it into the message with ⌘V, or drag it in from Downloads.")
            }
        }
    }

    enum Failure: Error {
        case noMailAccount
        case couldNotSaveAttachment(String)
        case couldNotOpenGmail

        var message: String {
            switch self {
            case .noMailAccount:
                String(localized: "Mail has no account to send from. Add one in Mail › Settings › Accounts, or choose Gmail in Settings.")
            case .couldNotSaveAttachment(let reason):
                String(localized: "The invoice PDF could not be saved: \(reason)")
            case .couldNotOpenGmail:
                String(localized: "Gmail could not be opened in the browser.")
            }
        }
    }

    static func compose(_ email: InvoiceEmail, attachment pdf: Data, via client: Client) throws(Failure) {
        switch client {
        case .appleMail: try composeInMail(email, attachment: pdf)
        case .gmail: try composeInGmail(email, attachment: pdf)
        }
    }

    // MARK: Apple Mail

    /// The compose-email sharing service: Mail opens a new message with the
    /// recipient, subject, body and attachment in place. The attachment has
    /// to be a file, so the PDF is written to the temporary directory first.
    private static func composeInMail(_ email: InvoiceEmail, attachment pdf: Data) throws(Failure) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(email.attachmentFilename)
        do {
            try pdf.write(to: url, options: .atomic)
        } catch {
            throw .couldNotSaveAttachment(error.localizedDescription)
        }
        let items: [Any] = [email.body, url]
        guard let service = NSSharingService(named: .composeEmail),
              service.canPerform(withItems: items)
        else { throw .noMailAccount }
        service.recipients = [email.recipient]
        service.subject = email.subject
        service.perform(withItems: items)
    }

    // MARK: Gmail

    /// A browser cannot be handed a file, so Gmail's compose URL carries the
    /// recipient, subject and body, and the PDF goes where the user can reach
    /// it: into Downloads, and onto the clipboard for a paste.
    private static func composeInGmail(_ email: InvoiceEmail, attachment pdf: Data) throws(Failure) {
        let url: URL
        do {
            let downloads = try FileManager.default.url(
                for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            url = availableURL(in: downloads, named: email.attachmentFilename)
            try pdf.write(to: url, options: .atomic)
        } catch {
            throw .couldNotSaveAttachment(error.localizedDescription)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])

        guard let compose = gmailComposeURL(for: email), NSWorkspace.shared.open(compose) else {
            throw .couldNotOpenGmail
        }
    }

    /// `name.pdf`, or `name 2.pdf` and so on when that file already exists —
    /// what is in Downloads is the user's, never overwritten.
    static func availableURL(in directory: URL, named filename: String) -> URL {
        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    /// Gmail's "compose in a new window" URL with the fields prefilled.
    /// Encoded by hand: `URLComponents` would leave `+` and `&` in the body
    /// alone, and Gmail reads a bare `+` as a space.
    nonisolated static func gmailComposeURL(for email: InvoiceEmail) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        func encoded(_ text: String) -> String {
            text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        }
        let query = [
            "view=cm", "fs=1",
            "to=\(encoded(email.recipient))",
            "su=\(encoded(email.subject))",
            "body=\(encoded(email.body))",
        ].joined(separator: "&")
        return URL(string: "https://mail.google.com/mail/?\(query)")
    }
}
