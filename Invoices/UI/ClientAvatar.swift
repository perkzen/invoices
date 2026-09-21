import AppKit
import SwiftUI

/// The client's logo, or their initials when they have none. Logos are drawn
/// for paper, so they always sit on a white plate — a dark list would
/// otherwise swallow a black wordmark.
struct ClientAvatar: View {
    let client: Client?
    var size: CGFloat = 32

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
    }

    var body: some View {
        Group {
            if let image = client?.logoData.flatMap(NSImage.init(data:)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.1)
                    .frame(width: size, height: size)
                    .background(.white)
            } else if let client, !client.monogram.isEmpty {
                Text(client.monogram)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(.quaternary)
            } else {
                Image(systemName: "person")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: size, height: size)
                    .background(.quaternary)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
