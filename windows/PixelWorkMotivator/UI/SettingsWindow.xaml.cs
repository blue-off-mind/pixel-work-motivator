using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using PixelWorkMotivator.Core;

namespace PixelWorkMotivator.UI;

public partial class SettingsWindow : Window
{
    public Action<PaySettings, WidgetSize, double, bool>? OnSave { get; set; }

    private readonly Store _store;
    private bool _firstRun;
    private AppLanguage _currentLanguage = AppLanguage.ZhHans;
    private bool _loading = false;

    public SettingsWindow(Store store)
    {
        InitializeComponent();
        _store = store;
        _firstRun = _store.Settings == null;

        InitComboBoxes();
        LoadValues();
        HookEvents();
        UpdateBilingualText();
        RefreshHint();
    }

    private void InitComboBoxes()
    {
        CmbLanguage.Items.Clear();
        CmbLanguage.Items.Add("简体中文");
        CmbLanguage.Items.Add("English");

        CmbCurrency.Items.Clear();
        foreach (var c in PaySettings.Currencies) CmbCurrency.Items.Add(c);

        CmbDecimals.Items.Clear();
        for (int i = 2; i <= 6; i++) CmbDecimals.Items.Add(i.ToString());

        CmbPayday.Items.Clear();
        CmbPayday.Items.Add("不显示");
        for (int d = 1; d <= 31; d++) CmbPayday.Items.Add($"每月 {d} 号");

        CmbSize.Items.Clear();
        foreach (WidgetSize s in Enum.GetValues(typeof(WidgetSize)))
            CmbSize.Items.Add(s.Title(_currentLanguage));
    }

    private void LoadValues()
    {
        _loading = true;
        var s = _store.Settings ?? new PaySettings();
        _currentLanguage = s.Language;

        CmbLanguage.SelectedIndex = s.Language == AppLanguage.En ? 1 : 0;
        TxtSalary.Text = s.Salary > 0 ? s.Salary.ToString(CultureInfo.InvariantCulture) : "";

        TxtStart.Text = PayCore.FormatTime(s.Start);
        TxtEnd.Text = PayCore.FormatTime(s.End);
        ChkLunch.IsChecked = s.LunchEnabled;
        TxtLunchStart.Text = PayCore.FormatTime(s.LunchStart);
        TxtLunchEnd.Text = PayCore.FormatTime(s.LunchEnd);

        ChkWk1.IsChecked = s.Workdays.Contains(1);
        ChkWk2.IsChecked = s.Workdays.Contains(2);
        ChkWk3.IsChecked = s.Workdays.Contains(3);
        ChkWk4.IsChecked = s.Workdays.Contains(4);
        ChkWk5.IsChecked = s.Workdays.Contains(5);
        ChkWk6.IsChecked = s.Workdays.Contains(6);
        ChkWk0.IsChecked = s.Workdays.Contains(0);

        CmbPayday.SelectedIndex = Math.Clamp(s.Payday, 0, 31);
        CmbCurrency.SelectedItem = s.Currency;
        CmbDecimals.SelectedIndex = Math.Clamp(s.Decimals - 2, 0, 4);

        CmbSize.SelectedIndex = (int)_store.Prefs.Size;
        SldOpacity.Value = _store.Prefs.Opacity;
        TxtOpacityVal.Text = $"{(int)(_store.Prefs.Opacity * 100)}%";
        ChkSound.IsChecked = s.Sound;
        ChkAutoStart.IsChecked = AutoStart.IsEnabled;

        TxtWishlist.Text = string.Join("\n", s.Wishlist.Select(w => $"{w.Name} {w.Price}"));

        TxtIntro.Visibility = _firstRun ? Visibility.Visible : Visibility.Collapsed;
        BtnSave.Content = _firstRun ? "保存并开始计时" : "保存";

        _loading = false;
        UpdateBilingualText();
    }

