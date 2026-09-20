# Invoices

SwiftUI desktop app (macOS) for managing invoices for a Slovenian **s.p.**

## Status

v0 scaffold. It builds, runs, and persists data. What works today:

Screens are named in English, as the source is; the Slovenian label each one carries on
a Slovenian Mac is given in brackets.

- **Clients** [Stranke] — client list with address and tax details (davčna številka,
  ID za DDV), and an optional logo shown next to the client in every list (the printed
  invoice carries only your own logo)
- **Invoices** [Računi] — draft invoices with line items, quantity/price/discount per
  line and live totals (VAT columns appear only when the DDV toggle in Settings is on)
- **Issuing** [Izdaja] — issuing a draft assigns the next sequential number (`2026-001`)
  and locks the invoice
- **PDF export** [Izvoz PDF] — A4 invoice with the mandatory Slovenian fields, paginated
  for long invoices; drafts carry an OSNUTEK watermark so one cannot be mistaken for a
  real invoice
- **Preview** [Predogled] — the invoice editor shows the PDF live in a pane beside the
  form, re-rendered as you type; Settings shows the same preview on a sample invoice
- **Year overview** [Pregled] — every issued invoice of one calendar year in one table,
  with a year picker and the SKUPAJ line, and **XLSX export** [Izvoz XLSX] writing the
  same table as a real Excel workbook — dates and amounts as values, not text, so the
  accountant can sort and sum them. The sheet keeps its Slovenian headers (stranka,
  številka, datum, valuta, obdobje storitve, vrednost, prejem plačila): it is written
  for the accountant, not for the app
- **Invoice template** [Predloga računa] — logo, tagline, signature and the three
  sentences (intro, payment instruction, closing) have their own sidebar section, with the
  sample preview beside the form.
  Sentences take placeholders such as `{MESEC}`, `{leto}`, `{trr}`, `{sklic}`; see
  `Core/InvoiceTemplate.swift`
- **Settings** [Nastavitve] — your own s.p. details (name, address, bank account, tax
  status, IBAN, default payment term, footer note), in the sidebar and under ⌘,
- **Private mode** [Zasebni način] — View › Skrij občutljive podatke (⇧⌘H) blanks the tax
  numbers, the IBAN and every amount in the interface, for a screen share or a look over
  your shoulder. It is a view preference, not a fact: the exported PDF, the spreadsheet
  and the printed račun carry the real values whether it is on or off. Mark a new value
  with `.sensitiveValue()`; `.privacyRedacted()` at the root of the window blanks it —
  see `App/PrivacyMode.swift`
- **English / Slovenian** — the interface follows the Mac's language, or the picker in
  Settings › Language. Strings live in `Resources/Localizable.xcstrings` with **English as
  the source language**: write the English text as the key in code, and Slovenian is the
  translation hanging off it. Two kinds of string deliberately stay out of the catalog,
  because they are Slovenian documents rather than interface — the printed račun (wrap any
  new string on the PDF page in `Text(verbatim:)`) and the .xlsx headers in
  `Core/YearOverviewXLSX.swift`. Counts go through the catalog's plural rules rather than
  an `if`: Slovenian needs `one` / `two` / `few` / `other` where English needs two, and
  `Formatting.invoiceCount` is the worked example. Where one English word covers two
  Slovenian ones, use a symbolic
  key: `InvoiceStatus.paid` is `"invoiceStatus.paid"` because an invoice is *plačan* while
  a year's receipts are *plačano*, and both are "Paid"

- **Updates** — the release build updates itself over Sparkle; pushing a `v*` tag
  publishes a signed DMG and its appcast to GitHub Releases

Not built yet: printing, e-računi, expenses.

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
| Updates itself | no | yes, over Sparkle |

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

## Updates

