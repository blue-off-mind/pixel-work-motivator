using System;
using System.Globalization;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Media.Imaging;
using PixelWorkMotivator.Core;
using PixelWorkMotivator.Graphics;
using PixelWorkMotivator.UI;

namespace PixelWorkMotivator;

public class LaunchOptions
{
    public string? Snapshot { get; set; }
    public string? SettingsSnapshot { get; set; }
    public DateTime? Now { get; set; }
    public double Speed { get; set; } = 1.0;
    public string? SettingsJson { get; set; }
    public WidgetSize? Size { get; set; }
    public bool Expanded { get; set; }
    public double? FishingMinutes { get; set; }
    public bool Celebrate { get; set; }
    public bool Coin { get; set; }
    public double Anim { get; set; }
    public uint? Background { get; set; } = 0x56627D;
    public bool PrintOnly { get; set; }

    public bool IsDebugRun => Snapshot != null || SettingsSnapshot != null || SettingsJson != null || PrintOnly;

    public static LaunchOptions Parse(string[] args)
    {
        var o = new LaunchOptions();
        for (int i = 0; i < args.Length; i++)
        {
            string arg = args[i];
            string? Next() => (i + 1 < args.Length) ? args[++i] : null;

            switch (arg)
            {
                case "--snapshot": o.Snapshot = Next(); break;
                case "--settings-snapshot": o.SettingsSnapshot = Next(); break;
                case "--now":
                    if (DateTime.TryParseExact(Next(), "yyyy-MM-dd'T'HH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.None, out var dt))
                        o.Now = dt;
                    break;
                case "--speed":
                    if (double.TryParse(Next(), NumberStyles.Any, CultureInfo.InvariantCulture, out double sp))
                        o.Speed = sp;
                    break;
                case "--settings": o.SettingsJson = Next(); break;
                case "--size":
                    if (Enum.TryParse<WidgetSize>(Next(), true, out var sz))
                        o.Size = sz;
                    break;
                case "--expanded": o.Expanded = true; break;
                case "--fishing":
                    if (double.TryParse(Next(), NumberStyles.Any, CultureInfo.InvariantCulture, out double fm))
                        o.FishingMinutes = fm;
                    break;
                case "--celebrate": o.Celebrate = true; break;
                case "--coin": o.Coin = true; break;
                case "--anim":
                    if (double.TryParse(Next(), NumberStyles.Any, CultureInfo.InvariantCulture, out double an))
                        o.Anim = an;
                    break;
                case "--no-bg": o.Background = null; break;
                case "--print": o.PrintOnly = true; break;
            }
        }
        return o;
    }
}

public partial class App : System.Windows.Application
{
    [System.Runtime.InteropServices.DllImport("kernel32.dll")]
    private static extern bool AttachConsole(int dwProcessId);
    [System.Runtime.InteropServices.DllImport("kernel32.dll")]
    private static extern IntPtr GetStdHandle(int nStdHandle);

    private static void EnableConsole()
    {
        if (AttachConsole(-1))
        {
            var hStdOut = GetStdHandle(-11);
            var safeHandle = new Microsoft.Win32.SafeHandles.SafeFileHandle(hStdOut, false);
            var fileStream = new FileStream(safeHandle, FileAccess.Write);
            var standardOutput = new StreamWriter(fileStream, System.Text.Encoding.UTF8) { AutoFlush = true };
            Console.SetOut(standardOutput);
        }
    }

    private Store _store = null!;
    private Clock _clock = null!;
    private WidgetWindow _widget = null!;
    private TrayManager _trayManager = null!;
    private SettingsWindow? _settingsWindow;

    private static Mutex? _singleInstanceMutex;
    private static EventWaitHandle? _showEvent;
    private static RegisteredWaitHandle? _waitHandle;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var options = LaunchOptions.Parse(e.Args);
        if (options.IsDebugRun)
        {
            EnableConsole();
        }
        else
        {
            const string mutexName = "PixelWorkMotivator_SingleInstance_Mutex_blue_off_mind";
            const string eventName = "PixelWorkMotivator_SingleInstance_Event_blue_off_mind";

            bool isNewInstance = false;
            try
            {
                _singleInstanceMutex = new Mutex(true, mutexName, out isNewInstance);
            }
            catch (AbandonedMutexException)
            {
                isNewInstance = true;
            }

            if (!isNewInstance)
            {
                // Another instance is already running. Signal it to activate.
                try
                {
                    if (EventWaitHandle.TryOpenExisting(eventName, out var existingEvent))
                    {
                        existingEvent.Set();
                        existingEvent.Dispose();
                    }
                }
                catch { }

                Shutdown(0);
                return;
            }

            try
            {
                _showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, eventName);
                _waitHandle = ThreadPool.RegisterWaitForSingleObject(_showEvent, (state, timedOut) =>
                {
                    Dispatcher.BeginInvoke(new Action(() =>
                    {
                        if (_settingsWindow != null && _settingsWindow.IsVisible)
                        {
                            if (_settingsWindow.WindowState == WindowState.Minimized)
                                _settingsWindow.WindowState = WindowState.Normal;
                            _settingsWindow.Activate();
                        }
                        else if (_store.Settings == null)
                        {
                            OpenSettings();
                        }
                        else
                        {
                            _widget.SetWidgetVisible(true);
                            _widget.Topmost = true;
                            _widget.Activate();
                        }
                    }));
                }, null, -1, false);
            }
            catch { }
        }

        _store = new Store(options.IsDebugRun, options.SettingsJson);
        if (options.IsDebugRun)
        {
            var p = _store.Prefs;
            p.Expanded = options.Expanded;
            if (options.Size.HasValue) p.Size = options.Size.Value;
            p.Locked = false;
            p.Fish = new FishState();
            _store.Prefs = p;
        }

        _clock = new Clock(options.Now, options.Speed);

        if (options.PrintOnly)
        {
            var snap = PayCore.Snapshot(_store.Settings ?? new PaySettings(), _clock.Now());
            var s = _store.Settings ?? new PaySettings();
            Console.WriteLine($"托盘文字：{PayCore.MenuBarText(s, snap)}");
            foreach (var l in PayCore.MenuLines(s, snap)) Console.WriteLine("  " + l);
            foreach (var t in PayCore.Tips(s, snap)) Console.WriteLine("  ▶ " + t);
            Shutdown(0);
            return;
        }

        if (!string.IsNullOrEmpty(options.Snapshot))
        {
            RunSnapshot(options);
            return;
        }

        if (!string.IsNullOrEmpty(options.SettingsSnapshot))
        {
            RunSettingsSnapshot(options);
            return;
        }

        _widget = new WidgetWindow(_store, _clock);

        _trayManager = new TrayManager(
            _store,
            openSettings: OpenSettings,
            toggleReceipt: () => _widget.ToggleReceipt(),
            toggleFishing: () => _widget.ToggleFishing(),
            toggleVisible: () => _widget.SetWidgetVisible(!_store.Prefs.Visible),
            toggleLock: () => _widget.SetLocked(!_store.Prefs.Locked),
            setSize: sz => _widget.SetWidgetSize(sz),
            setOpacity: op => _widget.SetWidgetOpacity(op),
            resetPosition: () => _widget.ResetPosition(),
            quit: QuitApp
        );

        _widget.OnTick = snap => _trayManager.UpdateStatus(snap, _widget.Settings);
        _widget.GetContextMenu = () => _trayManager.GetContextMenu();

        _widget.Start();

        if (_store.Settings == null)
        {
            OpenSettings();
        }
    }

