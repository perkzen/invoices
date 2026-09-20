import Foundation
import SwiftData
import Testing
@testable import Invoices

/// The list columns keep their selection as a `PersistentIdentifier`. That
/// only works for a freshly inserted model if the identifier is already the
/// permanent one, which is why `newInvoice()` and `newClient()` save first.
@Suite("Identiteta modelov")
struct ModelIdentityTests {
    @MainActor
    @Test func `a new model's identifier changes once the context saves`() throws {
        let container = try ModelContainer(
            for: Invoice.self, InvoiceLine.self, Client.self, BusinessProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let client = Client(name: "Nova stranka")
        context.insert(client)
        let unsaved = client.persistentModelID

        try context.save()
        let saved = client.persistentModelID
        #expect(unsaved != saved)

        // The saved identifier is the one a fetch answers to.
        let fetched = try context.fetch(FetchDescriptor<Client>())
        #expect(fetched.first?.persistentModelID == saved)
    }
}
