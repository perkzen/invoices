# Features

What the app does, in more detail than the [README](../README.md) has room for.

- **Clients** — address and tax details (tax number, VAT ID), and an optional logo shown
  next to the client in every list; the printed invoice carries only your own logo
- **Invoices** — drafts with line items, quantity, price and discount per line, and live
  totals; the list is searchable and can be narrowed to drafts, open, paid or cancelled
- **Issuing** — assigns the next sequential number of the year (`2026-001`) and locks the
  invoice; only drafts can be edited or deleted
- **PDF export** — an A4 invoice carrying the fields Slovenian law requires, previewed
  live in the editor as you type; drafts are watermarked
- **Send by email** — a toolbar button on an issued invoice, and an offer the moment
  one is issued, opens the invoice as a new email to the client: subject and message from
  two templates on the business page, the PDF attached. *Settings › Email* picks the
  client. Apple Mail is handed everything, including the attachment. Gmail opens in the
  browser with the address, subject and message filled in, but a browser cannot take a
  file from the app, so the PDF is saved to Downloads and copied to the clipboard for a
  paste or a drag. Nothing is sent until you press Send in the mail client. Clients keep
  an email address for this; without one the button says so
- **Year overview** — the year's invoiced, paid, outstanding and overdue amounts above a
  table of its invoices, each opening as its printed page beside the table; exported as a
  real Excel workbook with dates and amounts as values, so the accountant can sort and sum
  them
- **Import** — *File › Import Spreadsheet…* (also on the Overview toolbar and the empty
  invoice list) reads a spreadsheet of issued invoices — the app's own year overview
  export, or the one a bookkeeper keeps by hand — and records them as issued, paid or
  cancelled under their own numbers, adding the clients it does not know. Columns are
  matched by heading in either language; a sheet the app cannot read whole gets a
  column-matching step, unknown clients get a step for their address and tax number, and
  everything is reviewed row by row before the ledger is written. Reads `.xlsx` and
  `.csv`; a Numbers document exports as either
- **My business** — one sidebar section for everything an invoice is printed from and
  printed with: name, address, tax status and bank details, the logo, the signature, the
  line of business, the three standard sentences and the email an invoice is sent with,
  all with placeholders for the month, year, IBAN and payment reference. The form fills one column and a live sample invoice
  the next, so every change is seen where it lands
- **Private mode** — *View › Hide sensitive values* (⇧⌘H) masks tax numbers, the IBAN
  and every amount, on screen and in the invoice preview alike, for a screen share.
  Exports keep the real values
- **English and Slovenian** — follows the Mac's language, or *Settings › Language*.
  English is the source language and the only language in the repository: Slovenian
  exists solely as translations in `Resources/Localizable.xcstrings`. The printed
  invoice, the spreadsheet, the exported file names and the template defaults stay
  Slovenian whatever the interface language, because they are documents rather than
  interface — their English keys are resolved through `Core/DocumentText.swift`, and a
  test in `LocalizationTests` lists every such key and fails when one has no Slovenian
  translation. The one exception is the `DRAFT` watermark, which stays English: it is not
  part of the document, it says the page is not one yet
- **Updates** — the release build updates itself over Sparkle
- **From the command line, and from an agent** — `invoices` is the same ledger as a
  command-line tool: it lists, drafts, edits, issues, pays and cancels invoices, keeps
  clients, renders the PDF and the year's spreadsheet, and answers in JSON. With the
  skill in `skills/invoices/` installed, Claude Code (or any agent with a skill system)
  can be told "invoice Parakeet for August, 80 hours at 45" and do it in the app's
  store. See [the command-line tool](cli.md)

Not built yet: printing, electronic invoicing, expenses.

An import brings in one amount per invoice, so every recorded invoice carries a single
line item; a spreadsheet says nothing about VAT, so the amount is taken as what the client
paid and, under VAT registration, the line's price is the net that grosses up to it.
