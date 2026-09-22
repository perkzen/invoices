# Working in this repository

## Building and testing

Always pass `-derivedDataPath build`. Without it every invocation invents its own
derived-data directory, and each one leaves behind an app bundle that Launch Services
registers — that is how nine copies of this app once ended up in Spotlight.

```bash
xcodegen generate
xcodebuild -project Invoices.xcodeproj -scheme Invoices -destination 'platform=macOS' -derivedDataPath build test
```

`project.yml` is the source of truth; `Invoices.xcodeproj` and `Invoices/App/Info.plist`
are generated and not committed. Re-run `xcodegen generate` after adding or renaming a
source file.

## The command-line tool

`InvoicesCLI` builds `invoices`, from `CLI/` plus the app's `Models/`, `Core/` and
`Services/` (less the email composer and the image normalizer) compiled a second time.
The app target depends on it and copies it into `Contents/Helpers/`, so building the app
builds the tool, and the installed one is the copy inside `/Applications/Invoices.app`,
reached through a symlink on the PATH.
Anything added to those folders has to compile without the rest of `App/`, `UI/` and
`Features/` — the tool links SwiftUI and AppKit, but not the app's views — and under
nonisolated default isolation, which the tool target uses so its command types can
satisfy ArgumentParser's nonisolated requirements: in shared code, write `@MainActor`
where it is meant rather than relying on the app's default. It has no unit tests; CI builds it and drives it through an
invoice's life against a throwaway store (`.github/workflows/ci.yml`), so a change to
its commands should keep that script passing.

```bash
xcodebuild -project Invoices.xcodeproj -scheme Invoices -destination 'platform=macOS' -derivedDataPath build build
INVOICES_STORE=/tmp/try.store "build/Build/Products/Debug/Invoices Dev.app/Contents/Helpers/invoices" --help
```

Never run it without `--store`, `INVOICES_STORE` or `--dev` while developing: the
default is the installed app's store, the user's real invoices.

## The two configurations

Debug builds `Invoices Dev.app` (`com.domenperko.Invoices.dev`), Release builds
`Invoices.app` (`com.domenperko.Invoices`, installed in `/Applications` by
`Scripts/install-release.sh`). The separate bundle ids give them separate sandbox
containers — never change the Debug id back, or a development build will write to the
user's real invoices.

Only Release updates itself, over Sparkle — `App/UpdaterCommands.swift` is behind
`#if !DEBUG`, and that gate has to stay. Debug is a different app, so an update installed
into it would replace the development build with the production one.

If you build somewhere outside `build/` anyway, unregister the leftover bundle when you
are done:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "<path>/Invoices Dev.app"
```
