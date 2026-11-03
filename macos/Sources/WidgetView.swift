// 悬浮窗的绘制与鼠标交互。所有东西都按像素网格画：边框/进度条 2pt 一格，
// 小办公室 2–3pt 一格，大数字 2–4pt 一格，文字用 12pt 像素字体。
import AppKit

struct Confetti {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var color: UInt32
}

struct FloatText {
    var text: String
    var x: Double
    var y: Double
    var age: Double = 0
    var life: Double = 1.4
    var color: UInt32 = Pal.gold
}

/// 一帧要画的全部内容，由 WidgetController 每次 tick 生成。
struct WidgetState {
    var settings = PaySettings()
    var snap: PaySnapshot?
    var size: WidgetSize = .medium
    var receipt: Double = 0 // 工资条拉出来的比例
    var fishing = false
    var fishEarned: Double = 0
    var tip = ""
    var diorama = DioramaInput(pose: .absent, hour: 12, jarLevel: 0, t: 0)
    var flash = false
    var confetti: [Confetti] = []
    var floaters: [FloatText] = []
    var locked = false
    var reducedMotion = false

    private func money(_ v: Double, _ dec: Int = 2) -> String { PayCore.formatMoney(v, settings, decimals: dec) }

    var chip: (text: String, color: UInt32) {
        guard let snap else { return (L10n.t(settings.language, "待设置", "Set up"), Pal.red) }
        if fishing && snap.status == .working { return (L10n.t(settings.language, "摸鱼中", "Slacking"), Pal.cyan) }
        return (PayCore.statusText(snap.status, settings.language), Pal.status(snap.status))
    }

    /// 状态行右侧：(灰色说明, 亮色数值)
    var right: (label: String, value: String) {
        let lang = settings.language
        guard let snap else { return ("", L10n.t(lang, "右键 › 设置", "Right-click › Settings")) }
        switch snap.status {
        case .working: return (L10n.t(lang, "距下班 ", "Off in "), PayCore.formatClock(snap.countdown))
        case .lunch: return (L10n.t(lang, "距开工 ", "Back in "), PayCore.formatClock(snap.countdown))
        case .before: return (L10n.t(lang, "距上班 ", "Start in "), PayCore.formatClock(snap.countdown))
        case .after:
            return snap.nextStart.map {
                lang == .en ? ("", $0.label) : ("", $0.label + " 上班")
            } ?? ("", L10n.t(lang, "收工", "Done"))
        case .off: return ("", L10n.t(lang, "本月已赚", "This month"))
        case .setup: return ("", L10n.t(lang, "右键 › 设置", "Right-click › Settings"))
        }
    }

    /// 休息日大数字显示本月已赚，其余时候显示今日已赚。
    var counterValue: Double {
        guard let snap else { return 0 }
        return snap.status == .off ? snap.monthEarned : snap.earnedToday
    }

    /// 只有上班中金额才在涨；其余时候计数器静止。
    var counterSpeed: Double {
        guard let snap, snap.status == .working else { return 0 }
        return snap.rate
    }

    /// 整数位按今天（休息日按本月）最多能赚到的钱固定，涨的过程中宽度不变。
    var intDigits: Int {
        guard let snap else { return 1 }
        let top = max(snap.status == .off ? snap.monthFull : snap.dailyPay, counterValue)
        return max(1, String(Int(top.rounded(.down))).count)
    }

    var barProgress: Double {
        guard let snap, snap.status != .setup else { return 0 }
        if snap.status == .off { return snap.monthFull > 0 ? snap.monthEarned / snap.monthFull : 0 }
        return snap.progress
    }

    var barColors: (base: UInt32, hi: UInt32) {
        guard let snap else { return (Pal.faint, Pal.muted) }
        if fishing && snap.status == .working { return (Pal.cyan, 0xD2FBFD) }
        switch snap.status {
        case .lunch: return (Pal.sky, 0xB8E2FA)
        case .after: return (Pal.gold, Pal.goldHi)
        case .off: return (Pal.lilac, 0xE2D2F7)
        default: return (Pal.green, Pal.greenHi)
        }
    }

