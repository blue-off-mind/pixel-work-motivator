// 悬浮窗：透明无边框、总在最前、所有桌面都显示、点它不抢焦点。
// 这里管计时循环、动画（金币/彩纸/飘字/Zzz）、工资条拉出、摸鱼计时和窗口位置。
import AppKit

final class WidgetPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class WidgetController: NSObject {
    let store: Store
    let clock: Clock
    let panel = WidgetPanel()
    let view = WidgetView()

    /// 约每 0.25 秒推一次，给菜单栏刷新。
    var onTick: ((PaySnapshot) -> Void)?
    var makeMenu: (() -> NSMenu)?

    private(set) var snapshot: PaySnapshot
    private var timer: Timer?
    private var interval: TimeInterval = 0
    private var lastReal = CACurrentMediaTime()
    private var animTime = 0.0
    private var lastPush = -1.0
    private var lastFull = -1.0

    private var receipt: Double
    private var coins: [(born: Double, unit: Double)] = []
    private var zzz: [(born: Double, x: Double)] = []
    private var lastZ = -10.0
    private var confetti: [Confetti] = []
    private var floaters: [FloatText] = []
    private var flashUntil = 0.0
    private var sparkleUntil = 0.0
    private var celebrateUntil = -1.0
    private var lastStatus: PaySnapshot.Status?
    private var lastCoin: Int?
    private var dayKey = ""
    private var tipIndex = 0
    private var tipAt = -100.0
    private var tip = ""

    var settings: PaySettings { store.settings ?? PaySettings() }
    /// 系统设置 › 辅助功能 › 减少动态效果：不滚轮、不撒彩纸、金币不飞
    private(set) var reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    init(store: Store, clock: Clock) {
        self.store = store
        self.clock = clock
        receipt = store.prefs.expanded ? 1 : 0
        snapshot = PayCore.snapshot(store.settings ?? PaySettings(), at: clock.now())
        super.init()
        panel.contentView = view
        view.onClick = { [weak self] in self?.toggleReceipt() }
        view.onMenu = { [weak self] event in
            guard let self, let menu = self.makeMenu?() else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self.view)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(windowMoved),
                                               name: NSWindow.didMoveNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    @objc private func displayOptionsChanged() {
        reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 拔掉外接显示器后，悬浮窗要是不在任何一块屏幕上了，就挪回主屏右上角。
    @objc private func screensChanged() {
        let f = panel.frame
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(f) }) { resetPosition() }
    }

    func start() {
        panel.ignoresMouseEvents = store.prefs.locked
        panel.alphaValue = store.prefs.opacity
        step(dt: 0)
        place()
        if store.prefs.visible { panel.orderFrontRegardless() }
        schedule(1.0 / 30)
    }

