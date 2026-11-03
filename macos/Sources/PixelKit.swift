// 像素绘制的基础件：调色板、位图、缺角边框、像素字体、粗体数字字形。
import AppKit
import CoreText

// MARK: - 调色板

enum Pal {
    static let ink: UInt32 = 0x14121C
    static let panel: UInt32 = 0x2A2639
    static let panelHi: UInt32 = 0x3D3756
    static let panelLo: UInt32 = 0x1C1927
    static let text: UInt32 = 0xF1ECF7
    static let muted: UInt32 = 0xA39CBA
    static let faint: UInt32 = 0x6F6889
    static let gold: UInt32 = 0xFFC83D
    static let goldHi: UInt32 = 0xFFF0B3
    static let goldLo: UInt32 = 0xE08A1E
    static let red: UInt32 = 0xE2463F
    static let green: UInt32 = 0x7BD66A
    static let greenHi: UInt32 = 0xC4F5B4
    static let greenLo: UInt32 = 0x3F9A45
    static let sky: UInt32 = 0x63B6EC
    static let lilac: UInt32 = 0xB896E6
    static let cyan: UInt32 = 0x73EFF7
    static let paper: UInt32 = 0xF3EAD3
    static let paperInk: UInt32 = 0x3A2F2A
    static let paperLine: UInt32 = 0xC4B38C
    static let paperFaint: UInt32 = 0x8A7B62

    static func status(_ s: PaySnapshot.Status, fishing: Bool = false) -> UInt32 {
        if fishing && s == .working { return cyan }
        switch s {
        case .working: return green
        case .lunch: return sky
        case .after: return gold
        case .off: return lilac
        case .setup: return red
        case .before: return muted
        }
    }
}

func cgColor(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func nsColor(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(cgColor: cgColor(hex, alpha)) ?? .white
}

// MARK: - 位图：用字符串画像素画，再整体放大绘制

struct PixelBitmap {
    let width: Int
    let height: Int
    private var bytes: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
    }

    mutating func set(_ x: Int, _ y: Int, _ hex: UInt32) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let i = (y * width + x) * 4
        bytes[i] = UInt8(hex >> 16 & 0xFF)
        bytes[i + 1] = UInt8(hex >> 8 & 0xFF)
        bytes[i + 2] = UInt8(hex & 0xFF)
        bytes[i + 3] = 255
    }

    mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ hex: UInt32) {
        for yy in y..<(y + h) { for xx in x..<(x + w) { set(xx, yy, hex) } }
    }

    /// 把字符串像素画贴到 (x, y)。'.' 和空格是透明。
    mutating func blit(_ art: [String], _ x: Int, _ y: Int, _ palette: [Character: UInt32]) {
        for (r, row) in art.enumerated() {
            for (c, ch) in row.enumerated() where ch != "." && ch != " " {
                if let hex = palette[ch] { set(x + c, y + r, hex) }
            }
        }
    }

    func image() -> CGImage {
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}

extension CGContext {
    func fill(_ hex: UInt32, _ r: CGRect, alpha: CGFloat = 1) {
        setFillColor(cgColor(hex, alpha))
        fill(r)
    }

    /// 在翻转坐标（左上角原点）的视图里按最近邻放大画位图。
    func drawPixels(_ img: CGImage, in r: CGRect) {
        saveGState()
        interpolationQuality = .none
        translateBy(x: r.minX, y: r.maxY)
        scaleBy(x: 1, y: -1)
        draw(img, in: CGRect(origin: .zero, size: r.size))
        restoreGState()
    }

    /// 四边粗 t、四角缺口的像素边框（画在 r 的内侧）。
    func pixelFrame(_ r: CGRect, _ t: CGFloat, _ hex: UInt32, alpha: CGFloat = 1) {
        fill(hex, CGRect(x: r.minX + t, y: r.minY, width: r.width - 2 * t, height: t), alpha: alpha)
        fill(hex, CGRect(x: r.minX + t, y: r.maxY - t, width: r.width - 2 * t, height: t), alpha: alpha)
        fill(hex, CGRect(x: r.minX, y: r.minY + t, width: t, height: r.height - 2 * t), alpha: alpha)
        fill(hex, CGRect(x: r.maxX - t, y: r.minY + t, width: t, height: r.height - 2 * t), alpha: alpha)
    }

    /// 四角各缺一格的实心块。
    func pixelBlock(_ r: CGRect, _ t: CGFloat, _ hex: UInt32, alpha: CGFloat = 1) {
        fill(hex, r.insetBy(dx: t, dy: 0), alpha: alpha)
        fill(hex, CGRect(x: r.minX, y: r.minY + t, width: t, height: r.height - 2 * t), alpha: alpha)
        fill(hex, CGRect(x: r.maxX - t, y: r.minY + t, width: t, height: r.height - 2 * t), alpha: alpha)
    }
}

// MARK: - 像素字体（缝合像素字体 12px，OFL-1.1）

@MainActor
enum PixelFont {
    private static let base: NSFont? = {
        guard let url = Bundle.main.url(forResource: "fusion-pixel-12px-monospaced-zh_hans", withExtension: "otf",
                                        subdirectory: "Fonts") ?? Bundle.main.url(
                                            forResource: "fusion-pixel-12px-monospaced-zh_hans", withExtension: "otf")
        else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let desc = descs.first else { return nil }
        return CTFontCreateWithFontDescriptor(desc, 12, nil) as NSFont
    }()

