import Foundation
import SwiftData
import Testing
@testable import Invoices

/// The placeholders were renamed from Slovenian to English. Sentences saved
/// before that still carry the old tokens; they are rewritten once, so the
/// editor shows the tokens its legend lists.
@Suite("Template migration")
struct TemplateMigrationTests {
    @Test func `every legacy token is rewritten and nothing else is touched`() {
        let old = "Za mesec {MESEC} {leto}, {stranka}: {stevilka} na {trr}, sklic {sklic}, do {valuta} ({mesec}) {unknown}"
        let new = InvoiceTemplate.modernized(old)
        #expect(new == "Za mesec {MONTH} {year}, {client}: {number} na {iban}, sklic {reference}, do {due} ({month}) {unknown}")
        #expect(InvoiceTemplate.modernized(new) == new)
    }

    @MainActor
    @Test func `the ledger rewrites the stored sentences once`() throws {
        let container = try ModelContainer(
            for: Invoice.self, InvoiceLine.self, Client.self, BusinessProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ledger = Ledger(container.mainContext)
        let profile = ledger.profile
        profile.introTemplate = "Zaračunavam vam storitev za mesec {MESEC} {leto}:"
        profile.paymentNoteTemplate = "Pri plačilu na TRR: {trr} navedite sklic: {sklic}."
        let invoice = ledger.newDraft()
        invoice.introOverride = "Za {stranka}, {mesec}"

        ledger.modernizeTemplates()

        #expect(profile.introTemplate == "Zaračunavam vam storitev za mesec {MONTH} {year}:")
        #expect(profile.paymentNoteTemplate == "Pri plačilu na TRR: {iban} navedite sklic: {reference}.")
        #expect(invoice.introOverride == "Za {client}, {month}")
    }
}
