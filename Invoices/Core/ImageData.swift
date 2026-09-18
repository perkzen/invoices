import AppKit
import Foundation

/// Logo and signature bitmaps stored on the profile. Whatever the user picks
/// (PNG, JPEG, HEIC, even a PDF) is re-encoded as a bounded PNG so the store
/// never swallows a 20 MB scan.
enum ImageData {
    static let maxDimension: CGFloat = 800

    static func normalized(_ data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let width = CGFloat(source.width)
        let height = CGFloat(source.height)
        let scale = min(1, maxDimension / max(width, height, 1))
        let size = NSSize(width: (width * scale).rounded(), height: (height * scale).rounded())

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: source, size: .zero).draw(in: NSRect(origin: .zero, size: size))

        return rep.representation(using: .png, properties: [:])
    }
}