    // MARK: 每一帧

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.5, now - lastReal)
        lastReal = now
        step(dt: dt)
        schedule(desiredInterval())
    }

    /// 推进一帧。dt：距上一帧的真实秒数（截图模式下用固定步长模拟）。
    func step(dt: Double) {
        animTime += dt
        let t = animTime
        let s = settings
        let snap = PayCore.snapshot(s, at: clock.now())
        snapshot = snap

        let today = Self.dayKey(snap)
        if today != dayKey {
            dayKey = today
            lastCoin = nil
            lastStatus = nil
            if store.prefs.fish.day != today && !store.prefs.fish.day.isEmpty { store.prefs.fish = FishState() }
        }
        statusChanged(snap, t)
        let pose = currentPose(snap, t)
        checkCoin(snap, t)
        animate(dt, t, pose)

        let target = store.prefs.expanded ? 1.0 : 0.0
        if receipt != target {
            let delta = reducedMotion ? 1 : dt / 0.4
            receipt = target > receipt ? min(target, receipt + delta) : max(target, receipt - delta)
        }
        if t - tipAt > 8 || tip.isEmpty { rotateTip(snap, s, t) }
        if store.prefs.visible || dt == 0 { render(snap, s, t, pose, full: dt == 0) }
        if t - lastPush >= 0.25 || dt == 0 {
            lastPush = t
            onTick?(snap)
        }
    }

    private func currentPose(_ snap: PaySnapshot, _ t: Double) -> Pose {
        if t < celebrateUntil { return .cheering }
        switch snap.status {
        case .working: return isFishing ? .fishing : .typing
        case .lunch: return .sleeping
        default: return .absent
        }
    }

    private func statusChanged(_ snap: PaySnapshot, _ t: Double) {
        defer { lastStatus = snap.status }
        guard let last = lastStatus, last != snap.status else { return }
        switch (last, snap.status) {
        case (.working, .after): celebrate(t)
        case (.working, .lunch): announce(L10n.t(settings.language, "干饭！", "Lunch!"))
        case (.before, .working), (.lunch, .working): announce(L10n.t(settings.language, "开工！", "Back to work!"))
        default: break
        }
    }

    /// 一枚金币对应多少钱：挑最小的整数面额，让金币至少隔 10 秒才掉一枚。
    static func coinUnit(rate: Double) -> Double {
        for unit in [0.01, 0.05, 0.1, 0.5, 1, 5, 10, 50, 100, 500] where rate <= 0 || unit / rate >= 10 {
            return unit
        }
        return 1000
    }

    private func checkCoin(_ snap: PaySnapshot, _ t: Double) {
        guard snap.status == .working, snap.rate > 0 else {
            lastCoin = nil
            return
        }
        let unit = Self.coinUnit(rate: snap.rate)
        let index = Int((snap.earnedToday / unit + 1e-9).rounded(.down))
        defer { lastCoin = index }
        guard let last = lastCoin, index > last else { return }
        if view.layout.diorama != nil && !reducedMotion {
            coins.append((t, unit))
        } else {
            coinLanded(unit, t)
        }
    }

    private func coinLanded(_ unit: Double, _ t: Double) {
        sparkleUntil = t + 0.25
        flashUntil = t + 0.12
        // "+¥0.5" 从存钱罐口冒出来；小号没有小办公室，就飘在金额右上方
        let L = view.layout
        let anchor: CGPoint
        if let d = L.diorama {
            anchor = CGPoint(x: d.minX + 4 * L.spriteScale + 6, y: d.minY + 8 * L.spriteScale)
        } else {
            let right = L.odometer.x + CGFloat(view.odometer.logicalWidth) * L.digitScale
            anchor = CGPoint(x: right - 18, y: L.odometer.y - 4)
        }
        floaters.append(FloatText(text: "+" + coinText(unit), x: anchor.x, y: anchor.y))
        if settings.sound { Sound.coin() }
    }

    private func coinText(_ unit: Double) -> String {
        let cur = settings.currency
        if unit >= 1 { return cur + String(Int(unit)) }
        return cur + String(format: unit < 0.1 ? "%.2f" : "%.1f", unit)
    }

    private func celebrate(_ t: Double) {
        celebrateUntil = t + 4
        announce(L10n.t(settings.language, "下班！", "Off work!"))
        if settings.sound { Sound.fanfare() }
        guard !reducedMotion else { return }
        let w = Double(view.layout.panel.width)
        let colors = [Pal.gold, Pal.green, Pal.sky, Pal.red, Pal.lilac, Pal.cyan, Pal.goldHi]
        for i in 0..<44 {
            confetti.append(Confetti(x: Double.random(in: 6...(w - 6)), y: Double.random(in: -40...0),
                                     vx: Double.random(in: -16...16), vy: Double.random(in: 20...70),
                                     color: colors[i % colors.count]))
        }
    }

    private func announce(_ text: String) {
        let L = view.layout
        let anchor = L.diorama.map { CGPoint(x: $0.midX, y: $0.minY + 4) }
            ?? CGPoint(x: L.column.minX + 60, y: L.column.minY + 18)
        floaters.append(FloatText(text: text, x: anchor.x, y: anchor.y, life: 2))
    }

    private func animate(_ dt: Double, _ t: Double, _ pose: Pose) {
        var landed: [Double] = []
        coins.removeAll { coin in
            guard t - coin.born >= 0.75 else { return false }
            landed.append(coin.unit)
            return true
        }
        for unit in landed { coinLanded(unit, t) }

        if pose == .sleeping && !reducedMotion && t - lastZ > 1.4 {
            zzz.append((t, 18))
            lastZ = t
        }
        zzz.removeAll { t - $0.born > 2.2 }

        let height = Double(view.layout.windowSize.height)
        for i in confetti.indices {
            confetti[i].vy += 90 * dt
            confetti[i].x += confetti[i].vx * dt
            confetti[i].y += confetti[i].vy * dt
        }
        confetti.removeAll { $0.y > height }

        for i in floaters.indices {
            floaters[i].age += dt
            floaters[i].y -= 9 * dt
        }
        floaters.removeAll { $0.age >= $0.life }
    }

    private func rotateTip(_ snap: PaySnapshot, _ s: PaySettings, _ t: Double) {
        var tips = PayCore.tips(s, snap)
        if isFishing {
            let earned = PayCore.formatMoney(fishEarned(snap), s, decimals: 2)
            tips.insert(L10n.t(s.language, "带薪摸鱼中，已经摸到 \(earned)。",
                               "Paid slacking: \(earned) earned so far."), at: 0)
        }
        tipIndex += 1
        tip = tips.isEmpty ? "" : tips[tipIndex % tips.count]
        tipAt = t
    }

    /// full：强制整窗重画（手动刷新、改设置时）。
    private func render(_ snap: PaySnapshot, _ s: PaySettings, _ t: Double, _ pose: Pose, full: Bool) {
        var st = WidgetState()
        st.settings = s
        st.snap = snap
        st.size = store.prefs.size
        st.receipt = receipt
        st.fishing = isFishing
        st.fishEarned = fishEarned(snap)
        st.tip = tip
        let jar: Double
        switch snap.status {
        case .working, .lunch: jar = snap.progress
        case .after: jar = 1
        default: jar = 0
        }
        st.diorama = DioramaInput(
            pose: pose, hour: snap.secOfDay / 3600, jarLevel: jar, t: t,
            coins: coins.map { coin in
                // 二次贝塞尔：笔记本上方 → 抛高 → 罐口
                let p = min(1, (t - coin.born) / 0.75), q = 1 - p
                let x = q * q * 16.5 + 2 * q * p * 10 + p * p * 3.5
                let y = q * q * 13 + 2 * q * p * -4 + p * p * 11
                return (x, y, t - coin.born)
            },
            zzz: zzz.map { z in (z.x + (t - z.born) * 1.5, 7 - (t - z.born) * 3) },
            sparkle: t < sparkleUntil
        )
        st.flash = t < flashUntil
        st.confetti = confetti
        st.floaters = floaters
        st.locked = store.prefs.locked
        st.reducedMotion = reducedMotion
        let size = view.apply(st)
        // 整窗每秒最多重画 8 次（小人动画、倒计时文字够用）；中间的帧只刷金额
        let animating = !coins.isEmpty || !confetti.isEmpty || !floaters.isEmpty || t < celebrateUntil
            || receipt != (store.prefs.expanded ? 1 : 0)
        if full || size != view.frame.size || animating || t - lastFull >= 0.124 {
            view.needsDisplay = true
            lastFull = t
        } else {
            view.setNeedsDisplay(view.layout.odometerRect)
        }
        resize(to: size)
    }

    private func desiredInterval() -> TimeInterval {
        if !store.prefs.visible { return 0.5 }
        let fastDigits = snapshot.status == .working && !reducedMotion
            && snapshot.rate * pow(10, Double(settings.decimals)) > 1.5
        let animating = !coins.isEmpty || !confetti.isEmpty || !floaters.isEmpty || animTime < celebrateUntil
            || receipt != (store.prefs.expanded ? 1 : 0)
        if animating { return 1.0 / 30 }
        return fastDigits ? 1.0 / 20 : 1.0 / 8
    }

    private func schedule(_ newInterval: TimeInterval) {
        guard newInterval != interval else { return }
        interval = newInterval
        timer?.invalidate()
        let t = Timer(timeInterval: newInterval, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        t.tolerance = newInterval * 0.15
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: 操作（菜单、点击）

    func toggleReceipt() {
        store.prefs.expanded.toggle()
        tipAt = -100
        schedule(1.0 / 30)
    }

    var isFishing: Bool { store.prefs.fish.since != nil && store.prefs.fish.day == Self.dayKey(snapshot) }

    func fishEarned(_ snap: PaySnapshot) -> Double {
        let f = store.prefs.fish
        guard f.day == Self.dayKey(snap) else { return 0 }
        let live = f.since.map { max(0, snap.worked - $0) } ?? 0
        return (f.total + live) * snap.rate
    }

    /// 开始/结束带薪摸鱼。minutesAgo 只给截图调试用。
    func toggleFishing(minutesAgo: Double = 0) {
        let snap = PayCore.snapshot(settings, at: clock.now())
        var f = store.prefs.fish
        if f.day != Self.dayKey(snap) { f = FishState(day: Self.dayKey(snap)) }
        if let since = f.since {
            f.total += max(0, snap.worked - since)
            f.since = nil
        } else {
            f.since = max(0, snap.worked - minutesAgo * 60)
        }
        store.prefs.fish = f
        tipAt = -100
        step(dt: 0)
    }

    func setVisible(_ visible: Bool) {
        store.prefs.visible = visible
        if visible {
            step(dt: 0)
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
        schedule(desiredInterval())
    }

    func setLocked(_ locked: Bool) {
        store.prefs.locked = locked
        panel.ignoresMouseEvents = locked
        step(dt: 0)
    }

    func setSize(_ size: WidgetSize) {
        store.prefs.size = size
        step(dt: 0)
    }

    func setOpacity(_ opacity: Double) {
        store.prefs.opacity = opacity
        panel.alphaValue = opacity
    }

    func resetPosition() {
        store.prefs.topLeft = nil
        place()
    }

    /// 改了设置：重新算金币进度和状态，避免误触发"下班"庆祝。
    func settingsChanged() {
        lastCoin = nil
        lastStatus = nil
        tip = ""
        step(dt: 0)
    }

    // MARK: 窗口位置

    private func place() {
        let size = view.layout.windowSize
        var origin: CGPoint
        if let tl = store.prefs.topLeft,
           NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -40, dy: -40).contains(tl) }) {
            origin = CGPoint(x: tl.x, y: tl.y - size.height)
        } else {
            let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
            origin = CGPoint(x: vf.maxX - size.width - 24, y: vf.maxY - size.height - 24)
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    /// 改尺寸时保持左上角不动；往下拉工资条快出屏幕时整体上移。
    private func resize(to size: CGSize) {
        var f = panel.frame
        guard f.size != size else { return }
        let top = f.maxY
        f.size = size
        f.origin.y = top - size.height
        if let vf = panel.screen?.visibleFrame, f.minY < vf.minY { f.origin.y = vf.minY }
        panel.setFrame(f, display: true)
    }

    @objc private func windowMoved() {
        let f = panel.frame
        store.prefs.topLeft = CGPoint(x: f.minX, y: f.maxY)
    }

    static func dayKey(_ snap: PaySnapshot) -> String {
        String(format: "%04d-%02d-%02d", snap.year, snap.month, snap.day)
    }

    // MARK: 调试：离屏截图

    func debugCelebrate() { celebrate(animTime) }

    func debugCoin() {
        coins.append((animTime, Self.coinUnit(rate: snapshot.rate)))
    }

    func simulate(seconds: Double) {
        var left = seconds
        while left > 0 {
            step(dt: min(1.0 / 30, left))
            left -= 1.0 / 30
        }
    }

    /// 把悬浮窗画进 PNG（2x）。background 不为空时垫一块"桌面"底色，方便看清透明边缘。
    func writeSnapshot(to path: String, background: UInt32?) throws {
        let size = view.layout.windowSize
        view.frame = CGRect(origin: .zero, size: size)
        let margin: CGFloat = background == nil ? 0 : 16
        let out = CGSize(width: size.width + margin * 2, height: size.height + margin * 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(out.width * 2),
                                         pixelsHigh: Int(out.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0)
        else { throw CocoaError(.fileWriteUnknown) }
        rep.size = out // 先定点数尺寸，上下文才会按 2x 建
        guard let base = NSGraphicsContext(bitmapImageRep: rep) else { throw CocoaError(.fileWriteUnknown) }
        let cg = base.cgContext
        if let background {
            cg.setFillColor(cgColor(background))
            cg.fill(CGRect(origin: .zero, size: out))
        }
        cg.translateBy(x: margin, y: out.height - margin)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: URL(fileURLWithPath: path))
    }
}
