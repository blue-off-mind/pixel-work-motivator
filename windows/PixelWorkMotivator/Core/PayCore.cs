using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace PixelWorkMotivator.Core;

public class Wish : IEquatable<Wish>
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("price")]
    public double Price { get; set; }

    public Wish() { }

    public Wish(string name, double price)
    {
        Name = name;
        Price = price;
    }

    public bool Equals(Wish? other)
    {
        if (other is null) return false;
        return Name == other.Name && Math.Abs(Price - other.Price) < 1e-9;
    }

    public override bool Equals(object? obj) => Equals(obj as Wish);
    public override int GetHashCode() => HashCode.Combine(Name, Price);
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum SalaryType
{
    [JsonPropertyName("monthly")] monthly,
    [JsonPropertyName("daily")] daily,
    [JsonPropertyName("hourly")] hourly
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum DayMode
{
    [JsonPropertyName("actual")] actual,
    [JsonPropertyName("standard")] standard,
    [JsonPropertyName("custom")] custom
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum MenuBarMode
{
    [JsonPropertyName("today")] today,
    [JsonPropertyName("month")] month,
    [JsonPropertyName("countdown")] countdown,
    [JsonPropertyName("off")] off
}

public class AppLanguageConverter : JsonConverter<AppLanguage>
{
    public override AppLanguage Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var str = reader.GetString();
        return str switch
        {
            "en" => AppLanguage.En,
            "zh-Hans" => AppLanguage.ZhHans,
            _ => AppLanguage.ZhHans
        };
    }

    public override void Write(Utf8JsonWriter writer, AppLanguage value, JsonSerializerOptions options)
    {
        writer.WriteStringValue(value == AppLanguage.En ? "en" : "zh-Hans");
    }
}

public class PaySettings : IEquatable<PaySettings>
{
    [JsonPropertyName("salaryType")]
    public SalaryType SalaryType { get; set; } = SalaryType.monthly;

    [JsonPropertyName("language")]
    [JsonConverter(typeof(AppLanguageConverter))]
    public AppLanguage Language { get; set; } = AppLanguage.ZhHans;

    [JsonPropertyName("salary")]
    public double Salary { get; set; } = 0;

    [JsonPropertyName("dayMode")]
    public DayMode DayMode { get; set; } = DayMode.actual;

    [JsonPropertyName("customDays")]
    public double CustomDays { get; set; } = 22;

    [JsonPropertyName("start")]
    public int Start { get; set; } = 9 * 60;

    [JsonPropertyName("end")]
    public int End { get; set; } = 18 * 60;

    [JsonPropertyName("lunchEnabled")]
    public bool LunchEnabled { get; set; } = true;

    [JsonPropertyName("lunchStart")]
    public int LunchStart { get; set; } = 12 * 60;

    [JsonPropertyName("lunchEnd")]
    public int LunchEnd { get; set; } = 13 * 60;

    [JsonPropertyName("workdays")]
    public List<int> Workdays { get; set; } = new() { 1, 2, 3, 4, 5 };

    [JsonPropertyName("payday")]
    public int Payday { get; set; } = 0;

    [JsonPropertyName("currency")]
    public string Currency { get; set; } = "¥";

    [JsonPropertyName("decimals")]
    public int Decimals { get; set; } = 4;

    [JsonPropertyName("menuBar")]
    public MenuBarMode MenuBar { get; set; } = MenuBarMode.today;

    [JsonPropertyName("sound")]
    public bool Sound { get; set; } = false;

    [JsonPropertyName("wishlist")]
    public List<Wish> Wishlist { get; set; } = new();

    public static readonly string[] Currencies = { "¥", "$", "€", "£" };

    public static List<Wish> DefaultWishlist => new()
    {
        new("一杯奶茶", 15),
        new("一张电影票", 45),
        new("一件 T 恤", 99),
        new("一顿火锅", 150),
        new("一双跑鞋", 599),
        new("一副降噪耳机", 1499),
        new("一台游戏机", 2599),
        new("一部新手机", 5999),
        new("一次旅行", 8000),
    };

    public static List<Wish> DefaultWishlistEN => new()
    {
        new("Milk tea", 15),
        new("Movie ticket", 45),
        new("T-shirt", 99),
        new("Hot pot", 150),
        new("Running shoes", 599),
        new("ANC headphones", 1499),
        new("Game console", 2599),
        new("New phone", 5999),
        new("Trip", 8000),
    };

    public static List<Wish> GetDefaultWishlist(AppLanguage lang) =>
        lang == AppLanguage.En ? DefaultWishlistEN : DefaultWishlist;

    public PaySettings()
    {
        Wishlist = GetDefaultWishlist(Language);
    }

    public void Normalize()
    {
        Salary = double.IsFinite(Salary) ? Math.Max(0, Salary) : 0;
        CustomDays = double.IsFinite(CustomDays) ? Math.Clamp(CustomDays, 1, 31) : 22;
        Start = Math.Clamp(Start, 0, 24 * 60);
        End = Math.Clamp(End, 0, 24 * 60);
        LunchStart = Math.Clamp(LunchStart, 0, 24 * 60);
        LunchEnd = Math.Clamp(LunchEnd, 0, 24 * 60);
        Workdays = Workdays.Where(d => d >= 0 && d <= 6).Distinct().OrderBy(d => d).ToList();
        Payday = Math.Clamp(Payday, 0, 31);
        if (!Currencies.Contains(Currency)) Currency = "¥";
        Decimals = Math.Clamp(Decimals, 2, 6);

        Wishlist = Wishlist
            .Select(w =>
            {
                var trimmed = (w.Name ?? "").Trim();
                var truncated = trimmed.Length > 20 ? trimmed.Substring(0, 20) : trimmed;
                return new Wish(truncated, w.Price);
            })
            .Where(w => !string.IsNullOrEmpty(w.Name) && double.IsFinite(w.Price) && w.Price > 0)
            .ToList();
    }

    public PaySettings Normalized()
    {
        var s = Clone();
        s.Normalize();
        return s;
    }

    public PaySettings Clone()
    {
        return new PaySettings
        {
            SalaryType = SalaryType,
            Language = Language,
            Salary = Salary,
            DayMode = DayMode,
            CustomDays = CustomDays,
            Start = Start,
            End = End,
            LunchEnabled = LunchEnabled,
            LunchStart = LunchStart,
            LunchEnd = LunchEnd,
            Workdays = new List<int>(Workdays),
            Payday = Payday,
            Currency = Currency,
            Decimals = Decimals,
            MenuBar = MenuBar,
            Sound = Sound,
            Wishlist = Wishlist.Select(w => new Wish(w.Name, w.Price)).ToList()
        };
    }

    public bool Equals(PaySettings? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;
        return SalaryType == other.SalaryType &&
               Language == other.Language &&
               Math.Abs(Salary - other.Salary) < 1e-9 &&
               DayMode == other.DayMode &&
               Math.Abs(CustomDays - other.CustomDays) < 1e-9 &&
               Start == other.Start &&
               End == other.End &&
               LunchEnabled == other.LunchEnabled &&
               LunchStart == other.LunchStart &&
               LunchEnd == other.LunchEnd &&
               Workdays.SequenceEqual(other.Workdays) &&
               Payday == other.Payday &&
               Currency == other.Currency &&
               Decimals == other.Decimals &&
               MenuBar == other.MenuBar &&
               Sound == other.Sound &&
               Wishlist.SequenceEqual(other.Wishlist);
    }

    public override bool Equals(object? obj) => Equals(obj as PaySettings);

    public override int GetHashCode()
    {
        var hash = new HashCode();
        hash.Add(SalaryType);
        hash.Add(Language);
        hash.Add(Salary);
        hash.Add(DayMode);
        hash.Add(CustomDays);
        hash.Add(Start);
        hash.Add(End);
        hash.Add(LunchEnabled);
        hash.Add(LunchStart);
        hash.Add(LunchEnd);
        hash.Add(Payday);
        hash.Add(Currency);
        hash.Add(Decimals);
        hash.Add(MenuBar);
        hash.Add(Sound);
        return hash.ToHashCode();
    }

    public static PaySettings FromJson(string json)
    {
        var options = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            ReadCommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true
        };

        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            var s = new PaySettings();

            if (root.TryGetProperty("language", out var pLang))
            {
                var lStr = pLang.GetString();
                s.Language = lStr == "en" ? AppLanguage.En : AppLanguage.ZhHans;
            }

            if (root.TryGetProperty("salaryType", out var pType))
            {
                if (Enum.TryParse<SalaryType>(pType.GetString(), true, out var st))
                    s.SalaryType = st;
            }

            if (root.TryGetProperty("salary", out var pSal) && pSal.TryGetDouble(out var sal))
                s.Salary = sal;

            if (root.TryGetProperty("dayMode", out var pDayMode))
            {
                if (Enum.TryParse<DayMode>(pDayMode.GetString(), true, out var dm))
                    s.DayMode = dm;
            }

            if (root.TryGetProperty("customDays", out var pCustDays) && pCustDays.TryGetDouble(out var cd))
                s.CustomDays = cd;

            if (root.TryGetProperty("start", out var pStart) && pStart.TryGetInt32(out var start))
                s.Start = start;

            if (root.TryGetProperty("end", out var pEnd) && pEnd.TryGetInt32(out var end))
                s.End = end;

            if (root.TryGetProperty("lunchEnabled", out var pLunchEn))
                s.LunchEnabled = pLunchEn.GetBoolean();

            if (root.TryGetProperty("lunchStart", out var pLs) && pLs.TryGetInt32(out var ls))
                s.LunchStart = ls;

            if (root.TryGetProperty("lunchEnd", out var pLe) && pLe.TryGetInt32(out var le))
                s.LunchEnd = le;

            if (root.TryGetProperty("workdays", out var pWd) && pWd.ValueKind == JsonValueKind.Array)
            {
                s.Workdays = pWd.EnumerateArray().Where(x => x.TryGetInt32(out _)).Select(x => x.GetInt32()).ToList();
            }

            if (root.TryGetProperty("payday", out var pPayday) && pPayday.TryGetInt32(out var pd))
                s.Payday = pd;

            if (root.TryGetProperty("currency", out var pCur))
                s.Currency = pCur.GetString() ?? "¥";

            if (root.TryGetProperty("decimals", out var pDec) && pDec.TryGetInt32(out var dec))
                s.Decimals = dec;

            if (root.TryGetProperty("menuBar", out var pMb))
            {
                if (Enum.TryParse<MenuBarMode>(pMb.GetString(), true, out var mb))
                    s.MenuBar = mb;
            }

            if (root.TryGetProperty("sound", out var pSnd))
                s.Sound = pSnd.GetBoolean();

            if (root.TryGetProperty("wishlist", out var pWl) && pWl.ValueKind == JsonValueKind.Array)
            {
                var wishes = new List<Wish>();
                foreach (var el in pWl.EnumerateArray())
                {
                    var name = el.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                    var price = el.TryGetProperty("price", out var p) && p.TryGetDouble(out var pr) ? pr : 0.0;
                    wishes.Add(new Wish(name, price));
                }
                s.Wishlist = wishes;
            }
            else
            {
                s.Wishlist = GetDefaultWishlist(s.Language);
            }

            s.Normalize();
            return s;
        }
        catch
        {
            var fallback = new PaySettings();
            fallback.Normalize();
            return fallback;
        }
    }

    public string ToJson()
    {
        var options = new JsonSerializerOptions
        {
            WriteIndented = true,
            Converters = { new AppLanguageConverter(), new JsonStringEnumConverter() }
        };
        return JsonSerializer.Serialize(this, options);
    }
}

