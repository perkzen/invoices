# Architecture

## Building

macOS 26+, Xcode 26+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The `.xcodeproj` is generated and not committed —
`project.yml` is the source of truth, so re-run `xcodegen` after adding or renaming a
file.

```bash
xcodegen generate && open Invoices.xcodeproj
```

```bash
xcodebuild -project Invoices.xcodeproj -scheme Invoices -destination 'platform=macOS' -derivedDataPath build test
```

Always pass the same `-derivedDataPath`, so builds land in `build/` and nowhere else.

## Two apps

Debug builds `Invoices Dev.app` (`com.domenperko.Invoices.dev`); Release builds
`Invoices.app` (`com.domenperko.Invoices`). The separate bundle ids give them separate
sandbox containers, so a half-finished feature can never write to the invoices you
actually issued, and the separate names keep Spotlight honest. Only Release updates
itself.

Release is the app you use. Build and install it into `/Applications` with:

```bash
Scripts/install-release.sh
```

## Layout

```
project.yml              target, build settings, Info.plist
Invoices/
  App/                   entry point, the three-column shell, private mode, menu
                         commands, Sparkle updater
  UI/                    the view vocabulary every feature reuses: client avatars,
                         status badges, image wells, and the modifiers for exporting a
                         file, alerting on failure and confirming a deletion
  Models/                SwiftData @Model types
  Core/                  pure value logic — imports Foundation and nothing else,
                         including the .xlsx writer and reader and the import planner
  Services/              the framework edge: the ledger over SwiftData, the PDF renderer,
                         the mail composer, AppKit images
  Features/              one folder per sidebar section
  Resources/             asset catalog, Localizable.xcstrings
CLI/                     the `invoices` command-line tool: one file per command group,
                         the store locator, the JSON records; compiles Models, Core and
                         Services alongside, and is copied into the app bundle
skills/invoices/         the agent skill that teaches Claude Code to use the tool; also
                         bundled into the app, and printed by `invoices skill`
Tests/InvoicesTests/     Swift Testing
Scripts/                 app icon renderer, release installer, tool installer, disk image
```

Anything in `Core/` is testable without a `ModelContainer`, a window or a run loop; that
is what the Foundation-only rule buys. The app icon is drawn in code — rerun
`swift Scripts/render-app-icon.swift` only after changing the artwork.

Two seams carry most of the app. Every change to an invoice's life — a new draft, issuing,
payment, cancellation, recording invoices imported from a spreadsheet, and whether a draft
or a client may be deleted — goes through `Services/Ledger.swift`, so each rule is tested
once and the views only ask. The import itself is pure: `Core/InvoiceImport.swift` turns a
grid of cells into a plan that says, row by row, what will be recorded and what is skipped
and why, and the sheet under `Features/Import/` only shows that plan. Everything the
printed invoice shows is fixed first as `Core/PrintedInvoice.swift`, a plain value built
from the models; the PDF page, the pagination budget, the live preview and the settings
sample all render from it, and the preview re-renders because the value changed, not
because a view listed what to watch.

## Decisions

Money is `Decimal`, rounded half-up to cents once per line and then summed. Formatting is
pinned to `sl_SI` rather than the system locale, because an invoice is a Slovenian
document even if the Mac is in English. Numbers run unbroken within a calendar year, so
an issued number stays in the list even when the invoice is cancelled.

Tax setup, decided 2026-09-18: flat-rate expenses, so only revenue matters; not
VAT-registered, so invoices charge no VAT and carry the Article 94 exemption clause; bank
transfer only, so fiscal verification of receipts is out of scope. The VAT toggle in
Settings stays for the day the turnover threshold is crossed.

Cancelling an invoice is a v0 simplification — it flips the status. Properly it is its
own numbered document, a cancellation invoice or a credit note referencing the original,
and that is worth fixing before this is used for real bookkeeping.

## Open questions

1. **Any public-sector clients?** They require electronic invoices in the eSLOG 2.0
   format, submitted through the state payment administration — a real chunk of work.
2. **Invoice language** — Slovenian only, or Slovenian and English for foreign clients?
3. **Storage** — local SwiftData store (today) or iCloud sync across machines?
