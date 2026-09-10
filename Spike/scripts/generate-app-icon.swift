// Run from the repository root with: swift Spike/scripts/generate-app-icon.swift
// Original geometric artwork; no fonts or third-party image assets.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
// Quartz supports a 32-bit RGB drawing context with an unused fourth component.
// A 24-bit NSBitmapImageRep cannot provide the drawing context needed here.
guard let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { throw CocoaError(.coderInvalidValue) }
context.setFillColor(CGColor(red: 0.055, green: 0.09, blue: 0.14, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setStrokeColor(CGColor(red: 0.29, green: 0.88, blue: 0.75, alpha: 1))
context.setLineWidth(62)
context.setLineCap(.round)
context.setLineJoin(.round)
context.move(to: CGPoint(x: 270, y: 650))
context.addLine(to: CGPoint(x: 440, y: 512))
context.addLine(to: CGPoint(x: 270, y: 374))
context.strokePath()
context.move(to: CGPoint(x: 550, y: 374))
context.addLine(to: CGPoint(x: 754, y: 374))
context.strokePath()
let output = URL(fileURLWithPath: "Spike/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
guard let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)
else { throw CocoaError(.fileWriteUnknown) }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