public record struct Segment(double Start, double End)
{
    public double Length => End - Start;
}

public record struct NextStart(DateTime Date, string Label);

public class PaySnapshot
{
    public enum StatusEnum { Setup, Before, Working, Lunch, After, Off }

    public StatusEnum Status { get; set; }
    public int Year { get; set; }
    public int Month { get; set; }
    public int Day { get; set; }
    public int Weekday { get; set; } // 0=Sunday...6=Saturday
    public double SecOfDay { get; set; }
    public bool IsWorkday { get; set; }
    public List<Segment> Segments { get; set; } = new();
    public double PaidPerDay { get; set; }
    public double DailyPay { get; set; }
    public double Rate { get; set; }
    public double Worked { get; set; }
    public double EarnedToday { get; set; }
    public double Countdown { get; set; }
    public DateTime PeriodStart { get; set; }
    public DateTime PeriodEnd { get; set; }
    public int PeriodWorkdays { get; set; }
    public double PeriodEarned { get; set; }
    public double PeriodFull { get; set; }
    public NextStart? NextStart { get; set; }
    public int? PaydayDays { get; set; }

    public double Hourly => Rate * 3600;
    public double Progress => PaidPerDay > 0 ? Worked / PaidPerDay : 0;
}

public enum SettingsField
{
    Salary,
    Start,
    End,
    Lunch,
    Workdays
}

