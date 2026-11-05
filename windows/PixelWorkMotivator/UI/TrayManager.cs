using System;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;
using PixelWorkMotivator.Core;

namespace PixelWorkMotivator.UI;

public class TrayManager : IDisposable
{
    private readonly NotifyIcon _notifyIcon;
    private readonly Store _store;
    private readonly Action _openSettings;
    private readonly Action _toggleReceipt;
    private readonly Action _toggleFishing;
    private readonly Action _toggleVisible;
    private readonly Action _toggleLock;
    private readonly Action<WidgetSize> _setSize;
    private readonly Action<double> _setOpacity;
    private readonly Action _resetPosition;
    private readonly Action _quit;

    private PaySnapshot? _lastSnapshot;

    public TrayManager(
        Store store,
        Action openSettings,
        Action toggleReceipt,
        Action toggleFishing,
        Action toggleVisible,
        Action toggleLock,
        Action<WidgetSize> setSize,
        Action<double> setOpacity,
        Action resetPosition,
        Action quit)
    {
        _store = store;
        _openSettings = openSettings;
        _toggleReceipt = toggleReceipt;
        _toggleFishing = toggleFishing;
        _toggleVisible = toggleVisible;
        _toggleLock = toggleLock;
        _setSize = setSize;
        _setOpacity = setOpacity;
        _resetPosition = resetPosition;
        _quit = quit;

        _notifyIcon = new NotifyIcon
        {
            Icon = CreateCoinIcon(),
            Visible = true,
            Text = "上班激励器"
        };

        _notifyIcon.MouseClick += (s, e) =>
        {
            if (e.Button == MouseButtons.Left)
            {
                // Single left click: toggle visible or bring to front
                if (!_store.Prefs.Visible)
                {
                    _toggleVisible();
                }
                else
                {
                    _toggleReceipt();
                }
            }
        };

        _notifyIcon.ContextMenuStrip = new ContextMenuStrip();
        _notifyIcon.ContextMenuStrip.Opening += (s, e) => BuildContextMenu();
    }

    public static Icon CreateCoinIcon()
    {
        string[] art = {
            "..NNNN..",
            ".NYYyyN.",
            "NYyyyyoN",
            "NYyyyyoN",
            "NyyyyyoN",
            "NyyyyooN",
            ".NyoooN.",
            "..NNNN.."
        };

        var pal = new System.Collections.Generic.Dictionary<char, Color>
        {
            ['N'] = Color.FromArgb(0x7A, 0x4A, 0x12),
            ['Y'] = Color.FromArgb(0xFF, 0xF0, 0xB3),
            ['y'] = Color.FromArgb(0xFF, 0xC8, 0x3D),
            ['o'] = Color.FromArgb(0xE0, 0x8A, 0x1E)
        };

        using var bmp = new Bitmap(16, 16);
        using (var g = System.Drawing.Graphics.FromImage(bmp))
        {
            g.Clear(Color.Transparent);
            for (int r = 0; r < art.Length; r++)
            {
                string row = art[r];
                for (int c = 0; c < row.Length; c++)
                {
                    if (pal.TryGetValue(row[c], out var color))
                    {
                        using var brush = new SolidBrush(color);
                        g.FillRectangle(brush, c * 2, r * 2, 2, 2);
                    }
                }
            }
        }

        IntPtr hIcon = bmp.GetHicon();
        return Icon.FromHandle(hIcon);
    }

    public void UpdateStatus(PaySnapshot snap, PaySettings s)
    {
        _lastSnapshot = snap;
        string text = PayCore.MenuBarText(s, snap);
        string title = string.IsNullOrEmpty(text) ? "上班激励器" : $"上班激励器 · {text}";
        if (title.Length > 63) title = title.Substring(0, 63);
        try
        {
            _notifyIcon.Text = title;
        }
        catch { }
    }