    static var isLoaded: Bool { base != nil }
    private static var cache: [CGFloat: NSFont] = [:]

    /// 只用 12 的整数倍字号，笔画才锐利。
    static func font(_ size: CGFloat = 12) -> NSFont {
        if let f = cache[size] { return f }
        let f = base.flatMap { NSFont(descriptor: $0.fontDescriptor, size: size) }
            ?? .monospacedSystemFont(ofSize: size * 0.9, weight: .regular)
        cache[size] = f
        return f
    }

    static func attrs(_ hex: UInt32, size: CGFloat = 12) -> [NSAttributedString.Key: Any] {
        [.font: font(size), .foregroundColor: nsColor(hex)]
    }

    /// 等宽像素字体：汉字 12，ASCII 6（12pt 时）。
    static func width(_ s: String, size: CGFloat = 12) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: font(size)]).width)
    }

    static func draw(_ s: String, at p: CGPoint, color: UInt32, size: CGFloat = 12) {
        (s as NSString).draw(at: CGPoint(x: p.x.rounded(), y: p.y.rounded()), withAttributes: attrs(color, size: size))
    }

    /// 带 1 像素描边的字（飘字用）。
    static func drawOutlined(_ s: String, at p: CGPoint, color: UInt32, outline: UInt32 = Pal.ink) {
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (1, 1)] {
            draw(s, at: CGPoint(x: p.x + CGFloat(dx), y: p.y + CGFloat(dy)), color: outline)
        }
        draw(s, at: p, color: color)
    }
}

// MARK: - 粗体像素数字（6×9）

enum Glyphs {
    static let height = 9
    static let big: [Character: [String]] = [
        "0": [".####.", "##..##", "##..##", "##..##", "##..##", "##..##", "##..##", "##..##", ".####."],
        "1": ["..##..", ".###..", "####..", "..##..", "..##..", "..##..", "..##..", "..##..", "######"],
        "2": [".####.", "##..##", "....##", "....##", "...##.", "..##..", ".##...", "##....", "######"],
        "3": [".####.", "##..##", "....##", "....##", "..###.", "....##", "....##", "##..##", ".####."],
        "4": ["....##", "...###", "..####", ".##.##", "##..##", "######", "....##", "....##", "....##"],
        "5": ["######", "##....", "##....", "#####.", "....##", "....##", "....##", "##..##", ".####."],
        "6": ["..###.", ".##...", "##....", "#####.", "##..##", "##..##", "##..##", "##..##", ".####."],
        "7": ["######", "....##", "....##", "...##.", "...##.", "..##..", "..##..", "..##..", "..##.."],
        "8": [".####.", "##..##", "##..##", "##..##", ".####.", "##..##", "##..##", "##..##", ".####."],
        "9": [".####.", "##..##", "##..##", "##..##", ".#####", "....##", "....##", "...##.", ".###.."],
        "¥": ["##..##", "##..##", ".####.", "..##..", "######", "..##..", "######", "..##..", "..##.."],
        "$": ["...#..", ".#####", "##.#..", "##.#..", ".####.", "...###", "...###", "#####.", "...#.."],
        "€": ["..####", ".##...", "##....", "#####.", "##....", "#####.", "##....", ".##...", "..####"],
        "£": ["..###.", ".##.##", ".##...", ".##...", "####..", ".##...", ".##...", ".##...", "######"],
        ".": ["..", "..", "..", "..", "..", "..", "..", "##", "##"],
        ",": ["...", "...", "...", "...", "...", "...", ".##", ".##", "##."],
    ]

    /// 三段竖向渐变 + 1 像素阴影。
    struct Style: Hashable {
        let bands: [UInt32]
        let shadow: UInt32?
        static let gold = Style(bands: [Pal.goldHi, Pal.gold, Pal.goldLo], shadow: Pal.ink)
        static let copper = Style(bands: [0xFFD0A8, 0xFF9A5C, 0xD8603A], shadow: Pal.ink)
        static let dim = Style(bands: [0x3A3550, 0x3A3550, 0x3A3550], shadow: nil)
        static let flash = Style(bands: [0xFFFFFF, 0xFFF8E0, 0xFFE89A], shadow: Pal.ink)
    }

    static func width(_ ch: Character) -> Int { big[ch]?.first?.count ?? 6 }

    static func draw(_ ch: Character, into bmp: inout PixelBitmap, x: Int, y: Int, style: Style) {
        guard let rows = big[ch] else { return }
        if let shadow = style.shadow {
            for (r, row) in rows.enumerated() { for (c, p) in row.enumerated() where p == "#" { bmp.set(x + c + 1, y + r + 1, shadow) } }
        }
        for (r, row) in rows.enumerated() {
            let band = style.bands[r < 3 ? 0 : r < 6 ? 1 : 2]
            for (c, p) in row.enumerated() where p == "#" { bmp.set(x + c, y + r, band) }
        }
    }

    // 3×5 小数字（墙上日历等）
    static let tiny: [Character: [String]] = [
        "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
        "2": ["###", "..#", "###", "#..", "###"], "3": ["###", "..#", "###", "..#", "###"],
        "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "###", "..#", "###"],
        "6": ["###", "#..", "###", "#.#", "###"], "7": ["###", "..#", "..#", "..#", "..#"],
        "8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "###"],
    ]
}
