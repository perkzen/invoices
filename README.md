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
- **Pregled** — every issued invoice of one calendar year in one table (stranka,
  številka, datum, valuta, obdobje storitve, vrednost, prejem plačila) with a year
  picker and the SKUPAJ line, and **Izvoz XLSX** writing the same table as a real
  Excel workbook — dates and amounts as values, not text, so the accountant can sort
  and sum them
- **Predloga računa** — logo, tagline, signature and the three sentences (intro, payment
  instruction, closing) live in Nastavitve › Predloga računa. Sentences take placeholders
  such as `{MESEC}`, `{leto}`, `{trr}`, `{sklic}`; see `Core/InvoiceTemplate.swift`
- **Nastavitve** — your own details (name, address, bank account, tax status) are in the
  sidebar and under ⌘,
- **Slovenščina / English** — the interface follows the Mac's language, or the picker in
  Nastavitve › Jezik. Strings live in `Resources/Localizable.xcstrings` with Slovenian as
  the source language. The printed invoice is always Slovenian; wrap any new string on
  the PDF page in `Text(verbatim:)` so it never lands in the catalog

Not built yet: printing, e-računi, expenses, search and filtering.

## Requirements

- macOS 26+, Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Building

The `.xcodeproj` is generated and **not** committed — `project.yml` is the source of truth.
After cloning, or after adding or renaming a file:

```bash
xcodegen generate && open Invoices.xcodeproj
```

From the command line — always with the same `-derivedDataPath`, so builds land in
`build/` and nowhere else:

```bash
xcodebuild -project Invoices.xcodeproj -scheme Invoices -destination 'platform=macOS' -derivedDataPath build test
```

## Two apps: Invoices and Invoices Dev

The two configurations build two separate applications, on purpose:

| | Debug | Release |
|---|---|---|
| Bundle | `Invoices Dev.app` | `Invoices.app` |
| Bundle id | `com.domenperko.Invoices.dev` | `com.domenperko.Invoices` |
| Data | its own sandbox container, empty at first | `~/Library/Containers/com.domenperko.Invoices` — the real invoices |
| Where it lives | wherever you built it | `/Applications` |

Debug is what Xcode runs. It carries a different name because Spotlight labels an app by
its file name, and a different bundle id so that a half-finished feature can never write
to the invoices you actually issued.

Release is the app you use. Build and install it with:

```bash
Scripts/install-release.sh
```

Every build of the Debug configuration — including ones an agent makes in a temporary
directory — is named `Invoices Dev`, so only one thing in Spotlight is ever called
`Invoices`. If stale copies do pile up, delete the build directories and tell Launch
Services they are gone:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "/path/to/stale/Invoices Dev.app"
```

## App icon

The icon is drawn in code, not painted — `Scripts/render-app-icon.swift` renders every
PNG in `AppIcon.appiconset` with CoreGraphics. Each pixel size is rendered natively and
drops detail as it shrinks: the right-hand amounts and the third line item go below 128px,
the remaining rules below 48px, and at 16px only the sheet and the amber total are left.
macOS does not mask a PNG app icon, so the script also draws the squircle, its inset and
its drop shadow — with a tighter inset at small sizes, where a proportional margin would
cost more pixels than the artwork can spare.

```bash
swift Scripts/render-app-icon.swift
```

The PNGs are committed, so a normal build needs none of this — rerun it only after
changing the artwork.

## Layout

```
project.yml              target, build settings, Info.plist
Invoices/
  App/                   @main entry point, Settings scene, sidebar shell, entitlements
  Models/                SwiftData @Model types + VatRate / InvoiceStatus enums
  Core/                  pure value logic — imports Foundation and nothing else
  Services/              the framework edge: SwiftData, AppKit, PDF and file export
  Features/              one folder per sidebar section, views and their local state
    Invoices/            list, editor, live preview
    Clients/             list and detail form
    YearOverview/        the year's table and its export
    Settings/            s.p. profile, invoice template, sample invoice
  Resources/             asset catalog, Localizable.xcstrings
Tests/InvoicesTests/     Swift Testing, covers the money arithmetic
Scripts/                 app icon renderer, release installer (not part of any target)
```

The split between `Core/` and `Services/` is enforceable by reading the imports: a file
in `Core/` imports Foundation only, so every rule about money, numbering and formatting is
testable without a `ModelContainer`, a window or a run loop. Anything that has to reach a
framework — `InvoiceNumbering` for its `ModelContext` fetch, `InvoicePDF` for
`ImageRenderer`, the two `FileDocument` wrappers, `ImageData` for AppKit — lives in
`Services/` instead.

`Core/XLSXWriter.swift` writes the .xlsx by hand — the OOXML parts plus a stored
(uncompressed) ZIP in `Core/ZIPArchive.swift` — so the app stays dependency-free. The
sheet a year overview fills is laid out in `Core/YearOverviewXLSX.swift`. The SKUPAJ
line is a value rather than a `=SUM()` formula, because cancelled invoices are listed
(their numbers belong to the sequence) but not counted, and a formula over the column
would quietly disagree with the app.

The money arithmetic lives in `Core/InvoiceMath.swift` as plain `Decimal` functions
rather than on the `@Model` classes, so it is testable without a `ModelContainer`.

`Services/InvoicePDF.swift` renders `Services/InvoicePDFPage.swift` through
`ImageRenderer` into a CGPDF context, one A4 page at a time. Pagination is a budget in layout units, not a row
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
