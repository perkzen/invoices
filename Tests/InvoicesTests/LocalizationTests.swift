import Foundation
import Testing
@testable import Invoices

@Suite("Localization")
struct LocalizationTests {
    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle(for: BusinessProfile.self).path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    /// What `sl.lproj` answers for a key, or `nil` when it has no entry.
    private func slovenian(_ key: String, in bundle: Bundle) -> String? {
        let value = bundle.localizedString(forKey: key, value: "∅", table: nil)
        return value == "∅" ? nil : value
    }

    /// Every key in code is English; the Slovenian hanging off it must exist
    /// and must differ, or a Slovenian Mac would see the English fall back.
    @Test func `the Slovenian localization ships in the app bundle`() throws {
        let sl = try bundle("sl")
        for key in ["Invoices", "Default payment term: %lld days", "Settings", "Hide sensitive values", "Details", "Page", "Subject", "Message"] {
            let value = try #require(slovenian(key, in: sl), "\(key) has no Slovenian translation")
            #expect(value != key)
        }
    }

    /// Slovenian declines the two differently, so they cannot share the "Paid"
    /// key the way English would: the status of one invoice and the year's
    /// total received are separate catalog entries with separate translations.
    @Test func `paid the status and paid the total are separate strings`() throws {
        let sl = try bundle("sl")
        let status = try #require(slovenian("invoiceStatus.paid", in: sl))
        let total = try #require(slovenian("Paid", in: sl))
        #expect(status != total)
        #expect(InvoiceStatus.paid.label == "Paid")
    }

    /// English ships as the source language with no en.lproj of its own, so it
    /// must still win negotiation via the development region.
    @Test func `a Slovenian Mac gets Slovenian, anything unsupported gets English`() {
        let app = Bundle(for: BusinessProfile.self)
        #expect(app.developmentLocalization == "en")
        #expect(Bundle.preferredLocalizations(from: app.localizations, forPreferences: ["sl"]) == ["sl"])
        #expect(Bundle.preferredLocalizations(from: app.localizations, forPreferences: ["en"]) == ["en"])
        #expect(Bundle.preferredLocalizations(from: app.localizations, forPreferences: ["de"]) == ["en"])
    }

    // MARK: Documents

    /// Every English key the printed invoice, the spreadsheet, the exported
    /// file names, the template defaults and the sample invoice resolve
    /// through `DocumentText`. Add to it when a document gains a label.
    private static let documentKeys = [
        // InvoicePDFPage
        "Tax number: %@", "VAT ID: %@", "Bank account: %@", "Invoice", "draft", "Date", "Due date",
        "Place of issue", "Date of service, abbreviated", "Reference number",
        "Invoice – continued", "Invoice no. %@ – continued", "No.", "Description of goods or services",
        "Quantity", "Unit", "Price", "Discount", "VAT", "Amount", "Subtotal excl. VAT:", "VAT %@:",
        "TOTAL DUE %@:", "Issued by:", "Page %lld / %lld",
        // InvoicePDF, YearOverviewXLSX
        "Draft-invoice", "Invoice-%@", "Issued-invoices-%@", "INVOICES ISSUED IN %@", "Client",
        "Invoice no.", "Date of service", "Payment received", "Amount in %@", "No client", "TOTAL",
        "Cancelled", "Invoices %@",
        // InvoiceTemplate, VatRate, SampleInvoice
        "I am invoicing you for services in the month of {MONTH} {year}:",
        "When paying to bank account {iban}, quote the reference {reference}.",
        "Please settle the invoice by the due date.", "SI00 (invoice number)",
        "Invoice {number}",
        "Hello,\n\nplease find attached invoice {number} for {month} {year}. Payment is due by {due}.\n\nKind regards",
        "VAT not charged under Article 94(1) of the VAT Act (ZDDV-1).",
        "Reverse charge / exempt under the VAT Act (ZDDV-1).",
        "Sample Company Ltd.", "1 Sample Street", "Software development", "Consulting and support",
        // ImportSession
        "Services rendered",
    ]

    /// The documents are Slovenian whatever language the app runs in, and
    /// `DocumentText` reads `sl.lproj` directly — so a key it uses without a
    /// Slovenian translation would print in English on a legal document.
    @Test func `every document string has a Slovenian translation`() throws {
        let sl = try bundle("sl")
        for key in Self.documentKeys {
            let value = try #require(slovenian(key, in: sl), "\(key) would print in English")
            #expect(value != key, "\(key) would print in English")
        }
    }

    /// The tests run with the interface in English; the document lookup must
    /// not follow it, and must still fill in the arguments.
    @Test func `document text stays Slovenian while the interface is English`() throws {
        let sl = try bundle("sl")
        #expect(DocumentText.string("Issued by:") == slovenian("Issued by:", in: sl))
        #expect(DocumentText.string("Issued by:") != "Issued by:")

        let page = DocumentText.string("Page \(2) / \(3)")
        #expect(page.contains("2 / 3"))
        #expect(page != "Page 2 / 3")

        // The exported file names are document text too, kept to ASCII.
        let filename = DocumentText.string("Issued-invoices-\(String(2026))")
        #expect(filename.hasSuffix("-2026"))
        #expect(filename.allSatisfy { $0.isASCII && !$0.isWhitespace })
    }

    /// Slovenian counts in four forms and the dual is not optional in writing,
    /// so the count is the one string that cannot be translated word for word.
    /// The categories are one / two / few / other, and 101 starts again at one.
    @Test func `the invoice count keeps all four Slovenian plural forms`() throws {
        let sl = try bundle("sl")
        let slovene = Locale(identifier: "sl")
        func count(_ n: Int) -> String {
            String(localized: "\(n) invoices", bundle: sl, locale: slovene)
        }
        /// The noun after the number.
        func noun(_ n: Int) -> String {
            let text = count(n)
            #expect(text.hasPrefix("\(n) "))
            return String(text.drop { $0.isNumber || $0 == " " })
        }
        #expect(Set([noun(1), noun(2), noun(3), noun(5)]).count == 4)
        #expect(noun(4) == noun(3))
        #expect(noun(11) == noun(5))
        #expect(noun(101) == noun(1))
        #expect(noun(0) == noun(5))
        #expect(count(1) != "1 invoice")
    }
}
