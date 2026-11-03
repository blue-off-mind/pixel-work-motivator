// 计算核心测试。运行：./macos/build.sh test
import Foundation

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
PayCore.calendar = cal

// 2026 年 11 月：1 号是周日，周一到周五共 21 个工作日
func at(_ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: mi, second: s))!
}

func settings(_ edit: (inout PaySettings) -> Void = { _ in }) -> PaySettings {
    var s = PaySettings()
    s.salary = 8000
    edit(&s)
    return s.normalized()
}

let base = settings()
let daily = 8000.0 / 21
let rate = daily / (8 * 3600)

var failed = 0
var current = ""
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    if !ok {
        failed += 1
        print("  ✗ 第 \(line) 行：\(what())")
    }
}
func eq<T: Equatable>(_ a: T, _ b: T, line: Int = #line) { check(a == b, "\(a) ≠ \(b)", line: line) }
func close(_ a: Double, _ b: Double, eps: Double = 1e-9, line: Int = #line) {
    check(abs(a - b) < eps, "\(a) ≉ \(b)", line: line)
}
func test(_ name: String, _ body: () -> Void) {
    let before = failed
    body()
    print(failed == before ? "✓ \(name)" : "✗ \(name)")
}

test("读设置时补默认值并清洗") {
    let json = """
    {"salary": 12000, "decimals": 99, "workdays": [5, 1, 1, 3, 9], "currency": "₿",
     "wishlist": [{"name": "  奶茶 ", "price": 15}, {"name": "", "price": 3}, {"name": "空", "price": 0}]}
    """
    let s = try! JSONDecoder().decode(PaySettings.self, from: Data(json.utf8))
    eq(s.salary, 12000)
    eq(s.start, 9 * 60)
    eq(s.decimals, 6)
    eq(s.workdays, [1, 3, 5])
    eq(s.currency, "¥")
    eq(s.wishlist, [Wish(name: "奶茶", price: 15)])
    let empty = try! JSONDecoder().decode(PaySettings.self, from: Data("{}".utf8))
    eq(empty, PaySettings())
    let roundTrip = try! JSONDecoder().decode(PaySettings.self, from: JSONEncoder().encode(base))
    eq(roundTrip, base)
}

test("validate 给出具体字段的错误") {
    check(PayCore.validate(base).isEmpty, "base 应当合法")
    let bad = settings { $0.salary = 0; $0.start = 18 * 60; $0.end = 9 * 60; $0.workdays = [] }
    let fields = PayCore.validate(bad).map(\.field)
    eq(fields, [.salary, .end, .lunch, .workdays])
    let lunchOut = settings { $0.lunchStart = 8 * 60; $0.lunchEnd = 8 * 60 + 30 }
    eq(PayCore.validate(lunchOut).map(\.field), [.lunch])
    let lunchBack = settings { $0.lunchStart = 13 * 60; $0.lunchEnd = 12 * 60 }
    eq(PayCore.validate(lunchBack).map(\.field), [.lunch])
    let noLunch = settings { $0.lunchEnabled = false; $0.lunchStart = 3; $0.lunchEnd = 1 }
    check(PayCore.validate(noLunch).isEmpty, "关掉午休后不再校验午休时间")
}

test("午休把一天切成两段，不计薪") {
    eq(PayCore.segments(base), [Segment(start: 9 * 3600, end: 12 * 3600), Segment(start: 13 * 3600, end: 18 * 3600)])
    eq(PayCore.segments(settings { $0.lunchEnabled = false }), [Segment(start: 9 * 3600, end: 18 * 3600)])
    let lunchAtStart = settings { $0.lunchStart = 9 * 60; $0.lunchEnd = 10 * 60 }
    eq(PayCore.segments(lunchAtStart), [Segment(start: 10 * 3600, end: 18 * 3600)])
}

test("工作日计数") {
    eq(PayCore.workdaysInMonth(base, year: 2026, month: 11), 21)
    eq(PayCore.workdaysInMonth(settings { $0.workdays = [1, 2, 3, 4, 5, 6] }, year: 2026, month: 11), 25)
}

test("上班中：已赚、倒计时、本月累计") {
    let snap = PayCore.snapshot(base, at: at(3, 15, 5, 39)) // 周二
    eq(snap.status, .working)
    let worked = Double(3 * 3600 + 2 * 3600 + 5 * 60 + 39)
    eq(snap.worked, worked)
    close(snap.earnedToday, worked * rate)
    close(snap.dailyPay, daily)
    close(snap.hourly, daily / 8)
    eq(snap.countdown, Double(2 * 3600 + 54 * 60 + 21))
    close(snap.monthEarned, daily + worked * rate) // 11/2 周一按满勤补算
    close(snap.monthFull, 8000, eps: 1e-6)
    close(snap.progress, worked / (8 * 3600))
    check(snap.nextStart == nil, "上班中不需要下次上班时间")
}

test("午休、上班前、下班后、休息日、待设置") {
    let lunch = PayCore.snapshot(base, at: at(3, 12, 30))
    eq(lunch.status, .lunch)
    eq(lunch.countdown, 1800)
    close(lunch.earnedToday, 3 * 3600 * rate)

    let before = PayCore.snapshot(base, at: at(3, 8))
    eq(before.status, .before)
    eq(before.countdown, 3600)
    eq(before.earnedToday, 0)
    eq(before.nextStart?.label, "今天 09:00")

    let after = PayCore.snapshot(base, at: at(3, 19))
    eq(after.status, .after)
    close(after.earnedToday, daily)
    eq(after.nextStart?.label, "明天 09:00")

    eq(PayCore.snapshot(base, at: at(6, 19)).nextStart?.label, "周一 09:00")

    let saturday = PayCore.snapshot(base, at: at(7, 10))
    eq(saturday.status, .off)
    eq(saturday.earnedToday, 0)
    eq(saturday.nextStart?.label, "周一 09:00")
    close(saturday.monthEarned, 5 * daily)

    let setup = PayCore.snapshot(PaySettings(), at: at(3, 10))
    eq(setup.status, .setup)
    eq(setup.earnedToday, 0)
}

test("按当月工作日折算时，月底最后一天下班正好拿满月薪") {
    close(PayCore.snapshot(base, at: at(30, 19)).monthEarned, 8000, eps: 1e-6)
}

test("21.75 天、自定义天数、日薪、时薪") {
    close(PayCore.snapshot(settings { $0.dayMode = .standard }, at: at(3, 10)).dailyPay, 8000 / 21.75)
    close(PayCore.snapshot(settings { $0.dayMode = .custom; $0.customDays = 20 }, at: at(3, 10)).dailyPay, 400)
    close(PayCore.snapshot(settings { $0.salaryType = .daily; $0.salary = 300 }, at: at(3, 10)).dailyPay, 300)
    let hourly = PayCore.snapshot(settings { $0.salaryType = .hourly; $0.salary = 50 }, at: at(3, 10))
    close(hourly.dailyPay, 400)
    close(hourly.hourly, 50)
}

test("发薪日倒数") {
    let s15 = settings { $0.payday = 15 }
    eq(PayCore.snapshot(s15, at: at(3, 10)).paydayDays, 12)
    eq(PayCore.snapshot(s15, at: at(15, 10)).paydayDays, 0)
    eq(PayCore.snapshot(s15, at: at(20, 10)).paydayDays, 25) // 11 月 30 天
    eq(PayCore.snapshot(settings { $0.payday = 31 }, at: at(3, 10)).paydayDays, 27) // 没有 31 号就按 30 号
    eq(PayCore.snapshot(base, at: at(3, 10)).paydayDays, nil)
}

test("金额格式：向下取整、千分位、浮点误差") {
    eq(PayCore.formatMoney(1234.56789, base), "¥1,234.5678")
    eq(PayCore.formatMoney(129.3, base), "¥129.3000")
    eq(PayCore.formatMoney(0.29999999, base, decimals: 2), "¥0.29")
    eq(PayCore.formatMoney(0, base), "¥0.0000")
    eq(PayCore.formatMoney(1234567.891, settings { $0.currency = "$" }, decimals: 2), "$1,234,567.89")
}

test("时长格式") {
    eq(PayCore.formatClock(10461), "2:54:21")
    eq(PayCore.formatClock(59.2), "0:01:00")
    eq(PayCore.formatClock(-5), "0:00:00")
    let day = 8.0 * 3600
    eq(PayCore.formatWorkTime(30, paidPerDay: day), "不到 1 分钟")
    eq(PayCore.formatWorkTime(600, paidPerDay: day), "10 分钟")
    eq(PayCore.formatWorkTime(3600, paidPerDay: day), "1 小时")
    eq(PayCore.formatWorkTime(2 * 3600 + 53 * 60 + 10, paidPerDay: day), "2 小时 53 分")
    eq(PayCore.formatWorkTime(3 * day, paidPerDay: day), "3.0 个工作日")
    eq(PayCore.formatWorkTime(12 * day, paidPerDay: day), "12 个工作日")
}

test("提示文案带具体数字") {
    let t = PayCore.tips(base, PayCore.snapshot(base, at: at(3, 10))) // 已干 1 小时，约 ¥47.6
    check(t.contains { $0.hasPrefix("再工作 ") && $0.contains("一件 T 恤（¥99）") }, t.joined(separator: " | "))
    check(t.contains("今天已经赚到一张电影票了。"), t.joined(separator: " | "))
    check(t.contains { $0.hasPrefix("这一分钟又进账 ¥0.79") }, t.joined(separator: " | "))

    let ta = PayCore.tips(base, PayCore.snapshot(base, at: at(3, 19)))
    check(ta.contains("今天的 ¥380.95 已经到手，收工！"), ta.joined(separator: " | "))
    check(ta.contains { $0.hasPrefix("今天已经赚到") }, ta.joined(separator: " | "))
    eq(PayCore.tips(PaySettings(), PayCore.snapshot(PaySettings(), at: at(3, 10))).count, 1)
}

test("菜单栏文字") {
    let now = at(3, 15, 5, 39)
    let snap = PayCore.snapshot(base, at: now)
    check(PayCore.menuBarText(base, snap).range(of: #"^¥\d+\.\d{2}$"#, options: .regularExpression) != nil,
          PayCore.menuBarText(base, snap))
    let countdown = settings { $0.menuBar = .countdown }
    eq(PayCore.menuBarText(countdown, snap), "下班 2:54:21")
    eq(PayCore.menuBarText(countdown, PayCore.snapshot(base, at: at(3, 12, 30))), "开工 0:30:00")
    eq(PayCore.menuBarText(settings { $0.menuBar = .off }, snap), "")
    eq(PayCore.menuBarText(base, PayCore.snapshot(base, at: at(7, 10))), "休息日")
    eq(PayCore.menuBarText(PaySettings(), PayCore.snapshot(PaySettings(), at: now)), "待设置")
    eq(PayCore.menuLines(base, snap)[1], "距离下班 2:54:21")
}

print(failed == 0 ? "\n全部通过" : "\n失败 \(failed) 处")
exit(failed == 0 ? 0 : 1)
