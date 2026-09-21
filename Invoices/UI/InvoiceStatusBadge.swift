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
        if invoice.isOverdue { return .red }
        switch invoice.status {
        case .draft, .cancelled: return .secondary
        case .issued: return .blue
        case .paid: return .green
        }
    }

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
            .accessibilityLabel(label)
    }
}