    private void HookEvents()
    {
        CmbLanguage.SelectionChanged += (s, e) =>
        {
            if (_loading) return;
            _currentLanguage = CmbLanguage.SelectedIndex == 1 ? AppLanguage.En : AppLanguage.ZhHans;
            UpdateBilingualText();
            RefreshHint();
        };

        CmbSalaryType.SelectionChanged += (s, e) => { if (!_loading) { RefreshEnabled(); RefreshHint(); } };
        CmbDayMode.SelectionChanged += (s, e) => { if (!_loading) { RefreshEnabled(); RefreshHint(); } };
        ChkLunch.Checked += (s, e) => { if (!_loading) { RefreshEnabled(); RefreshHint(); } };
        ChkLunch.Unchecked += (s, e) => { if (!_loading) { RefreshEnabled(); RefreshHint(); } };

        TxtSalary.TextChanged += (s, e) => { if (!_loading) RefreshHint(); };
        TxtCustomDays.TextChanged += (s, e) => { if (!_loading) RefreshHint(); };
        TxtStart.TextChanged += (s, e) => { if (!_loading) RefreshHint(); };
        TxtEnd.TextChanged += (s, e) => { if (!_loading) RefreshHint(); };
        TxtLunchStart.TextChanged += (s, e) => { if (!_loading) RefreshHint(); };
        TxtLunchEnd.TextChanged += (s, e) => { if (!_loading) RefreshHint(); };

        ChkWk1.Click += (s, e) => { if (!_loading) RefreshHint(); };
        ChkWk2.Click += (s, e) => { if (!_loading) RefreshHint(); };
        ChkWk3.Click += (s, e) => { if (!_loading) RefreshHint(); };
        ChkWk4.Click += (s, e) => { if (!_loading) RefreshHint(); };
        ChkWk5.Click += (s, e) => { if (!_loading) RefreshHint(); };
        ChkWk6.Click += (s, e) => { if (!_loading) RefreshHint(); };
        ChkWk0.Click += (s, e) => { if (!_loading) RefreshHint(); };

        CmbPayday.SelectionChanged += (s, e) => { if (!_loading) RefreshHint(); };
        CmbCurrency.SelectionChanged += (s, e) => { if (!_loading) RefreshHint(); };

        SldOpacity.ValueChanged += (s, e) =>
        {
            TxtOpacityVal.Text = $"{(int)(SldOpacity.Value * 100)}%";
        };

        BtnCancel.Click += (s, e) => Close();
        BtnSave.Click += (s, e) => Save();
    }

