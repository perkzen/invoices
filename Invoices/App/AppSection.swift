import Foundation

/// The sidebar's top-level destinations. Settings appears here as well as in
/// the ⌘, window, so nobody has to know the shortcut to find it — pinned to
/// the bottom, apart from the three sections that hold the work.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case invoices
    case clients
    case overview
    case business
    case settings

    var id: String { rawValue }

    /// The sections listed at the top of the sidebar. The overview opens
    /// first: it answers "how am I doing" before any one invoice is touched.
    static let content: [AppSection] = [.overview, .invoices, .clients, .business]

    var title: String {
        switch self {
        case .invoices: String(localized: "Invoices")
        case .clients: String(localized: "Clients")
        case .overview: String(localized: "Overview")
        case .business: String(localized: "My business")
        case .settings: String(localized: "Settings")
        }
    }

    var symbol: String {
        switch self {
        case .invoices: "doc.text"
        case .clients: "person.2"
        case .overview: "tablecells"
        case .business: "building.2"
        case .settings: "gearshape"
        }
    }
}
