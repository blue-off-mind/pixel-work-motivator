// 上班激励器 · 计算核心
//
// 纯 Foundation，不依赖 AppKit：悬浮窗、菜单栏、单元测试共用这一份。
// 以后做 Windows 版照着这个文件移植，规则说明见 docs/计算规则.md。

import Foundation

struct Wish: Codable, Equatable {
    var name: String
    var price: Double
}

struct PaySettings: Codable, Equatable {
    enum SalaryType: String, Codable, CaseIterable { case monthly, daily, hourly }
    /// 月薪折算日薪按几天：本期（没设发薪日就是本月）实际工作日 / 21.75 天 / 自定义
    enum DayMode: String, Codable, CaseIterable { case actual, standard, custom }
    enum MenuBarMode: String, Codable, CaseIterable { case today, month, countdown, off }

    var salaryType: SalaryType = .monthly
    var language: AppLanguage = .zhHans
    var salary: Double = 0
    var dayMode: DayMode = .actual
    var customDays: Double = 22
    var start = 9 * 60 // 上班时间：零点起的分钟数
    var end = 18 * 60
    var lunchEnabled = true // 午休不计薪
    var lunchStart = 12 * 60
    var lunchEnd = 13 * 60
    var workdays: [Int] = [1, 2, 3, 4, 5] // 0=周日 … 6=周六
    var payday = 0 // 每月几号发薪；设了就按发薪周期累计，0 表示不设、按自然月
    var currency = "¥"
    var decimals = 4
    var menuBar: MenuBarMode = .today
    var sound = false
    var wishlist: [Wish] = PaySettings.defaultWishlist

    static let currencies = ["¥", "$", "€", "£"]
    static let defaultWishlist: [Wish] = [
        Wish(name: "一杯奶茶", price: 15),
        Wish(name: "一张电影票", price: 45),
        Wish(name: "一件 T 恤", price: 99),
        Wish(name: "一顿火锅", price: 150),
        Wish(name: "一双跑鞋", price: 599),
        Wish(name: "一副降噪耳机", price: 1499),
        Wish(name: "一台游戏机", price: 2599),
        Wish(name: "一部新手机", price: 5999),
        Wish(name: "一次旅行", price: 8000),
    ]
    static let defaultWishlistEN: [Wish] = [
        Wish(name: "Milk tea", price: 15),
        Wish(name: "Movie ticket", price: 45),
        Wish(name: "T-shirt", price: 99),
        Wish(name: "Hot pot", price: 150),
        Wish(name: "Running shoes", price: 599),
        Wish(name: "ANC headphones", price: 1499),
        Wish(name: "Game console", price: 2599),
        Wish(name: "New phone", price: 5999),
        Wish(name: "Trip", price: 8000),
    ]

    static func defaultWishlist(for language: AppLanguage) -> [Wish] {
        language == .en ? defaultWishlistEN : defaultWishlist
    }

    init() {}

    /// 旧版本或缺字段的 JSON 一律用默认值兜底，读进来再整理一遍。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PaySettings()
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        salaryType = get(.salaryType, d.salaryType)
        language = get(.language, d.language)
        salary = get(.salary, d.salary)
        dayMode = get(.dayMode, d.dayMode)
        customDays = get(.customDays, d.customDays)
        start = get(.start, d.start)
        end = get(.end, d.end)
        lunchEnabled = get(.lunchEnabled, d.lunchEnabled)
        lunchStart = get(.lunchStart, d.lunchStart)
        lunchEnd = get(.lunchEnd, d.lunchEnd)
        workdays = get(.workdays, d.workdays)
        payday = get(.payday, d.payday)
        currency = get(.currency, d.currency)
        decimals = get(.decimals, d.decimals)
        menuBar = get(.menuBar, d.menuBar)
        sound = get(.sound, d.sound)
        wishlist = get(.wishlist, PaySettings.defaultWishlist(for: language))
        normalize()
    }

    /// 把越界、重复、空白的值整理成合法范围；不负责判断"上下班时间是否合理"，那是 validate 的事。
    mutating func normalize() {
        salary = salary.isFinite ? max(0, salary) : 0
        customDays = customDays.isFinite ? min(31, max(1, customDays)) : 22
        for keyPath in [\PaySettings.start, \.end, \.lunchStart, \.lunchEnd] {
            self[keyPath: keyPath] = min(24 * 60, max(0, self[keyPath: keyPath]))
        }
        workdays = Array(Set(workdays.filter { (0...6).contains($0) })).sorted()
        payday = min(31, max(0, payday))
        if !PaySettings.currencies.contains(currency) { currency = "¥" }
        decimals = min(6, max(2, decimals))
        wishlist = wishlist
            .map { Wish(name: String($0.name.trimmingCharacters(in: .whitespaces).prefix(20)), price: $0.price) }
            .filter { !$0.name.isEmpty && $0.price.isFinite && $0.price > 0 }
    }

    func normalized() -> PaySettings {
        var s = self
        s.normalize()
        return s
    }
}

