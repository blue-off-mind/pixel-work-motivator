// 设置窗口：原生控件，填工资、上下班时间、显示选项和心愿单。
import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    /// 保存回调：返回开机启动的错误信息（设置本身已经保存）。
    var onSave: ((PaySettings, WidgetSize, Double, Bool) -> String?)?
    var onClose: (() -> Void)?

    private let salaryType = NSPopUpButton()
    private let languageControl = NSPopUpButton()
    private let salaryField = NSTextField()
    private let salaryUnit = NSTextField(labelWithString: "元 / 月")
    private let dayMode = NSPopUpButton()
    private let customDays = NSTextField()
    private let customDaysUnit = NSTextField(labelWithString: "天")
    private let dailyHint = NSTextField(wrappingLabelWithString: "") // 实时显示日薪是怎么算出来的
    private let start = SettingsWindowController.timePicker()
    private let end = SettingsWindowController.timePicker()
    private let lunch = NSButton(checkboxWithTitle: "午休不计薪", target: nil, action: nil)
    private let lunchStart = SettingsWindowController.timePicker()
    private let lunchTo = NSTextField(labelWithString: "至")
    private let lunchEnd = SettingsWindowController.timePicker()
    private let workdays = NSSegmentedControl(labels: ["一", "二", "三", "四", "五", "六", "日"],
                                              trackingMode: .selectAny, target: nil, action: nil)
    private let payday = NSPopUpButton()
    private let currency = NSPopUpButton()
    private let decimals = NSPopUpButton()
    private let menuBar = NSPopUpButton()
    private let size = NSSegmentedControl(labels: WidgetSize.allCases.map(\.title), trackingMode: .selectOne,
                                          target: nil, action: nil)
    private let opacity = NSSlider(value: 1, minValue: 0.4, maxValue: 1, target: nil, action: nil)
    private let sound = NSButton(checkboxWithTitle: "进账时播放金币音", target: nil, action: nil)
    private let login = NSButton(checkboxWithTitle: "开机自动启动", target: nil, action: nil)
    private let wishes = NSTextView()
    private let error = NSTextField(labelWithString: "")
    private let firstRun: Bool
    private let language: AppLanguage
    private let originalSettings: PaySettings?

    /// 分段控件从"一"排到"日"，对应 weekday 1…6、0。
    private static let weekdayOrder = [1, 2, 3, 4, 5, 6, 0]

    init(settings: PaySettings?, size widgetSize: WidgetSize, opacity alpha: Double, launchAtLogin: Bool) {
        firstRun = settings == nil
        language = settings?.language ?? .zhHans
        originalSettings = settings
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L10n.t(language, "上班激励器 · 设置", "Work Motivator · Settings")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        build()
        load(settings ?? PaySettings(), size: widgetSize, opacity: alpha, launchAtLogin: launchAtLogin)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: 搭界面

    private func tr(_ zh: String, _ en: String) -> String { L10n.t(language, zh, en) }

    private func build() {
        languageControl.addItems(withTitles: ["简体中文", "English"])
        salaryType.addItems(withTitles: language == .en ? ["Monthly", "Daily", "Hourly"] : ["月薪", "日薪", "时薪"])
        dayMode.addItems(withTitles: language == .en
            ? ["Actual workdays", "21.75 days", "Custom days"]
            : ["按实际工作日", "按 21.75 天", "自定义天数"])
        payday.addItem(withTitle: tr("不显示", "Hidden"))
        payday.addItems(withTitles: (1...31).map { tr("每月 \($0) 号", "Day \($0)") })
        currency.addItems(withTitles: PaySettings.currencies)
        decimals.addItems(withTitles: (2...6).map { tr("\($0) 位", "\($0) digits") })
        menuBar.addItems(withTitles: language == .en
            ? ["Today's earnings", "This month's earnings", "Countdown to off work", "Icon only"]
            : ["今日已赚", "本月已赚", "下班倒计时", "只显示图标"])
        lunch.title = tr("午休不计薪", "Unpaid lunch break")
        lunchTo.stringValue = tr("至", "to")
        sound.title = tr("进账时播放金币音", "Play a coin sound as earnings increase")
        login.title = tr("开机自动启动", "Launch at login")
        let weekdays = language == .en ? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] : ["一", "二", "三", "四", "五", "六", "日"]
        for (i, title) in weekdays.enumerated() { workdays.setLabel(title, forSegment: i) }
        for (i, widgetSize) in WidgetSize.allCases.enumerated() {
            size.setLabel(widgetSize.title(language), forSegment: i)
        }
        for picker in [start, end, lunchStart, lunchEnd] {
            picker.locale = Locale(identifier: language == .en ? "en_GB" : "zh_CN")
        }
        // 这些一变，日薪说明就跟着重算
        let live: [NSControl] = [salaryType, dayMode, lunch, payday, currency, workdays, start, end, lunchStart, lunchEnd]
        for control in live {
            control.target = self
            control.action = #selector(refreshEnabled)
        }
        salaryField.delegate = self
        customDays.delegate = self
        dailyHint.textColor = .secondaryLabelColor
        dailyHint.font = .systemFont(ofSize: 12)
        dailyHint.preferredMaxLayoutWidth = 320
        dailyHint.maximumNumberOfLines = 2
        dailyHint.cell?.truncatesLastVisibleLine = true
        dailyHint.stringValue = "-\n-" // 固定两行高，文字变了窗口也不跳
        dailyHint.heightAnchor.constraint(equalToConstant: dailyHint.fittingSize.height).isActive = true

        salaryField.placeholderString = tr("例如 8000", "e.g. 8000")
        customDaysUnit.stringValue = tr("天", "days")
        salaryField.widthAnchor.constraint(equalToConstant: 120).isActive = true
        customDays.widthAnchor.constraint(equalToConstant: 48).isActive = true
        opacity.widthAnchor.constraint(equalToConstant: 110).isActive = true
        error.textColor = .systemRed
        error.lineBreakMode = .byWordWrapping
        error.maximumNumberOfLines = 2
        error.preferredMaxLayoutWidth = 240

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = wishes
        wishes.isRichText = false
        wishes.font = .systemFont(ofSize: 13)
        wishes.isAutomaticQuoteSubstitutionEnabled = false
        wishes.isAutomaticTextReplacementEnabled = false
        wishes.autoresizingMask = [.width]
        wishes.isVerticallyResizable = true
        wishes.textContainerInset = NSSize(width: 4, height: 4)
        scroll.widthAnchor.constraint(equalToConstant: 300).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 108).isActive = true

        var rows: [[NSView]] = []
        var headers: [Int] = []
        func header(_ text: String) {
            headers.append(rows.count)
            let l = NSTextField(labelWithString: text)
            l.font = .boldSystemFont(ofSize: 13)
            rows.append([l, NSGridCell.emptyContentView])
        }
        func row(_ title: String, _ views: NSView...) {
            let l = NSTextField(labelWithString: title)
            l.textColor = .secondaryLabelColor
            let stack = NSStackView(views: views)
            stack.orientation = .horizontal
            stack.spacing = 8
            stack.alignment = .centerY
            rows.append([l, stack])
        }

        header(tr("工资", "Salary"))
        row(tr("计薪方式", "Pay type"), salaryType)
        row(tr("金额", "Amount"), salaryField, salaryUnit)
        row(tr("日薪折算", "Daily pay basis"), dayMode, customDays, customDaysUnit)
        row("", dailyHint)
        header(tr("上下班", "Working hours"))
        row(tr("上班时间", "Start time"), start, inline(tr("下班时间", "End time")), end)
        row(tr("午休", "Lunch"), lunch, lunchStart, lunchTo, lunchEnd)
        row(tr("工作日", "Workdays"), workdays)
        header(tr("显示", "Display"))
        row(tr("语言", "Language"), languageControl)
        row(tr("发薪日", "Payday"), payday)
        row(tr("货币", "Currency"), currency, inline(tr("小数位", "Decimals")), decimals)
        row(tr("菜单栏", "Menu bar"), menuBar)
        row(tr("悬浮窗大小", "Widget size"), size, inline(tr("不透明度", "Opacity")), opacity)
        row("", sound)
        row("", login)
        header(tr("心愿单", "Wishlist"))
        row("", hint(tr("每行一项：名称 价格，例如「一杯奶茶 15」。悬浮窗会算出还要工作多久才买得起。",
                        "One item per line: Name Price, e.g. “Milk tea 15”. The widget calculates how much longer you need to work to afford it.")))
        row("", scroll)

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.rowAlignment = .none
        grid.column(at: 0).xPlacement = .trailing
        for i in 0..<grid.numberOfRows { grid.row(at: i).yPlacement = .center }
        for i in headers {
            grid.row(at: i).mergeCells(in: NSRange(location: 0, length: 2))
            grid.cell(atColumnIndex: 0, rowIndex: i).xPlacement = .leading
            if i > 0 { grid.row(at: i).topPadding = 10 }
        }

        let intro = NSTextField(wrappingLabelWithString: tr(
            "先填工资和上下班时间。保存后，屏幕右上角的像素悬浮窗就开始实时跳钱；之后右键悬浮窗、或点菜单栏的金币，都能回来改。",
            "Enter your salary and working hours. After saving, the pixel widget in the upper-right corner starts counting your earnings. Right-click the widget or click the menu-bar coin to return here."))
        intro.preferredMaxLayoutWidth = 420
        intro.isHidden = !firstRun

        let cancel = NSButton(title: tr("取消", "Cancel"), target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: firstRun ? tr("保存并开始计时", "Save and start") : tr("保存", "Save"),
                            target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [error, spacer, cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [intro, grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window?.contentView = content
        window?.setContentSize(stack.fittingSize)
    }

    private func inline(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func hint(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.textColor = .secondaryLabelColor
        l.font = .systemFont(ofSize: 12)
        l.preferredMaxLayoutWidth = 300
        return l
    }

    private static func timePicker() -> NSDatePicker {
        let p = NSDatePicker()
        p.datePickerStyle = .textFieldAndStepper
        p.datePickerElements = .hourMinute
        p.locale = Locale(identifier: "zh_CN")
        let gmt = TimeZone(secondsFromGMT: 0)!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = gmt
        p.calendar = cal
        p.timeZone = gmt
        return p
    }

    private func setMinutes(_ p: NSDatePicker, _ m: Int) {
        p.dateValue = Date(timeIntervalSinceReferenceDate: TimeInterval(m) * 60)
    }

    private func minutes(_ p: NSDatePicker) -> Int {
        let total = Int(p.dateValue.timeIntervalSinceReferenceDate.rounded()) / 60
        return (total % 1440 + 1440) % 1440
    }

    // MARK: 读写

    private func load(_ s: PaySettings, size widgetSize: WidgetSize, opacity alpha: Double, launchAtLogin: Bool) {
        languageControl.selectItem(at: AppLanguage.allCases.firstIndex(of: s.language) ?? 0)
        salaryType.selectItem(at: PaySettings.SalaryType.allCases.firstIndex(of: s.salaryType) ?? 0)
        salaryField.stringValue = s.salary > 0 ? Self.plain(s.salary) : ""
        dayMode.selectItem(at: PaySettings.DayMode.allCases.firstIndex(of: s.dayMode) ?? 0)
        customDays.stringValue = Self.plain(s.customDays)
        setMinutes(start, s.start)
        setMinutes(end, s.end)
        lunch.state = s.lunchEnabled ? .on : .off
        setMinutes(lunchStart, s.lunchStart)
        setMinutes(lunchEnd, s.lunchEnd)
        for (i, d) in Self.weekdayOrder.enumerated() { workdays.setSelected(s.workdays.contains(d), forSegment: i) }
        payday.selectItem(at: s.payday)
        currency.selectItem(withTitle: s.currency)
        decimals.selectItem(at: s.decimals - 2)
        menuBar.selectItem(at: PaySettings.MenuBarMode.allCases.firstIndex(of: s.menuBar) ?? 0)
        size.selectedSegment = WidgetSize.allCases.firstIndex(of: widgetSize) ?? 1
        opacity.doubleValue = alpha
        sound.state = s.sound ? .on : .off
        login.state = launchAtLogin ? .on : .off
        wishes.string = s.wishlist.map { "\($0.name) \(Self.plain($0.price))" }.joined(separator: "\n")
        refreshEnabled()
    }

    @objc private func refreshEnabled() {
        let type = PaySettings.SalaryType.allCases[max(0, salaryType.indexOfSelectedItem)]
        salaryUnit.stringValue = language == .en
            ? ["/ month", "/ day", "/ hour"][max(0, salaryType.indexOfSelectedItem)]
            : ["元 / 月", "元 / 天", "元 / 小时"][max(0, salaryType.indexOfSelectedItem)]
        dayMode.isEnabled = type == .monthly
        customDays.isEnabled = type == .monthly && dayMode.indexOfSelectedItem == 2
        let lunchOn = lunch.state == .on
        lunchStart.isEnabled = lunchOn
        lunchEnd.isEnabled = lunchOn
        lunchTo.textColor = lunchOn ? .secondaryLabelColor : .disabledControlTextColor
        menuBar.item(at: 1)?.title = payday.indexOfSelectedItem > 0
            ? tr("本期已赚", "This period's earnings") : tr("本月已赚", "This month's earnings")
        refreshHint()
    }

    func controlTextDidChange(_ obj: Notification) {
        refreshHint()
    }

    /// 按表单现在填的内容算出日薪、时薪，并写明是怎么算的。计薪方式选错了，在这里一眼就能看出来。
    private func refreshHint() {
        let s = formSettings()
        guard s.salary > 0, !PayCore.segments(s).isEmpty, !s.workdays.isEmpty else {
            dailyHint.stringValue = tr("填好金额和上下班时间，这里会算出日薪和时薪。",
                                       "Enter the amount and hours to see your daily and hourly pay.")
            return
        }
        let snap = PayCore.snapshot(s, at: Date())
        func money(_ v: Double) -> String { PayCore.formatMoney(v, s, decimals: 2) }
        let range = PayCore.periodRange(snap)
        let n = snap.periodWorkdays
        let hours = PayCore.formatWorkTime(snap.paidPerDay, paidPerDay: 0, language: language)
        var lines: [String]
        switch s.salaryType {
        case .monthly:
            let basis: String
            switch s.dayMode {
            case .actual:
                basis = s.payday > 0 ? tr("本期 \(n) 个工作日（\(range)）", "\(n) workdays (\(range))")
                    : tr("\(snap.month) 月 \(n) 个工作日", "\(n) workdays this month")
            case .standard: basis = tr("21.75 天", "21.75 days")
            case .custom: basis = tr("\(Self.plain(s.customDays)) 天", "\(Self.plain(s.customDays)) days")
            }
            lines = [tr("折合日薪 \(money(snap.dailyPay))，时薪 \(money(snap.hourly))",
                        "≈ \(money(snap.dailyPay))/day, \(money(snap.hourly))/hour"),
                     "= \(Self.plain(s.salary)) ÷ \(basis)"]
        case .daily:
            lines = [tr("时薪 \(money(snap.hourly))（每天计薪 \(hours)）",
                        "\(money(snap.hourly))/hour (\(hours) paid per day)")]
        case .hourly:
            lines = [tr("折合日薪 \(money(snap.dailyPay))（每天计薪 \(hours)）",
                        "≈ \(money(snap.dailyPay))/day (\(hours) paid per day)")]
        }
        if s.salaryType != .monthly {
            lines.append(s.payday > 0
                ? tr("本期满勤 \(money(snap.periodFull))（\(n) 个工作日，\(range)）",
                     "Full period \(money(snap.periodFull)) (\(n) workdays, \(range))")
                : tr("本月满勤 \(money(snap.periodFull))（\(n) 个工作日）",
                     "Full month \(money(snap.periodFull)) (\(n) workdays)"))
        }
        dailyHint.stringValue = lines.joined(separator: "\n")
    }

    /// 按表单现在的样子拼一份设置（还没校验）。
    private func formSettings() -> PaySettings {
        var s = PaySettings()
        s.language = AppLanguage.allCases[max(0, languageControl.indexOfSelectedItem)]
        s.salaryType = PaySettings.SalaryType.allCases[max(0, salaryType.indexOfSelectedItem)]
        s.salary = Self.number(salaryField.stringValue) ?? 0
        s.dayMode = PaySettings.DayMode.allCases[max(0, dayMode.indexOfSelectedItem)]
        s.customDays = Self.number(customDays.stringValue) ?? 22
        s.start = minutes(start)
        s.end = minutes(end)
        s.lunchEnabled = lunch.state == .on
        s.lunchStart = minutes(lunchStart)
        s.lunchEnd = minutes(lunchEnd)
        s.workdays = Self.weekdayOrder.enumerated().filter { workdays.isSelected(forSegment: $0.offset) }.map(\.element)
        s.payday = max(0, payday.indexOfSelectedItem)
        s.currency = currency.titleOfSelectedItem ?? "¥"
        s.decimals = decimals.indexOfSelectedItem + 2
        s.menuBar = PaySettings.MenuBarMode.allCases[max(0, menuBar.indexOfSelectedItem)]
        s.sound = sound.state == .on
        s.wishlist = Self.parseWishes(wishes.string)
        let previousLanguage = originalSettings?.language ?? .zhHans
        if s.language != previousLanguage, s.wishlist == PaySettings.defaultWishlist(for: previousLanguage) {
            s.wishlist = PaySettings.defaultWishlist(for: s.language)
        }
        s.normalize()
        return s
    }

    @objc private func save() {
        let s = formSettings()
        if let problem = PayCore.validate(s).first {
            error.stringValue = problem.message
            switch problem.field {
            case .salary: window?.makeFirstResponder(salaryField)
            case .end: window?.makeFirstResponder(end)
            case .lunch: window?.makeFirstResponder(lunchStart)
            case .start, .workdays: break
            }
            NSSound.beep()
            return
        }
        error.stringValue = ""
        let widgetSize = WidgetSize.allCases[max(0, size.selectedSegment)]
        if let loginError = onSave?(s, widgetSize, opacity.doubleValue, login.state == .on) {
            let alert = NSAlert()
            alert.messageText = L10n.t(s.language, "设置已保存，但开机自动启动没有打开",
                                       "Settings saved, but launch at login could not be enabled")
            alert.informativeText = loginError + L10n.t(s.language,
                "\n\n把「上班激励器」拖进「应用程序」文件夹后再试一次。",
                "\n\nMove Work Motivator into the Applications folder and try again.")
            alert.runModal()
        }
        window?.close()
    }

    @objc private func cancel() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    // MARK: 小工具

    private static func number(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "¥", with: "").trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    private static func plain(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    /// "一件 T 恤 99" → 名称「一件 T 恤」，价格 99。最后一段是价格，前面都算名称。
    static func parseWishes(_ text: String) -> [Wish] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            var parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "　" }).map(String.init)
            guard parts.count >= 2, let last = parts.popLast(),
                  let price = number(last.replacingOccurrences(of: "元", with: "")), price > 0 else { return nil }
            return Wish(name: parts.joined(separator: " "), price: price)
        }
    }
}
