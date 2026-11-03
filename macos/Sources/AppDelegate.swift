// 应用入口：菜单栏金币 + 实时金额、右键/菜单栏共用的菜单、设置窗口、开机自启、调试截图。
import AppKit
import ServiceManagement

/// 命令行参数（调试用）：
///   --snapshot out.png         把悬浮窗画成 PNG 后退出（不读写用户设置）
///   --settings-snapshot out.png 把设置窗口画成 PNG 后退出
///   --now 2026-11-03T15:05:39  假装现在是这个时刻；--speed 60 让时间 60 倍速走
///   --settings '{"salary":8000}'  用这份设置（只在内存里，不保存）
///   --size small|medium|large  --expanded  --fishing 分钟  --celebrate  --coin  --anim 秒  --no-bg
///   --print                     打印菜单栏文字后退出
struct LaunchOptions {
    var snapshot: String?
    var settingsSnapshot: String?
    var now: Date?
    var speed: Double = 1
    var settingsJSON: String?
    var size: WidgetSize?
    var expanded = false
    var fishingMinutes: Double?
    var celebrate = false
    var coin = false
    var anim: Double = 0
    var background: UInt32? = 0x56627D
    var printOnly = false
    var menubarSnapshot: String?

    static func parse(_ args: [String]) -> LaunchOptions {
        var o = LaunchOptions()
        var i = 1
        func next() -> String? {
            i += 1
            return i < args.count ? args[i] : nil
        }
        while i < args.count {
            switch args[i] {
            case "--snapshot": o.snapshot = next()
            case "--settings-snapshot": o.settingsSnapshot = next()
            case "--now":
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                o.now = next().flatMap(f.date(from:))
            case "--speed": o.speed = next().flatMap(Double.init) ?? 1
            case "--settings": o.settingsJSON = next()
            case "--size": o.size = next().flatMap(WidgetSize.init(rawValue:))
            case "--expanded": o.expanded = true
            case "--fishing": o.fishingMinutes = next().flatMap(Double.init) ?? 0
            case "--celebrate": o.celebrate = true
            case "--coin": o.coin = true
            case "--anim": o.anim = next().flatMap(Double.init) ?? 0
            case "--no-bg": o.background = nil
            case "--print": o.printOnly = true
            case "--menubar-snapshot": o.menubarSnapshot = next()
            default: break // 忽略系统附带的参数（如 -NSDocumentRevisionsDebugMode）
            }
            i += 1
        }
        return o
    }

