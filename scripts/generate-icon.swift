#!/usr/bin/env swift

import AppKit
import Foundation

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let supportDir = root.appendingPathComponent(".build-support", isDirectory: true)
let packagingDir = supportDir.appendingPathComponent("packaging", isDirectory: true)
let iconsetDir = packagingDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let outputICNS = packagingDir.appendingPathComponent("AppIcon.icns", isDirectory: false)

if fileManager.fileExists(atPath: iconsetDir.path(percentEncoded: false)) {
    try fileManager.removeItem(at: iconsetDir)
}
if fileManager.fileExists(atPath: outputICNS.path(percentEncoded: false)) {
    try fileManager.removeItem(at: outputICNS)
}

try fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (fileName, size) in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let context = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    context.setFillColor(NSColor.clear.cgColor)
    context.fill(rect)

    let inset = size * 0.11
    let roundedRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = size * 0.21
    let path = NSBezierPath(roundedRect: roundedRect, xRadius: radius, yRadius: radius)

    NSColor(calibratedRed: 243/255, green: 238/255, blue: 229/255, alpha: 1).setFill()
    path.fill()

    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.02)
    shadow.shadowBlurRadius = size * 0.08
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.10)
    shadow.set()
    path.fill()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let fontSize = size * 0.50
    let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 43/255, green: 39/255, blue: 35/255, alpha: 1),
        .paragraphStyle: paragraph
    ]

    let text = NSString(string: "问")
    let textSize = text.size(withAttributes: attributes)
    let textRect = CGRect(
        x: (size - textSize.width) / 2,
        y: (size - textSize.height) / 2 - size * 0.04,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: textRect, withAttributes: attributes)

    image.unlockFocus()

    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "IconGeneration", code: 1)
    }

    try pngData.write(to: iconsetDir.appendingPathComponent(fileName), options: .atomic)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "--convert", "icns",
    iconsetDir.path(percentEncoded: false),
    "--output", outputICNS.path(percentEncoded: false)
]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "IconGeneration", code: Int(process.terminationStatus))
}

print(outputICNS.path(percentEncoded: false))