    public void BuildContextMenu()
    {
        var menu = _notifyIcon.ContextMenuStrip;
        if (menu == null) return;
        menu.Items.Clear();

        var s = _store.Settings ?? new PaySettings();
        var p = _store.Prefs;
        var lang = s.Language;
        string Tr(string zh, string en) => L10n.T(lang, zh, en);

        if (_lastSnapshot != null)
        {
            var lines = PayCore.MenuLines(s, _lastSnapshot);
            foreach (var line in lines)
            {
                var item = new ToolStripMenuItem(line) { Enabled = false };
                menu.Items.Add(item);
            }

            double fish = GetFishEarned(_lastSnapshot);
            if (IsFishing || fish > 0)
            {
                var item = new ToolStripMenuItem(Tr("今日带薪摸鱼 ", "Paid slacking today: ") +
                    PayCore.FormatMoney(fish, s, 2))
                { Enabled = false };
                menu.Items.Add(item);
            }
        }

        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(new ToolStripMenuItem(
            p.Expanded ? Tr("收起工资条", "Collapse pay slip") : Tr("拉出工资条", "Show pay slip"),
            null, (s, e) => _toggleReceipt()));

        menu.Items.Add(new ToolStripMenuItem(
            IsFishing ? Tr("结束摸鱼", "End slacking") : Tr("开始带薪摸鱼", "Start paid slacking"),
            null, (s, e) => _toggleFishing()));

        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(new ToolStripMenuItem(
            p.Visible ? Tr("隐藏悬浮窗", "Hide widget") : Tr("显示悬浮窗", "Show widget"),
            null, (s, e) => _toggleVisible()));

        var lockItem = new ToolStripMenuItem(Tr("锁定悬浮窗（鼠标穿透）", "Lock widget (click-through)"), null, (s, e) => _toggleLock())
        {
            Checked = p.Locked
        };
        menu.Items.Add(lockItem);

        // Size Submenu
        var sizeMenu = new ToolStripMenuItem(Tr("悬浮窗大小", "Widget size"));
        foreach (WidgetSize size in Enum.GetValues(typeof(WidgetSize)))
        {
            var item = new ToolStripMenuItem(size.Title(lang), null, (s, e) => _setSize(size))
            {
                Checked = p.Size == size
            };
            sizeMenu.DropDownItems.Add(item);
        }
        menu.Items.Add(sizeMenu);

        // Opacity Submenu
        var alphaMenu = new ToolStripMenuItem(Tr("不透明度", "Opacity"));
        foreach (double alpha in new[] { 1.0, 0.85, 0.7, 0.55 })
        {
            var item = new ToolStripMenuItem($"{(int)(alpha * 100)}%", null, (s, e) => _setOpacity(alpha))
            {
                Checked = Math.Abs(p.Opacity - alpha) < 0.01
            };
            alphaMenu.DropDownItems.Add(item);
        }
        menu.Items.Add(alphaMenu);

        menu.Items.Add(new ToolStripMenuItem(Tr("移回屏幕右上角", "Move to upper-right corner"), null, (s, e) => _resetPosition()));

        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(new ToolStripMenuItem(Tr("设置…", "Settings…"), null, (s, e) => _openSettings()));

        var autoStartItem = new ToolStripMenuItem(Tr("开机自动启动", "Launch at login"), null, (s, e) =>
        {
            bool current = AutoStart.IsEnabled;
            string? err = AutoStart.Set(!current, lang);
            if (!string.IsNullOrEmpty(err))
            {
                MessageBox.Show(err, Tr("开机自动启动没有打开", "Launch at login could not be enabled"),
                                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        })
        {
            Checked = AutoStart.IsEnabled
        };
        menu.Items.Add(autoStartItem);

        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(new ToolStripMenuItem(Tr("退出上班激励器", "Quit Work Motivator"), null, (s, e) => _quit()));
    }

    public ContextMenuStrip GetContextMenu()
    {
        BuildContextMenu();
        return _notifyIcon.ContextMenuStrip ?? new ContextMenuStrip();
    }

    private bool IsFishing
    {
        get
        {
            if (_lastSnapshot == null) return false;
            string dayKey = $"{_lastSnapshot.Year}-{_lastSnapshot.Month:D2}-{_lastSnapshot.Day:D2}";
            return _store.Prefs.Fish.Since != null && _store.Prefs.Fish.Day == dayKey;
        }
    }

    private double GetFishEarned(PaySnapshot snap)
    {
        var f = _store.Prefs.Fish;
        string dayKey = $"{snap.Year}-{snap.Month:D2}-{snap.Day:D2}";
        if (f.Day != dayKey) return 0;
        double live = f.Since.HasValue ? Math.Max(0, snap.Worked - f.Since.Value) : 0;
        return (f.Total + live) * snap.Rate;
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
    }
}