struct Segment: Equatable {
    var start: Double // 零点起的秒
    var end: Double
    var length: Double { end - start }
}

struct NextStart: Equatable {
    var date: Date
    var label: String
}

struct PaySnapshot {
    enum Status: String { case setup, before, working, lunch, after, off }

    var status: Status
    var year: Int
    var month: Int // 1...12
    var day: Int
    var weekday: Int // 0=周日
    var secOfDay: Double
    var isWorkday: Bool
    var segments: [Segment]
    var paidPerDay: Double // 一天计薪秒数
    var dailyPay: Double
    var rate: Double // 每计薪秒
    var worked: Double // 今天已干的计薪秒
    var earnedToday: Double
    var countdown: Double // 距下一个节点（下班/开工/上班）的秒数
    /// 本期：设了发薪日是 [上一个发薪日, 下一个发薪日)，没设就是自然月。都是当天零点，end 不含。
    var periodStart: Date
    var periodEnd: Date
    var periodWorkdays: Int
    var periodEarned: Double // 本期已过的工作日按满勤算，加上今天已赚
    var periodFull: Double
    var nextStart: NextStart?
    var paydayDays: Int?

    var hourly: Double { rate * 3600 }
    var progress: Double { paidPerDay > 0 ? worked / paidPerDay : 0 }
}

enum SettingsField: String {
    case salary, start, end, lunch, workdays
}

enum PayCore {
    static let weekdayCN = ["日", "一", "二", "三", "四", "五", "六"]
    static let weekdayEN = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    static func statusText(_ status: PaySnapshot.Status, _ language: AppLanguage) -> String {
        if language == .en {
            switch status {
            case .setup: return "Set up"
            case .before: return "Before work"
            case .working: return "Working"
            case .lunch: return "Lunch"
            case .after: return "Off work"
            case .off: return "Day off"
            }
        }
        return [
            .setup: "待设置", .before: "未上班", .working: "上班中",
            .lunch: "午休中", .after: "已下班", .off: "休息日",
        ][status]!
    }

    static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    // MARK: 设置

    /// 按字段给出错误提示；空数组表示可以保存。
    static func validate(_ s: PaySettings) -> [(field: SettingsField, message: String)] {
        var e: [(SettingsField, String)] = []
        func tr(_ zh: String, _ en: String) -> String { L10n.t(s.language, zh, en) }
        if !(s.salary > 0) { e.append((.salary, tr("工资要填一个大于 0 的数", "Enter a salary greater than 0"))) }
        if s.end <= s.start {
            e.append((.end, tr("下班时间要晚于上班时间（暂不支持跨零点的班次）",
                               "End time must be after start time (overnight shifts are not supported)")))
        }
        if s.lunchEnabled {
            if s.lunchEnd <= s.lunchStart {
                e.append((.lunch, tr("午休结束要晚于开始", "Lunch end must be after its start")))
            } else if s.lunchStart < s.start || s.lunchEnd > s.end {
                e.append((.lunch, tr("午休要落在上下班时间之内", "Lunch must fall within working hours")))
            }
        }
        if s.workdays.isEmpty { e.append((.workdays, tr("至少选一天上班", "Select at least one working day"))) }
        return e
    }