    private void UpdateBilingualText()
    {
        var lang = _currentLanguage;
        string Tr(string zh, string en) => L10n.T(lang, zh, en);

        Title = Tr("上班激励器 · 设置", "Work Motivator · Settings");
        TxtIntro.Text = Tr(
            "先填工资和上下班时间。保存后，屏幕右上角的像素悬浮窗就开始实时跳钱；之后右键悬浮窗、或点系统托盘金币，都能回来改。",
            "Enter your salary and working hours. After saving, the pixel widget starts counting in the upper-right corner. Right-click the widget or tray icon to return here.");

        HdrSalary.Text = Tr("工资", "Salary");
        LblPayType.Text = Tr("计薪方式", "Pay type");
        LblAmount.Text = Tr("金额", "Amount");
        LblDayMode.Text = Tr("日薪折算", "Daily pay basis");
        TxtCustomDaysUnit.Text = Tr("天", "days");

        HdrHours.Text = Tr("上下班", "Working hours");
        LblStartTime.Text = Tr("上班时间", "Start time");
        LblEndTime.Text = Tr("下班时间", "End time");
        LblLunch.Text = Tr("午休", "Lunch");
        ChkLunch.Content = Tr("午休不计薪", "Unpaid lunch break");
        TxtLunchTo.Text = Tr("至", "to");
        LblWorkdays.Text = Tr("工作日", "Workdays");

        ChkWk1.Content = Tr("一", "Mon");
        ChkWk2.Content = Tr("二", "Tue");
        ChkWk3.Content = Tr("三", "Wed");
        ChkWk4.Content = Tr("四", "Thu");
        ChkWk5.Content = Tr("五", "Fri");
        ChkWk6.Content = Tr("六", "Sat");
        ChkWk0.Content = Tr("日", "Sun");

        HdrDisplay.Text = Tr("显示", "Display");
        LblLang.Text = Tr("语言", "Language");
        LblPayday.Text = Tr("发薪日", "Payday");
        LblCurrency.Text = Tr("货币", "Currency");
        LblDecimals.Text = Tr("小数位", "Decimals");
        LblMenuBar.Text = Tr("托盘显示", "Tray display");
        LblSize.Text = Tr("悬浮窗大小", "Widget size");
        LblOpacity.Text = Tr("不透明度", "Opacity");
        ChkSound.Content = Tr("进账时播放金币音", "Play coin sound as earnings increase");
        ChkAutoStart.Content = Tr("开机自动启动", "Launch at login");

        HdrWishlist.Text = Tr("心愿单", "Wishlist");
        TxtWishlistHint.Text = Tr(
            "每行一项：名称 价格，例如「一杯奶茶 15」。悬浮窗会算出还要工作多久才买得起。",
            "One item per line: Name Price, e.g. “Milk tea 15”. The widget calculates how much longer you need to work to afford it.");

        BtnCancel.Content = Tr("取消", "Cancel");
        BtnSave.Content = _firstRun ? Tr("保存并开始计时", "Save and start") : Tr("保存", "Save");

        // Re-populate options in dropdowns
        int selSalaryType = CmbSalaryType.SelectedIndex;
        CmbSalaryType.Items.Clear();
        foreach (var t in lang == AppLanguage.En ? new[] { "Monthly", "Daily", "Hourly" } : new[] { "月薪", "日薪", "时薪" })
            CmbSalaryType.Items.Add(t);
        CmbSalaryType.SelectedIndex = selSalaryType >= 0 ? selSalaryType : (_store.Settings?.SalaryType switch
        {
            SalaryType.daily => 1,
            SalaryType.hourly => 2,
            _ => 0
        });

        int selDayMode = CmbDayMode.SelectedIndex;
        CmbDayMode.Items.Clear();
        foreach (var d in lang == AppLanguage.En ? new[] { "Actual workdays", "21.75 days", "Custom days" } : new[] { "按实际工作日", "按 21.75 天", "自定义天数" })
            CmbDayMode.Items.Add(d);
        CmbDayMode.SelectedIndex = selDayMode >= 0 ? selDayMode : (_store.Settings?.DayMode switch
        {
            DayMode.standard => 1,
            DayMode.custom => 2,
            _ => 0
        });

        int selMb = CmbMenuBar.SelectedIndex;
        CmbMenuBar.Items.Clear();
        foreach (var mb in lang == AppLanguage.En
                     ? new[] { "Today's earnings", "This month's earnings", "Countdown to off work", "Icon only" }
                     : new[] { "今日已赚", "本月已赚", "下班倒计时", "只显示图标" })
            CmbMenuBar.Items.Add(mb);
        CmbMenuBar.SelectedIndex = selMb >= 0 ? selMb : (_store.Settings?.MenuBar switch
        {
            MenuBarMode.month => 1,
            MenuBarMode.countdown => 2,
            MenuBarMode.off => 3,
            _ => 0
        });

        int selSize = CmbSize.SelectedIndex >= 0 ? CmbSize.SelectedIndex : (int)_store.Prefs.Size;
        CmbSize.Items.Clear();
        foreach (WidgetSize ws in Enum.GetValues(typeof(WidgetSize)))
            CmbSize.Items.Add(ws.Title(lang));
        CmbSize.SelectedIndex = Math.Clamp(selSize, 0, 2);

        int selPayday = CmbPayday.SelectedIndex >= 0 ? CmbPayday.SelectedIndex : (_store.Settings?.Payday ?? 0);
        CmbPayday.Items.Clear();
        CmbPayday.Items.Add(Tr("不显示", "Hidden"));
        for (int d = 1; d <= 31; d++)
            CmbPayday.Items.Add(Tr($"每月 {d} 号", $"Day {d}"));
        CmbPayday.SelectedIndex = Math.Clamp(selPayday, 0, 31);

        int selDec = CmbDecimals.SelectedIndex >= 0 ? CmbDecimals.SelectedIndex : (_store.Settings?.Decimals ?? 4) - 2;
        CmbDecimals.Items.Clear();
        for (int i = 2; i <= 6; i++)
            CmbDecimals.Items.Add(Tr($"{i} 位", $"{i} digits"));
        CmbDecimals.SelectedIndex = Math.Clamp(selDec, 0, 4);

        RefreshEnabled();
    }

