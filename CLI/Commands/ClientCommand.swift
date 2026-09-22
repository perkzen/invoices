import ArgumentParser
import Foundation

/// Clients: the counterparties invoices are addressed to.
nonisolated struct ClientCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "client",
            abstract: "Clients — look them up, add, change and delete them.",
            discussion: """
                A client is named by its id, its name, or a part of the name that fits one \
                client only; case and diacritics do not matter. A client with issued invoices \
                cannot be deleted: the invoice keeps no copy of its counterparty.
                """,
            subcommands: [List.self, Show.self, Add.self, Update.self, Delete.self],
            defaultSubcommand: List.self
        )
    }

    /// The fields a client is made of, as options. Shared by `add` and `set`.
    nonisolated struct Fields: ParsableArguments {
        @Option(help: "Street and number.") var street: String?
        @Option(name: .customLong("postal-code")) var postalCode: String?
        @Option var city: String?
        @Option(name: .customLong("country-code"), help: "Two letters; SI is not printed on the invoice.")
        var countryCode: String?
        @Option(name: .customLong("tax-number"), help: "Tax number, without the SI prefix.") var taxNumber: String?
        @Option(name: .customLong("vat-id"), help: "VAT ID; empty when the client is not VAT registered.") var vatID: String?
        @Option(help: "Where \"Send by email\" addresses the invoice.") var email: String?
        @Option(name: .customLong("payment-term"), help: "The client's payment term in days.") var paymentTerm: Int?
        @Option(help: "Notes, shown in the app only.") var notes: String?

        @MainActor func apply(to client: Client) throws {
            if let street { client.street = street }
            if let postalCode { client.postalCode = postalCode }
            if let city { client.city = city }
            if let countryCode { client.countryCode = countryCode.uppercased() }
            if let taxNumber { client.taxNumber = taxNumber }
            if let vatID { client.vatID = vatID }
            if let email { client.email = email }
            if let paymentTerm {
                guard paymentTerm >= 0 else { throw ToolError("The payment term cannot be negative.") }
                client.defaultPaymentTermDays = paymentTerm
            }
            if let notes { client.notes = notes }
        }
    }

    nonisolated struct List: LedgerCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "list", abstract: "List clients, by name.")
        }

        @OptionGroup var store: StoreOptions
        @Option(help: "Only clients whose name contains this.") var search: String?

        @MainActor func execute(_ book: Book) throws {
            var clients = try book.clients()
            if let search {
                let key = InvoiceImport.normalized(search)
                clients = clients.filter { InvoiceImport.normalized($0.name).contains(key) }
            }
            Output.print(clients.map { ClientRecord($0) })
        }
    }

    nonisolated struct Show: LedgerCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "show", abstract: "One client, with its invoices.")
        }

        @OptionGroup var store: StoreOptions
        @Argument(help: "The client's id or name.") var client: String

        @MainActor func execute(_ book: Book) throws {
            Output.print(ClientRecord(try book.client(client), listingInvoices: true))
        }
    }

    nonisolated struct Add: LedgerCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "add", abstract: "Add a client.")
        }

        @OptionGroup var store: StoreOptions
        @Option(help: "The client's name, as printed on the invoice.") var name: String
        @OptionGroup var fields: Fields

        @MainActor func execute(_ book: Book) throws {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ToolError("A client needs a name.") }
            let key = InvoiceImport.normalized(trimmed)
            if let existing = try book.clients().first(where: { InvoiceImport.normalized($0.name) == key }) {
                throw ToolError(
                    "A client named \"\(existing.name)\" already exists (\(existing.uuid?.uuidString ?? "no id")). "
                        + "Change it with `client set`, or pick a name that tells the two apart."
                )
            }
            let client = Client(name: trimmed)
            try fields.apply(to: client)
            book.context.insert(client)
            try book.save()
            Output.print(ClientRecord(client))
        }
    }

    nonisolated struct Update: LedgerCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "set", abstract: "Change a client's fields. Only the options given are changed.")
        }

        @OptionGroup var store: StoreOptions
        @Argument(help: "The client's id or name.") var client: String
        @Option(help: "A new name.") var name: String?
        @OptionGroup var fields: Fields

        @MainActor func execute(_ book: Book) throws {
            let client = try book.client(self.client)
            if let name {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw ToolError("A client needs a name.") }
                client.name = trimmed
            }
            try fields.apply(to: client)
            Output.print(ClientRecord(client))
        }
    }

    nonisolated struct Delete: LedgerCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "delete", abstract: "Delete a client that has no issued invoices.")
        }

        @OptionGroup var store: StoreOptions
        @Argument(help: "The client's id or name.") var client: String

        @MainActor func execute(_ book: Book) throws {
            let client = try book.client(self.client)
            let record = ClientRecord(client)
            try book.ledger.delete(client)
            Output.print(record)
        }
    }
}
