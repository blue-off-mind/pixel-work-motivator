using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using PixelWorkMotivator.Core;

namespace Tests;

class Program
{
    static int failed = 0;

    static DateTime At(int d, int h = 0, int mi = 0, int s = 0) =>
        new(2026, 11, d, h, mi, s, DateTimeKind.Unspecified);

    static DateTime Ymd(int y, int m, int d, int h = 0, int mi = 0, int s = 0) =>
        new(y, m, d, h, mi, s, DateTimeKind.Unspecified);

    static PaySettings Settings(Action<PaySettings>? edit = null)
    {
        var s = new PaySettings { Salary = 8000 };
        edit?.Invoke(s);
        return s.Normalized();
    }

    static void Check(bool ok, string what, int line = 0)
    {
        if (!ok)
        {
            failed++;
            Console.WriteLine($"  ✗ Line {line}: {what}");
        }
    }

    static void Eq<T>(T a, T b, [System.Runtime.CompilerServices.CallerLineNumber] int line = 0)
    {
        Check(EqualityComparer<T>.Default.Equals(a, b), $"{a} ≠ {b}", line);
    }

    static void Close(double a, double b, double eps = 1e-9, [System.Runtime.CompilerServices.CallerLineNumber] int line = 0)
    {
        Check(Math.Abs(a - b) < eps, $"{a} ≉ {b}", line);
    }

    static void Test(string name, Action body)
    {
        int before = failed;
        try
        {
            body();
        }
        catch (Exception ex)
        {
            failed++;
            Console.WriteLine($"  ✗ Exception: {ex.Message}");
        }
        Console.WriteLine(failed == before ? $"✓ {name}" : $"✗ {name}");
    }