public static class PayCore
{
    public static readonly string[] WeekdayCN = { "日", "一", "二", "三", "四", "五", "六" };
    public static readonly string[] WeekdayEN = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };

    public static string StatusText(PaySnapshot.StatusEnum status, AppLanguage language)
    {
        if (language == AppLanguage.En)
        {
            return status switch
            {
                PaySnapshot.StatusEnum.Setup => "Set up",
                PaySnapshot.StatusEnum.Before => "Before work",
                PaySnapshot.StatusEnum.Working => "Working",
                PaySnapshot.StatusEnum.Lunch => "Lunch",
                PaySnapshot.StatusEnum.After => "Off work",
                PaySnapshot.StatusEnum.Off => "Day off",
                _ => ""
            };
        }

        return status switch
        {
            PaySnapshot.StatusEnum.Setup => "待设置",
            PaySnapshot.StatusEnum.Before => "未上班",
            PaySnapshot.StatusEnum.Working => "上班中",
            PaySnapshot.StatusEnum.Lunch => "午休中",
            PaySnapshot.StatusEnum.After => "已下班",
            PaySnapshot.StatusEnum.Off => "休息日",
            _ => ""
        };
    }

    public static List<(SettingsField Field, string Message)> Validate(PaySettings s)
    {
        var e = new List<(SettingsField, string)>();
        string Tr(string zh, string en) => L10n.T(s.Language, zh, en);

        if (!(s.Salary > 0))
            e.Add((SettingsField.Salary, Tr("工资要填一个大于 0 的数", "Enter a salary greater than 0")));

        if (s.End <= s.Start)
        {
            e.Add((SettingsField.End, Tr("下班时间要晚于上班时间（暂不支持跨零点的班次）",
                                          "End time must be after start time (overnight shifts are not supported)")));
        }

        if (s.LunchEnabled)
        {
            if (s.LunchEnd <= s.LunchStart)
            {
                e.Add((SettingsField.Lunch, Tr("午休结束要晚于开始", "Lunch end must be after its start")));
            }
            else if (s.LunchStart < s.Start || s.LunchEnd > s.End)
            {
                e.Add((SettingsField.Lunch, Tr("午休要落在上下班时间之内", "Lunch must fall within working hours")));
            }
        }

        if (!s.Workdays.Any())
            e.Add((SettingsField.Workdays, Tr("至少选一天上班", "Select at least one working day")));

        return e;
    }

    public static string FormatTime(int minutes)
    {
        return $"{minutes / 60:D2}:{minutes % 60:D2}";
    }

    public static List<Segment> Segments(PaySettings s)
    {
        double st = s.Start * 60;
        double en = s.End * 60;
        if (en <= st) return new List<Segment>();

        if (s.LunchEnabled)
        {
            double ls = s.LunchStart * 60;
            double le = s.LunchEnd * 60;
            if (le > ls && ls >= st && le <= en)
            {
                var outSegs = new List<Segment>();
                if (ls > st) outSegs.Add(new Segment(st, ls));
                if (en > le) outSegs.Add(new Segment(le, en));
                return outSegs;
            }
        }

        return new List<Segment> { new(st, en) };
    }

    public static double WorkedSeconds(List<Segment> segs, double sec)
    {
        return segs.Sum(seg => Math.Min(Math.Max(sec - seg.Start, 0), seg.Length));
    }

    public static int DaysInMonth(int year, int month)
    {
        return DateTime.DaysInMonth(year, month);
    }

    public static (DateTime Start, DateTime End) PayPeriod(PaySettings s, int y, int m, int d)
    {
        DateTime Dt(int yr, int mn, int dy) => new(yr, mn, dy, 0, 0, 0, DateTimeKind.Unspecified);

        (int Year, int Month) Shift(int months)
        {
            int t = y * 12 + (m - 1) + months;
            return (t / 12, t % 12 + 1);
        }

        int PaydayCalc(int yr, int mn) => Math.Min(s.Payday, DaysInMonth(yr, mn));

        var next = Shift(1);
        if (s.Payday <= 0)
        {
            return (Dt(y, m, 1), Dt(next.Year, next.Month, 1));
        }

        if (d >= PaydayCalc(y, m))
        {
            return (Dt(y, m, PaydayCalc(y, m)), Dt(next.Year, next.Month, PaydayCalc(next.Year, next.Month)));
        }

        var prev = Shift(-1);
        return (Dt(prev.Year, prev.Month, PaydayCalc(prev.Year, prev.Month)), Dt(y, m, PaydayCalc(y, m)));
    }

    public static int Workdays(PaySettings s, DateTime from, DateTime to)
    {
        int n = (int)(to.Date - from.Date).TotalDays;
        int first = (int)from.DayOfWeek;
        int count = 0;
        for (int i = 0; i < n; i++)
        {
            int wd = (first + i) % 7;
            if (s.Workdays.Contains(wd)) count++;
        }
        return count;
    }

    public static double DailyPay(PaySettings s, int periodWorkdays, double paidPerDay)
    {
        return s.SalaryType switch
        {
            SalaryType.daily => s.Salary,
            SalaryType.hourly => s.Salary * paidPerDay / 3600.0,
            SalaryType.monthly => s.DayMode switch
            {
                DayMode.standard => s.Salary / 21.75,
                DayMode.custom => s.CustomDays > 0 ? s.Salary / s.CustomDays : 0,
                DayMode.actual => periodWorkdays > 0 ? s.Salary / periodWorkdays : 0,
                _ => 0
            },
            _ => 0
        };
    }

    public static NextStart? NextWorkStart(PaySettings s, DateTime date, List<Segment> segs)
    {
        if (!segs.Any() || !s.Workdays.Any()) return null;
        var first = segs[0];
        var midnight = date.Date;

        for (int i = 0; i < 15; i++)
        {
            var day = midnight.AddDays(i);
            int weekday = (int)day.DayOfWeek;
            if (!s.Workdays.Contains(weekday)) continue;

            var start = day.AddSeconds(first.Start);
            if (start <= date) continue;

            string hm = FormatTime((int)first.Start / 60);
            string label;
            if (i == 0)
                label = s.Language == AppLanguage.En ? $"Today {hm}" : $"今天 {hm}";
            else if (i == 1)
                label = s.Language == AppLanguage.En ? $"Tomorrow {hm}" : $"明天 {hm}";
            else if (i < 7)
                label = s.Language == AppLanguage.En ? $"{WeekdayEN[weekday]} {hm}" : $"周{WeekdayCN[weekday]} {hm}";
            else
                label = s.Language == AppLanguage.En ? $"{day.Month}/{day.Day} {hm}" : $"{day.Month}月{day.Day}日 {hm}";

            return new NextStart(start, label);
        }

        return null;
    }

    public static int? PaydayDays(PaySettings s, int year, int month, int day)
    {
        if (s.Payday <= 0) return null;
        int dim = DaysInMonth(year, month);
        int thisMonth = Math.Min(s.Payday, dim);
        if (day <= thisMonth) return thisMonth - day;

        var (ny, nm) = month == 12 ? (year + 1, 1) : (year, month + 1);
        return dim - day + Math.Min(s.Payday, DaysInMonth(ny, nm));
    }

    public static PaySnapshot Snapshot(PaySettings s, DateTime date)
    {
        int y = date.Year;
        int m = date.Month;
        int d = date.Day;
        int weekday = (int)date.DayOfWeek;
        var midnight = date.Date;
        double sec = (date - midnight).TotalSeconds;

        var segs = Segments(s);
        double paidPerDay = segs.Sum(x => x.Length);
        bool isWorkday = s.Workdays.Contains(weekday);
        var period = PayPeriod(s, y, m, d);
        int periodDays = Workdays(s, period.Start, period.End);
        double daily = paidPerDay > 0 ? DailyPay(s, periodDays, paidPerDay) : 0;
        double rate = paidPerDay > 0 ? daily / paidPerDay : 0;
        double worked = isWorkday ? WorkedSeconds(segs, sec) : 0;

        PaySnapshot.StatusEnum status;
        double countdown = 0;

        if (!segs.Any() || !(s.Salary > 0))
        {
            status = PaySnapshot.StatusEnum.Setup;
        }
        else if (!isWorkday)
        {
            status = PaySnapshot.StatusEnum.Off;
        }
        else if (sec < segs[0].Start)
        {
            status = PaySnapshot.StatusEnum.Before;
            countdown = segs[0].Start - sec;
        }
        else if (sec >= segs[^1].End)
        {
            status = PaySnapshot.StatusEnum.After;
        }
        else if (segs.Any(seg => sec >= seg.Start && sec < seg.End))
        {
            status = PaySnapshot.StatusEnum.Working;
            countdown = segs[^1].End - sec;
        }
        else
        {
            status = PaySnapshot.StatusEnum.Lunch;
            var nextSeg = segs.FirstOrDefault(seg => seg.Start > sec);
            countdown = (nextSeg.Length > 0 ? nextSeg.Start : sec) - sec;
        }

        int pastDays = Workdays(s, period.Start, midnight);
        double earned = worked * rate;

        var snap = new PaySnapshot
        {
            Status = status,
            Year = y,
            Month = m,
            Day = d,
            Weekday = weekday,
            SecOfDay = sec,
            IsWorkday = isWorkday,
            Segments = segs,
            PaidPerDay = paidPerDay,
            DailyPay = daily,
            Rate = rate,
            Worked = worked,
            EarnedToday = earned,
            Countdown = countdown,
            PeriodStart = period.Start,
            PeriodEnd = period.End,
            PeriodWorkdays = periodDays,
            PeriodEarned = pastDays * daily + earned,
            PeriodFull = periodDays * daily,
            NextStart = (status is PaySnapshot.StatusEnum.Before or PaySnapshot.StatusEnum.After or PaySnapshot.StatusEnum.Off)
                ? NextWorkStart(s, date, segs)
                : null,
            PaydayDays = PaydayDays(s, y, m, d)
        };

        return snap;
    }

    public static string FormatMoney(double v, PaySettings s, int? decimals = null)
    {
        int dec = decimals ?? s.Decimals;
        double p = Math.Pow(10.0, dec);
        double floored = Math.Floor(v * p * (1 + 1e-12) + 1e-9) / p;

        // Group thousands with comma
        long intPart = (long)Math.Floor(floored);
        double frac = floored - intPart;

        string intStr = intPart.ToString("N0", CultureInfo.InvariantCulture);
        if (dec > 0)
        {
            string fmt = "F" + dec;
            string fullStr = floored.ToString(fmt, CultureInfo.InvariantCulture);
            int dotIdx = fullStr.IndexOf('.');
            string fracStr = dotIdx >= 0 ? fullStr.Substring(dotIdx + 1) : new string('0', dec);
            return $"{s.Currency}{intStr}.{fracStr}";
        }

        return $"{s.Currency}{intStr}";
    }

    public static string FormatClock(double sec)
    {
        int t = Math.Max(0, (int)Math.Ceiling(sec));
        return $"{t / 3600}:{t % 3600 / 60:D2}:{t % 60:D2}";
    }

    public static string PeriodEarnedLabel(PaySettings s)
    {
        return s.Payday > 0
            ? L10n.T(s.Language, "本期已赚", "This period")
            : L10n.T(s.Language, "本月已赚", "This month");
    }

    public static string PeriodRange(PaySnapshot snap)
    {
        var last = snap.PeriodEnd.AddDays(-1);
        return $"{snap.PeriodStart.Month}.{snap.PeriodStart.Day:D2}-{last.Month}.{last.Day:D2}";
    }

    public static string FormatWorkTime(double sec, double paidPerDay, AppLanguage language = AppLanguage.ZhHans)
    {
        if (language == AppLanguage.En)
        {
            if (sec < 60) return "under 1 min";
            if (paidPerDay > 0 && sec > paidPerDay * 1.5)
            {
                double days = sec / paidPerDay;
                return (days < 10 ? days.ToString("F1", CultureInfo.InvariantCulture) : Math.Round(days).ToString("F0", CultureInfo.InvariantCulture)) + " workdays";
            }
            int h = (int)sec / 3600;
            int mm = (int)sec % 3600 / 60;
            if (h == 0) return $"{mm} min";
            return $"{h} hr" + (mm > 0 ? $" {mm} min" : "");
        }

        if (sec < 60) return "不到 1 分钟";
        if (paidPerDay > 0 && sec > paidPerDay * 1.5)
        {
            double days = sec / paidPerDay;
            return (days < 10 ? days.ToString("F1", CultureInfo.InvariantCulture) : Math.Round(days).ToString("F0", CultureInfo.InvariantCulture)) + " 个工作日";
        }
        int hours = (int)sec / 3600;
        int mins = (int)sec % 3600 / 60;
        if (hours == 0) return $"{mins} 分钟";
        return $"{hours} 小时" + (mins > 0 ? $" {mins} 分" : "");
    }

    private static string CountOf(string name, int n)
    {
        return name.StartsWith("一") ? $"{n} " + name.Substring(1) : $"{name} ×{n}";
    }

    public static List<string> Tips(PaySettings s, PaySnapshot snap)
    {
        string Money(double v, int dec = 2) => FormatMoney(v, s, dec);
        string Tr(string zh, string en) => L10n.T(s.Language, zh, en);

        if (snap.Status == PaySnapshot.StatusEnum.Setup)
        {
            return new List<string>
            {
                Tr("右键 › 设置，填好工资和上下班时间就开始计时。",
                   "Right-click › Settings, then enter your salary and working hours to start.")
            };
        }

        var outTips = new List<string>();
        var items = s.Wishlist.OrderBy(w => w.Price).ToList();
        double earned = snap.EarnedToday;

        if ((snap.Status is PaySnapshot.StatusEnum.Working or PaySnapshot.StatusEnum.Lunch or PaySnapshot.StatusEnum.Before) &&
            snap.Rate > 0)
        {
            var next = items.FirstOrDefault(w => w.Price > earned);
            if (next != null)
            {
                string need = FormatWorkTime((next.Price - earned) / snap.Rate, snap.PaidPerDay, s.Language);
                outTips.Add(Tr($"再工作 {need}，就能赚到{next.Name}（{Money(next.Price, 0)}）。",
                               $"Another {need} of work earns you {next.Name} ({Money(next.Price, 0)})."));
            }
        }

        switch (snap.Status)
        {
            case PaySnapshot.StatusEnum.Working:
                outTips.Add(Tr($"这一分钟又进账 {Money(snap.Rate * 60)}，一小时就是 {Money(snap.Hourly)}。",
                               $"This minute adds {Money(snap.Rate * 60)}; one hour earns {Money(snap.Hourly)}."));
                break;
            case PaySnapshot.StatusEnum.Lunch:
                outTips.Add(Tr($"午休不计薪，吃饱再战。还有 {FormatClock(snap.Countdown)} 开工。",
                               $"Lunch is unpaid. Back to work in {FormatClock(snap.Countdown)}."));
                break;
            case PaySnapshot.StatusEnum.Before:
                outTips.Add(Tr($"今天满勤能赚 {Money(snap.DailyPay)}，{FormatClock(snap.Countdown)} 后开始进账。",
                               $"A full day earns {Money(snap.DailyPay)}. Earnings start in {FormatClock(snap.Countdown)}."));
                break;
            case PaySnapshot.StatusEnum.After:
                outTips.Add(Tr($"今天的 {Money(snap.DailyPay)} 已经到手，收工！",
                               $"Today's {Money(snap.DailyPay)} is earned. Time to clock out!"));
                outTips.Add(Tr("还没走？现在多待的每一秒都是免费加班。",
                               "Still here? Every extra second is unpaid overtime."));
                break;
            case PaySnapshot.StatusEnum.Off:
                outTips.Add(Tr($"今天休息，{PeriodEarnedLabel(s)} {Money(snap.PeriodEarned)}。",
                               $"Day off. You've earned {Money(snap.PeriodEarned)} " + (s.Payday > 0 ? "this pay period." : "this month.")));
                break;
        }

        if (snap.Status != PaySnapshot.StatusEnum.Before && snap.Status != PaySnapshot.StatusEnum.Off)
        {
            var got = items.LastOrDefault(w => w.Price <= earned);
            if (got != null)
            {
                int n = (int)(earned / got.Price);
                if (s.Language == AppLanguage.En)
                {
                    outTips.Add($"Today's earnings cover {(n > 1 ? $"{got.Name} ×{n}" : got.Name)}.");
                }
                else
                {
                    outTips.Add($"今天已经赚到{(n > 1 ? CountOf(got.Name, n) : got.Name)}了。");
                }
            }
        }

        if (snap.PaydayDays.HasValue)
        {
            int days = snap.PaydayDays.Value;
            outTips.Add(days == 0
                ? Tr("今天发工资，记得查账。", "It's payday—remember to check your account.")
                : Tr($"离发工资还有 {days} 天。", days == 1 ? "1 day until payday." : $"{days} days until payday."));
        }

        return outTips;
    }

    public static string MenuBarText(PaySettings s, PaySnapshot snap)
    {
        if (s.MenuBar == MenuBarMode.off) return "";
        if (snap.Status == PaySnapshot.StatusEnum.Setup) return StatusText(PaySnapshot.StatusEnum.Setup, s.Language);

        return s.MenuBar switch
        {
            MenuBarMode.month => FormatMoney(snap.PeriodEarned, s, 2),
            MenuBarMode.countdown => snap.Status switch
            {
                PaySnapshot.StatusEnum.Working => L10n.T(s.Language, "下班 ", "Off in ") + FormatClock(snap.Countdown),
                PaySnapshot.StatusEnum.Lunch => L10n.T(s.Language, "开工 ", "Back in ") + FormatClock(snap.Countdown),
                PaySnapshot.StatusEnum.Before => L10n.T(s.Language, "上班 ", "Start in ") + FormatClock(snap.Countdown),
                _ => StatusText(snap.Status, s.Language)
            },
            _ => snap.Status == PaySnapshot.StatusEnum.Off
                ? StatusText(PaySnapshot.StatusEnum.Off, s.Language)
                : FormatMoney(snap.EarnedToday, s, 2)
        };
    }

    public static List<string> MenuLines(PaySettings s, PaySnapshot snap)
    {
        string Tr(string zh, string en) => L10n.T(s.Language, zh, en);
        if (snap.Status == PaySnapshot.StatusEnum.Setup)
            return new List<string> { Tr("还没设置工资", "Salary not set") };

        var lines = new List<string>
        {
            Tr($"{StatusText(snap.Status, s.Language)} · 今日已赚 {FormatMoney(snap.EarnedToday, s)}",
               $"{StatusText(snap.Status, s.Language)} · Today {FormatMoney(snap.EarnedToday, s)}")
        };

        switch (snap.Status)
        {
            case PaySnapshot.StatusEnum.Working:
                lines.Add(Tr("距离下班 ", "Off work in ") + FormatClock(snap.Countdown));
                break;
            case PaySnapshot.StatusEnum.Lunch:
                lines.Add(Tr("午休还剩 ", "Back to work in ") + FormatClock(snap.Countdown));
                break;
            case PaySnapshot.StatusEnum.Before:
                lines.Add(Tr("距离上班 ", "Work starts in ") + FormatClock(snap.Countdown));
                break;
            default:
                if (snap.NextStart.HasValue)
                {
                    lines.Add(Tr("下次上班 ", "Next start: ") + snap.NextStart.Value.Label);
                }
                break;
        }

        lines.Add(PeriodEarnedLabel(s) + Tr(" ", ": ") + FormatMoney(snap.PeriodEarned, s, 2));
        return lines;
    }
}
