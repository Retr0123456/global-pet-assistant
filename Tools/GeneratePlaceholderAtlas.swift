import AppKit

let outputPath = CommandLine.arguments.dropFirst().first
    ?? "Sources/GlobalPetAssistant/Resources/SamplePets/placeholder/spritesheet.png"

let atlasWidth = 1536
let atlasHeight = 1872
let columns = 8
let rows = 9
let cellWidth = 192
let cellHeight = 208

let rowNames = [
    "idle",
    "running-right",
    "running-left",
    "waving",
    "jumping",
    "failed",
    "waiting",
    "running",
    "review"
]

let colors: [NSColor] = [
    .systemTeal,
    .systemBlue,
    .systemIndigo,
    .systemGreen,
    .systemPurple,
    .systemRed,
    .systemOrange,
    .systemMint,
    .systemPink
]

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: atlasWidth,
    pixelsHigh: atlasHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Failed to allocate placeholder atlas bitmap.")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: atlasWidth, height: atlasHeight).fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph
]

for row in 0..<rows {
    for column in 0..<columns {
        let x = column * cellWidth
        let y = atlasHeight - ((row + 1) * cellHeight)
        let cell = NSRect(x: x, y: y, width: cellWidth, height: cellHeight)

        colors[row].withAlphaComponent(0.18).setFill()
        cell.fill()

        let bodyInset = CGFloat(28 + ((column % 3) * 4))
        let body = cell.insetBy(dx: bodyInset, dy: 32)
        colors[row].setFill()
        NSBezierPath(ovalIn: body).fill()

        NSColor.white.withAlphaComponent(0.90).setFill()
        NSBezierPath(ovalIn: NSRect(x: body.midX - 32, y: body.midY + 18, width: 18, height: 18)).fill()
        NSBezierPath(ovalIn: NSRect(x: body.midX + 14, y: body.midY + 18, width: 18, height: 18)).fill()

        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(ovalIn: NSRect(x: body.midX - 26, y: body.midY + 23, width: 8, height: 8)).fill()
        NSBezierPath(ovalIn: NSRect(x: body.midX + 20, y: body.midY + 23, width: 8, height: 8)).fill()

        let label = "\(rowNames[row]) \(column)"
        label.draw(
            in: NSRect(x: cell.minX + 8, y: cell.minY + 10, width: cell.width - 16, height: 22),
            withAttributes: attributes
        )
    }
}

NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to render placeholder atlas.")
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try data.write(to: outputURL)
print(outputURL.path)
