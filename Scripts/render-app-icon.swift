#!/usr/bin/env swift
//
//  render-app-icon.swift
//
//  Draws the Invoices app icon and writes every PNG the AppIcon.appiconset
//  asks for. The artwork is vector code, so each pixel size is rendered
//  natively rather than downsampled — a 16pt icon scaled down from 1024
//  turns to mush.
//
//  Usage: swift Scripts/render-app-icon.swift [output-directory]
//         (defaults to Invoices/Resources/Assets.xcassets/AppIcon.appiconset)
//
//  The design: a deep navy squircle, a cream invoice sheet with a folded
//  corner, and an amber "total" row — the one detail that says bill rather
//  than document. macOS does not mask legacy PNG icons, so the squircle and
//  its drop shadow are drawn here, inset in the canvas like every other
//  Dock icon.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Palette

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

enum Palette {
    static let navyTop = rgb(0x32457A)
    static let navyBottom = rgb(0x131B33)
    static let paper = rgb(0xFBFBF8)
    static let paperShade = rgb(0xDEDFD8)
    static let rule = rgb(0xC3C8D6)
    static let ink = rgb(0x2B3A5C)
    static let amberTop = rgb(0xFFC24D)
    static let amberBottom = rgb(0xEF9F27)
}

// MARK: - Geometry helpers

/// A superellipse — the continuous-corner shape Apple icons use. A plain
/// rounded rect reads as slightly too "boxy" next to the rest of the Dock.
func superellipse(in rect: CGRect, n: CGFloat = 5, steps: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let exponent = 2 / n
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), exponent)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), exponent)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func pill(_ rect: CGRect) -> CGPath {
    let r = min(rect.height / 2, rect.width / 2)
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

extension CGContext {
    func fill(_ path: CGPath, _ color: CGColor) {
        setFillColor(color)
        addPath(path)
        fillPath()
    }

    /// Fills a path with a vertical two-stop gradient.
    func fill(_ path: CGPath, from top: CGColor, to bottom: CGColor, in rect: CGRect) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [top, bottom] as CFArray,
                                        locations: [0, 1]) else { return }
        saveGState()
        addPath(path)
        clip()
        drawLinearGradient(gradient,
                           start: CGPoint(x: rect.midX, y: rect.minY),
                           end: CGPoint(x: rect.midX, y: rect.maxY),
                           options: [])
        restoreGState()
    }
}

// MARK: - The artwork

/// How much of the sheet's contents to draw. Fine rules disappear at small
/// sizes rather than smearing into grey fog.
enum Detail {
    case minimal   // < 48px: silhouette and the amber total only
    case medium    // 48..<128px
    case full      // >= 128px

    init(pixels: Int) {
        switch pixels {
        case ..<48: self = .minimal
        case 48..<128: self = .medium
        default: self = .full
        }
    }
}

/// Draws the icon into a 1024x1024 coordinate space with the origin at the
/// top left and y growing downwards.
func drawIcon(in ctx: CGContext, detail: Detail) {
    // The squircle sits inset in the canvas, and the margin is where the drop
    // shadow lives — macOS does not mask legacy PNG icons, so this is what
    // gives the icon the same visual weight as its neighbours in the Dock.
    // Small sizes take a tighter inset: at 16pt a proportional margin costs
    // more pixels than the artwork can spare.
    let margin: CGFloat
    switch detail {
    case .full: margin = 100
    case .medium: margin = 74
    case .minimal: margin = 44
    }
    let plate = CGRect(x: margin, y: margin * 0.88,
                       width: 1024 - 2 * margin, height: 1024 - 2 * margin)
    let platePath = superellipse(in: plate)

    if detail != .minimal {
        ctx.saveGState()
        let shadow = plate.width / 824
        ctx.setShadow(offset: CGSize(width: 0, height: 18 * shadow),
                      blur: 30 * shadow, color: rgb(0x000000, 0.24))
        ctx.fill(platePath, Palette.navyTop)
        ctx.restoreGState()
    }
    ctx.fill(platePath, from: Palette.navyTop, to: Palette.navyBottom, in: plate)

    // A soft highlight in the top-left corner keeps the flat navy from
    // looking like a printed swatch.
    if detail == .full, let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                               colors: [rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0)] as CFArray,
                                               locations: [0, 1]) {
        ctx.saveGState()
        ctx.addPath(platePath)
        ctx.clip()
        ctx.drawRadialGradient(sheen,
                               startCenter: CGPoint(x: plate.minX + 140, y: plate.minY + 90), startRadius: 0,
                               endCenter: CGPoint(x: plate.minX + 140, y: plate.minY + 90), endRadius: 760,
                               options: [])
        ctx.restoreGState()
    }

    // The sheet and its contents are laid out against the full-size plate, then
    // mapped onto whichever plate this size actually uses.
    let reference = CGRect(x: 100, y: 88, width: 824, height: 824)
    let unit = plate.width / reference.width
    ctx.saveGState()
    ctx.translateBy(x: plate.minX, y: plate.minY)
    ctx.scaleBy(x: unit, y: unit)
    ctx.translateBy(x: -reference.minX, y: -reference.minY)
    drawSheet(in: ctx, detail: detail, unit: unit)
    ctx.restoreGState()
}

