// Draws the notifier's app icon (1024px PNG) so the repo carries no binary asset:
// a dark rounded square with an amber bolt.   swift icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

// macOS icon grid: 824px body centred in 1024, corner radius ~185.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.22, alpha: 1),
                    NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.09, alpha: 1)])!
    .draw(in: shape, angle: -90)

let cfg = NSImage.SymbolConfiguration(pointSize: 520, weight: .bold)
if let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let tinted = NSImage(size: bolt.size, flipped: false) { r in
        bolt.draw(in: r)
        NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.16, alpha: 1).set()
        r.fill(using: .sourceAtop)
        return true
    }
    let s = tinted.size
    tinted.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}
img.unlockFocus()

guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
