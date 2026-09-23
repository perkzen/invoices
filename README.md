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
  store. See [The command-line tool](#the-command-line-tool)

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

## The command-line tool

The tool ships inside the app, at `Invoices.app/Contents/Helpers/invoices`, so every
release carries it and a Sparkle update replaces it along with the app. Putting it on
the PATH is a symlink into the bundle, and the skill that teaches Claude Code to use it
is printed by the tool itself:

```bash
sudo ln -sfn /Applications/Invoices.app/Contents/Helpers/invoices /usr/local/bin/invoices
mkdir -p ~/.claude/skills/invoices && invoices skill > ~/.claude/skills/invoices/SKILL.md
```

`Scripts/install-cli.sh` does both (pass another directory as the first argument), and
clears the quarantine flag a disk-image install leaves on the helper, which Gatekeeper
would otherwise hold against it separately from the app.

**Invoices › Install Command Line Tool…** and **Install…** under Command line tool in
Settings make the same link from inside the app, for when a terminal is not at hand.
Either asks which folder to link into, because a sandboxed app may write only where the
user has pointed it, and it offers `~/.local/bin`: `/usr/local/bin` belongs to root, so
the app is refused there and the `sudo` line above stays the way in. It links the tool
and nothing else — the skill is still `invoices skill`. Only the release build offers
either; the development build would link a copy of itself in `build/`, which the next
clean build empties. Then:

```bash
invoices --help
invoices invoice list --overdue
invoices invoice create --client parakeet --service-date 2026-08-01 --service-end month \
  --line '{"description": "Razvoj programske opreme", "quantity": 80, "unit": "h", "unitPrice": 45}'
invoices invoice issue draft
invoices invoice pdf 2026-003
invoices overview --year 2026 --xlsx ~/Desktop/Izdani-racuni-2026.xlsx
```

The tool is not a second implementation. Its target compiles the app's `Models/`,
`Core/` and `Services/` — the same `Ledger`, the same numbering, the same PDF page and
spreadsheet — and opens the app's SwiftData store by path, inside the app's sandbox
container. That is why it is Swift and lives in this project: a tool in another
language would have to re-derive the Core Data schema and every rule in the ledger, and
break the first time either moved.

Three things follow from opening the store directly, and one from living in the bundle:

- It opens the **installed app's** store, the one under `com.domenperko.Invoices`. `--dev`
  opens the development build's instead; `--store <path>` (or `INVOICES_STORE`) opens a
  file outright, and creates it when it does not exist, which is what the CI smoke test
  runs against. The app's own store is never created by the tool: launch the app once.
- The first time a terminal opens a store in `~/Library/Containers`, macOS asks whether
  Terminal may access data from other apps. Allow it once.
- The tool is a bare executable with no resources, so it takes the Slovenian document
  strings and the skill from the app around it: the `.app` above its own executable,
  resolved through the symlink; or `INVOICES_APP`; or, for a build-tree binary run on
  its own, whichever build Launch Services finds. Rendering a PDF or a spreadsheet
  refuses to run without one rather than print a legal document in English; everything
  else works either way.

Every command prints JSON. Records carry an `id` (a UUID stored on the invoice and the
client, given to older rows at launch) so a draft can be named before it has a number;
issued invoices are named by number. Errors are `{"error": "…"}` on stderr with exit
status 1, worded so that an agent knows what to do next. `skills/invoices/SKILL.md` is
the agent-facing manual, written the way [herdr](https://github.com/herdrdev/herdr)
writes its skill: check the binary exists, learn the syntax from `--help`, read state
from the JSON, and confirm with the user before the irreversible steps — issuing,
cancelling, deleting.

The running app does not watch the store for changes made by another process; if it is
open while the tool writes, relaunch it to see them.

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