    static int Main(string[] args)
    {
        var @base = Settings();
        double daily = 8000.0 / 21;
        double rate = daily / (8 * 3600);

        Test("读设置时补默认值并清洗", () =>
        {
            string json = """
            {"salary": 12000, "decimals": 99, "workdays": [5, 1, 1, 3, 9], "currency": "₿",
             "wishlist": [{"name": "  奶茶 ", "price": 15}, {"name": "", "price": 3}, {"name": "空", "price": 0}]}
            """;
            var s = PaySettings.FromJson(json);
            Eq(s.Salary, 12000.0);
            Eq(s.Start, 9 * 60);
            Eq(s.Decimals, 6);
            Check(s.Workdays.SequenceEqual(new[] { 1, 3, 5 }), "workdays should be 1, 3, 5");
            Eq(s.Currency, "¥");
            Check(s.Wishlist.Count == 1 && s.Wishlist[0].Name == "奶茶" && s.Wishlist[0].Price == 15, "wishlist match");

            var empty = PaySettings.FromJson("{}");
            Eq(empty, new PaySettings());

            var roundTrip = PaySettings.FromJson(@base.ToJson());
            Eq(roundTrip, @base);
        });

        Test("validate 给出具体字段的错误", () =>
        {
            Check(!PayCore.Validate(@base).Any(), "base 应当合法");
            var bad = Settings(s => { s.Salary = 0; s.Start = 18 * 60; s.End = 9 * 60; s.Workdays = new(); });
            var fields = PayCore.Validate(bad).Select(x => x.Field).ToList();
            Check(fields.SequenceEqual(new[] { SettingsField.Salary, SettingsField.End, SettingsField.Lunch, SettingsField.Workdays }), "bad fields match");

            var lunchOut = Settings(s => { s.LunchStart = 8 * 60; s.LunchEnd = 8 * 60 + 30; });
            Check(PayCore.Validate(lunchOut).Select(x => x.Field).SequenceEqual(new[] { SettingsField.Lunch }), "lunchOut");

            var lunchBack = Settings(s => { s.LunchStart = 13 * 60; s.LunchEnd = 12 * 60; });
            Check(PayCore.Validate(lunchBack).Select(x => x.Field).SequenceEqual(new[] { SettingsField.Lunch }), "lunchBack");

            var noLunch = Settings(s => { s.LunchEnabled = false; s.LunchStart = 3; s.LunchEnd = 1; });
            Check(!PayCore.Validate(noLunch).Any(), "关掉午休后不再校验午休时间");
        });

        Test("午休把一天切成两段，不计薪", () =>
        {
            Check(PayCore.Segments(@base).SequenceEqual(new[] {
                new Segment(9 * 3600, 12 * 3600),
                new Segment(13 * 3600, 18 * 3600)
            }), "base segments");

            Check(PayCore.Segments(Settings(s => s.LunchEnabled = false)).SequenceEqual(new[] {
                new Segment(9 * 3600, 18 * 3600)
            }), "no lunch segments");

            var lunchAtStart = Settings(s => { s.LunchStart = 9 * 60; s.LunchEnd = 10 * 60; });
            Check(PayCore.Segments(lunchAtStart).SequenceEqual(new[] {
                new Segment(10 * 3600, 18 * 3600)
            }), "lunchAtStart segments");
        });

        Test("工作日计数", () =>
        {
            Eq(PayCore.Workdays(@base, Ymd(2026, 11, 1), Ymd(2026, 12, 1)), 21);
            var sixDays = Settings(s => s.Workdays = new List<int> { 1, 2, 3, 4, 5, 6 });
            Eq(PayCore.Workdays(sixDays, Ymd(2026, 11, 1), Ymd(2026, 12, 1)), 25);
            Eq(PayCore.Workdays(@base, Ymd(2026, 10, 15), Ymd(2026, 11, 15)), 22);
            Eq(PayCore.Workdays(@base, Ymd(2026, 11, 3), Ymd(2026, 11, 3)), 0);
        });

        Test("上班中：已赚、倒计时、本月累计", () =>
        {
            var snap = PayCore.Snapshot(@base, At(3, 15, 5, 39));
            Eq(snap.Status, PaySnapshot.StatusEnum.Working);
            double worked = 3 * 3600 + 2 * 3600 + 5 * 60 + 39;
            Eq(snap.Worked, worked);
            Close(snap.EarnedToday, worked * rate);
            Close(snap.DailyPay, daily);
            Close(snap.Hourly, daily / 8);
            Eq(snap.Countdown, (double)(2 * 3600 + 54 * 60 + 21));
            Close(snap.PeriodEarned, daily + worked * rate);
            Close(snap.PeriodFull, 8000, 1e-6);
            Eq(snap.PeriodStart, Ymd(2026, 11, 1));
            Eq(snap.PeriodEnd, Ymd(2026, 12, 1));
            Close(snap.Progress, worked / (8 * 3600));
            Check(!snap.NextStart.HasValue, "上班中不需要下次上班时间");
        });

        Test("午休、上班前、下班后、休息日、待设置", () =>
        {
            var lunch = PayCore.Snapshot(@base, At(3, 12, 30));
            Eq(lunch.Status, PaySnapshot.StatusEnum.Lunch);
            Eq(lunch.Countdown, 1800.0);
            Close(lunch.EarnedToday, 3 * 3600 * rate);

            var before = PayCore.Snapshot(@base, At(3, 8));
            Eq(before.Status, PaySnapshot.StatusEnum.Before);
            Eq(before.Countdown, 3600.0);
            Eq(before.EarnedToday, 0.0);
            Eq(before.NextStart?.Label, "今天 09:00");

            var after = PayCore.Snapshot(@base, At(3, 19));
            Eq(after.Status, PaySnapshot.StatusEnum.After);
            Close(after.EarnedToday, daily);
            Eq(after.NextStart?.Label, "明天 09:00");

            Eq(PayCore.Snapshot(@base, At(6, 19)).NextStart?.Label, "周一 09:00");

            var saturday = PayCore.Snapshot(@base, At(7, 10));
            Eq(saturday.Status, PaySnapshot.StatusEnum.Off);
            Eq(saturday.EarnedToday, 0.0);
            Eq(saturday.NextStart?.Label, "周一 09:00");
            Close(saturday.PeriodEarned, 5 * daily);

            var setup = PayCore.Snapshot(new PaySettings(), At(3, 10));
            Eq(setup.Status, PaySnapshot.StatusEnum.Setup);
            Eq(setup.EarnedToday, 0.0);
        });

        Test("按当月工作日折算时，月底最后一天下班正好拿满月薪", () =>
        {
            Close(PayCore.Snapshot(@base, At(30, 19)).PeriodEarned, 8000, 1e-6);
        });

        Test("设了发薪日：本期从上一个发薪日算起", () =>
        {
            var s15 = Settings(s => s.Payday = 15);
            double daily15 = 8000.0 / 22;
            var snap = PayCore.Snapshot(s15, At(3, 15, 5, 39));
            Eq(snap.PeriodStart, Ymd(2026, 10, 15));
            Eq(snap.PeriodEnd, Ymd(2026, 11, 15));
            Eq(snap.PeriodWorkdays, 22);
            Eq(PayCore.PeriodRange(snap), "10.15-11.14");
            Close(snap.DailyPay, daily15);
            double worked = 3 * 3600 + 2 * 3600 + 5 * 60 + 39;
            Close(snap.PeriodEarned, 13 * daily15 + worked * daily15 / (8 * 3600));
            Close(snap.PeriodFull, 8000, 1e-6);
            Check(PayCore.MenuLines(s15, snap).Last().StartsWith("本期已赚 ¥"), "menuLines prefix");

            Close(PayCore.Snapshot(s15, At(13, 19)).PeriodEarned, 8000, 1e-6);

            var payday = PayCore.Snapshot(s15, At(15, 10));
            Eq(payday.PeriodStart, Ymd(2026, 11, 15));
            Eq(payday.PeriodEnd, Ymd(2026, 12, 15));
            Eq(payday.PeriodEarned, 0.0);
            Eq(payday.PaydayDays, 0);

            var weekend = PayCore.Tips(s15, PayCore.Snapshot(s15, At(7, 10)));
            Check(weekend.Any(x => x.StartsWith("今天休息，本期已赚 ¥")), string.Join(" | ", weekend));
        });

        Test("发薪周期的边界：月底、跨年、二月、1 号", () =>
        {
            var s31 = Settings(s => s.Payday = 31);
            Eq(PayCore.Snapshot(s31, At(3, 10)).PeriodStart, Ymd(2026, 10, 31));
            Eq(PayCore.Snapshot(s31, At(3, 10)).PeriodEnd, Ymd(2026, 11, 30));
            Eq(PayCore.Snapshot(s31, At(30, 10)).PeriodStart, Ymd(2026, 11, 30));
            Eq(PayCore.Snapshot(s31, At(30, 10)).PeriodEnd, Ymd(2026, 12, 31));

            var s15 = Settings(s => s.Payday = 15);
            Eq(PayCore.Snapshot(s15, Ymd(2027, 1, 5, 10)).PeriodStart, Ymd(2026, 12, 15));
            Eq(PayCore.Snapshot(s15, Ymd(2027, 1, 5, 10)).PeriodEnd, Ymd(2027, 1, 15));

            var s30 = Settings(s => s.Payday = 30);
            Eq(PayCore.Snapshot(s30, Ymd(2027, 3, 1, 10)).PeriodStart, Ymd(2027, 2, 28));
            Eq(PayCore.Snapshot(s30, Ymd(2027, 3, 1, 10)).PeriodEnd, Ymd(2027, 3, 30));

            var s1 = PayCore.Snapshot(Settings(s => s.Payday = 1), At(3, 15));
            Eq(s1.PeriodStart, Ymd(2026, 11, 1));
            Close(s1.PeriodEarned, PayCore.Snapshot(@base, At(3, 15)).PeriodEarned);
        });

        Test("日薪 + 15 号发薪：日薪原样用，本期按天累计", () =>
        {
            var s = Settings(x =>
            {
                x.SalaryType = SalaryType.daily;
                x.Salary = 300;
                x.Payday = 15;
                x.LunchStart = 11 * 60 + 30;
            });
            var snap = PayCore.Snapshot(s, At(3, 18, 3, 59));
            Eq(snap.Status, PaySnapshot.StatusEnum.After);
            Eq(snap.DailyPay, 300.0);
            Close(snap.Hourly, 40.0);
            Close(snap.PeriodEarned, 14 * 300.0);
            Close(snap.PeriodFull, 22 * 300.0);
            Eq(PayCore.MenuLines(s, snap).Last(), "本期已赚 ¥4,200.00");

            var monthly = s.Clone();
            monthly.SalaryType = SalaryType.monthly;
            monthly.Salary = 6000;
            var m = PayCore.Snapshot(monthly, At(3, 18, 3, 59));
            Close(m.DailyPay, 6000.0 / 22);
            Close(m.PeriodFull, 6000, 1e-6);
        });

        Test("21.75 天、自定义天数、日薪、时薪", () =>
        {
            Close(PayCore.Snapshot(Settings(s => s.DayMode = DayMode.standard), At(3, 10)).DailyPay, 8000 / 21.75);
            Close(PayCore.Snapshot(Settings(s => { s.DayMode = DayMode.custom; s.CustomDays = 20; }), At(3, 10)).DailyPay, 400.0);
            Close(PayCore.Snapshot(Settings(s => { s.SalaryType = SalaryType.daily; s.Salary = 300; }), At(3, 10)).DailyPay, 300.0);
            var hourly = PayCore.Snapshot(Settings(s => { s.SalaryType = SalaryType.hourly; s.Salary = 50; }), At(3, 10));
            Close(hourly.DailyPay, 400.0);
            Close(hourly.Hourly, 50.0);
        });

        Test("发薪日倒数", () =>
        {
            var s15 = Settings(s => s.Payday = 15);
            Eq(PayCore.Snapshot(s15, At(3, 10)).PaydayDays, 12);
            Eq(PayCore.Snapshot(s15, At(15, 10)).PaydayDays, 0);
            Eq(PayCore.Snapshot(s15, At(20, 10)).PaydayDays, 25);
            Eq(PayCore.Snapshot(Settings(s => s.Payday = 31), At(3, 10)).PaydayDays, 27);
            Eq(PayCore.Snapshot(@base, At(3, 10)).PaydayDays, (int?)null);
        });

        Test("金额格式：向下取整、千分位、浮点误差", () =>
        {
            Eq(PayCore.FormatMoney(1234.56789, @base), "¥1,234.5678");
            Eq(PayCore.FormatMoney(129.3, @base), "¥129.3000");
            Eq(PayCore.FormatMoney(0.29999999, @base, decimals: 2), "¥0.29");
            Eq(PayCore.FormatMoney(0, @base), "¥0.0000");
            Eq(PayCore.FormatMoney(1234567.891, Settings(s => s.Currency = "$"), decimals: 2), "$1,234,567.89");
        });

        Test("时长格式", () =>
        {
            Eq(PayCore.FormatClock(10461), "2:54:21");
            Eq(PayCore.FormatClock(59.2), "0:01:00");
            Eq(PayCore.FormatClock(-5), "0:00:00");
            double day = 8.0 * 3600;
            Eq(PayCore.FormatWorkTime(30, paidPerDay: day), "不到 1 分钟");
            Eq(PayCore.FormatWorkTime(600, paidPerDay: day), "10 分钟");
            Eq(PayCore.FormatWorkTime(3600, paidPerDay: day), "1 小时");
            Eq(PayCore.FormatWorkTime(2 * 3600 + 53 * 60 + 10, paidPerDay: day), "2 小时 53 分");
            Eq(PayCore.FormatWorkTime(3 * day, paidPerDay: day), "3.0 个工作日");
            Eq(PayCore.FormatWorkTime(12 * day, paidPerDay: day), "12 个工作日");
        });

        Test("提示文案带具体数字", () =>
        {
            var t = PayCore.Tips(@base, PayCore.Snapshot(@base, At(3, 10)));
            Check(t.Any(x => x.StartsWith("再工作 ") && x.Contains("一件 T 恤（¥99）")), string.Join(" | ", t));
            Check(t.Contains("今天已经赚到一张电影票了。"), string.Join(" | ", t));
            Check(t.Any(x => x.StartsWith("这一分钟又进账 ¥0.79")), string.Join(" | ", t));

            var ta = PayCore.Tips(@base, PayCore.Snapshot(@base, At(3, 19)));
            Check(ta.Contains("今天的 ¥380.95 已经到手，收工！"), string.Join(" | ", ta));
            Check(ta.Any(x => x.StartsWith("今天已经赚到")), string.Join(" | ", ta));
            Eq(PayCore.Tips(new PaySettings(), PayCore.Snapshot(new PaySettings(), At(3, 10))).Count, 1);
        });

        Test("菜单栏文字", () =>
        {
            var now = At(3, 15, 5, 39);
            var snap = PayCore.Snapshot(@base, now);
            Check(Regex.IsMatch(PayCore.MenuBarText(@base, snap), @"^¥\d+\.\d{2}$"), PayCore.MenuBarText(@base, snap));
            var countdown = Settings(s => s.MenuBar = MenuBarMode.countdown);
            Eq(PayCore.MenuBarText(countdown, snap), "下班 2:54:21");
            Eq(PayCore.MenuBarText(countdown, PayCore.Snapshot(@base, At(3, 12, 30))), "开工 0:30:00");
            Eq(PayCore.MenuBarText(Settings(s => s.MenuBar = MenuBarMode.off), snap), "");
            Eq(PayCore.MenuBarText(@base, PayCore.Snapshot(@base, At(7, 10))), "休息日");
            Eq(PayCore.MenuBarText(new PaySettings(), PayCore.Snapshot(new PaySettings(), now)), "待设置");
            Eq(PayCore.MenuLines(@base, snap)[1], "距离下班 2:54:21");
        });

        Test("英文设置、日期、提示和菜单文案", () =>
        {
            var en = PaySettings.FromJson("""{"salary":8000,"language":"en"}""");
            Eq(en.Language, AppLanguage.En);
            Check(en.Wishlist.SequenceEqual(PaySettings.DefaultWishlistEN), "wishlist en");
            Eq(PaySettings.FromJson(en.ToJson()), en);

            var working = PayCore.Snapshot(en, At(3, 10));
            Eq(PayCore.Snapshot(en, At(3, 19)).NextStart?.Label, "Tomorrow 09:00");
            Eq(PayCore.Snapshot(en, At(6, 19)).NextStart?.Label, "Mon 09:00");
            Eq(PayCore.FormatWorkTime(10461, paidPerDay: 8 * 3600, language: AppLanguage.En), "2 hr 54 min");
            Eq(PayCore.FormatWorkTime(30, paidPerDay: 8 * 3600, language: AppLanguage.En), "under 1 min");
            Check(string.Join(" | ", PayCore.Tips(en, working)).Contains("T-shirt"), "英文提示应使用英文心愿单");
            Check(PayCore.MenuLines(en, working)[0].StartsWith("Working · Today "), PayCore.MenuLines(en, working)[0]);

            var countdown = en.Clone();
            countdown.MenuBar = MenuBarMode.countdown;
            Eq(PayCore.MenuBarText(countdown, working), "Off in 8:00:00");
            Eq(PayCore.MenuBarText(en, PayCore.Snapshot(en, At(7, 10))), "Day off");

            var payday = en.Clone();
            payday.Payday = 15;
            Check(PayCore.Tips(payday, PayCore.Snapshot(payday, At(14, 10))).Contains("1 day until payday."), "英文发薪日倒数应使用单数 day");

            var invalid = en.Clone();
            invalid.Salary = 0;
            Eq(PayCore.Validate(invalid).First().Message, "Enter a salary greater than 0");
        });

        Console.WriteLine(failed == 0 ? "\n全部通过" : $"\n失败 {failed} 处");
        return failed == 0 ? 0 : 1;
    }
}
