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

## The two configurations

Debug builds `Invoices Dev.app` (`com.domenperko.Invoices.dev`), Release builds
`Invoices.app` (`com.domenperko.Invoices`, installed in `/Applications` by
`Scripts/install-release.sh`). The separate bundle ids give them separate sandbox
containers — never change the Debug id back, or a development build will write to the
user's real invoices.

If you build somewhere outside `build/` anyway, unregister the leftover bundle when you
are done:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "<path>/Invoices Dev.app"
```