    var receiptRows: [(String, String)] {
        let lang = settings.language
        guard let snap else { return [(L10n.t(lang, "先设置工资", "Set salary first"), "")] }
        let payday: String
        switch snap.paydayDays {
        case nil: payday = L10n.t(lang, "未设置", "Not set")
        case 0?: payday = L10n.t(lang, "就是今天", "Today")
        case let d?: payday = L10n.t(lang, "还有 \(d) 天", d == 1 ? "In 1 day" : "In \(d) days")
        }
        return [
            (L10n.t(lang, "本月已赚", "This month"), money(snap.monthEarned)),
            (L10n.t(lang, "今日满勤", "Full day"), money(snap.dailyPay)),
            (L10n.t(lang, "时薪", "Hourly"), money(snap.hourly)),
            (L10n.t(lang, "今日进度", "Progress"), String(format: "%.1f%%", snap.progress * 100)),
            (L10n.t(lang, "发薪日", "Payday"), payday),
            (L10n.t(lang, "带薪摸鱼", "Paid slacking"), money(fishEarned)),
        ]
    }
}

struct WidgetLayout {
    static let u: CGFloat = 2 // 边框、进度条的像素

    let spriteScale: CGFloat // 0 = 不画小办公室
    let digitScale: CGFloat
    let panel: CGRect
    let diorama: CGRect?
    let column: CGRect
    let odometer: CGPoint
    let odometerRect: CGRect // 只有这一块在高频刷新
    let bar: CGRect
    let slot: CGRect
    let receipt: CGRect // 完全拉出时的工资条
    let receiptShown: CGFloat
    let tipLines: Int
    let windowSize: CGSize

    init(size: WidgetSize, odometerLogicalWidth: Int, receiptFraction: Double, language: AppLanguage = .zhHans) {
        let u = WidgetLayout.u
        let pad: CGFloat
        let baseTipLines: Int
        switch size {
        case .small: (spriteScale, digitScale, pad, baseTipLines) = (0, 2, 6, 3)
        case .medium: (spriteScale, digitScale, pad, baseTipLines) = (2, 3, 8, 2)
        case .large: (spriteScale, digitScale, pad, baseTipLines) = (3, 4, 10, 2)
        }
        tipLines = baseTipLines + (language == .en ? 1 : 0)
        let dioramaOuter = spriteScale > 0 ? CGFloat(Diorama.size + 2) * spriteScale : 0
        let statusH: CGFloat = 16
        let gap: CGFloat = size == .large ? 8 : 6
        let odoH = CGFloat(Odometer.cellHeight) * digitScale
        let barH: CGFloat = 8
        let columnH = statusH + gap + odoH + gap + barH
        let innerH = max(columnH, dioramaOuter)
        let columnW = max(CGFloat(odometerLogicalWidth) * digitScale, language == .en ? 196 : 156)
        let left = u + pad
        let colX = left + (dioramaOuter > 0 ? dioramaOuter + 10 : 0)
        let panelW = colX + columnW + pad + u
        let panelH = u + pad + innerH + 12 + u // 进度条下面留出出纸口
        panel = CGRect(x: 0, y: 0, width: panelW, height: panelH)

        if dioramaOuter > 0 {
            let top = u + pad + ((innerH - dioramaOuter) / 2).rounded(.down)
            let side = CGFloat(Diorama.size) * spriteScale
            diorama = CGRect(x: left + spriteScale, y: top + spriteScale, width: side, height: side)
        } else {
            diorama = nil
        }
        let colTop = u + pad + ((innerH - columnH) / 2).rounded(.down)
        column = CGRect(x: colX, y: colTop, width: columnW, height: columnH)
        odometer = CGPoint(x: colX, y: colTop + statusH + gap)
        odometerRect = CGRect(x: colX, y: colTop + statusH + gap, width: columnW, height: odoH)
        bar = CGRect(x: colX, y: colTop + statusH + gap + odoH + gap, width: columnW, height: barH)

        let inset = left + 4
        slot = CGRect(x: inset - 2, y: panelH - u - 6, width: panelW - 2 * inset + 4, height: 2)
        let full = WidgetLayout.receiptHeight(tipLines: tipLines)
        receipt = CGRect(x: inset, y: panelH - u, width: panelW - 2 * inset, height: full)
        receiptShown = (full * CGFloat(min(1, max(0, receiptFraction))) / 2).rounded() * 2
        windowSize = CGSize(width: panelW + u, height: max(panelH + u, panelH + receiptShown + u))
    }

