# Invoices

A macOS app, written in SwiftUI, for issuing and tracking invoices as a Slovenian sole
proprietor.

## What it does

- **Clients** — address and tax details (tax number, VAT ID), and an optional logo shown
  next to the client in every list; the printed invoice carries only your own logo
- **Invoices** — drafts with line items, quantity, price and discount per line, and live
  totals; the list is searchable and can be narrowed to drafts, open, paid or cancelled
- **Issuing** — assigns the next sequential number of the year (`2026-001`) and locks the
  invoice; only drafts can be edited or deleted
- **PDF export** — an A4 invoice carrying the fields Slovenian law requires, previewed
  live in the editor as you type; drafts are watermarked
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
  line of business and the three standard sentences, with placeholders for the month,
  year, IBAN and payment reference. The form fills one column and a live sample invoice
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
  translation
- **Updates** — the release build updates itself over Sparkle

Not built yet: printing, electronic invoicing, expenses.

An import brings in one amount per invoice, so every recorded invoice carries a single
line item; a spreadsheet says nothing about VAT, so the amount is taken as what the client
paid and, under VAT registration, the line's price is the net that grosses up to it.

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

## Releasing

```bash
git tag v0.0.2 && git push origin v0.0.2
```

`.github/workflows/release.yml` builds Release, packages a DMG, signs it with the EdDSA
key, writes `appcast.xml` and publishes both on a GitHub release. The tag is the only
source of the version number. The workflow's comments explain the rest.

The image itself is built by `Scripts/make-dmg.sh`, which lays out the mounted window
— fixed size, the app beside the Applications alias — from `Scripts/dmg-settings.py`.
It needs [dmgbuild](https://github.com/dmgbuild/dmgbuild) (`pipx install dmgbuild`),
which the workflow installs for itself. Build one from a local Release build to see
what a release will look like:

```bash
Scripts/make-dmg.sh build/Build/Products/Release/Invoices.app 0.0.0
```

The app's update feed is `…/releases/latest/download/appcast.xml` — GitHub redirects
that fixed path to whichever release is newest, so the URL compiled into the app never
has to change.

### The signing key, once

The EdDSA key pair is the whole of an update's security, since the build is not
notarized. The private key lives in the login keychain of whoever set this up. Sparkle's
tools are on disk after any build:

```bash
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt
gh secret set SPARKLE_PRIVATE_KEY < sparkle-private-key.txt
rm -P sparkle-private-key.txt
```

**Keep a backup of that private key.** It is not recoverable, and installed copies of the
app accept only updates signed with it — losing it means replacing every install by hand.
The matching public key is already in `project.yml` as `SUPublicEDKey`.

### Gatekeeper on first install

The DMG is ad-hoc signed, not notarized, so the **first** install is refused on a
double-click: open *System Settings › Privacy & Security*, find the blocked app near the
bottom and choose **Open Anyway**. That applies once. Sparkle verifies its own downloads
against `SUPublicEDKey`, so every update after that is unattended.

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
                         AppKit images
  Features/              one folder per sidebar section
  Resources/             asset catalog, Localizable.xcstrings
Tests/InvoicesTests/     Swift Testing
Scripts/                 app icon renderer, release installer, disk image
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
