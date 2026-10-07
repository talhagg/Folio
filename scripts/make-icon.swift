// Folio uygulama simgesini üretir: swift scripts/make-icon.swift <çıktı-klasörü>
// macOS simge şablonu: 1024 tuval, 824'lük squircle 100 pt kenar boşluklu.
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: size / 1024, y: size / 1024)

    // Zemin: squircle + gölge + dikey gradyan (accent tonları).
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = rounded(body, 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    color(0x1F6F5C).setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()
    NSGradient(colors: [color(0x2C8771), color(0x1F6F5C), color(0x16503F)])!
        .draw(in: body, angle: -90)
    // Üstte ince ışık.
    NSGradient(colors: [color(0xFFFFFF, 0.14), color(0xFFFFFF, 0)])!
        .draw(in: CGRect(x: 100, y: 620, width: 824, height: 304), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Sayfa
    let page = CGRect(x: 257, y: 186, width: 510, height: 612)
    NSGraphicsContext.saveGraphicsState()
    let pageShadow = NSShadow()
    pageShadow.shadowColor = color(0x0B2A22, 0.45)
    pageShadow.shadowBlurRadius = 36
    pageShadow.shadowOffset = NSSize(width: 0, height: -14)
    pageShadow.set()
    color(0xF6F5F2).setFill()
    rounded(page, 40).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Ayraç (kil)
    let ribbon = NSBezierPath()
    ribbon.move(to: CGPoint(x: 648, y: 818))
    ribbon.line(to: CGPoint(x: 712, y: 818))
    ribbon.line(to: CGPoint(x: 712, y: 650))
    ribbon.line(to: CGPoint(x: 680, y: 676))
    ribbon.line(to: CGPoint(x: 648, y: 650))
    ribbon.close()
    color(0xC2410C).setFill()
    ribbon.fill()
    color(0x9A330A).setFill()
    NSBezierPath(rect: CGRect(x: 648, y: 798, width: 64, height: 20)).fill()

    let left: CGFloat = 317
    // Başlık
    color(0x1E1C19).setFill()
    rounded(CGRect(x: left, y: 690, width: 270, height: 42), 21).fill()
    // Metin satırları
    color(0xCFCAC0).setFill()
    rounded(CGRect(x: left, y: 618, width: 390, height: 24), 12).fill()
    rounded(CGRect(x: left, y: 570, width: 300, height: 24), 12).fill()

    // Görevler: işaretli + işaretsiz
    let box: CGFloat = 40
    let checked = CGRect(x: left, y: 466, width: box, height: box)
    color(0x1F6F5C).setFill()
    rounded(checked, 10).fill()
    let tick = NSBezierPath()
    tick.move(to: CGPoint(x: checked.minX + 10, y: checked.midY + 1))
    tick.line(to: CGPoint(x: checked.minX + 17, y: checked.minY + 12))
    tick.line(to: CGPoint(x: checked.maxX - 9, y: checked.maxY - 11))
    tick.lineWidth = 6
    tick.lineCapStyle = .round
    tick.lineJoinStyle = .round
    color(0xFFFFFF).setStroke()
    tick.stroke()
    color(0xB9B3A8).setFill()
    rounded(CGRect(x: left + 62, y: 474, width: 250, height: 24), 12).fill()

    let unchecked = CGRect(x: left + 3, y: 395, width: box - 6, height: box - 6)
    let uncheckedPath = rounded(unchecked, 8)
    uncheckedPath.lineWidth = 6
    color(0x8F8A81).setStroke()
    uncheckedPath.stroke()
    color(0xCFCAC0).setFill()
    rounded(CGRect(x: left + 62, y: 400, width: 200, height: 24), 12).fill()

    // İlerleme çubuğu
    let track = CGRect(x: left, y: 272, width: 390, height: 32)
    color(0xE3E0D9).setFill()
    rounded(track, 16).fill()
    color(0x1F6F5C).setFill()
    rounded(CGRect(x: track.minX, y: track.minY, width: track.width * 0.62, height: track.height), 16).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let output = CommandLine.arguments.dropFirst().first ?? "."
let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (points, scale) in sizes {
    let pixels = points * scale
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    let data = drawIcon(size: CGFloat(pixels)).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
    images.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: URL(fileURLWithPath: output).appendingPathComponent("Contents.json"))
print("Simge üretildi: \(output)")
