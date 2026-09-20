# Invoices

A macOS app, written in SwiftUI, for issuing and tracking invoices as a Slovenian sole
proprietor.

## What it does

- **Clients** — address and tax details (tax number, VAT ID)
- **Invoices** — drafts with line items, quantity, price and discount per line, and live
  totals
- **Issuing** — assigns the next sequential number of the year (`2026-001`) and locks the
  invoice; only drafts can be edited or deleted
- **PDF export** — an A4 invoice carrying the fields Slovenian law requires, previewed
  live in the editor as you type; drafts are watermarked
- **Year overview** — a year's invoices in one table, exported as a real Excel workbook
  with dates and amounts as values, so the accountant can sort and sum them
- **Invoice template** — logo, tagline, signature and the three standard sentences, with
  placeholders for the month, year, IBAN and payment reference
- **Private mode** — *View › Hide sensitive values* (⇧⌘H) blanks tax numbers, the IBAN
  and every amount on screen, for a screen share. Exports keep the real values
- **English and Slovenian** — follows the Mac's language, or *Settings › Language*.
  English is the source language; the printed invoice and the spreadsheet headers stay
  Slovenian, because they are documents rather than interface
- **Updates** — the release build updates itself over Sparkle

Not built yet: printing, electronic invoicing, expenses, search and filtering.

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
  App/                   entry point, sidebar shell, private mode, Sparkle updater
  Models/                SwiftData @Model types
  Core/                  pure value logic — imports Foundation and nothing else
  Services/              the framework edge: SwiftData, AppKit, PDF and file export
  Features/              one folder per sidebar section
  Resources/             asset catalog, Localizable.xcstrings
Tests/InvoicesTests/     Swift Testing
Scripts/                 app icon renderer, release installer
```

Anything in `Core/` is testable without a `ModelContainer`, a window or a run loop; that
is what the Foundation-only rule buys. The app icon is drawn in code — rerun
`swift Scripts/render-app-icon.swift` only after changing the artwork.

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