    private void RefreshEnabled()
    {
        int typeIdx = CmbSalaryType.SelectedIndex;
        TxtSalaryUnit.Text = _currentLanguage == AppLanguage.En
            ? new[] { "/ month", "/ day", "/ hour" }[Math.Max(0, typeIdx)]
            : new[] { "元 / 月", "元 / 天", "元 / 小时" }[Math.Max(0, typeIdx)];

        CmbDayMode.IsEnabled = typeIdx == 0;
        TxtCustomDays.IsEnabled = typeIdx == 0 && CmbDayMode.SelectedIndex == 2;

        bool lunchOn = ChkLunch.IsChecked == true;
        TxtLunchStart.IsEnabled = lunchOn;
        TxtLunchEnd.IsEnabled = lunchOn;
    }

    private int ParseTime(string text, int fallback)
    {
        var parts = text.Split(':');
        if (parts.Length == 2 && int.TryParse(parts[0], out int h) && int.TryParse(parts[1], out int m))
        {
            return Math.Clamp(h * 60 + m, 0, 1440);
        }
        return fallback;
    }

    private PaySettings FormSettings()
    {
        var s = new PaySettings
        {
            Language = _currentLanguage,
            SalaryType = CmbSalaryType.SelectedIndex switch
            {
                1 => SalaryType.daily,
                2 => SalaryType.hourly,
                _ => SalaryType.monthly
            },
            DayMode = CmbDayMode.SelectedIndex switch
            {
                1 => DayMode.standard,
                2 => DayMode.custom,
                _ => DayMode.actual
            },
            Salary = double.TryParse(TxtSalary.Text, NumberStyles.Any, CultureInfo.InvariantCulture, out double sal) ? sal : 0,
            CustomDays = double.TryParse(TxtCustomDays.Text, NumberStyles.Any, CultureInfo.InvariantCulture, out double cd) ? cd : 22,
            Start = ParseTime(TxtStart.Text, 9 * 60),
            End = ParseTime(TxtEnd.Text, 18 * 60),
            LunchEnabled = ChkLunch.IsChecked == true,
            LunchStart = ParseTime(TxtLunchStart.Text, 12 * 60),
            LunchEnd = ParseTime(TxtLunchEnd.Text, 13 * 60),
            Workdays = new List<int>(),
            Payday = Math.Clamp(CmbPayday.SelectedIndex, 0, 31),
            Currency = CmbCurrency.SelectedItem?.ToString() ?? "¥",
            Decimals = CmbDecimals.SelectedIndex + 2,
            MenuBar = CmbMenuBar.SelectedIndex switch
            {
                1 => MenuBarMode.month,
                2 => MenuBarMode.countdown,
                3 => MenuBarMode.off,
                _ => MenuBarMode.today
            },
            Sound = ChkSound.IsChecked == true
        };

        if (ChkWk1.IsChecked == true) s.Workdays.Add(1);
        if (ChkWk2.IsChecked == true) s.Workdays.Add(2);
        if (ChkWk3.IsChecked == true) s.Workdays.Add(3);
        if (ChkWk4.IsChecked == true) s.Workdays.Add(4);
        if (ChkWk5.IsChecked == true) s.Workdays.Add(5);
        if (ChkWk6.IsChecked == true) s.Workdays.Add(6);
        if (ChkWk0.IsChecked == true) s.Workdays.Add(0);

        var wishes = new List<Wish>();
        var lines = TxtWishlist.Text.Split('\n');
        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            if (string.IsNullOrEmpty(trimmed)) continue;
            int lastSpace = trimmed.LastIndexOf(' ');
            if (lastSpace > 0)
            {
                string name = trimmed.Substring(0, lastSpace).Trim();
                string prStr = trimmed.Substring(lastSpace + 1).Trim();
                if (double.TryParse(prStr, NumberStyles.Any, CultureInfo.InvariantCulture, out double pr))
                {
                    wishes.Add(new Wish(name, pr));
                }
            }
        }
        s.Wishlist = wishes.Count > 0 ? wishes : PaySettings.GetDefaultWishlist(s.Language);

