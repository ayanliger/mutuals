// Draws the app icon: two overlapping circles, the people you follow and the
// people who follow you, with the part that isn't mutual filled in.
//
// Usage: swift scripts/make-icon.swift Mutuals/Assets.xcassets/AppIcon.appiconset

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: space,
        components: [CGFloat(hex >> 16 & 0xFF) / 255, CGFloat(hex >> 8 & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha]
    )!
}

func draw(background: CGColor?, fill: CGColor, stroke: CGColor, name: String) {
    let size = 1024
    let alpha = background == nil ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: alpha.rawValue)!
    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    if let background {
        context.setFillColor(background)
        context.fill(canvas)
    }

    let radius: CGFloat = 250
    let offset: CGFloat = 125
    let following = CGRect(x: 512 - offset - radius, y: 512 - radius, width: radius * 2, height: radius * 2)
    let followers = CGRect(x: 512 + offset - radius, y: 512 - radius, width: radius * 2, height: radius * 2)

    // Fill "following" everywhere outside "followers".
    context.saveGState()
    context.addRect(canvas)
    context.addEllipse(in: followers)
    context.clip(using: .evenOdd)
    context.setFillColor(fill)
    context.fillEllipse(in: following)
    context.restoreGState()

    context.setStrokeColor(stroke)
    context.setLineWidth(26)
    context.strokeEllipse(in: following)
    context.strokeEllipse(in: followers)

    let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

draw(background: color(0xF3EFE6), fill: color(0x2F6B57), stroke: color(0x1F2A26), name: "AppIcon.png")
draw(background: nil, fill: color(0x7CC4A6), stroke: color(0xE8E4DA), name: "AppIcon-dark.png")
draw(background: nil, fill: color(0xFFFFFF), stroke: color(0xA0A0A0), name: "AppIcon-tinted.png")