    // 工资条：抬头、虚线、6 行明细、备注、虚线、提示、撕边
    static func receiptHeight(tipLines: Int) -> CGFloat {
        8 + 16 + 8 + 6 * 16 + 16 + 8 + CGFloat(tipLines) * 16 + 6 + 6
    }
}

@MainActor
final class WidgetView: NSView {
    private(set) var state = WidgetState()
    private(set) var layout = WidgetLayout(size: .medium, odometerLogicalWidth: 68, receiptFraction: 0)
    let odometer = Odometer()

    var onClick: (() -> Void)?
    var onMenu: ((NSEvent) -> Void)?

    private var hover = false
    private var downPoint: NSPoint?
    private var dragging = false

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 换上新的一帧；返回这一帧需要的窗口尺寸（计数器位数、工资条展开都会改变尺寸）。
    /// 重画哪一块由调用方决定：整窗 needsDisplay，或者只刷金额 setNeedsDisplay(layout.odometerRect)。
    @discardableResult
    func apply(_ st: WidgetState) -> CGSize {
        state = st
        odometer.layout(currency: st.settings.currency, intDigits: st.intDigits, decimals: st.settings.decimals)
        layout = WidgetLayout(size: st.size, odometerLogicalWidth: odometer.logicalWidth,
                              receiptFraction: st.receipt, language: st.settings.language)
        return layout.windowSize
    }

    // MARK: 旁白（VoiceOver）

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? {
        let lang = state.settings.language
        guard let snap = state.snap else { return L10n.t(lang, "上班激励器", "Work Motivator") }
        let what = L10n.t(lang, snap.status == .off ? "本月已赚" : "今日已赚",
                          snap.status == .off ? "This month" : "Today")
        let money = PayCore.formatMoney(state.counterValue, state.settings, decimals: 2)
        return "\(state.chip.text), \(what) \(money), \(state.right.label)\(state.right.value)"
    }

