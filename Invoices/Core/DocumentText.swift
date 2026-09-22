import Foundation

/// Strings on the printed invoice, the accountant's spreadsheet and the
/// exported files. Those are Slovenian documents whatever language the
/// interface runs in, so they are resolved against the Slovenian
/// localization directly instead of the one the app is running in.
///
/// Every key is English and lives in `Localizable.xcstrings` like any other
/// string; only the lookup is pinned. A key without a Slovenian translation
/// would come back in English, which `LocalizationTests` guards against.
nonisolated enum DocumentText {
    static let locale = Formatting.locale

    /// Where `sl.lproj` is looked for. The app never sets this: its own
    /// bundle carries the localization. The command-line tool is a bare
    /// executable with no resources of its own, so it points this at the
    /// installed app before it renders anything — once, at startup, before
    /// the first lookup, which is why an unsynchronized global is enough.
    nonisolated(unsafe) static var resourceBundle: Bundle = .main

    /// The `sl.lproj` inside `resourceBundle`. Falling back to the main
    /// bundle only happens when the localization is missing altogether.
    static var bundle: Bundle {
        guard let path = resourceBundle.path(forResource: "sl", ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }

    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: bundle, locale: locale)
    }
}