    static func formatTime(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    // MARK: 排班

    /// 一天里计薪的时间段。午休把一天切成两段。
    static func segments(_ s: PaySettings) -> [Segment] {
        let st = Double(s.start * 60), en = Double(s.end * 60)
        guard en > st else { return [] }
        if s.lunchEnabled {
            let ls = Double(s.lunchStart * 60), le = Double(s.lunchEnd * 60)
            if le > ls, ls >= st, le <= en {
                var out: [Segment] = []
                if ls > st { out.append(Segment(start: st, end: ls)) }
                if en > le { out.append(Segment(start: le, end: en)) }
                return out
            }
        }
        return [Segment(start: st, end: en)]
    }

    /// 截至当天第 sec 秒，已经干了多少计薪秒。
    static func workedSeconds(_ segs: [Segment], at sec: Double) -> Double {
        segs.reduce(0) { $0 + min(max(sec - $1.start, 0), $1.length) }
    }

    static func daysInMonth(year: Int, month: Int, cal: Calendar) -> Int {
        let first = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        return cal.range(of: .day, in: .month, for: first)!.count
    }

    /// 本期的起止（都是当天零点，end 不含）。设了发薪日：从上一个发薪日（含当天）到下一个发薪日，
    /// 发薪日超过当月天数按月底算；没设：自然月。
    static func payPeriod(_ s: PaySettings, year y: Int, month m: Int, day d: Int,
                          cal: Calendar) -> (start: Date, end: Date) {
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }
        func shift(_ months: Int) -> (year: Int, month: Int) {
            let t = y * 12 + (m - 1) + months
            return (t / 12, t % 12 + 1)
        }
        func payday(_ y: Int, _ m: Int) -> Int { min(s.payday, daysInMonth(year: y, month: m, cal: cal)) }

        let next = shift(1)
        guard s.payday > 0 else { return (date(y, m, 1), date(next.year, next.month, 1)) }
        if d >= payday(y, m) {
            return (date(y, m, payday(y, m)), date(next.year, next.month, payday(next.year, next.month)))
        }
        let prev = shift(-1)
        return (date(prev.year, prev.month, payday(prev.year, prev.month)), date(y, m, payday(y, m)))
    }

    /// [from, to) 之间有几个工作日。from、to 都传当天零点。
    static func workdays(_ s: PaySettings, from: Date, to: Date, cal: Calendar = calendar) -> Int {
        let n = cal.dateComponents([.day], from: from, to: to).day ?? 0
        let first = cal.component(.weekday, from: from) - 1
        return (0..<max(0, n)).filter { s.workdays.contains((first + $0) % 7) }.count
    }

    static func dailyPay(_ s: PaySettings, periodWorkdays: Int, paidPerDay: Double) -> Double {
        switch s.salaryType {
        case .daily: return s.salary
        case .hourly: return s.salary * paidPerDay / 3600
        case .monthly:
            let days: Double
            switch s.dayMode {
            case .standard: days = 21.75
            case .custom: days = s.customDays
            case .actual: days = Double(periodWorkdays) // 本期最后一个工作日下班时，正好拿满一个月薪
            }
            return days > 0 ? s.salary / days : 0
        }
    }

    /// 从 date 往后找下一个上班时刻（最多看两周）。
    static func nextWorkStart(_ s: PaySettings, after date: Date, segs: [Segment], cal: Calendar) -> NextStart? {
        guard let first = segs.first, !s.workdays.isEmpty else { return nil }
        let midnight = cal.startOfDay(for: date)
        for i in 0..<15 {
            guard let day = cal.date(byAdding: .day, value: i, to: midnight) else { continue }
            let weekday = cal.component(.weekday, from: day) - 1
            guard s.workdays.contains(weekday),
                  let start = cal.date(byAdding: .second, value: Int(first.start), to: day),
                  start > date else { continue }
            let hm = formatTime(Int(first.start) / 60)
            let label: String
            switch i {
            case 0: label = s.language == .en ? "Today \(hm)" : "今天 \(hm)"
            case 1: label = s.language == .en ? "Tomorrow \(hm)" : "明天 \(hm)"
            case 2..<7:
                label = s.language == .en ? "\(weekdayEN[weekday]) \(hm)" : "周\(weekdayCN[weekday]) \(hm)"
            default:
                let c = cal.dateComponents([.month, .day], from: day)
                label = s.language == .en ? "\(c.month!)/\(c.day!) \(hm)" : "\(c.month!)月\(c.day!)日 \(hm)"
            }
            return NextStart(date: start, label: label)
        }
        return nil
    }