    var isDebugRun: Bool {
        snapshot != nil || settingsSnapshot != nil || settingsJSON != nil || printOnly || menubarSnapshot != nil
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    /// 返回 nil 表示成功，否则是给人看的错误信息。
    static func set(_ on: Bool, language: AppLanguage = .zhHans) -> String? {
        guard #available(macOS 13, *) else {
            return L10n.t(language, "开机自动启动需要 macOS 13 或更新的系统。",
                          "Launch at login requires macOS 13 or later.")
        }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

enum Icons {
    /// 菜单栏上的像素金币（8×8，每格 2pt）。
    static func menuBarCoin() -> NSImage {
        let art = ["..NNNN..", ".NYYyyN.", "NYyyyyoN", "NYyyyyoN", "NyyyyyoN", "NyyyyooN", ".NyoooN.", "..NNNN.."]
        let pal: [Character: UInt32] = ["N": 0x7A4A12, "Y": 0xFFF0B3, "y": 0xFFC83D, "o": 0xE08A1E]
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            for (r, row) in art.enumerated() {
                for (c, ch) in row.enumerated() {
                    guard let hex = pal[ch] else { continue }
                    nsColor(hex).setFill()
                    NSRect(x: c * 2, y: r * 2, width: 2, height: 2).fill()
                }
            }
            return true
        }
        img.isTemplate = false
        return img
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let options: LaunchOptions
    private var store: Store!
    private var widget: WidgetController!
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private var infoItems: [NSMenuItem] = []
    private var menuOpen = false
    private var lastTitle = ""
    private var settingsController: SettingsWindowController?
    private var activity: NSObjectProtocol?

    init(options: LaunchOptions) {
        self.options = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = Store(ephemeral: options.isDebugRun, settingsJSON: options.settingsJSON)
        if options.isDebugRun {
            store.prefs.expanded = options.expanded
            store.prefs.size = options.size ?? .medium
            store.prefs.locked = false
            store.prefs.fish = FishState()
        }
        widget = WidgetController(store: store, clock: Clock(base: options.now, speed: options.speed))

        if let path = options.snapshot { return runSnapshot(path) }
        if let path = options.settingsSnapshot { return runSettingsSnapshot(path) }
        if options.printOnly { return runPrint() }
        if let path = options.menubarSnapshot { return runMenubarSnapshot(path) }

        setupMainMenu()
        setupStatusItem()
        widget.makeMenu = { [weak self] in
            let menu = NSMenu()
            self?.fill(menu)
            return menu
        }
        widget.onTick = { [weak self] snap in self?.refreshStatusItem(snap) }
        widget.start()
        // 别让系统把计时器"打盹"（App Nap），否则悬浮窗和菜单栏会一卡一卡
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: L10n.t(widget.settings.language, "悬浮窗实时显示工资",
                                                                        "Live earnings widget"))
        if store.settings == nil { openSettings(nil) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Icons.menuBarCoin()
        item.button?.imagePosition = .imageLeft
        statusMenu.delegate = self
        item.menu = statusMenu
        statusItem = item
    }

    private func refreshStatusItem(_ snap: PaySnapshot) {
        let s = widget.settings
        let text = PayCore.menuBarText(s, snap)
        let title = text.isEmpty ? "" : " " + text
        if title != lastTitle {
            lastTitle = title
            statusItem?.button?.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: PixelFont.isLoaded ? PixelFont.font(12) : NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
                .baselineOffset: PixelFont.isLoaded ? -1 : 0,
            ])
        }
        if menuOpen {
            let lines = PayCore.menuLines(s, snap)
            for (item, line) in zip(infoItems, lines) where item.title != line { item.title = line }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusMenu { fill(menu) }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === statusMenu { menuOpen = true }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === statusMenu { menuOpen = false }
    }

    private func fill(_ menu: NSMenu) {
        menu.removeAllItems()
        let snap = widget.snapshot, s = widget.settings, p = store.prefs
        let lang = s.language
        func tr(_ zh: String, _ en: String) -> String { L10n.t(lang, zh, en) }
        let lines = PayCore.menuLines(s, snap).map { line -> NSMenuItem in
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
        if menu === statusMenu { infoItems = lines }
        lines.forEach(menu.addItem)
        let fish = widget.fishEarned(snap)
        if widget.isFishing || fish > 0 {
            let item = NSMenuItem(title: tr("今日带薪摸鱼 ", "Paid slacking today: ")
                + PayCore.formatMoney(fish, s, decimals: 2), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(action(p.expanded ? tr("收起工资条", "Collapse pay slip") : tr("拉出工资条", "Show pay slip"), #selector(toggleReceipt)))
        menu.addItem(action(widget.isFishing ? tr("结束摸鱼", "End slacking") : tr("开始带薪摸鱼", "Start paid slacking"), #selector(toggleFishing)))

        menu.addItem(.separator())
        menu.addItem(action(p.visible ? tr("隐藏悬浮窗", "Hide widget") : tr("显示悬浮窗", "Show widget"), #selector(toggleVisible)))
        let lock = action(tr("锁定悬浮窗（鼠标穿透）", "Lock widget (click-through)"), #selector(toggleLock))
        lock.state = p.locked ? .on : .off
        menu.addItem(lock)

        let sizeMenu = NSMenu()
        for size in WidgetSize.allCases {
            let item = action(size.title(lang), #selector(pickSize(_:)))
            item.representedObject = size.rawValue
            item.state = p.size == size ? .on : .off
            sizeMenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: tr("悬浮窗大小", "Widget size"), action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let alphaMenu = NSMenu()
        for alpha in [1.0, 0.85, 0.7, 0.55] {
            let item = action("\(Int(alpha * 100))%", #selector(pickOpacity(_:)))
            item.representedObject = alpha
            item.state = abs(p.opacity - alpha) < 0.01 ? .on : .off
            alphaMenu.addItem(item)
        }
        let alphaItem = NSMenuItem(title: tr("不透明度", "Opacity"), action: nil, keyEquivalent: "")
        alphaItem.submenu = alphaMenu
        menu.addItem(alphaItem)
        menu.addItem(action(tr("移回屏幕右上角", "Move to upper-right corner"), #selector(resetPosition)))

        menu.addItem(.separator())
        menu.addItem(action(tr("设置…", "Settings…"), #selector(openSettings(_:)), key: ","))
        let login = action(tr("开机自动启动", "Launch at login"), #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(action(tr("退出上班激励器", "Quit Work Motivator"), #selector(quit), key: "q"))
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleReceipt() { widget.toggleReceipt() }
    @objc private func toggleFishing() { widget.toggleFishing() }
    @objc private func toggleVisible() { widget.setVisible(!store.prefs.visible) }
    @objc private func toggleLock() { widget.setLocked(!store.prefs.locked) }
    @objc private func resetPosition() { widget.resetPosition() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func pickSize(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let size = WidgetSize(rawValue: raw) { widget.setSize(size) }
    }

    @objc private func pickOpacity(_ sender: NSMenuItem) {
        if let alpha = sender.representedObject as? Double { widget.setOpacity(alpha) }
    }

    @objc private func toggleLogin() {
        let lang = widget.settings.language
        if let problem = LoginItem.set(!LoginItem.isEnabled, language: lang) {
            let alert = NSAlert()
            alert.messageText = L10n.t(lang, "开机自动启动没有打开", "Launch at login could not be enabled")
            alert.informativeText = problem + L10n.t(lang,
                "\n\n把「上班激励器」拖进「应用程序」文件夹后再试一次。",
                "\n\nMove Work Motivator into the Applications folder and try again.")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: 设置窗口

    @objc func openSettings(_ sender: Any?) {
        if settingsController == nil {
            let c = SettingsWindowController(settings: store.settings, size: store.prefs.size,
                                             opacity: store.prefs.opacity, launchAtLogin: LoginItem.isEnabled)
            c.onSave = { [weak self] s, size, opacity, login in
                guard let self else { return nil }
                self.store.save(settings: s)
                self.widget.setOpacity(opacity)
                self.widget.setSize(size)
                self.widget.settingsChanged()
                self.setupMainMenu()
                return login != LoginItem.isEnabled ? LoginItem.set(login, language: s.language) : nil
            }
            c.onClose = { [weak self] in
                self?.settingsController = nil
                NSApp.setActivationPolicy(.accessory) // 关掉设置就把程序坞图标收起来
            }
            settingsController = c
        }
        NSApp.setActivationPolicy(.regular) // 设置窗口打开时要能用 ⌘V 等快捷键
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    private func setupMainMenu() {
        let lang = widget.settings.language
        func tr(_ zh: String, _ en: String) -> String { L10n.t(lang, zh, en) }
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: tr("关于上班激励器", "About Work Motivator"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(action(tr("设置…", "Settings…"), #selector(openSettings(_:)), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("退出上班激励器", "Quit Work Motivator"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: tr("编辑", "Edit"))
        edit.addItem(withTitle: tr("撤销", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: tr("重做", "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: tr("剪切", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: tr("拷贝", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: tr("粘贴", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: tr("全选", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: tr("窗口", "Window"))
        windowMenu.addItem(withTitle: tr("关闭", "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    // MARK: 调试

    private func runSnapshot(_ path: String) {
        if let minutes = options.fishingMinutes { widget.toggleFishing(minutesAgo: minutes) }
        widget.step(dt: 0)
        if options.celebrate { widget.debugCelebrate() }
        if options.coin { widget.debugCoin() }
        widget.simulate(seconds: options.anim)
        do {
            try widget.writeSnapshot(to: path, background: options.background)
            print("已写入 \(path)  字体加载：\(PixelFont.isLoaded)  菜单栏：\(PayCore.menuBarText(widget.settings, widget.snapshot))")
            exit(0)
        } catch {
            print("截图失败：\(error)")
            exit(1)
        }
    }

    private func runSettingsSnapshot(_ path: String) {
        let c = SettingsWindowController(settings: store.settings, size: store.prefs.size,
                                         opacity: store.prefs.opacity, launchAtLogin: false)
        guard let view = c.window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: rep)
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("已写入 \(path)")
            exit(0)
        } catch {
            print("截图失败：\(error)")
            exit(1)
        }
    }

    private func runMenubarSnapshot(_ path: String) {
        setupStatusItem()
        refreshStatusItem(widget.snapshot)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            guard let button = statusItem?.button,
                  let rep = button.bitmapImageRepForCachingDisplay(in: button.bounds) else { exit(1) }
            button.cacheDisplay(in: button.bounds, to: rep)
            // 垫一块深灰底（菜单栏文字是白的），放大 4 倍方便看对齐
            let size = NSSize(width: button.bounds.width * 4, height: button.bounds.height * 4)
            let out = NSImage(size: size, flipped: false) { r in
                NSColor(white: 0.25, alpha: 1).setFill()
                r.fill()
                NSGraphicsContext.current?.imageInterpolation = .none
                rep.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                return true
            }
            if let tiff = out.tiffRepresentation, let bmp = NSBitmapImageRep(data: tiff) {
                try? bmp.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            print("已写入 \(path)  按钮 \(button.bounds.size)  菜单栏高度 \(NSStatusBar.system.thickness)")
            exit(0)
        }
    }

    private func runPrint() {
        let snap = widget.snapshot, s = widget.settings
        print("菜单栏：\(PayCore.menuBarText(s, snap))")
        PayCore.menuLines(s, snap).forEach { print("  " + $0) }
        PayCore.tips(s, snap).forEach { print("  ▶ " + $0) }
        exit(0)
    }
}
