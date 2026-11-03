// 生成应用图标：深色圆角底 + 刻着 ¥ 的像素金币 + 两颗闪光。
// 用法：swift macos/tools/make-icon.swift build/AppIcon.iconset
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let coin = [
    ".....NNNNNN.....",
    "...NNYYYYyyNN...",
    "..NYYyyyyyyyoN..",
    ".NYyyyyyyyyyyoN.",
    ".NYyyyyyyyyyyoN.",
    "NYyyyyyyyyyyyyoN",
    "NYyyyyyyyyyyyyoN",
    "NyyyyyyyyyyyyyoN",
    "NyyyyyyyyyyyyyoN",
    "NyyyyyyyyyyyyyoN",
    "NyyyyyyyyyyyyooN",
    ".NyyyyyyyyyyyoN.",
    ".NyyyyyyyyyyooN.",
    "..NoyyyyyyyooN..",
    "...NNooooooNN...",
    ".....NNNNNN.....",
]
let yen = ["##..##", "##..##", ".####.", "..##..", "######", "..##..", "######", "..##..", "..##.."]
let sparkle = ["..#..", "..#..", "##Y##", "..#..", "..#.."]
let pal: [Character: UInt32] = [
    "N": 0x7A4A12, "Y": 0xFFF0B3, "y": 0xFFC83D, "o": 0xE08A1E,
    "#": 0xFFE27A, "E": 0xB8661A, "H": 0xFFF6D5,
]

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let s = CGFloat(px) / 1024

    // 圆角底（按 macOS 图标模板：1024 画布里 824 的圆角方块）
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    color(0x2A2639).setFill()
    NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s).fill()
    color(0x3D3756).setFill()
    NSBezierPath(roundedRect: tile.insetBy(dx: 24 * s, dy: 24 * s), xRadius: 165 * s, yRadius: 165 * s).fill()
    color(0x2A2639).setFill()
    NSBezierPath(roundedRect: tile.insetBy(dx: 24 * s, dy: 24 * s).offsetBy(dx: 0, dy: -10 * s),
                 xRadius: 165 * s, yRadius: 165 * s).fill()

    // 像素部分：每格 32（1024 画布）
    ctx.shouldAntialias = false
    let unit = 32 * s
    func cell(_ gx: Int, _ gy: Int, _ hex: UInt32) {
        color(hex).setFill()
        // 画布 y 向上，网格 y 向下
        NSRect(x: CGFloat(gx) * unit, y: CGFloat(px) - CGFloat(gy + 1) * unit, width: unit, height: unit).fill()
    }
    let ox = 8, oy = 8 // 金币放在 32×32 网格中间
    for (r, row) in coin.enumerated() {
        for (c, ch) in row.enumerated() where ch != "." { cell(ox + c, oy + r, pal[ch]!) }
    }
    for (r, row) in yen.enumerated() { // 刻字：深色笔画，下方一行高光
        for (c, ch) in row.enumerated() where ch == "#" {
            cell(ox + 5 + c, oy + 3 + r, pal["E"]!)
            let below = r + 1 < yen.count ? Array(yen[r + 1])[c] : "."
            if below != "#" { cell(ox + 5 + c, oy + 4 + r, pal["H"]!) }
        }
    }
    for (sx, sy) in [(23, 5), (5, 21)] {
        for (r, row) in sparkle.enumerated() {
            for (c, ch) in row.enumerated() where ch != "." { cell(sx + c, sy + r, ch == "Y" ? 0xFFFFFF : 0xFFE27A) }
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(px).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(name).png"))
}
print("图标已生成：\(outDir)")