    // MARK: 鼠标：拖动搬家，单击拉出/收起工资条，右键菜单

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hover = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hover = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onMenu?(event)
            return
        }
        downPoint = event.locationInWindow
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let p = downPoint, !dragging else { return }
        if hypot(event.locationInWindow.x - p.x, event.locationInWindow.y - p.y) > 3 {
            dragging = true
            window?.performDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            downPoint = nil
            dragging = false
        }
        if !dragging && downPoint != nil { onClick?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        onMenu?(event)
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setShouldAntialias(false)
        ctx.setAllowsFontSmoothing(false)
        ctx.interpolationQuality = .none
        let L = layout, st = state
        // 大多数帧只刷金额那一块：底色重铺一下、数字重画，别的都跳过
        let onlyOdometer = L.odometerRect.contains(dirtyRect)
        if onlyOdometer {
            ctx.fill(Pal.panel, L.odometerRect)
        } else {
            drawReceipt(ctx, L, st)
            drawPanel(ctx, L)
            if let d = L.diorama {
                let s = L.spriteScale
                ctx.pixelFrame(d.insetBy(dx: -s, dy: -s), s, Pal.ink)
                ctx.drawPixels(Diorama.render(st.diorama), in: d)
            }
            drawStatus(ctx, L, st)
            drawBar(ctx, L, st)
            ctx.fill(Pal.ink, L.slot)
        }
        odometer.draw(in: ctx, at: L.odometer, scale: L.digitScale, value: st.counterValue,
                      decimals: st.settings.decimals, speed: st.counterSpeed, flash: st.flash,
                      rolling: !st.reducedMotion)
        if onlyOdometer { return }

        for c in st.confetti {
            ctx.fill(c.color, CGRect(x: (c.x / 2).rounded() * 2, y: (c.y / 2).rounded() * 2, width: 2, height: 2))
        }
        for f in st.floaters {
            let alpha = min(1, max(0, (f.life - f.age) / 0.4))
            guard alpha > 0.05 else { continue }
            let w = PixelFont.width(f.text)
            ctx.setAlpha(alpha)
            PixelFont.drawOutlined(f.text, at: CGPoint(x: f.x - w / 2, y: f.y), color: f.color)
            ctx.setAlpha(1)
        }
        if st.locked { drawLock(ctx, L) }
    }

    private func drawPanel(_ ctx: CGContext, _ L: WidgetLayout) {
        let p = L.panel, u = WidgetLayout.u
        ctx.pixelBlock(p.offsetBy(dx: u, dy: u), u, Pal.ink, alpha: 0.5) // 硬阴影
        ctx.fill(Pal.panel, p.insetBy(dx: u, dy: u))
        ctx.fill(Pal.panelHi, CGRect(x: p.minX + u, y: p.minY + u, width: p.width - 2 * u, height: u))
        ctx.fill(Pal.panelHi, CGRect(x: p.minX + u, y: p.minY + u, width: u, height: p.height - 2 * u))
        ctx.fill(Pal.panelLo, CGRect(x: p.minX + 2 * u, y: p.maxY - 2 * u, width: p.width - 3 * u, height: u))
        ctx.fill(Pal.panelLo, CGRect(x: p.maxX - 2 * u, y: p.minY + 2 * u, width: u, height: p.height - 3 * u))
        ctx.pixelFrame(p, u, hover ? Pal.gold : Pal.ink)
    }

    private func drawStatus(_ ctx: CGContext, _ L: WidgetLayout, _ st: WidgetState) {
        let chip = st.chip
        let cw = PixelFont.width(chip.text)
        let r = CGRect(x: L.column.minX, y: L.column.minY, width: cw + 8, height: 16)
        ctx.pixelBlock(r, 2, chip.color)
        PixelFont.draw(chip.text, at: CGPoint(x: r.minX + 4, y: r.minY + 2), color: Pal.ink)

        let right = st.right
        let vw = PixelFont.width(right.value)
        let lw = PixelFont.width(right.label)
        let x = L.column.maxX - vw
        PixelFont.draw(right.label, at: CGPoint(x: x - lw, y: r.minY + 2), color: Pal.muted)
        PixelFont.draw(right.value, at: CGPoint(x: x, y: r.minY + 2), color: Pal.text)
    }

    /// 20 格进度条，最后一格按 2pt 一步部分填充。
    private func drawBar(_ ctx: CGContext, _ L: WidgetLayout, _ st: WidgetState) {
        let b = L.bar
        ctx.pixelFrame(b, 2, Pal.ink)
        let inner = b.insetBy(dx: 2, dy: 2)
        ctx.fill(Pal.panelLo, inner)
        let cells = 20, gap: CGFloat = 2
        let cellW = ((inner.width - CGFloat(cells - 1) * gap) / CGFloat(cells)).rounded(.down)
        var x = inner.minX + ((inner.width - CGFloat(cells) * cellW - CGFloat(cells - 1) * gap) / 2).rounded(.down)
        let filled = st.barProgress * Double(cells)
        let colors = st.barColors
        for i in 0..<cells {
            let f = min(1, max(0, filled - Double(i)))
            if f > 0 {
                let w = max(2, (CGFloat(f) * cellW / 2).rounded(.down) * 2)
                ctx.fill(colors.base, CGRect(x: x, y: inner.minY, width: w, height: inner.height))
                ctx.fill(colors.hi, CGRect(x: x, y: inner.minY, width: w, height: 2))
                if w < cellW { ctx.fill(0x2A2639, CGRect(x: x + w, y: inner.minY, width: cellW - w, height: inner.height)) }
            } else {
                ctx.fill(0x2A2639, CGRect(x: x, y: inner.minY, width: cellW, height: inner.height))
            }
            x += cellW + gap
        }
    }

    /// 工资条从出纸口里滑出来：先露出撕边，内容跟着往下走。
    private func drawReceipt(_ ctx: CGContext, _ L: WidgetLayout, _ st: WidgetState) {
        guard L.receiptShown > 0 else { return }
        let R = L.receipt
        let top = R.minY + L.receiptShown - R.height
        let bodyH = R.height - 6

        ctx.saveGState()
        ctx.clip(to: CGRect(x: R.minX - 2, y: R.minY, width: R.width + 6, height: L.receiptShown + 2))

        ctx.fill(Pal.ink, CGRect(x: R.minX + 2, y: top + 2, width: R.width, height: bodyH), alpha: 0.5)
        ctx.fill(Pal.ink, CGRect(x: R.minX, y: top, width: R.width, height: bodyH))
        ctx.fill(Pal.paper, CGRect(x: R.minX + 2, y: top, width: R.width - 4, height: bodyH))
        // 撕边：每 12pt 一个齿，超出纸宽的部分裁掉
        ctx.saveGState()
        ctx.clip(to: CGRect(x: R.minX, y: top + bodyH, width: R.width, height: 6))
        var x = R.minX
        while x < R.maxX {
            let y = top + bodyH
            ctx.fill(Pal.ink, CGRect(x: x, y: y, width: 2, height: 2))
            ctx.fill(Pal.paper, CGRect(x: x + 2, y: y, width: 8, height: 2))
            ctx.fill(Pal.ink, CGRect(x: x + 10, y: y, width: 2, height: 2))
            ctx.fill(Pal.ink, CGRect(x: x + 2, y: y + 2, width: 2, height: 2))
            ctx.fill(Pal.paper, CGRect(x: x + 4, y: y + 2, width: 4, height: 2))
            ctx.fill(Pal.ink, CGRect(x: x + 8, y: y + 2, width: 2, height: 2))
            ctx.fill(Pal.ink, CGRect(x: x + 4, y: y + 4, width: 4, height: 2))
            x += 12
        }
        ctx.restoreGState()

        let tx = R.minX + 10, tr = R.maxX - 10
        var y = top + 8
        let receiptTitle = L10n.t(st.settings.language, "工 资 条", "PAY SLIP")
        if let snap = st.snap {
            PixelFont.draw(receiptTitle, at: CGPoint(x: tx, y: y), color: Pal.paperInk)
            let ym = "\(snap.year).\(String(format: "%02d", snap.month))"
            PixelFont.draw(ym, at: CGPoint(x: tr - PixelFont.width(ym), y: y), color: Pal.paperFaint)
        } else {
            PixelFont.draw(receiptTitle, at: CGPoint(x: tx, y: y), color: Pal.paperInk)
        }
        y += 16
        dashed(ctx, x0: tx, x1: tr, y: y + 2)
        y += 8
        for (label, value) in st.receiptRows {
            PixelFont.draw(label, at: CGPoint(x: tx, y: y), color: Pal.paperInk)
            let lw = PixelFont.width(label), vw = PixelFont.width(value)
            PixelFont.draw(value, at: CGPoint(x: tr - vw, y: y), color: Pal.paperInk)
            dotted(ctx, x0: tx + lw + 6, x1: tr - vw - 6, y: y + 9)
            y += 16
        }
        y += 16 * CGFloat(max(0, 6 - st.receiptRows.count))
        PixelFont.draw(L10n.t(st.settings.language, "* 已过的工作日按满勤计", "* Past workdays paid in full"),
                       at: CGPoint(x: tx, y: y), color: Pal.paperFaint)
        y += 16
        dashed(ctx, x0: tx, x1: tr, y: y + 2)
        y += 8
        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = 16
        para.maximumLineHeight = 16
        para.lineBreakMode = .byWordWrapping // 中文照常逐字折行，"¥47.61" 这种不会被拆开
        var attrs = PixelFont.attrs(Pal.paperInk)
        attrs[.paragraphStyle] = para
        let tipRect = CGRect(x: tx, y: y, width: tr - tx, height: 16 * CGFloat(L.tipLines))
        (("▶ " + st.tip) as NSString).draw(with: tipRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                            attributes: attrs)
        ctx.restoreGState()
    }

    private func dashed(_ ctx: CGContext, x0: CGFloat, x1: CGFloat, y: CGFloat) {
        var x = x0
        while x + 4 <= x1 {
            ctx.fill(Pal.paperLine, CGRect(x: x, y: y, width: 4, height: 2))
            x += 8
        }
    }

    private func dotted(_ ctx: CGContext, x0: CGFloat, x1: CGFloat, y: CGFloat) {
        var x = (x0 / 2).rounded(.up) * 2
        while x + 2 <= x1 {
            ctx.fill(Pal.paperLine, CGRect(x: x, y: y, width: 2, height: 2))
            x += 4
        }
    }

    private func drawLock(_ ctx: CGContext, _ L: WidgetLayout) {
        let art = [".###.", "#...#", "#...#", "#####", "##.##", "#####"]
        let ox = L.panel.maxX - 2 * WidgetLayout.u - 12, oy = L.panel.minY + 2 * WidgetLayout.u + 2
        for (r, row) in art.enumerated() {
            for (c, ch) in row.enumerated() where ch == "#" {
                ctx.fill(Pal.faint, CGRect(x: ox + CGFloat(c) * 2, y: oy + CGFloat(r) * 2, width: 2, height: 2))
            }
        }
    }
}
