// Renders each emoji argument to <outdir>/<index>.png with Apple Color Emoji.
// PIL can't shape flag sequences without raqm, so the hero composer uses these.
// Usage: swift render_emoji.swift <outdir> 🇬🇧 🇧🇷 ...
import AppKit
let args = CommandLine.arguments
let out = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (i, emoji) in args.dropFirst(2).enumerated() {
    let str = NSAttributedString(string: emoji, attributes: [.font: NSFont(name: "Apple Color Emoji", size: 160)!])
    let size = str.size()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    str.draw(at: .zero)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(i).png"))
}
