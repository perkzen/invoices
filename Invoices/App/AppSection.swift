import Foundation

/// The sidebar's top-level destinations. Settings appears here as well as in
/// the ⌘, window, so nobody has to know the shortcut to find it.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case invoices
    case clients
    case overview
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .invoices: String(localized: "Računi")
        case .clients: String(localized: "Stranke")
        case .overview: String(localized: "Pregled")
        case .settings: String(localized: "Nastavitve")
        }
    }

    var symbol: String {
        switch self {
        case .invoices: "doc.text"
        case .clients: "person.2"
        case .overview: "tablecells"
        case .settings: "gearshape"
        }
    }
}
