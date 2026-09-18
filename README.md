# Invoices

SwiftUI desktop app (macOS) for managing invoices for a Slovenian **s.p.**

## Status

v0 scaffold. It builds, runs, and persists data. What works today:

- **Stranke** — client list with address and tax details (davčna številka, ID za DDV)
- **Računi** — draft invoices with line items, quantity/price/discount per line and live
  totals (VAT columns appear only when the DDV toggle in Nastavitve is on)
- **Nastavitve** — your own s.p. details: tax status, IBAN, default payment term, footer note
- **Izdaja** — issuing a draft assigns the next sequential number (`2026-001`) and locks the invoice
- **Izvoz PDF** — A4 invoice with the mandatory Slovenian fields, paginated for long
  invoices; drafts carry an OSNUTEK watermark so one cannot be mistaken for a real invoice
- **Predogled** — the invoice editor shows the PDF live in a trailing inspector, re-rendered
  as you type; Nastavitve shows the same preview on a sample invoice
- **Predloga računa** — logo, tagline, signature and the three sentences (intro, payment
  instruction, closing) live in Nastavitve › Predloga računa. Sentences take placeholders
  such as `{MESEC}`, `{leto}`, `{trr}`, `{sklic}`; see `Core/InvoiceTemplate.swift`

Not built yet: printing, e-računi, expenses, reports, search and filtering.

## Requirements

- macOS 26+, Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Building

The `.xcodeproj` is generated and **not** committed — `project.yml` is the source of truth.
After cloning, or after adding or renaming a file:

```bash
xcodegen generate && open Invoices.xcodeproj
```

From the command line:

```bash
xcodebuild -project Invoices.xcodeproj -scheme Invoices -destination 'platform=macOS' test
```

## Layout

```
project.yml              target, build settings, Info.plist
Invoices/
  App/                   @main entry point, Settings scene, entitlements
  Models/                SwiftData @Model types + VatRate / InvoiceStatus enums
  Core/                  pure value logic: totals, rounding, numbering, sl_SI formatting
  Views/                 NavigationSplitView shell, lists, editors
Tests/InvoicesTests/     Swift Testing, covers the money arithmetic
```

The money arithmetic lives in `Core/InvoiceMath.swift` as plain `Decimal` functions
rather than on the `@Model` classes, so it is testable without a `ModelContainer`.

`Core/InvoicePDF.swift` renders `Views/InvoicePDFPage.swift` through `ImageRenderer` into
a CGPDF context, one A4 page at a time. Pagination is a budget in layout units, not a row
count: a row costs 2 units of padding plus one per wrapped line of its description, so a
long description cannot silently push the last row off the page. Continuation pages get a
slim header — with the full one they would not fit the rows the budget assumes. The
40-character wrap estimate is a heuristic, not a measurement; `lineLimit(2)` means a wrong
guess truncates a description rather than overflowing the page.

## Domain rules already encoded

- **Sequential numbering.** Numbers run unbroken within a calendar year and are only
  assigned when an invoice is issued, so drafts cannot punch gaps into the sequence.
- **Issued invoices are immutable.** `InvoiceStatus.isEditable` is true only for drafts;
  the editor disables itself otherwise. Corrections belong in a storno or dobropis.
- **Datum opravljene storitve** is stored separately from the issue date, since both are
  mandatory and frequently differ.
- **Non-zavezanec.** `VatRate.exempt` charges 0 % and carries the clause
  *"DDV ni obračunan na podlagi 1. odstavka 94. člena ZDDV-1."*, printed under the totals.
- **Money is `Decimal`**, rounded half-up to cents once per line, then summed.
- **Only drafts can be deleted or edited.** An issued number stays in the list even if
  the invoice is cancelled, so the sequence has no unexplainable gaps.
- **Storno is a v0 simplification.** Today "Storniraj" flips the invoice to `.cancelled`.
  Properly, a storno is its own numbered document (storno račun / dobropis) that references
  the original — worth fixing before this is used for real bookkeeping.
- **Formatting is pinned to `sl_SI`**, not the system locale — an invoice is a Slovenian
  document even if the Mac is in English.

## Tax setup (decided 2026-09-18)

- **Normiranec** — flat-rate expenses, so the app does not need to track actual costs.
  Only revenue matters.
- **Not a DDV zavezanec** — invoices charge no VAT. The VAT rate picker and the VAT recap
  stay hidden, and every invoice carries the 94. člen ZDDV-1 exemption clause.
- **Bank transfer only** — no cash, so davčno potrjevanje računov does not apply and is
  permanently out of scope.

The DDV toggle in Nastavitve stays, because the status changes the day the turnover
threshold is crossed. Flipping it brings back the per-line rate picker and the VAT recap —
the model already stores a `VatRate` per line.

## Open questions

1. **Any public-sector clients?** Those require e-računi in eSLOG 2.0 via UJP — a real
   chunk of work, worth knowing up front.
2. **Invoice language** — Slovenian only, or Slovenian + English for foreign clients?
3. **Storage** — local SwiftData store (today) or iCloud sync across machines?
