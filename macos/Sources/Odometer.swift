// 机械里程表式的滚轮金额。
// 最低位连续转动；高位只在低一位从 9 转向 0 的那一段跟着进位。位移吸附到像素网格，看起来一格一格地滚。
import AppKit

final class Odometer {
    static let pitch = 12 // 滚轮上相邻两个数字的距离：9 行字形 + 3 行空隙
    static let cellHeight = 10 // 可见窗口：9 行字形 + 1 行阴影
    static let gap = 2

    enum Kind {
        case symbol(Character, litFrom: Int?) // litFrom：数值达到 10^n 才点亮（千分位逗号）
        case digit(place: Int) // 10 的几次方：个位 0，小数第一位 -1
    }

    struct Cell {
        let kind: Kind
        let x: Int
        let width: Int
    }

    private(set) var cells: [Cell] = []
    private(set) var logicalWidth = 0
    private var key = ""
    private var strips: [Glyphs.Style: CGImage] = [:]
    private var symbols: [String: CGImage] = [:]

    /// 整数位数按"今天最多能赚到多少"固定，从 0 涨到满勤时宽度不跳；没走到的高位显示成暗色 0。
    func layout(currency: String, intDigits: Int, decimals: Int) {
        let newKey = "\(currency)|\(intDigits)|\(decimals)"
        guard newKey != key else { return }
        key = newKey
        var out: [Cell] = []
        var x = 0
        func push(_ kind: Kind, _ width: Int, extra: Int = 0) {
            out.append(Cell(kind: kind, x: x, width: width))
            x += width + Odometer.gap + extra
        }
        let cur = Character(currency)
        push(.symbol(cur, litFrom: nil), Glyphs.width(cur), extra: 2)
        for k in stride(from: max(1, intDigits) - 1, through: 0, by: -1) {
            push(.digit(place: k), 6)
            if k > 0 && k % 3 == 0 { push(.symbol(",", litFrom: k), 3) }
        }
        push(.symbol(".", litFrom: nil), 2)
        for j in 1...max(1, decimals) { push(.digit(place: -j), 6) }
        cells = out
        logicalWidth = x - Odometer.gap + 1
    }

    func size(scale: CGFloat) -> CGSize {
        CGSize(width: CGFloat(logicalWidth) * scale, height: CGFloat(Odometer.cellHeight) * scale)
    }

    /// speed：数值每秒涨多少（静止时传 0，各位对齐到整数字）。rolling = false（减少动态效果）时也不滚。
    func draw(in ctx: CGContext, at origin: CGPoint, scale s: CGFloat, value: Double, decimals: Int,
              speed: Double, flash: Bool, rolling: Bool) {
        let v = max(0, value)
        let moving = rolling && speed > 0
        let highest = cells.reduce(0) { m, c in
            if case .digit(let p) = c.kind { return max(m, p) }
            return m
        }

        // 从最低位往上算每个轮子的位置（0..<10 的连续值）
        var positions: [Int: Double] = [:]
        var carry = 0.0
        for place in (-decimals)...highest {
            let x = v * pow(10, Double(-place)) * (1 + 1e-12) + 1e-9
            let digit = floor(x).truncatingRemainder(dividingBy: 10)
            let pos = place == -decimals && moving ? x.truncatingRemainder(dividingBy: 10) : digit + carry
            // 每秒转过 12 个数以上的轮子不画半格、直接跳字，不然一帧里全是字形碎片
            positions[place] = speed / pow(10, Double(place)) > 12 ? floor(pos) : pos
            carry = moving && pos > 9 ? pos - 9 : 0
        }

        for cell in cells {
            let rect = CGRect(x: origin.x + CGFloat(cell.x) * s, y: origin.y,
                              width: CGFloat(cell.width + 1) * s, height: CGFloat(Odometer.cellHeight) * s)
            switch cell.kind {
            case let .symbol(ch, litFrom):
                let lit = litFrom.map { v >= pow(10, Double($0)) } ?? true
                let img = symbol(ch, flash ? .flash : lit ? .gold : .dim)
                ctx.drawPixels(img, in: CGRect(x: rect.minX, y: rect.minY,
                                               width: CGFloat(img.width) * s, height: CGFloat(img.height) * s))
            case let .digit(place):
                let pos = positions[place] ?? 0
                let d = Int(floor(pos)) % 10
                let offset = Int(floor((pos - floor(pos)) * Double(Odometer.pitch)))
                let lit = place <= 0 || v >= pow(10, Double(place))
                let style: Glyphs.Style = flash ? .flash : !lit ? .dim : place < -2 ? .copper : .gold
                let img = strip(style)
                ctx.saveGState()
                ctx.clip(to: rect)
                ctx.drawPixels(img, in: CGRect(x: rect.minX, y: rect.minY - CGFloat(d * Odometer.pitch + offset) * s,
                                               width: CGFloat(img.width) * s, height: CGFloat(img.height) * s))
                ctx.restoreGState()
            }
        }
    }

    // 0…9 再接一个 0 的竖条，滚动时从里面截一段
    private func strip(_ style: Glyphs.Style) -> CGImage {
        if let img = strips[style] { return img }
        var bmp = PixelBitmap(width: 7, height: Odometer.pitch * 11)
        for i in 0...10 {
            Glyphs.draw(Character(String(i % 10)), into: &bmp, x: 0, y: i * Odometer.pitch, style: style)
        }
        let img = bmp.image()
        strips[style] = img
        return img
    }

    private func symbol(_ ch: Character, _ style: Glyphs.Style) -> CGImage {
        let k = "\(ch)-\(style.bands[1])"
        if let img = symbols[k] { return img }
        var bmp = PixelBitmap(width: Glyphs.width(ch) + 1, height: Odometer.cellHeight)
        Glyphs.draw(ch, into: &bmp, x: 0, y: 0, style: style)
        let img = bmp.image()
        symbols[k] = img
        return img
    }
}