/// The invoice itself, in the 1024-point design space.
private func drawSheet(in ctx: CGContext, detail: Detail, unit: CGFloat) {
    let sheet = CGRect(x: 308, y: 226, width: 408, height: 548)
    let fold: CGFloat = 112
    let sheetPath = CGMutablePath()
    sheetPath.move(to: CGPoint(x: sheet.minX, y: sheet.minY))
    sheetPath.addLine(to: CGPoint(x: sheet.maxX - fold, y: sheet.minY))
    sheetPath.addLine(to: CGPoint(x: sheet.maxX, y: sheet.minY + fold))
    sheetPath.addLine(to: CGPoint(x: sheet.maxX, y: sheet.maxY))
    sheetPath.addLine(to: CGPoint(x: sheet.minX, y: sheet.maxY))
    sheetPath.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12 * unit),
                  blur: 28 * unit, color: rgb(0x000814, 0.42))
    ctx.fill(sheetPath, Palette.paper)
    ctx.restoreGState()

    let flap = CGMutablePath()
    flap.move(to: CGPoint(x: sheet.maxX - fold, y: sheet.minY))
    flap.addLine(to: CGPoint(x: sheet.maxX, y: sheet.minY + fold))
    flap.addLine(to: CGPoint(x: sheet.maxX - fold, y: sheet.minY + fold))
    flap.closeSubpath()
    ctx.fill(flap, Palette.paperShade)

    let contentX = sheet.minX + 54
    let contentWidth = sheet.width - 108   // 300

    // The total row: the whole point of the icon, and the only content that
    // survives at 16pt.
    let totalHeight: CGFloat = detail == .minimal ? 80 : 54
    let totalY = sheet.maxY - (detail == .minimal ? 212 : 152)
    let amber = CGRect(x: detail == .minimal ? contentX : contentX + 136,
                       y: totalY,
                       width: detail == .minimal ? contentWidth : 164,
                       height: totalHeight)
    ctx.fill(pill(amber), from: Palette.amberTop, to: Palette.amberBottom, in: amber)

    guard detail != .minimal else { return }

    ctx.fill(pill(CGRect(x: contentX, y: totalY, width: 124, height: totalHeight)), Palette.ink)

    // Header block — stands in for the business name at the top of the invoice.
    ctx.fill(pill(CGRect(x: contentX, y: sheet.minY + 72, width: 152, height: 30)), Palette.ink)

    // Line items: a label on the left, an amount on the right.
    let rows: [CGFloat] = detail == .full ? [366, 430, 494] : [376, 452]
    for y in rows {
        ctx.fill(pill(CGRect(x: contentX, y: y, width: 172, height: 22)), Palette.rule)
        if detail == .full {
            ctx.fill(pill(CGRect(x: contentX + contentWidth - 78, y: y, width: 78, height: 22)), Palette.rule)
        }
    }
}

// MARK: - Rendering

func render(pixels: Int) -> Data {
    guard let ctx = CGContext(data: nil,
                              width: pixels, height: pixels,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("could not create a \(pixels)px bitmap context")
    }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // Flip to a top-left origin, then work in 1024-point design coordinates.
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: 1, y: -1)
    let unit = CGFloat(pixels) / 1024
    ctx.scaleBy(x: unit, y: unit)

    drawIcon(in: ctx, detail: Detail(pixels: pixels))

    guard let image = ctx.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fatalError("could not encode the \(pixels)px icon")
    }
    return png
}

let defaultOutput = "Invoices/Resources/Assets.xcassets/AppIcon.appiconset"
let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultOutput
let output = URL(fileURLWithPath: outputDirectory, isDirectory: true)
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// name -> pixel size. 32, 256 and 512 appear twice; each is rendered once.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

var cache: [Int: Data] = [:]
for variant in variants {
    let png = cache[variant.pixels] ?? render(pixels: variant.pixels)
    cache[variant.pixels] = png
    let file = output.appendingPathComponent("\(variant.name).png")
    try png.write(to: file)
    print("\(variant.name).png  \(variant.pixels)x\(variant.pixels)  \(png.count) bytes")
}
