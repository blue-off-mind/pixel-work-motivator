using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using PixelWorkMotivator.Core;
using PixelWorkMotivator.Graphics;

namespace PixelWorkMotivator.UI;

public partial class WidgetWindow : Window
{
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int WS_EX_NOACTIVATE = 0x08000000;
    private const int WS_EX_TRANSPARENT = 0x00000020;

    [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
    private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    private readonly Store _store;
    private readonly Clock _clock;
    private readonly WidgetRenderer _renderer = new();

    private DispatcherTimer? _timer;
    private Stopwatch _stopwatch = Stopwatch.StartNew();
    private double _lastRealTime = 0;
    private double _animTime = 0;

    private double _receipt = 0;
    private List<(double Born, double Unit)> _coins = new();
    private List<(double Born, double X)> _zzz = new();
    private double _lastZ = -10;
    private List<Confetti> _confetti = new();
    private List<FloatText> _floaters = new();
    private double _flashUntil = 0;
    private double _sparkleUntil = 0;
    private double _celebrateUntil = -1;
    private PaySnapshot.StatusEnum? _lastStatus = null;
    private int? _lastCoin = null;
    private string _dayKey = "";
    private int _tipIndex = 0;
    private double _tipAt = -100;
    private string _tip = "";

    private bool _hover = false;
    private System.Windows.Point _downPoint;
    private bool _isDragging = false;
    private bool _hasMouseDown = false;

    private WriteableBitmap? _writeableBitmap;
    private WidgetLayout? _currentLayout;

    public PaySnapshot Snapshot { get; private set; }
    public PaySettings Settings => _store.Settings ?? new PaySettings();
    public Action<PaySnapshot>? OnTick { get; set; }
    public Func<System.Windows.Forms.ContextMenuStrip>? GetContextMenu { get; set; }

    public WidgetWindow(Store store, Clock clock)
    {
        InitializeComponent();
        _store = store;
        _clock = clock;

        _receipt = _store.Prefs.Expanded ? 1.0 : 0.0;
        Snapshot = PayCore.Snapshot(Settings, _clock.Now());

        SourceInitialized += (s, e) => ApplyExtendedStyles();
        MouseEnter += (s, e) => { _hover = true; InvalidateVisual(); };
        MouseLeave += (s, e) => { _hover = false; InvalidateVisual(); };

        MouseDown += OnMouseDownHandler;
        MouseMove += OnMouseMoveHandler;
        MouseUp += OnMouseUpHandler;
        LocationChanged += (s, e) => SavePosition();
    }

    public void Start()
    {
        var hwnd = new WindowInteropHelper(this).EnsureHandle();
        ApplyExtendedStyles();
        ApplySettingsAndPrefs();
        Step(0);
        PositionWindow();

        if (_store.Prefs.Visible)
        {
            Show();
        }

        _lastRealTime = _stopwatch.Elapsed.TotalSeconds;
        StartTimer(1.0 / 30);
    }

    private void ApplyExtendedStyles()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        int exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
        exStyle |= WS_EX_TOOLWINDOW;
        exStyle |= WS_EX_NOACTIVATE;
        if (_store.Prefs.Locked)
        {
            exStyle |= WS_EX_TRANSPARENT;
        }
        SetWindowLong(hwnd, GWL_EXSTYLE, exStyle);
    }