The release build updates itself with [Sparkle](https://sparkle-project.org). It checks
on its own schedule, and *Invoices › Check for Updates…* checks on demand. The debug
build does not: it is a different app, so installing a release over it would silently
replace the development build with the production one — hence the `#if !DEBUG` in
`App/UpdaterCommands.swift`.

The feed is `…/releases/latest/download/appcast.xml`. GitHub redirects that fixed path
to whichever release is newest, so the URL compiled into the app never has to change and
there is no branch or server to host.

Because the app is sandboxed it cannot replace its own bundle, so Sparkle does it from
two XPC services inside `Sparkle.framework`. That is what the
`com.apple.security.temporary-exception.mach-lookup.global-name` entitlements and
`SUEnableInstallerLauncherService` are for — without them an update downloads fine and
then fails at install time, which is easy to miss.

`Scripts/install-release.sh` and the DMG are not alternatives: the script is the local
path, building Release from your own checkout straight into `/Applications`, and the DMG
is how the app reaches a machine that is not this one.

## Releasing

```bash
git tag v0.0.2 && git push origin v0.0.2
```

`.github/workflows/release.yml` builds Release, packages `Invoices.app` into a DMG, signs
it with the EdDSA key, writes `appcast.xml`, and publishes both as assets on a GitHub
release. The tag is the only source of the version number — `MARKETING_VERSION` in
`project.yml` is just the placeholder local builds use. `CURRENT_PROJECT_VERSION` comes
from the tag too, because that is the field Sparkle compares; left at `1` no update would
ever be offered.

The appcast holds a single item, rewritten on every release. Sparkle only needs the
newest version to decide whether to offer an update, and a one-item feed cannot drift out
of step with what is actually attached to the release.

### One-time setup

The EdDSA key pair is what makes an update trustworthy — it is the whole of the security
here, since the build is not notarized. The private key lives in the login keychain of
whoever set this up. Sparkle's tools come down with the package, so they are on disk
after any build:

```bash
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt
gh secret set SPARKLE_PRIVATE_KEY < sparkle-private-key.txt
rm -P sparkle-private-key.txt
```

Piping the file straight into `gh` keeps the key out of the terminal and out of shell
history. Without `gh`, paste the file into *Settings › Secrets and variables › Actions ›
New repository secret*, named `SPARKLE_PRIVATE_KEY`. The matching public key is already
in `project.yml` as `SUPublicEDKey`.

**Keep a backup of that private key.** It is not recoverable, and installed copies of the
app will only accept updates signed with it — losing it means every existing install has
to be replaced by hand.

### Gatekeeper on first install

The DMG is ad-hoc signed, not signed with an Apple Developer ID and not notarized (that
needs the paid Developer Program). So the **first** install is refused on a double-click:
open *System Settings › Privacy & Security*, find the blocked app near the bottom and
choose **Open Anyway**.

That applies once, to the DMG you download by hand. Sparkle verifies its own downloads
against `SUPublicEDKey` and installs them without going through Gatekeeper quarantine, so
updates after that first install are unattended.

The ad-hoc signature is also why the release workflow passes `ENABLE_HARDENED_RUNTIME=NO`.
Hardened runtime enables library validation, which requires an embedded framework to
share the app's Team ID — an ad-hoc signature has none, so `Sparkle.framework` fails to
load and the app dies at launch. `project.yml` keeps `ENABLE_HARDENED_RUNTIME: YES` for
the signed case; the workflow overrides it, and that override goes away with a Developer
ID. Moving to a notarized build later changes only the workflow's signing step — nothing
in the app or the appcast.

### The first release is a manual install

Whatever is installed today has no Sparkle in it at all, so it cannot be offered an
update: the first release has to be downloaded and dragged across by hand. That also
sidesteps a version-comparison trap — the current build reports `CFBundleVersion` `1`,
and Sparkle reads `1` as *newer* than `0.0.1`. From the first release onwards every
version comes from a tag, so the comparison is consistent and updates flow on their own.

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
  App/                   @main entry point, Settings scene, sidebar shell, private mode, entitlements
  Models/                SwiftData @Model types + VatRate / InvoiceStatus enums
  Core/                  pure value logic — imports Foundation and nothing else
  Services/              the framework edge: SwiftData, AppKit, PDF and file export
  Features/              one folder per sidebar section, views and their local state
    Invoices/            list, editor, live preview
    Clients/             list and detail form
    YearOverview/        the year's table and its export
    Settings/            s.p. profile, invoice template, sample invoice
  Resources/             asset catalog, Localizable.xcstrings
  App/UpdaterCommands.swift  Sparkle updater + Check for Updates… (release only)
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
- **Service date** (datum opravljene storitve) is stored separately from the issue date,
  since both are mandatory and frequently differ.
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

The DDV toggle in Settings stays, because the status changes the day the turnover
threshold is crossed. Flipping it brings back the per-line rate picker and the VAT recap —
the model already stores a `VatRate` per line.

## Open questions

1. **Any public-sector clients?** Those require e-računi in eSLOG 2.0 via UJP — a real
   chunk of work, worth knowing up front.
2. **Invoice language** — Slovenian only, or Slovenian + English for foreign clients?
3. **Storage** — local SwiftData store (today) or iCloud sync across machines?
