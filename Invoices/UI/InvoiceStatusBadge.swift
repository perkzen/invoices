import SwiftUI

/// The invoice's state as a tinted capsule. Colour is spent on state alone:
/// blue for money still expected, green once it arrived, red the day it is
/// late, and no colour at all for a draft or a cancelled invoice.
struct InvoiceStatusBadge: View {
    let invoice: Invoice

    private var label: String {
        invoice.isOverdue ? String(localized: "Overdue") : invoice.status.label
    }

    private var tint: Color {
        invoice.isOverdue ? .red : invoice.status.tint
    }

    var body: some View {
        StatusCapsule(label: label, tint: tint)
            .accessibilityLabel(label)
    }
}

/// The tinted capsule itself, drawn the same in the list, the toolbar and
/// the status pop-up's menu.
struct StatusCapsule: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            // A state is one word in one line. Squeezed by a narrow list
            // row, the text would otherwise break — "Can-celled" — and
            // stretch the capsule into a two-line lozenge.
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

/// A menu item shows a title and an image, never a view, and ignores the
/// colour of its title — so the pop-up's options are the capsules drawn
/// into images. Rendered once per state and appearance.
@MainActor
enum StatusCapsuleImage {
    private struct Key: Hashable {
        let status: InvoiceStatus
        let colorScheme: ColorScheme
    }
    private static var cache: [Key: NSImage] = [:]

    static func image(for status: InvoiceStatus, in colorScheme: ColorScheme) -> NSImage {
        let key = Key(status: status, colorScheme: colorScheme)
        if let image = cache[key] { return image }
        let renderer = ImageRenderer(
            content: StatusCapsule(label: status.label, tint: status.tint)
                .environment(\.colorScheme, colorScheme)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.accessibilityDescription = status.label
        cache[key] = image
        return image
    }
}

extension InvoiceStatus {
    /// The colour the state is shown in wherever it is named: blue for
    /// money still expected, green once it arrived, none for a draft or a
    /// cancelled invoice. Overdue is the badge's own red, not a state.
    var tint: Color {
        switch self {
        case .draft, .cancelled: .secondary
        case .issued: .blue
        case .paid: .green
        }
    }
}