    public void SetClickThrough(bool locked)
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd == IntPtr.Zero) return;
        int exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
        if (locked) exStyle |= WS_EX_TRANSPARENT;
        else exStyle &= ~WS_EX_TRANSPARENT;
        SetWindowLong(hwnd, GWL_EXSTYLE, exStyle);
    }

    public void PositionWindow()
    {
        double screenW = SystemParameters.PrimaryScreenWidth;
        double screenH = SystemParameters.PrimaryScreenHeight;

        if (_store.Prefs.Left.HasValue && _store.Prefs.Top.HasValue)
        {
            double l = _store.Prefs.Left.Value;
            double t = _store.Prefs.Top.Value;
            if (l >= -Width && l < screenW && t >= -Height && t < screenH)
            {
                Left = l;
                Top = t;
                return;
            }
        }

        // Default: upper right corner with margin
        Left = screenW - Width - 30;
        Top = 40;
        SavePosition();
    }

    public void ResetPosition()
    {
        double screenW = SystemParameters.PrimaryScreenWidth;
        Left = screenW - Width - 30;
        Top = 40;
        SavePosition();
    }

    private void SavePosition()
    {
        if (IsLoaded && !double.IsNaN(Left) && !double.IsNaN(Top))
        {
            var p = _store.Prefs;
            p.Left = Left;
            p.Top = Top;
            _store.Prefs = p;
        }
    }

    public void ApplySettingsAndPrefs()
    {
        Opacity = _store.Prefs.Opacity;
        SetClickThrough(_store.Prefs.Locked);
        Step(0);
    }

    private void StartTimer(double intervalSeconds)
    {
        _timer?.Stop();
        _timer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromSeconds(intervalSeconds)
        };
        _timer.Tick += (s, e) => Tick();
        _timer.Start();
    }

    private void Tick()
    {
        double now = _stopwatch.Elapsed.TotalSeconds;
        double dt = Math.Min(0.5, now - _lastRealTime);
        _lastRealTime = now;

        Step(dt);

        double desired = DesiredInterval();
        if (_timer != null && Math.Abs(_timer.Interval.TotalSeconds - desired) > 0.005)
        {
            _timer.Interval = TimeSpan.FromSeconds(desired);
        }
    }

    public void Step(double dt)
    {
        _animTime += dt;
        double t = _animTime;
        var s = Settings;
        var snap = PayCore.Snapshot(s, _clock.Now());
        Snapshot = snap;

        string today = $"{snap.Year}-{snap.Month:D2}-{snap.Day:D2}";
        if (today != _dayKey)
        {
            _dayKey = today;
            _lastCoin = null;
            _lastStatus = null;
            if (_store.Prefs.Fish.Day != today && !string.IsNullOrEmpty(_store.Prefs.Fish.Day))
            {
                var f = _store.Prefs;
                f.Fish = new FishState(today);
                _store.Prefs = f;
            }
        }

        StatusChanged(snap, t);
        var pose = CurrentPose(snap, t);
        CheckCoin(snap, t);
        Animate(dt, t, pose);

        double target = _store.Prefs.Expanded ? 1.0 : 0.0;
        if (Math.Abs(_receipt - target) > 1e-4)
        {
            double delta = dt / 0.4;
            _receipt = target > _receipt ? Math.Min(target, _receipt + delta) : Math.Max(target, _receipt - delta);
        }

        if (t - _tipAt > 8 || string.IsNullOrEmpty(_tip))
        {
            RotateTip(snap, s, t);
        }

        RenderFrame(snap, s, t, pose);
        OnTick?.Invoke(snap);
    }

    private Pose CurrentPose(PaySnapshot snap, double t)
    {
        if (t < _celebrateUntil) return Pose.Cheering;
        return snap.Status switch
        {
            PaySnapshot.StatusEnum.Working => IsFishing ? Pose.Fishing : Pose.Typing,
            PaySnapshot.StatusEnum.Lunch => Pose.Sleeping,
            _ => Pose.Absent
        };
    }

    private void StatusChanged(PaySnapshot snap, double t)
    {
        if (_lastStatus.HasValue && _lastStatus.Value != snap.Status)
        {
            var last = _lastStatus.Value;
            if (last == PaySnapshot.StatusEnum.Working && snap.Status == PaySnapshot.StatusEnum.After)
            {
                Celebrate(t);
            }
            else if (last == PaySnapshot.StatusEnum.Working && snap.Status == PaySnapshot.StatusEnum.Lunch)
            {
                Announce(L10n.T(Settings.Language, "干饭！", "Lunch!"));
            }
            else if ((last == PaySnapshot.StatusEnum.Before || last == PaySnapshot.StatusEnum.Lunch) && snap.Status == PaySnapshot.StatusEnum.Working)
            {
                Announce(L10n.T(Settings.Language, "开工！", "Back to work!"));
            }
        }
        _lastStatus = snap.Status;
    }

    private static double CoinUnit(double rate)
    {
        double[] units = { 0.01, 0.05, 0.1, 0.5, 1, 5, 10, 50, 100, 500 };
        foreach (var unit in units)
        {
            if (rate <= 0 || unit / rate >= 10) return unit;
        }
        return 1000;
    }

    private void CheckCoin(PaySnapshot snap, double t)
    {
        if (snap.Status != PaySnapshot.StatusEnum.Working || snap.Rate <= 0)
        {
            _lastCoin = null;
            return;
        }

        double unit = CoinUnit(snap.Rate);
        int index = (int)Math.Floor(snap.EarnedToday / unit + 1e-9);
        if (_lastCoin.HasValue && index > _lastCoin.Value)
        {
            if (_store.Prefs.Size != WidgetSize.small)
            {
                _coins.Add((t, unit));
            }
            else
            {
                CoinLanded(unit, t);
            }
        }
        _lastCoin = index;
    }

    private void CoinLanded(double unit, double t)
    {
        _sparkleUntil = t + 0.25;
        _flashUntil = t + 0.12;

        double anchorX, anchorY;
        if (_currentLayout?.DioramaX != null && _currentLayout.DioramaY != null)
        {
            anchorX = _currentLayout.DioramaX.Value + 4 * _currentLayout.SpriteScale + 6;
            anchorY = _currentLayout.DioramaY.Value + 8 * _currentLayout.SpriteScale;
        }
        else
        {
            anchorX = (_currentLayout?.OdometerX ?? 100) + 120;
            anchorY = (_currentLayout?.OdometerY ?? 20) - 4;
        }

        _floaters.Add(new FloatText("+" + CoinText(unit), anchorX, anchorY));
        if (Settings.Sound) Sound.Coin();
    }

    private string CoinText(double unit)
    {
        string cur = Settings.Currency;
        if (unit >= 1) return $"{cur}{(int)unit}";
        return $"{cur}{unit:F2}";
    }

    private void Celebrate(double t)
    {
        _celebrateUntil = t + 4.0;
        Announce(L10n.T(Settings.Language, "下班！", "Off work!"));
        if (Settings.Sound) Sound.Fanfare();

        double w = _currentLayout?.PanelW ?? 260;
        uint[] colors = { Pal.Gold, Pal.Green, Pal.Sky, Pal.Red, Pal.Lilac, Pal.Cyan, Pal.GoldHi };
        var rnd = new Random();
        for (int i = 0; i < 44; i++)
        {
            _confetti.Add(new Confetti(
                rnd.NextDouble() * (w - 12) + 6,
                rnd.NextDouble() * -40,
                rnd.NextDouble() * 32 - 16,
                rnd.NextDouble() * 50 + 20,
                colors[i % colors.Length]
            ));
        }
    }

    private void Announce(string text)
    {
        double x = _currentLayout?.DioramaX.HasValue == true
            ? _currentLayout.DioramaX.Value + (_currentLayout.DioramaSide ?? 48) / 2
            : (_currentLayout?.ColumnX ?? 80) + 60;
        double y = _currentLayout?.DioramaY.HasValue == true
            ? _currentLayout.DioramaY.Value + 4
            : (_currentLayout?.ColumnY ?? 20) + 18;

        _floaters.Add(new FloatText(text, x, y, 2.0));
    }

    private void Animate(double dt, double t, Pose pose)
    {
        var landed = new List<double>();
        _coins.RemoveAll(c =>
        {
            if (t - c.Born >= 0.75)
            {
                landed.Add(c.Unit);
                return true;
            }
            return false;
        });
        foreach (var u in landed) CoinLanded(u, t);

        if (pose == Pose.Sleeping && t - _lastZ > 1.4)
        {
            _zzz.Add((t, 18));
            _lastZ = t;
        }
        _zzz.RemoveAll(z => t - z.Born > 2.2);

        double height = _currentLayout?.WindowHeight ?? 200;
        foreach (var c in _confetti)
        {
            c.Vy += 90 * dt;
            c.X += c.Vx * dt;
            c.Y += c.Vy * dt;
        }
        _confetti.RemoveAll(c => c.Y > height);

        foreach (var f in _floaters)
        {
            f.Age += dt;
            f.Y -= 9 * dt;
        }
        _floaters.RemoveAll(f => f.Age >= f.Life);
    }

    private void RotateTip(PaySnapshot snap, PaySettings s, double t)
    {
        var tips = PayCore.Tips(s, snap);
        if (IsFishing)
        {
            string earned = PayCore.FormatMoney(FishEarned(snap), s, 2);
            tips.Insert(0, L10n.T(s.Language, $"带薪摸鱼中，已经摸到 {earned}。", $"Paid slacking: {earned} earned so far."));
        }
        _tipIndex++;
        _tip = tips.Count > 0 ? tips[_tipIndex % tips.Count] : "";
        _tipAt = t;
    }

    private void RenderFrame(PaySnapshot snap, PaySettings s, double t, Pose pose)
    {
        double jarLevel = snap.Status switch
        {
            PaySnapshot.StatusEnum.Working or PaySnapshot.StatusEnum.Lunch => snap.Progress,
            PaySnapshot.StatusEnum.After => 1.0,
            _ => 0.0
        };

        var dioramaInput = new DioramaInput
        {
            Pose = pose,
            Hour = snap.SecOfDay / 3600.0,
            JarLevel = jarLevel,
            T = t,
            Coins = _coins.Select(c =>
            {
                double p = Math.Min(1.0, (t - c.Born) / 0.75);
                double q = 1.0 - p;
                double x = q * q * 16.5 + 2 * q * p * 10 + p * p * 3.5;
                double y = q * q * 13 + 2 * q * p * -4 + p * p * 11;
                return new CoinAnim(x, y, t - c.Born);
            }).ToList(),
            Zzz = _zzz.Select(z => new ZeeAnim(z.X + (t - z.Born) * 1.5, 7 - (t - z.Born) * 3)).ToList(),
            Sparkle = t < _sparkleUntil
        };

        var st = new WidgetState
        {
            Settings = s,
            Snap = snap,
            Size = _store.Prefs.Size,
            Receipt = _receipt,
            Fishing = IsFishing,
            FishEarned = FishEarned(snap),
            Tip = _tip,
            Diorama = dioramaInput,
            Flash = t < _flashUntil,
            Confetti = _confetti,
            Floaters = _floaters,
            Locked = _store.Prefs.Locked,
            ReducedMotion = false
        };

        var odo = new Odometer();
        odo.Layout(s.Currency, st.IntDigits, s.Decimals);
        var layout = new WidgetLayout(_store.Prefs.Size, odo.LogicalWidth, _receipt, s.Language);
        _currentLayout = layout;

        if (_writeableBitmap == null || _writeableBitmap.PixelWidth != layout.WindowWidth || _writeableBitmap.PixelHeight != layout.WindowHeight)
        {
            _writeableBitmap = new WriteableBitmap(
                layout.WindowWidth, layout.WindowHeight,
                96, 96,
                System.Windows.Media.PixelFormats.Bgra32,
                null
            );
            DisplayImage.Source = _writeableBitmap;
            Width = layout.WindowWidth;
            Height = layout.WindowHeight;
        }

        var bmp = _renderer.Render(st, layout, _hover);
        bmp.UpdateWriteableBitmap(_writeableBitmap);
    }

    private double DesiredInterval()
    {
        if (!_store.Prefs.Visible) return 0.5;
        bool fastDigits = Snapshot.Status == PaySnapshot.StatusEnum.Working &&
                          Snapshot.Rate * Math.Pow(10, Settings.Decimals) > 1.5;
        bool animating = _coins.Count > 0 || _confetti.Count > 0 || _floaters.Count > 0 || _animTime < _celebrateUntil
                         || Math.Abs(_receipt - (_store.Prefs.Expanded ? 1.0 : 0.0)) > 1e-4;

        if (animating) return 1.0 / 30;
        return fastDigits ? 1.0 / 20 : 1.0 / 8;
    }

    public bool IsFishing
    {
        get
        {
            string dayKey = $"{Snapshot.Year}-{Snapshot.Month:D2}-{Snapshot.Day:D2}";
            return _store.Prefs.Fish.Since != null && _store.Prefs.Fish.Day == dayKey;
        }
    }

    public double FishEarned(PaySnapshot snap)
    {
        var f = _store.Prefs.Fish;
        string dayKey = $"{snap.Year}-{snap.Month:D2}-{snap.Day:D2}";
        if (f.Day != dayKey) return 0;
        double live = f.Since.HasValue ? Math.Max(0, snap.Worked - f.Since.Value) : 0;
        return (f.Total + live) * snap.Rate;
    }

    public void ToggleReceipt()
    {
        var p = _store.Prefs;
        p.Expanded = !p.Expanded;
        _store.Prefs = p;
        _tipAt = -100;
        StartTimer(1.0 / 30);
    }

    public void ToggleFishing(double minutesAgo = 0)
    {
        var snap = PayCore.Snapshot(Settings, _clock.Now());
        var p = _store.Prefs;
        var f = p.Fish;
        string day = $"{snap.Year}-{snap.Month:D2}-{snap.Day:D2}";
        if (f.Day != day) f = new FishState(day);

        if (f.Since.HasValue)
        {
            f.Total += Math.Max(0, snap.Worked - f.Since.Value);
            f.Since = null;
        }
        else
        {
            f.Since = Math.Max(0, snap.Worked - minutesAgo * 60);
        }

        p.Fish = f;
        _store.Prefs = p;
        _tipAt = -100;
        Step(0);
    }

    public void SetWidgetVisible(bool visible)
    {
        var p = _store.Prefs;
        p.Visible = visible;
        _store.Prefs = p;
        if (visible)
        {
            Step(0);
            Show();
        }
        else
        {
            Hide();
        }
    }

    public void SetLocked(bool locked)
    {
        var p = _store.Prefs;
        p.Locked = locked;
        _store.Prefs = p;
        SetClickThrough(locked);
        Step(0);
    }

    public void SetWidgetSize(WidgetSize size)
    {
        var p = _store.Prefs;
        p.Size = size;
        _store.Prefs = p;
        Step(0);
    }

    public void SetWidgetOpacity(double opacity)
    {
        var p = _store.Prefs;
        p.Opacity = opacity;
        _store.Prefs = p;
        Opacity = opacity;
    }

    private void OnMouseDownHandler(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Right)
        {
            var menu = GetContextMenu?.Invoke();
            if (menu != null)
            {
                var screenPoint = PointToScreen(e.GetPosition(this));
                menu.Show((int)screenPoint.X, (int)screenPoint.Y);
            }
            return;
        }

        if (e.ChangedButton == MouseButton.Left)
        {
            _downPoint = PointToScreen(e.GetPosition(this));
            _isDragging = false;
            _hasMouseDown = true;
        }
    }

    private void OnMouseMoveHandler(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (_hasMouseDown && e.LeftButton == MouseButtonState.Pressed && !_isDragging)
        {
            var cur = PointToScreen(e.GetPosition(this));
            if ((cur - _downPoint).Length > 3)
            {
                _isDragging = true;
                DragMove();
            }
        }
    }

    private void OnMouseUpHandler(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left && _hasMouseDown)
        {
            _hasMouseDown = false;
            if (!_isDragging)
            {
                ToggleReceipt();
            }
            _isDragging = false;
        }
    }
}
