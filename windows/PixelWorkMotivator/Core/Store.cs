using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Win32;

namespace PixelWorkMotivator.Core;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum WidgetSize
{
    [JsonPropertyName("small")] small,
    [JsonPropertyName("medium")] medium,
    [JsonPropertyName("large")] large
}

public static class WidgetSizeExtensions
{
    public static string Title(this WidgetSize size, AppLanguage language = AppLanguage.ZhHans)
    {
        return size switch
        {
            WidgetSize.small => L10n.T(language, "小", "Small"),
            WidgetSize.medium => L10n.T(language, "中", "Medium"),
            WidgetSize.large => L10n.T(language, "大", "Large"),
            _ => ""
        };
    }
}

public class FishState : IEquatable<FishState>
{
    [JsonPropertyName("day")]
    public string Day { get; set; } = "";

    [JsonPropertyName("total")]
    public double Total { get; set; } = 0;

    [JsonPropertyName("since")]
    public double? Since { get; set; } = null;

    public FishState() { }

    public FishState(string day)
    {
        Day = day;
    }

    public bool Equals(FishState? other)
    {
        if (other is null) return false;
        return Day == other.Day && Math.Abs(Total - other.Total) < 1e-9 && Nullable.Equals(Since, other.Since);
    }

    public override bool Equals(object? obj) => Equals(obj as FishState);
    public override int GetHashCode() => HashCode.Combine(Day, Total, Since);
}

public class WidgetPrefs : IEquatable<WidgetPrefs>
{
    [JsonPropertyName("top")]
    public double? Top { get; set; }

    [JsonPropertyName("left")]
    public double? Left { get; set; }

    [JsonPropertyName("expanded")]
    public bool Expanded { get; set; } = false;

    [JsonPropertyName("locked")]
    public bool Locked { get; set; } = false;

    [JsonPropertyName("visible")]
    public bool Visible { get; set; } = true;

    [JsonPropertyName("size")]
    public WidgetSize Size { get; set; } = WidgetSize.medium;

    [JsonPropertyName("opacity")]
    public double Opacity { get; set; } = 1.0;

    [JsonPropertyName("fish")]
    public FishState Fish { get; set; } = new();

    public void Normalize()
    {
        Opacity = Math.Clamp(Opacity, 0.3, 1.0);
    }

    public bool Equals(WidgetPrefs? other)
    {
        if (other is null) return false;
        return Top == other.Top &&
               Left == other.Left &&
               Expanded == other.Expanded &&
               Locked == other.Locked &&
               Visible == other.Visible &&
               Size == other.Size &&
               Math.Abs(Opacity - other.Opacity) < 1e-6 &&
               Fish.Equals(other.Fish);
    }

    public override bool Equals(object? obj) => Equals(obj as WidgetPrefs);
    public override int GetHashCode() => HashCode.Combine(Top, Left, Expanded, Locked, Visible, Size, Opacity, Fish);
}

public static class AutoStart
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string AppName = "PixelWorkMotivator";

    public static bool IsEnabled
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RunKey, false);
                return key?.GetValue(AppName) != null;
            }
            catch
            {
                return false;
            }
        }
    }

    public static string? Set(bool enable, AppLanguage language = AppLanguage.ZhHans)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, true);
            if (key == null) return L10n.T(language, "无法访问注册表自启动项", "Unable to access registry run key");

            if (enable)
            {
                string? exePath = Environment.ProcessPath;
                if (string.IsNullOrEmpty(exePath))
                    return L10n.T(language, "无法获取应用路径", "Unable to get executable path");

                key.SetValue(AppName, $"\"{exePath}\"");
            }
            else
            {
                key.DeleteValue(AppName, false);
            }
            return null;
        }
        catch (Exception ex)
        {
            return ex.Message;
        }
    }
}

public class Store
{
    private readonly bool _ephemeral;
    private readonly string _settingsPath;
    private readonly string _prefsPath;

    public PaySettings? Settings { get; private set; }
    private WidgetPrefs _prefs = new();

    public WidgetPrefs Prefs
    {
        get => _prefs;
        set
        {
            if (!_prefs.Equals(value))
            {
                _prefs = value;
                SavePrefs();
            }
        }
    }

    public Store(bool ephemeral, string? settingsJson = null)
    {
        _ephemeral = ephemeral;
        string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        string folder = Path.Combine(appData, "PixelWorkMotivator");
        _settingsPath = Path.Combine(folder, "settings.json");
        _prefsPath = Path.Combine(folder, "prefs.json");

        if (!ephemeral && !Directory.Exists(folder))
        {
            try { Directory.CreateDirectory(folder); } catch { }
        }

        if (!string.IsNullOrEmpty(settingsJson))
        {
            Settings = PaySettings.FromJson(settingsJson);
        }
        else if (!ephemeral && File.Exists(_settingsPath))
        {
            try
            {
                string json = File.ReadAllText(_settingsPath);
                Settings = PaySettings.FromJson(json);
            }
            catch { }
        }

        if (!ephemeral && File.Exists(_prefsPath))
        {
            try
            {
                string json = File.ReadAllText(_prefsPath);
                var p = JsonSerializer.Deserialize<WidgetPrefs>(json);
                if (p != null)
                {
                    p.Normalize();
                    _prefs = p;
                }
            }
            catch { }
        }
    }

    public void SaveSettings(PaySettings s)
    {
        Settings = s;
        if (_ephemeral) return;
        try
        {
            File.WriteAllText(_settingsPath, s.ToJson());
        }
        catch { }
    }

    private void SavePrefs()
    {
        if (_ephemeral) return;
        try
        {
            var options = new JsonSerializerOptions { WriteIndented = true };
            File.WriteAllText(_prefsPath, JsonSerializer.Serialize(_prefs, options));
        }
        catch { }
    }
}

public class Clock
{
    public DateTime? Base { get; set; }
    public double Speed { get; set; } = 1.0;
    public DateTime Started { get; } = DateTime.Now;

    public Clock(DateTime? baseDate = null, double speed = 1.0)
    {
        Base = baseDate;
        Speed = speed;
    }

    public DateTime Now()
    {
        if (!Base.HasValue && Math.Abs(Speed - 1.0) < 1e-9)
            return DateTime.Now;

        return (Base ?? Started).AddSeconds((DateTime.Now - Started).TotalSeconds * Speed);
    }
}
