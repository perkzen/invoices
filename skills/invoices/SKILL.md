---
name: invoices
description: "Work with the user's invoices and clients in the Invoices macOS app through the `invoices` command-line tool: look invoices and clients up, draft and edit invoices, issue them, mark them paid, cancel them, render the PDF, and report a year's totals. Use when the user asks about their invoices, clients, revenue or outstanding payments, or wants an invoice made or changed. Requires the `invoices` binary on PATH."
---

# Invoices

The Invoices app keeps one Slovenian sole trader's clients and invoices. The `invoices`
tool opens the app's own store and applies the app's own rules, so anything done here
shows up in the app, and nothing here can do what the app would refuse.

Before anything else, check that the tool is installed:

```bash
command -v invoices
```

If it is not, say so and stop. The tool ships inside the app; putting it on the PATH is
one line the user runs themselves:

```bash
sudo ln -sfn /Applications/Invoices.app/Contents/Helpers/invoices /usr/local/bin/invoices
```

Do not look for the store or edit it by other means.

## Learn the current tool

The installed binary is the authority for command syntax. Start with:

```bash
invoices --help
```

Then print the command group you need:

```bash
invoices invoice --help
invoices client --help
invoices profile --help
invoices overview --help
```

Every command prints JSON on stdout. A failure prints `{"error": "…"}` on stderr and
exits with status 1; the message says what to do instead. Read ids, numbers and amounts
from the JSON rather than predicting them.

## The rules the tool enforces

- **A draft is the only invoice that can be edited or deleted.** Once issued, an
  invoice's content is fixed. A mistake in an issued invoice is corrected by cancelling
  it and drafting a new one — never by editing.
- **Issuing cannot be undone.** It assigns the next number in the year's unbroken
  sequence (`2026-003`) and locks the invoice. Show the user the draft (`invoice show`)
  and get their go-ahead before `invoice issue` or `invoice create --issue`, unless they
  already asked for it to be issued.
- **An issued invoice is cancelled, never deleted.** It keeps its number and stays in
  the year overview, uncounted. Cancelling and deleting are also worth confirming.
- **Paid means money arrived.** `invoice pay` takes the day it arrived (`--on`);
  `invoice unpay` is the way back from a payment marked by mistake.
- **A client with issued invoices stays**; the invoice keeps no copy of its
  counterparty.

## Naming things

- An invoice: its number (`2026-003`, or `2026-3`), its `id`, or `draft` when exactly
  one draft exists.
- A client: its `id`, its name, or a unique part of the name; case and diacritics do
  not matter. When several match, the error lists them — ask the user which.
- Dates: `YYYY-MM-DD`. Amounts: plain numbers, `49.9` or `"49,90"`. Money is EUR.
- A line item is a JSON object: `description`, `quantity` (default 1), `unit` (`h`,
  `kos`, `dan`; empty hides the column), `unitPrice`, `discountPercent`, `vatRate`.

## Which store

By default the tool opens the installed app's store — the user's real invoices.
`--dev` opens the development build's, which is a separate app with separate data;
use it only when the user is developing the app and says so. The first time a terminal
opens the store, macOS may ask to allow access to data from other apps; that is expected.

## Recipes

Draft an invoice for a month's work and show it before issuing:

```bash
invoices invoice create --client "Parakeet" --service-date 2026-08-01 --service-end month \
  --line '{"description": "Razvoj programske opreme", "quantity": 80, "unit": "h", "unitPrice": 45}'
invoices invoice show draft
invoices invoice issue draft
invoices invoice pdf 2026-003 --output ~/Desktop/Invoice-2026-003.pdf
```

What is outstanding, and who is late:

```bash
invoices invoice list --status issued
invoices invoice list --overdue
invoices overview --year 2026
```

Record a payment, correct an invoice that went out wrong:

```bash
invoices invoice pay 2026-003 --on 2026-09-20
invoices invoice cancel 2026-004
invoices invoice create --client "Parakeet" --line '…' --issue
```

Add a client, then find it later:

```bash
invoices client add --name "Parakeet AI Ltd." --street "Dunajska 5" --postal-code 1000 --city Ljubljana --tax-number 12345678 --email billing@parakeet.ai
invoices client show parakeet
```

## Reporting back

Say what was done in the app's terms — drafted, issued, paid, cancelled — with the
invoice number and the gross total from the JSON. The app shows the change on its next
refresh; if the user has it open and does not see it, relaunching the app is enough.