    private void RunSnapshot(LaunchOptions options)
    {
        var s = _store.Settings ?? new PaySettings();
        var snap = PayCore.Snapshot(s, _clock.Now());

        var odo = new Odometer();
        odo.Layout(s.Currency, 2, s.Decimals);
        var layout = new WidgetLayout(_store.Prefs.Size, odo.LogicalWidth, options.Expanded ? 1.0 : 0.0, s.Language);

        var renderer = new WidgetRenderer();
        var st = new WidgetState
        {
            Settings = s,
            Snap = snap,
            Size = _store.Prefs.Size,
            Receipt = options.Expanded ? 1.0 : 0.0,
            Tip = PayCore.Tips(s, snap).FirstOrDefault() ?? ""
        };

        var bmp = renderer.Render(st, layout, false);
        var bmpSource = bmp.ToBitmapSource();

        using var fileStream = new FileStream(options.Snapshot!, FileMode.Create);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bmpSource));
        encoder.Save(fileStream);

        Console.WriteLine($"已写入 {options.Snapshot}");
        Shutdown(0);
    }

    private void RunSettingsSnapshot(LaunchOptions options)
    {
        try
        {
            var win = new SettingsWindow(_store);
            win.Show();
            win.UpdateLayout();

            int w = (int)Math.Max(540, win.ActualWidth);
            int h = (int)Math.Max(800, win.ActualHeight);

            var rtb = new RenderTargetBitmap(w, h, 96, 96, System.Windows.Media.PixelFormats.Pbgra32);
            rtb.Render(win);

            using (var fileStream = new FileStream(options.SettingsSnapshot!, FileMode.Create))
            {
                var encoder = new PngBitmapEncoder();
                encoder.Frames.Add(BitmapFrame.Create(rtb));
                encoder.Save(fileStream);
            }

            win.Close();
            Console.WriteLine($"已写入 {options.SettingsSnapshot}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Snapshot error: {ex}");
        }
        Shutdown(0);
    }

    private void OpenSettings()
    {
        if (_settingsWindow == null)
        {
            _settingsWindow = new SettingsWindow(_store);
            _settingsWindow.OnSave = (s, size, opacity, autoStart) =>
            {
                _widget.SetWidgetSize(size);
                _widget.SetWidgetOpacity(opacity);
                _widget.ApplySettingsAndPrefs();
                _widget.Step(0);
                if (_store.Prefs.Visible)
                {
                    _widget.Show();
                }
            };
            _settingsWindow.Closed += (s, e) => _settingsWindow = null;
        }

        _settingsWindow.Show();
        _settingsWindow.Activate();
    }

    private void CleanupSingleInstance()
    {
        try { _waitHandle?.Unregister(null); } catch { }
        try { _showEvent?.Dispose(); } catch { }
        if (_singleInstanceMutex != null)
        {
            try { _singleInstanceMutex.ReleaseMutex(); } catch { }
            try { _singleInstanceMutex.Dispose(); } catch { }
            _singleInstanceMutex = null;
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        CleanupSingleInstance();
        base.OnExit(e);
    }

    private void QuitApp()
    {
        _trayManager.Dispose();
        CleanupSingleInstance();
        Shutdown(0);
    }
}