    static func paydayDays(_ s: PaySettings, year: Int, month: Int, day: Int, cal: Calendar) -> Int? {
        guard s.payday > 0 else { return nil }
        let dim = daysInMonth(year: year, month: month, cal: cal)
        let thisMonth = min(s.payday, dim)
        if day <= thisMonth { return thisMonth - day }
        let (ny, nm) = month == 12 ? (year + 1, 1) : (year, month + 1)
        return dim - day + min(s.payday, daysInMonth(year: ny, month: nm, cal: cal))
    }

    // MARK: 快照：悬浮窗每一帧、菜单栏每次刷新都调这个

    static func snapshot(_ s: PaySettings, at date: Date, cal: Calendar = calendar) -> PaySnapshot {
        let c = cal.dateComponents([.year, .month, .day, .weekday], from: date)
        let (y, m, d) = (c.year!, c.month!, c.day!)
        let weekday = c.weekday! - 1
        let midnight = cal.startOfDay(for: date)
        let sec = date.timeIntervalSince(midnight)

        let segs = segments(s)
        let paidPerDay = segs.reduce(0) { $0 + $1.length }
        let workday = s.workdays.contains(weekday)
        let period = payPeriod(s, year: y, month: m, day: d, cal: cal)
        let periodDays = workdays(s, from: period.start, to: period.end, cal: cal)
        let daily = paidPerDay > 0 ? dailyPay(s, periodWorkdays: periodDays, paidPerDay: paidPerDay) : 0
        let rate = paidPerDay > 0 ? daily / paidPerDay : 0
        let worked = workday ? workedSeconds(segs, at: sec) : 0

        var status: PaySnapshot.Status
        var countdown = 0.0
        if segs.isEmpty || !(s.salary > 0) {
            status = .setup
        } else if !workday {
            status = .off
        } else if sec < segs[0].start {
            status = .before
            countdown = segs[0].start - sec
        } else if sec >= segs[segs.count - 1].end {
            status = .after
        } else if segs.contains(where: { sec >= $0.start && sec < $0.end }) {
            status = .working
            countdown = segs[segs.count - 1].end - sec
        } else {
            status = .lunch
            countdown = (segs.first(where: { $0.start > sec })?.start ?? sec) - sec
        }

        // 本期：今天之前的工作日按满勤算，再加上今天已赚
        let pastDays = workdays(s, from: period.start, to: midnight, cal: cal)
        let earned = worked * rate

        return PaySnapshot(
            status: status, year: y, month: m, day: d, weekday: weekday, secOfDay: sec,
            isWorkday: workday, segments: segs, paidPerDay: paidPerDay, dailyPay: daily, rate: rate,
            worked: worked, earnedToday: earned, countdown: countdown,
            periodStart: period.start, periodEnd: period.end, periodWorkdays: periodDays,
            periodEarned: Double(pastDays) * daily + earned,
            periodFull: Double(periodDays) * daily,
            nextStart: [.before, .after, .off].contains(status) ? nextWorkStart(s, after: date, segs: segs, cal: cal) : nil,
            paydayDays: paydayDays(s, year: y, month: m, day: d, cal: cal)
        )
    }

    // MARK: 文案与格式

    /// 向下取整再格式化：计数器永远不显示还没挣到的钱。
    static func formatMoney(_ v: Double, _ s: PaySettings, decimals: Int? = nil) -> String {
        let dec = decimals ?? s.decimals
        let p = pow(10.0, Double(dec))
        let floored = (v * p * (1 + 1e-12) + 1e-9).rounded(.down) / p
        let text = String(format: "%.\(dec)f", floored)
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        var grouped = ""
        for (i, ch) in parts[0].reversed().enumerated() {
            if i > 0 && i % 3 == 0 { grouped.append(",") }
            grouped.append(ch)
        }
        return s.currency + String(grouped.reversed()) + (parts.count > 1 ? "." + parts[1] : "")
    }

