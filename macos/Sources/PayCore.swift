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
    /// 月薪折算日薪按几天：当月实际工作日 / 21.75 天 / 自定义
    enum DayMode: String, Codable, CaseIterable { case actual, standard, custom }
    enum MenuBarMode: String, Codable, CaseIterable { case today, month, countdown, off }

    var salaryType: SalaryType = .monthly
    var salary: Double = 0
    var dayMode: DayMode = .actual
    var customDays: Double = 22
    var start = 9 * 60 // 上班时间：零点起的分钟数
    var end = 18 * 60
    var lunchEnabled = true // 午休不计薪
    var lunchStart = 12 * 60
    var lunchEnd = 13 * 60
    var workdays: [Int] = [1, 2, 3, 4, 5] // 0=周日 … 6=周六
    var payday = 0 // 每月几号发薪，0 表示不显示
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

    init() {}

    /// 旧版本或缺字段的 JSON 一律用默认值兜底，读进来再整理一遍。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PaySettings()
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        salaryType = get(.salaryType, d.salaryType)
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
        wishlist = get(.wishlist, d.wishlist)
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
    var monthEarned: Double
    var monthFull: Double
    var workdaysInMonth: Int
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
    static let statusText: [PaySnapshot.Status: String] = [
        .setup: "待设置", .before: "未上班", .working: "上班中",
        .lunch: "午休中", .after: "已下班", .off: "休息日",
    ]

    static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    // MARK: 设置

    /// 按字段给出错误提示；空数组表示可以保存。
    static func validate(_ s: PaySettings) -> [(field: SettingsField, message: String)] {
        var e: [(SettingsField, String)] = []
        if !(s.salary > 0) { e.append((.salary, "工资要填一个大于 0 的数")) }
        if s.end <= s.start { e.append((.end, "下班时间要晚于上班时间（暂不支持跨零点的班次）")) }
        if s.lunchEnabled {
            if s.lunchEnd <= s.lunchStart {
                e.append((.lunch, "午休结束要晚于开始"))
            } else if s.lunchStart < s.start || s.lunchEnd > s.end {
                e.append((.lunch, "午休要落在上下班时间之内"))
            }
        }
        if s.workdays.isEmpty { e.append((.workdays, "至少选一天上班")) }
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

    static func firstWeekday(year: Int, month: Int, cal: Calendar) -> Int {
        let first = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        return cal.component(.weekday, from: first) - 1
    }

    static func workdaysInMonth(_ s: PaySettings, year: Int, month: Int, cal: Calendar = calendar) -> Int {
        let first = firstWeekday(year: year, month: month, cal: cal)
        let n = daysInMonth(year: year, month: month, cal: cal)
        return (0..<n).filter { s.workdays.contains((first + $0) % 7) }.count
    }

    static func dailyPay(_ s: PaySettings, year: Int, month: Int, paidPerDay: Double, cal: Calendar) -> Double {
        switch s.salaryType {
        case .daily: return s.salary
        case .hourly: return s.salary * paidPerDay / 3600
        case .monthly:
            let days: Double
            switch s.dayMode {
            case .standard: days = 21.75
            case .custom: days = s.customDays
            case .actual: days = Double(workdaysInMonth(s, year: year, month: month, cal: cal))
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
            case 0: label = "今天 \(hm)"
            case 1: label = "明天 \(hm)"
            case 2..<7: label = "周\(weekdayCN[weekday]) \(hm)"
            default:
                let c = cal.dateComponents([.month, .day], from: day)
                label = "\(c.month!)月\(c.day!)日 \(hm)"
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
        let sec = date.timeIntervalSince(cal.startOfDay(for: date))

        let segs = segments(s)
        let paidPerDay = segs.reduce(0) { $0 + $1.length }
        let workday = s.workdays.contains(weekday)
        let daily = paidPerDay > 0 ? dailyPay(s, year: y, month: m, paidPerDay: paidPerDay, cal: cal) : 0
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

        // 本月：今天之前的工作日按满勤算，再加上今天已赚
        let first = firstWeekday(year: y, month: m, cal: cal)
        let pastDays = (0..<(d - 1)).filter { s.workdays.contains((first + $0) % 7) }.count
        let monthDays = workdaysInMonth(s, year: y, month: m, cal: cal)
        let earned = worked * rate

        return PaySnapshot(
            status: status, year: y, month: m, day: d, weekday: weekday, secOfDay: sec,
            isWorkday: workday, segments: segs, paidPerDay: paidPerDay, dailyPay: daily, rate: rate,
            worked: worked, earnedToday: earned, countdown: countdown,
            monthEarned: Double(pastDays) * daily + earned,
            monthFull: Double(monthDays) * daily,
            workdaysInMonth: monthDays,
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

    /// 计薪秒 → "2 小时 53 分"；超过一天半的工时折成工作日。
    static func formatWorkTime(_ sec: Double, paidPerDay: Double) -> String {
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
        if snap.status == .setup { return ["右键 › 设置，填好工资和上下班时间就开始计时。"] }

        var out: [String] = []
        let items = s.wishlist.sorted { $0.price < $1.price }
        let earned = snap.earnedToday

        if [.working, .lunch, .before].contains(snap.status), snap.rate > 0,
           let next = items.first(where: { $0.price > earned }) {
            let need = formatWorkTime((next.price - earned) / snap.rate, paidPerDay: snap.paidPerDay)
            out.append("再工作 \(need)，就能赚到\(next.name)（\(money(next.price, 0))）。")
        }
        switch snap.status {
        case .working: out.append("这一分钟又进账 \(money(snap.rate * 60))，一小时就是 \(money(snap.hourly))。")
        case .lunch: out.append("午休不计薪，吃饱再战。还有 \(formatClock(snap.countdown)) 开工。")
        case .before: out.append("今天满勤能赚 \(money(snap.dailyPay))，\(formatClock(snap.countdown)) 后开始进账。")
        case .after:
            out.append("今天的 \(money(snap.dailyPay)) 已经到手，收工！")
            out.append("还没走？现在多待的每一秒都是免费加班。")
        case .off: out.append("今天休息，本月已赚 \(money(snap.monthEarned))。")
        case .setup: break
        }
        if snap.status != .before, snap.status != .off,
           let got = items.last(where: { $0.price <= earned }) {
            let n = Int(earned / got.price)
            out.append("今天已经赚到\(n > 1 ? countOf(got.name, n) : got.name)了。")
        }
        if let days = snap.paydayDays {
            out.append(days == 0 ? "今天发工资，记得查账。" : "离发工资还有 \(days) 天。")
        }
        return out
    }

    /// 菜单栏上的那一小段文字。
    static func menuBarText(_ s: PaySettings, _ snap: PaySnapshot) -> String {
        if s.menuBar == .off { return "" }
        if snap.status == .setup { return "待设置" }
        switch s.menuBar {
        case .month: return formatMoney(snap.monthEarned, s, decimals: 2)
        case .countdown:
            switch snap.status {
            case .working: return "下班 " + formatClock(snap.countdown)
            case .lunch: return "开工 " + formatClock(snap.countdown)
            case .before: return "上班 " + formatClock(snap.countdown)
            default: return statusText[snap.status]!
            }
        default:
            return snap.status == .off ? "休息日" : formatMoney(snap.earnedToday, s, decimals: 2)
        }
    }

    /// 菜单里的几行说明。
    static func menuLines(_ s: PaySettings, _ snap: PaySnapshot) -> [String] {
        if snap.status == .setup { return ["还没设置工资"] }
        var lines = ["\(statusText[snap.status]!) · 今日已赚 \(formatMoney(snap.earnedToday, s))"]
        switch snap.status {
        case .working: lines.append("距离下班 " + formatClock(snap.countdown))
        case .lunch: lines.append("午休还剩 " + formatClock(snap.countdown))
        case .before: lines.append("距离上班 " + formatClock(snap.countdown))
        default: if let next = snap.nextStart { lines.append("下次上班 " + next.label) }
        }
        lines.append("本月已赚 " + formatMoney(snap.monthEarned, s, decimals: 2))
        return lines
    }
}
