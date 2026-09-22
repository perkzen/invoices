import ArgumentParser
import Foundation

/// Invoices: drafting, editing, issuing, payment, cancellation, the PDF.
nonisolated struct InvoiceCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "invoice",
            abstract: "Invoices — list, draft, edit, issue, mark paid, cancel, render as PDF.",
            discussion: """
                An invoice is named by its number (2026-003), by its id, or by "draft" when \
                exactly one draft exists. Only a draft can be edited or deleted. Issuing gives \
                a draft the next number of the year and fixes its content; from then on it is \
                marked paid or cancelled, never changed — a mistake in an issued invoice is \
                corrected by cancelling it and drafting a new one. Issuing cannot be undone.
                """,
            subcommands: [
                List.self, Show.self, Create.self, Update.self, Line.self,
                Issue.self, Pay.self, Unpay.self, Cancel.self, Delete.self, PDF.self,
            ],
            defaultSubcommand: List.self
        )
    }

    /// The fields of a draft, as options. Shared by `create` and `set`.
    nonisolated struct Fields: ParsableArguments {
        @Option(help: "The client's id or name.") var client: String?
        @Option(name: .customLong("issue-date"), help: "YYYY-MM-DD; today by default.") var issueDate: String?
        @Option(name: .customLong("service-date"), help: "YYYY-MM-DD; the day the service was rendered, or a period's first day.")
        var serviceDate: String?
        @Option(
            name: .customLong("service-end"),
            help: "YYYY-MM-DD, the period's last day; \"month\" for one month from the service date; \"none\" for a single day."
        )
        var serviceEnd: String?
        @Option(name: .customLong("due-date"), help: "YYYY-MM-DD; the issue date plus the profile's payment term by default.")
        var dueDate: String?
        @Option(help: "Place of issue; the profile's city by default.") var place: String?
        @Option(help: "Payment reference; \"SI00 <number>\" is filled in at issue when empty.") var reference: String?
        @Option(help: "Notes printed under the total.") var notes: String?
        @Option(help: "This invoice's own intro sentence, in place of the profile's template. Same placeholders.")
        var intro: String?

        var setsAnything: Bool {
            [client, issueDate, serviceDate, serviceEnd, dueDate, place, reference, notes, intro].contains { $0 != nil }
        }

        @MainActor func apply(to invoice: Invoice, in book: Book) throws {
            if let client { invoice.client = try book.client(client) }
            if let issueDate { invoice.issueDate = try Day.parse(issueDate) }
            if let serviceDate { invoice.serviceDate = try Day.parse(serviceDate) }
            if let serviceEnd {
                switch serviceEnd.lowercased() {
                case "none": invoice.serviceDateEnd = nil
                case "month": invoice.serviceDateEnd = Ledger.defaultPeriodEnd(from: invoice.serviceDate)
                default:
                    let end = try Day.parse(serviceEnd)
                    guard end >= invoice.serviceDate else {
                        throw ToolError("The service period ends before it starts (\(Day.string(invoice.serviceDate))).")
                    }
                    invoice.serviceDateEnd = end
                }
            }
            if let dueDate { invoice.dueDate = try Day.parse(dueDate) }
            if let place { invoice.placeOfIssue = place }
            if let reference { invoice.paymentReference = reference }
            if let notes { invoice.notes = notes }
            if let intro { invoice.introOverride = intro }
        }
    }

    /// Editing is for drafts. The message says what to do instead, because
    /// the caller is often an agent that would otherwise keep trying.
    @MainActor static func requireDraft(_ invoice: Invoice, to verb: String) throws {
        guard invoice.status.isEditable else {
            throw ToolError(
                "Invoice \(invoice.number) is \(invoice.status.rawValue); its content is fixed and cannot be \(verb). "
                    + "Cancel it and draft a new one, or mark it paid."
            )
        }
    }

    nonisolated struct List: LedgerCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "list", abstract: "List invoices: drafts first, then newest number first.")
        }

        @OptionGroup var store: StoreOptions
        @Option(help: "Only invoices numbered in this year.") var year: Int?
        @Option(help: "Only this status: \(InvoiceStatus.allCases.map(\.rawValue).joined(separator: ", ")).")
        var status: InvoiceStatus?
        @Option(help: "Only invoices of this client (id or name).") var client: String?
        @Flag(help: "Only issued invoices past their due date.") var overdue = false

        @MainActor func execute(_ book: Book) throws {
            var invoices = try book.invoices()
            if let year { invoices = invoices.filter { $0.year == year } }
            if let status { invoices = invoices.filter { $0.status == status } }
            if let client {
                let wanted = try book.client(client)
                invoices = invoices.filter { $0.client === wanted }
            }
            if overdue { invoices = invoices.filter { $0.isOverdue } }
            Output.print(invoices.map { InvoiceSummary($0) })
        }
    }

    nonisolated struct Show: LedgerCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "show", abstract: "One invoice, with its line items and totals.")
        }

        @OptionGroup var store: StoreOptions
        @Argument(help: "Number, id, or \"draft\".") var invoice: String

        @MainActor func execute(_ book: Book) throws {
            Output.print(InvoiceRecord(try book.invoice(invoice)))
        }
    }

    nonisolated struct Create: LedgerCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "create",
                abstract: "Draft a new invoice, and issue it in the same step with --issue.",
                discussion: "A draft with no --line gets one empty line item to fill in with `invoice line set`. " + LineSpec.help
            )
        }

        @OptionGroup var store: StoreOptions
        @OptionGroup var fields: Fields
        @Option(name: .customLong("line"), help: "A line item, as JSON; repeat for each line.") var lines: [String] = []
        @Flag(help: "Issue the invoice once drafted: assigns the next number of the year and locks it. Cannot be undone.")
        var issue = false

        @MainActor func execute(_ book: Book) throws {
            // Parse everything before touching the store, so a bad line
            // leaves no half-made draft behind.
            let specs = try lines.map(LineSpec.parse)
            let ledger = book.ledger
            let invoice = ledger.newDraft()
            try fields.apply(to: invoice, in: book)
            if fields.serviceDate == nil, fields.issueDate != nil {
                invoice.serviceDate = invoice.issueDate
                if fields.serviceEnd?.lowercased() == "month" {
                    invoice.serviceDateEnd = Ledger.defaultPeriodEnd(from: invoice.serviceDate)
                }
            }
            if fields.dueDate == nil, fields.issueDate != nil {
                invoice.dueDate = Formatting.calendar.date(
                    byAdding: .day, value: book.profile.defaultPaymentTermDays, to: invoice.issueDate
                ) ?? invoice.issueDate
            }
            if !specs.isEmpty {
                // The ledger starts a draft with one empty line; the caller
                // brought its own.
                for line in invoice.sortedLines { ledger.removeLine(line) }
                for spec in specs {
                    guard let line = ledger.addLine(to: invoice) else { break }
                    spec.apply(to: line)
                }
            }
            if issue {
                try ledger.issue(invoice)
            }
            try book.save()
            Output.print(InvoiceRecord(invoice))
        }
    }

    nonisolated struct Update: LedgerCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "set", abstract: "Change a draft's fields. Only the options given are changed.")
        }

        @OptionGroup var store: StoreOptions
        @Argument(help: "Number, id, or \"draft\".") var invoice: String
        @OptionGroup var fields: Fields

        @MainActor func execute(_ book: Book) throws {
            let invoice = try book.invoice(self.invoice)
            try InvoiceCommand.requireDraft(invoice, to: "changed")
            guard fields.setsAnything else { throw ToolError("Nothing to change: give at least one option.") }
            try fields.apply(to: invoice, in: book)
            Output.print(InvoiceRecord(invoice))
        }
    }

    nonisolated struct Line: ParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "line",
                abstract: "The line items of a draft.",
                discussion: LineSpec.help,
                subcommands: [Add.self, Update.self, Remove.self]
            )
        }

        nonisolated struct Add: LedgerCommand {
            static var configuration: CommandConfiguration {
                CommandConfiguration(commandName: "add", abstract: "Append a line item to a draft.")
            }

            @OptionGroup var store: StoreOptions
            @Argument(help: "Number, id, or \"draft\".") var invoice: String
            @Argument(help: "The line item, as JSON.") var line: String

            @MainActor func execute(_ book: Book) throws {
                let spec = try LineSpec.parse(line)
                let invoice = try book.invoice(self.invoice)
                try InvoiceCommand.requireDraft(invoice, to: "changed")
                guard let added = book.ledger.addLine(to: invoice) else { throw ToolError("The line could not be added.") }
                spec.apply(to: added)
                Output.print(InvoiceRecord(invoice))
            }
        }

        nonisolated struct Update: LedgerCommand {
            static var configuration: CommandConfiguration {
                CommandConfiguration(commandName: "set", abstract: "Change a line item. Only the keys given are changed.")
            }

            @OptionGroup var store: StoreOptions
            @Argument(help: "Number, id, or \"draft\".") var invoice: String
            @Argument(help: "The line's position, 1 for the first — as `invoice show` lists it.") var index: Int
            @Argument(help: "The changes, as JSON.") var line: String

            @MainActor func execute(_ book: Book) throws {
                let spec = try LineSpec.parse(line)
                let invoice = try book.invoice(self.invoice)
                try InvoiceCommand.requireDraft(invoice, to: "changed")
                spec.apply(to: try InvoiceCommand.line(at: index, of: invoice))
                Output.print(InvoiceRecord(invoice))
            }
        }

        nonisolated struct Remove: LedgerCommand {
            static var configuration: CommandConfiguration {
                CommandConfiguration(commandName: "remove", abstract: "Remove a line item from a draft.")
            }

            @OptionGroup var store: StoreOptions
            @Argument(help: "Number, id, or \"draft\".") var invoice: String
            @Argument(help: "The line's position, 1 for the first.") var index: Int

            @MainActor func execute(_ book: Book) throws {
                let invoice = try book.invoice(self.invoice)
                try InvoiceCommand.requireDraft(invoice, to: "changed")
                book.ledger.removeLine(try InvoiceCommand.line(at: index, of: invoice))
                Output.print(InvoiceRecord(invoice))
            }
        }
    }

    @MainActor static func line(at index: Int, of invoice: Invoice) throws -> InvoiceLine {
        let lines = invoice.sortedLines
        guard index >= 1, index <= lines.count else {
            throw ToolError("The invoice has \(lines.count) line item(s); there is no line \(index).")
        }
        return lines[index - 1]
    }

    nonisolated struct Issue: LedgerCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "issue",
                abstract: "Issue a draft: assign the next number of its issue date's year and lock it. Cannot be undone."
            )
        }

        @OptionGroup var store: StoreOptions
        @Argument(help: "Number, id, or \"draft\".") var invoice: String

        @MainActor func execute(_ book: Book) throws {
            let invoice = try book.invoice(self.invoice)
            try book.ledger.issue(invoice)
            try book.save()
            Output.print(InvoiceRecord(invoice))
        }
    }

    nonisolated struct Pay: LedgerCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "pay", abstract: "Mark an issued invoice paid.")
        }

        @OptionGroup var store: StoreOptions
        @Argument(help: "Number or id.") var invoice: String
        @Option(help: "The day the payment arrived, YYYY-MM-DD; today by default.") var on: String?

        @MainActor func execute(_ book: Book) throws {
            let invoice = try book.invoice(self.invoice)
            guard invoice.status == .issued else {
                throw ToolError("Only an issued invoice can be marked paid; \(invoice.number.isEmpty ? "the draft" : invoice.number) is \(invoice.status.rawValue).")
            }
            book.ledger.markPaid(invoice, on: try on.map(Day.parse) ?? Date())
            Output.print(InvoiceRecord(invoice))
        }
    }

    nonisolated struct Unpay: LedgerCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "unpay", abstract: "Undo a payment marked by mistake: the invoice is issued and outstanding again.")
        }

        @OptionGroup var store: StoreOptions
        @Argument(help: "Number or id.") var invoice: String

        @MainActor func execute(_ book: Book) throws {
            let invoice = try book.invoice(self.invoice)
            guard invoice.status == .paid else {
                throw ToolError("\(invoice.number.isEmpty ? "The draft" : invoice.number) is not marked paid; it is \(invoice.status.rawValue).")
            }
            book.ledger.markUnpaid(invoice)
            Output.print(InvoiceRecord(invoice))
        }
    }

    nonisolated struct Cancel: LedgerCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "cancel",
                abstract: "Cancel an issued, unpaid invoice. It keeps its number and stays in the year overview, uncounted."
            )
        }

        @OptionGroup var store: StoreOptions
        @Argument(help: "Number or id.") var invoice: String

        @MainActor func execute(_ book: Book) throws {
            let invoice = try book.invoice(self.invoice)
            guard invoice.status == .issued else {
                let what = invoice.number.isEmpty ? "The draft" : invoice.number
                let hint = invoice.status == .paid ? " Mark it unpaid first." : invoice.status.isEditable ? " Delete a draft instead." : ""
                throw ToolError("Only an issued, unpaid invoice can be cancelled; \(what) is \(invoice.status.rawValue).\(hint)")
            }
            book.ledger.cancel(invoice)
            Output.print(InvoiceRecord(invoice))
        }
    }

    nonisolated struct Delete: LedgerCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: "delete", abstract: "Delete a draft. An issued invoice is cancelled instead.")
        }

        @OptionGroup var store: StoreOptions
        @Argument(help: "Id, or \"draft\".") var invoice: String

        @MainActor func execute(_ book: Book) throws {
            let invoice = try book.invoice(self.invoice)
            let record = InvoiceRecord(invoice)
            try book.ledger.delete(invoice)
            Output.print(record)
        }
    }

    nonisolated struct PDF: LedgerCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "pdf",
                abstract: "Render the invoice as the A4 PDF the app exports. A draft is watermarked DRAFT."
            )
        }

        @OptionGroup var store: StoreOptions
        @Argument(help: "Number, id, or \"draft\".") var invoice: String
        @Option(name: [.short, .long], help: "Where to write it; \"Invoice-<number>.pdf\" in the current directory by default.")
        var output: String?

        nonisolated struct Record: Encodable {
            var path: String
            var number: String?
            var pages: Int
        }

        @MainActor func execute(_ book: Book) throws {
            try book.requireApp()
            let invoice = try book.invoice(self.invoice)
            let printed = PrintedInvoice.make(invoice: invoice, profile: book.profile)
            guard let data = InvoicePDF.render(printed) else { throw ToolError("The invoice could not be rendered.") }
            let url = output.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appending(path: "\(printed.suggestedFilename).pdf")
            try data.write(to: url)
            Output.print(Record(path: url.path, number: invoice.number.isEmpty ? nil : invoice.number, pages: InvoicePDF.pages(of: printed).count))
        }
    }
}