    /// 秒 → 2:54:20
    static func formatClock(_ sec: Double) -> String {
        let t = max(0, Int(sec.rounded(.up)))
        return String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60)
    }

    /// 「本期已赚」（设了发薪日，按发薪周期）或「本月已赚」（自然月）。
    static func periodEarnedLabel(_ s: PaySettings) -> String {
        s.payday > 0 ? L10n.t(s.language, "本期已赚", "This period") : L10n.t(s.language, "本月已赚", "This month")
    }

    /// 本期日期，含首尾两天，例如 "10.15-11.14"。
    static func periodRange(_ snap: PaySnapshot, cal: Calendar = calendar) -> String {
        let last = cal.date(byAdding: .day, value: -1, to: snap.periodEnd) ?? snap.periodEnd
        let a = cal.dateComponents([.month, .day], from: snap.periodStart)
        let b = cal.dateComponents([.month, .day], from: last)
        return String(format: "%d.%02d-%d.%02d", a.month!, a.day!, b.month!, b.day!)
    }

    /// 计薪秒 → "2 小时 53 分" / "2 hr 53 min"；超过一天半的工时折成工作日。
    static func formatWorkTime(_ sec: Double, paidPerDay: Double, language: AppLanguage = .zhHans) -> String {
        if language == .en {
            if sec < 60 { return "under 1 min" }
            if paidPerDay > 0, sec > paidPerDay * 1.5 {
                let days = sec / paidPerDay
                return (days < 10 ? String(format: "%.1f", days) : String(Int(days.rounded()))) + " workdays"
            }
            let h = Int(sec) / 3600, mm = Int(sec) % 3600 / 60
            if h == 0 { return "\(mm) min" }
            return "\(h) hr" + (mm > 0 ? " \(mm) min" : "")
        }
        if sec < 60 { return "不到 1 分钟" }
        if paidPerDay > 0, sec > paidPerDay * 1.5 {
            let days = sec / paidPerDay
            return (days < 10 ? String(format: "%.1f", days) : String(Int(days.rounded()))) + " 个工作日"
        }
        let h = Int(sec) / 3600, mm = Int(sec) % 3600 / 60
        if h == 0 { return "\(mm) 分钟" }
        return "\(h) 小时" + (mm > 0 ? " \(mm) 分" : "")
    }

    private static func countOf(_ name: String, _ n: Int) -> String {
        name.hasPrefix("一") ? "\(n) " + name.dropFirst() : "\(name) ×\(n)"
    }

    /// 工资条上轮播的提示，每条都带具体数字。
    static func tips(_ s: PaySettings, _ snap: PaySnapshot) -> [String] {
        func money(_ v: Double, _ dec: Int = 2) -> String { formatMoney(v, s, decimals: dec) }
        func tr(_ zh: String, _ en: String) -> String { L10n.t(s.language, zh, en) }
        if snap.status == .setup {
            return [tr("右键 › 设置，填好工资和上下班时间就开始计时。",
                       "Right-click › Settings, then enter your salary and working hours to start.")]
        }

        var out: [String] = []
        let items = s.wishlist.sorted { $0.price < $1.price }
        let earned = snap.earnedToday

        if [.working, .lunch, .before].contains(snap.status), snap.rate > 0,
           let next = items.first(where: { $0.price > earned }) {
            let need = formatWorkTime((next.price - earned) / snap.rate, paidPerDay: snap.paidPerDay, language: s.language)
            out.append(tr("再工作 \(need)，就能赚到\(next.name)（\(money(next.price, 0))）。",
                          "Another \(need) of work earns you \(next.name) (\(money(next.price, 0)))."))
        }
        switch snap.status {
        case .working:
            out.append(tr("这一分钟又进账 \(money(snap.rate * 60))，一小时就是 \(money(snap.hourly))。",
                          "This minute adds \(money(snap.rate * 60)); one hour earns \(money(snap.hourly))."))
        case .lunch:
            out.append(tr("午休不计薪，吃饱再战。还有 \(formatClock(snap.countdown)) 开工。",
                          "Lunch is unpaid. Back to work in \(formatClock(snap.countdown))."))
        case .before:
            out.append(tr("今天满勤能赚 \(money(snap.dailyPay))，\(formatClock(snap.countdown)) 后开始进账。",
                          "A full day earns \(money(snap.dailyPay)). Earnings start in \(formatClock(snap.countdown))."))
        case .after:
            out.append(tr("今天的 \(money(snap.dailyPay)) 已经到手，收工！",
                          "Today's \(money(snap.dailyPay)) is earned. Time to clock out!"))
            out.append(tr("还没走？现在多待的每一秒都是免费加班。",
                          "Still here? Every extra second is unpaid overtime."))
        case .off:
            out.append(tr("今天休息，\(periodEarnedLabel(s)) \(money(snap.periodEarned))。",
                          "Day off. You've earned \(money(snap.periodEarned)) "
                              + (s.payday > 0 ? "this pay period." : "this month.")))
        case .setup: break
        }
        if snap.status != .before, snap.status != .off,
           let got = items.last(where: { $0.price <= earned }) {
            let n = Int(earned / got.price)
            if s.language == .en {
                out.append("Today's earnings cover \(n > 1 ? "\(got.name) ×\(n)" : got.name).")
            } else {
                out.append("今天已经赚到\(n > 1 ? countOf(got.name, n) : got.name)了。")
            }
        }
        if let days = snap.paydayDays {
            out.append(days == 0
                ? tr("今天发工资，记得查账。", "It's payday—remember to check your account.")
                : tr("离发工资还有 \(days) 天。", days == 1 ? "1 day until payday." : "\(days) days until payday."))
        }
        return out
    }

    /// 菜单栏上的那一小段文字。
    static func menuBarText(_ s: PaySettings, _ snap: PaySnapshot) -> String {
        if s.menuBar == .off { return "" }
        if snap.status == .setup { return statusText(.setup, s.language) }
        switch s.menuBar {
        case .month: return formatMoney(snap.periodEarned, s, decimals: 2)
        case .countdown:
            switch snap.status {
            case .working: return L10n.t(s.language, "下班 ", "Off in ") + formatClock(snap.countdown)
            case .lunch: return L10n.t(s.language, "开工 ", "Back in ") + formatClock(snap.countdown)
            case .before: return L10n.t(s.language, "上班 ", "Start in ") + formatClock(snap.countdown)
            default: return statusText(snap.status, s.language)
            }
        default:
            return snap.status == .off ? statusText(.off, s.language) : formatMoney(snap.earnedToday, s, decimals: 2)
        }
    }

    /// 菜单里的几行说明。
    static func menuLines(_ s: PaySettings, _ snap: PaySnapshot) -> [String] {
        func tr(_ zh: String, _ en: String) -> String { L10n.t(s.language, zh, en) }
        if snap.status == .setup { return [tr("还没设置工资", "Salary not set")] }
        var lines = [tr("\(statusText(snap.status, s.language)) · 今日已赚 \(formatMoney(snap.earnedToday, s))",
                        "\(statusText(snap.status, s.language)) · Today \(formatMoney(snap.earnedToday, s))")]
        switch snap.status {
        case .working: lines.append(tr("距离下班 ", "Off work in ") + formatClock(snap.countdown))
        case .lunch: lines.append(tr("午休还剩 ", "Back to work in ") + formatClock(snap.countdown))
        case .before: lines.append(tr("距离上班 ", "Work starts in ") + formatClock(snap.countdown))
        default:
            if let next = snap.nextStart { lines.append(tr("下次上班 ", "Next start: ") + next.label) }
        }
        lines.append(periodEarnedLabel(s) + tr(" ", ": ") + formatMoney(snap.periodEarned, s, decimals: 2))
        return lines
    }
}