        s.Normalize();
        return s;
    }

    private void RefreshHint()
    {
        var s = FormSettings();
        string Tr(string zh, string en) => L10n.T(_currentLanguage, zh, en);

        if (!(s.Salary > 0) || !PayCore.Segments(s).Any() || !s.Workdays.Any())
        {
            TxtDailyHint.Text = Tr("填好金额和上下班时间，这里会算出日薪和时薪。",
                                   "Enter the amount and hours to see your daily and hourly pay.");
            return;
        }

        var snap = PayCore.Snapshot(s, DateTime.Now);
        string Money(double v) => PayCore.FormatMoney(v, s, 2);
        string range = PayCore.PeriodRange(snap);
        int n = snap.PeriodWorkdays;
        string hours = PayCore.FormatWorkTime(snap.PaidPerDay, 0, _currentLanguage);

        var lines = new List<string>();
        switch (s.SalaryType)
        {
            case SalaryType.monthly:
                string basis = s.DayMode switch
                {
                    DayMode.standard => Tr("21.75 天", "21.75 days"),
                    DayMode.custom => Tr($"{s.CustomDays} 天", $"{s.CustomDays} days"),
                    _ => s.Payday > 0
                        ? Tr($"本期 {n} 个工作日（{range}）", $"{n} workdays ({range})")
                        : Tr($"{snap.Month} 月 {n} 个工作日", $"{n} workdays this month")
                };
                lines.Add(Tr($"折合日薪 {Money(snap.DailyPay)}，时薪 {Money(snap.Hourly)}",
                             $"≈ {Money(snap.DailyPay)}/day, {Money(snap.Hourly)}/hour"));
                lines.Add($"= {s.Salary} ÷ {basis}");
                break;
            case SalaryType.daily:
                lines.Add(Tr($"时薪 {Money(snap.Hourly)}（每天计薪 {hours}）",
                             $"{Money(snap.Hourly)}/hour ({hours} paid per day)"));
                break;
            case SalaryType.hourly:
                lines.Add(Tr($"折合日薪 {Money(snap.DailyPay)}（每天计薪 {hours}）",
                             $"≈ {Money(snap.DailyPay)}/day ({hours} paid per day)"));
                break;
        }

        if (s.SalaryType != SalaryType.monthly)
        {
            lines.Add(s.Payday > 0
                ? Tr($"本期满勤 {Money(snap.PeriodFull)}（{n} 个工作日，{range}）",
                     $"Full period {Money(snap.PeriodFull)} ({n} workdays, {range})")
                : Tr($"本月满勤 {Money(snap.PeriodFull)}（{n} 个工作日）",
                     $"Full month {Money(snap.PeriodFull)} ({n} workdays)"));
        }

        TxtDailyHint.Text = string.Join("\n", lines);
    }

    private void Save()
    {
        var s = FormSettings();
        var errors = PayCore.Validate(s);
        if (errors.Any())
        {
            TxtError.Text = errors.First().Message;
            return;
        }

        TxtError.Text = "";
        var size = CmbSize.SelectedIndex switch
        {
            0 => WidgetSize.small,
            2 => WidgetSize.large,
            _ => WidgetSize.medium
        };
        double opacity = SldOpacity.Value;
        bool autoStart = ChkAutoStart.IsChecked == true;

        _store.SaveSettings(s);
        AutoStart.Set(autoStart, s.Language);
        OnSave?.Invoke(s, size, opacity, autoStart);
        Close();
    }
}
