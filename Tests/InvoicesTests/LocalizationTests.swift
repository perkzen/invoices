import Foundation
import Testing
@testable import Invoices

@Suite("Lokalizacija")
struct LocalizationTests {
    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle(for: BusinessProfile.self).path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test func `the Slovenian localization ships in the app bundle`() throws {
        let sl = try bundle("sl")
        #expect(sl.localizedString(forKey: "Invoices", value: nil, table: nil) == "Računi")
        #expect(sl.localizedString(forKey: "Default payment term: %lld days", value: nil, table: nil)
                == "Privzeti rok plačila: %lld dni")
        #expect(sl.localizedString(forKey: "Settings", value: nil, table: nil) == "Nastavitve")
        #expect(sl.localizedString(forKey: "Hide sensitive values", value: nil, table: nil)
                == "Skrij občutljive podatke")
    }

    /// Slovenian declines the two differently, so they cannot share the "Paid"
    /// key the way English would: one invoice is "Plačan", the year's total
    /// received is "Plačano".
    @Test func `paid the status and paid the total are separate strings`() throws {
        let sl = try bundle("sl")
        #expect(sl.localizedString(forKey: "invoiceStatus.paid", value: nil, table: nil) == "Plačan")
        #expect(sl.localizedString(forKey: "Paid", value: nil, table: nil) == "Plačano")
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

    @Test func `the invoice page is not localized`() throws {
        // The PDF is a Slovenian legal document; none of its labels may
        // have leaked into the catalog where a translation could swap them.
        let sl = try bundle("sl")
        for key in ["OSNUTEK", "Račun izdal:", "Stran %lld / %lld", "Davčna številka: %@"] {
            #expect(sl.localizedString(forKey: key, value: "∅", table: nil) == "∅")
        }
    }

    /// Slovenian counts in four forms and the dual is not optional in writing,
    /// so the count is the one string that cannot be translated word for word:
    /// 1 račun, 2 računa, 3 računi, 5 računov — and 101 starts again at one.
    @Test func `the invoice count keeps all four Slovenian plural forms`() throws {
        let sl = try bundle("sl")
        let slovene = Locale(identifier: "sl")
        func count(_ n: Int) -> String {
            String(localized: "\(n) invoices", bundle: sl, locale: slovene)
        }
        #expect(count(1) == "1 račun")
        #expect(count(2) == "2 računa")
        #expect(count(3) == "3 računi")
        #expect(count(4) == "4 računi")
        #expect(count(5) == "5 računov")
        #expect(count(11) == "11 računov")
        #expect(count(101) == "101 račun")
        #expect(count(0) == "0 računov")
    }

    /// The sheet goes to a Slovenian accountant whatever language the app is
    /// running in, so its headers must not travel through the catalog either.
    @Test func `the spreadsheet headers are not localized`() throws {
        let sl = try bundle("sl")
        for key in YearOverviewXLSX.columnHeaders {
            #expect(sl.localizedString(forKey: key, value: "∅", table: nil) == "∅")
        }
    }
}
