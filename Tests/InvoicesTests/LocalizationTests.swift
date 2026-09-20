import Foundation
import Testing
@testable import Invoices

@Suite("Lokalizacija")
struct LocalizationTests {
    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle(for: BusinessProfile.self).path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test func `the English localization ships in the app bundle`() throws {
        let en = try bundle("en")
        #expect(en.localizedString(forKey: "Računi", value: nil, table: nil) == "Invoices")
        #expect(en.localizedString(forKey: "Privzeti rok plačila: %lld dni", value: nil, table: nil)
                == "Default payment term: %lld days")
        #expect(en.localizedString(forKey: "Nastavitve", value: nil, table: nil) == "Settings")
        #expect(en.localizedString(forKey: "Skrij občutljive podatke", value: nil, table: nil)
                == "Hide sensitive values")
    }

    /// Slovenian ships as the source language with no sl.lproj of its own,
    /// so it must still win negotiation via the development region.
    @Test func `a Slovenian Mac gets Slovenian, anything unsupported gets English`() {
        let app = Bundle(for: BusinessProfile.self)
        #expect(app.developmentLocalization == "sl")
        #expect(Bundle.preferredLocalizations(from: app.localizations, forPreferences: ["sl"]) == ["sl"])
        #expect(Bundle.preferredLocalizations(from: app.localizations, forPreferences: ["en"]) == ["en"])
        #expect(Bundle.preferredLocalizations(from: app.localizations, forPreferences: ["de"]) == ["en"])
    }

    @Test func `the invoice page is not localized`() throws {
        // The PDF is a Slovenian legal document; none of its labels may
        // have leaked into the catalog where a translation could swap them.
        let en = try bundle("en")
        for key in ["OSNUTEK", "Račun izdal:", "Stran %lld / %lld", "Davčna številka: %@"] {
            #expect(en.localizedString(forKey: key, value: "∅", table: nil) == "∅")
        }
    }
}
