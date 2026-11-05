using System;
using System.Collections.Generic;
using System.Linq;
using PixelWorkMotivator.Core;

namespace PixelWorkMotivator.Graphics;

public class Confetti
{
    public double X { get; set; }
    public double Y { get; set; }
    public double Vx { get; set; }
    public double Vy { get; set; }
    public uint Color { get; set; }

    public Confetti(double x, double y, double vx, double vy, uint color)
    {
        X = x; Y = y; Vx = vx; Vy = vy; Color = color;
    }
}

public class FloatText
{
    public string Text { get; set; }
    public double X { get; set; }
    public double Y { get; set; }
    public double Age { get; set; } = 0;
    public double Life { get; set; } = 1.4;
    public uint Color { get; set; } = Pal.Gold;

    public FloatText(string text, double x, double y, double life = 1.4, uint color = Pal.Gold)
    {
        Text = text; X = x; Y = y; Life = life; Color = color;
    }
}

public class WidgetState
{
    public PaySettings Settings { get; set; } = new();
    public PaySnapshot? Snap { get; set; }
    public WidgetSize Size { get; set; } = WidgetSize.medium;
    public double Receipt { get; set; } = 0.0;
    public bool Fishing { get; set; } = false;
    public double FishEarned { get; set; } = 0;
    public string Tip { get; set; } = "";
    public DioramaInput Diorama { get; set; } = new();
    public bool Flash { get; set; } = false;
    public List<Confetti> Confetti { get; set; } = new();
    public List<FloatText> Floaters { get; set; } = new();
    public bool Locked { get; set; } = false;
    public bool ReducedMotion { get; set; } = false;

    private string Money(double v, int dec = 2) => PayCore.FormatMoney(v, Settings, dec);

    public (string Text, uint Color) Chip
    {
        get
        {
            if (Snap == null)
                return (L10n.T(Settings.Language, "待设置", "Set up"), Pal.Red);
            if (Fishing && Snap.Status == PaySnapshot.StatusEnum.Working)
                return (L10n.T(Settings.Language, "摸鱼中", "Slacking"), Pal.Cyan);
            return (PayCore.StatusText(Snap.Status, Settings.Language), Pal.Status(Snap.Status, Fishing));
        }
    }

    public (string Label, string Value) Right
    {
        get
        {
            var lang = Settings.Language;
            if (Snap == null)
                return ("", L10n.T(lang, "右键 › 设置", "Right-click › Settings"));

            return Snap.Status switch
            {
                PaySnapshot.StatusEnum.Working => (L10n.T(lang, "距下班 ", "Off in "), PayCore.FormatClock(Snap.Countdown)),
                PaySnapshot.StatusEnum.Lunch => (L10n.T(lang, "距开工 ", "Back in "), PayCore.FormatClock(Snap.Countdown)),
                PaySnapshot.StatusEnum.Before => (L10n.T(lang, "距上班 ", "Start in "), PayCore.FormatClock(Snap.Countdown)),
                PaySnapshot.StatusEnum.After => Snap.NextStart.HasValue
                    ? ("", lang == AppLanguage.En ? Snap.NextStart.Value.Label : Snap.NextStart.Value.Label + " 上班")
                    : ("", L10n.T(lang, "收工", "Done")),
                PaySnapshot.StatusEnum.Off => ("", PayCore.PeriodEarnedLabel(Settings)),
                _ => ("", L10n.T(lang, "右键 › 设置", "Right-click › Settings"))
            };
        }
    }

    public double CounterValue
    {
        get
        {
            if (Snap == null) return 0;
            return Snap.Status == PaySnapshot.StatusEnum.Off ? Snap.PeriodEarned : Snap.EarnedToday;
        }
    }

    public double CounterSpeed
    {
        get
        {
            if (Snap == null || Snap.Status != PaySnapshot.StatusEnum.Working) return 0;
            return Snap.Rate;
        }
    }

    public int IntDigits
    {
        get
        {
            if (Snap == null) return 1;
            double top = Math.Max(Snap.Status == PaySnapshot.StatusEnum.Off ? Snap.PeriodFull : Snap.DailyPay, CounterValue);
            return Math.Max(1, ((long)Math.Floor(top)).ToString().Length);
        }
    }

    public double BarProgress
    {
        get
        {
            if (Snap == null || Snap.Status == PaySnapshot.StatusEnum.Setup) return 0;
            if (Snap.Status == PaySnapshot.StatusEnum.Off)
                return Snap.PeriodFull > 0 ? Snap.PeriodEarned / Snap.PeriodFull : 0;
            return Snap.Progress;
        }
    }

    public (uint Base, uint Hi) BarColors
    {
        get
        {
            if (Snap == null) return (Pal.Faint, Pal.Muted);
            if (Fishing && Snap.Status == PaySnapshot.StatusEnum.Working)
                return (Pal.Cyan, 0xD2FBFD);

            return Snap.Status switch
            {
                PaySnapshot.StatusEnum.Lunch => (Pal.Sky, 0xB8E2FA),
                PaySnapshot.StatusEnum.After => (Pal.Gold, Pal.GoldHi),
                PaySnapshot.StatusEnum.Off => (Pal.Lilac, 0xE2D2F7),
                _ => (Pal.Green, Pal.GreenHi)
            };
        }
    }

    public List<(string Label, string Value)> ReceiptRows
    {
        get
        {
            var lang = Settings.Language;
            if (Snap == null)
                return new List<(string, string)> { (L10n.T(lang, "先设置工资", "Set salary first"), "") };

            string paydayStr;
            if (!Snap.PaydayDays.HasValue)
                paydayStr = L10n.T(lang, "未设置", "Not set");
            else if (Snap.PaydayDays.Value == 0)
                paydayStr = L10n.T(lang, "就是今天", "Today");
            else
            {
                int d = Snap.PaydayDays.Value;
                paydayStr = L10n.T(lang, $"还有 {d} 天", d == 1 ? "In 1 day" : $"In {d} days");
            }

            return new List<(string, string)>
            {
                (PayCore.PeriodEarnedLabel(Settings), Money(Snap.PeriodEarned)),
                (L10n.T(lang, "今日满勤", "Full day"), Money(Snap.DailyPay)),
                (L10n.T(lang, "时薪", "Hourly"), Money(Snap.Hourly)),
                (L10n.T(lang, "今日进度", "Progress"), $"{Snap.Progress * 100:F1}%"),
                (L10n.T(lang, "发薪日", "Payday"), paydayStr),
                (L10n.T(lang, "带薪摸鱼", "Paid slacking"), Money(FishEarned))
            };
        }
    }
}

public class WidgetLayout
{
    public const int U = 2;

    public int SpriteScale { get; }
    public int DigitScale { get; }
    public int PanelX { get; }
    public int PanelY { get; }
    public int PanelW { get; }
    public int PanelH { get; }
    public int? DioramaX { get; }
    public int? DioramaY { get; }
    public int? DioramaSide { get; }
    public int ColumnX { get; }
    public int ColumnY { get; }
    public int ColumnW { get; }
    public int ColumnH { get; }
    public int OdometerX { get; }
    public int OdometerY { get; }
    public int BarX { get; }
    public int BarY { get; }
    public int BarW { get; }
    public int BarH { get; }
    public int SlotX { get; }
    public int SlotY { get; }
    public int SlotW { get; }
    public int SlotH { get; }
    public int ReceiptX { get; }
    public int ReceiptY { get; }
    public int ReceiptW { get; }
    public int ReceiptH { get; }
    public int ReceiptShown { get; }
    public int TipLines { get; }
    public int WindowWidth { get; }
    public int WindowHeight { get; }

    public WidgetLayout(WidgetSize size, int odometerLogicalWidth, double receiptFraction, AppLanguage language = AppLanguage.ZhHans)
    {
        int pad, baseTipLines;
        switch (size)
        {
            case WidgetSize.small:
                (SpriteScale, DigitScale, pad, baseTipLines) = (0, 2, 6, 3);
                break;
            case WidgetSize.large:
                (SpriteScale, DigitScale, pad, baseTipLines) = (3, 4, 10, 2);
                break;
            default:
                (SpriteScale, DigitScale, pad, baseTipLines) = (2, 3, 8, 2);
                break;
        }

        TipLines = baseTipLines + (language == AppLanguage.En ? 1 : 0);
        int dioramaOuter = SpriteScale > 0 ? (Diorama.Size + 2) * SpriteScale : 0;
        int statusH = 16;
        int gap = size == WidgetSize.large ? 8 : 6;
        int odoH = Odometer.CellHeight * DigitScale;
        int barH = 8;
        ColumnH = statusH + gap + odoH + gap + barH;
        int innerH = Math.Max(ColumnH, dioramaOuter);
        ColumnW = Math.Max(odometerLogicalWidth * DigitScale, language == AppLanguage.En ? 196 : 156);
        int left = U + pad;
        int colX = left + (dioramaOuter > 0 ? dioramaOuter + 10 : 0);
        PanelW = colX + ColumnW + pad + U;
        PanelH = U + pad + innerH + 12 + U;
        PanelX = 0;
        PanelY = 0;

        if (dioramaOuter > 0)
        {
            int top = U + pad + (int)Math.Floor((double)(innerH - dioramaOuter) / 2);
            int side = Diorama.Size * SpriteScale;
            DioramaX = left + SpriteScale;
            DioramaY = top + SpriteScale;
            DioramaSide = side;
        }
        else
        {
            DioramaX = null;
            DioramaY = null;
            DioramaSide = null;
        }

        int colTop = U + pad + (int)Math.Floor((double)(innerH - ColumnH) / 2);
        ColumnX = colX;
        ColumnY = colTop;

        OdometerX = colX;
        OdometerY = colTop + statusH + gap;

        BarX = colX;
        BarY = colTop + statusH + gap + odoH + gap;
        BarW = ColumnW;
        BarH = barH;

        int inset = left + 4;
        SlotX = inset - 2;
        SlotY = PanelH - U - 6;
        SlotW = PanelW - 2 * inset + 4;
        SlotH = 2;

        int fullReceiptH = ReceiptHeight(TipLines);
        ReceiptX = inset;
        ReceiptY = PanelH - U;
        ReceiptW = PanelW - 2 * inset;
        ReceiptH = fullReceiptH;

        ReceiptShown = (int)(Math.Round(fullReceiptH * Math.Clamp(receiptFraction, 0.0, 1.0) / 2.0) * 2.0);
        WindowWidth = PanelW + U;
        WindowHeight = Math.Max(PanelH + U, PanelH + ReceiptShown + U);
    }

    public static int ReceiptHeight(int tipLines)
    {
        return 8 + 16 + 8 + 6 * 16 + 16 + 8 + tipLines * 16 + 6 + 6;
    }
}

public class WidgetRenderer
{
    private readonly Odometer _odometer = new();

    public PixelBitmap Render(WidgetState st, WidgetLayout layout, bool hover)
    {
        var bmp = new PixelBitmap(layout.WindowWidth, layout.WindowHeight);
        _odometer.Layout(st.Settings.Currency, st.IntDigits, st.Settings.Decimals);

        // 1. Draw Receipt if visible
        DrawReceipt(bmp, layout, st);

        // 2. Draw Panel
        DrawPanel(bmp, layout, hover);

        // 3. Draw Diorama
        if (layout.DioramaX.HasValue && layout.DioramaY.HasValue && layout.DioramaSide.HasValue)
        {
            int dx = layout.DioramaX.Value;
            int dy = layout.DioramaY.Value;
            int s = layout.SpriteScale;
            bmp.PixelFrame(dx - s, dy - s, layout.DioramaSide.Value + 2 * s, layout.DioramaSide.Value + 2 * s, s, Pal.Ink);

            var dioramaBmp = Diorama.Render(st.Diorama);
            bmp.BlitScaled(dioramaBmp, dx, dy, s);
        }

        // 4. Draw Status Chip and Right Label
        DrawStatus(bmp, layout, st);

        // 5. Draw Progress Bar
        DrawBar(bmp, layout, st);

        // 6. Draw Paper Feed Slot
        bmp.Rect(layout.SlotX, layout.SlotY, layout.SlotW, layout.SlotH, Pal.Ink);

        // 7. Draw Odometer
        _odometer.Draw(bmp, layout.OdometerX, layout.OdometerY, layout.DigitScale, st.CounterValue,
                       st.Settings.Decimals, st.CounterSpeed, st.Flash, !st.ReducedMotion);

        // 8. Draw Confetti
        foreach (var c in st.Confetti)
        {
            int cx = (int)(Math.Round(c.X / 2.0) * 2.0);
            int cy = (int)(Math.Round(c.Y / 2.0) * 2.0);
            bmp.Rect(cx, cy, 2, 2, c.Color);
        }

        // 9. Draw Floaters
        foreach (var f in st.Floaters)
        {
            double alpha = Math.Clamp((f.Life - f.Age) / 0.4, 0.0, 1.0);
            if (alpha > 0.05)
            {
                int w = PixelFont.MeasureWidth(f.Text);
                PixelFont.DrawOutlined(bmp, f.Text, (int)(f.X - w / 2), (int)f.Y, f.Color, Pal.Ink);
            }
        }

        // 10. Draw Lock
        if (st.Locked)
        {
            DrawLock(bmp, layout);
        }

        return bmp;
    }

    private void DrawPanel(PixelBitmap bmp, WidgetLayout L, bool hover)
    {
        int px = L.PanelX, py = L.PanelY, pw = L.PanelW, ph = L.PanelH;
        int u = WidgetLayout.U;

        // Hard shadow offset by (u, u)
        bmp.PixelBlock(px + u, py + u, pw, ph, u, Pal.Ink, 128);

        // Fill panel
        bmp.Rect(px + u, py + u, pw - 2 * u, ph - 2 * u, Pal.Panel);

        // Highlight top & left
        bmp.Rect(px + u, py + u, pw - 2 * u, u, Pal.PanelHi);
        bmp.Rect(px + u, py + u, u, ph - 2 * u, Pal.PanelHi);

        // Shadow bottom & right
        bmp.Rect(px + 2 * u, py + ph - 2 * u, pw - 3 * u, u, Pal.PanelLo);
        bmp.Rect(px + pw - 2 * u, py + 2 * u, u, ph - 3 * u, Pal.PanelLo);

        // Border frame
        bmp.PixelFrame(px, py, pw, ph, u, hover ? Pal.Gold : Pal.Ink);
    }

    private void DrawStatus(PixelBitmap bmp, WidgetLayout L, WidgetState st)
    {
        var chip = st.Chip;
        int cw = PixelFont.MeasureWidth(chip.Text);
        int chipW = cw + 8;
        int chipH = 16;
        int rx = L.ColumnX;
        int ry = L.ColumnY;

        bmp.PixelBlock(rx, ry, chipW, chipH, 2, chip.Color);
        PixelFont.Draw(bmp, chip.Text, rx + 4, ry + 2, Pal.Ink);

        var right = st.Right;
        string rVal = right.Value;
        string rLbl = right.Label.TrimEnd();
        int vw = PixelFont.MeasureWidth(rVal);
        int lw = PixelFont.MeasureWidth(rLbl);
        int gap = (!string.IsNullOrEmpty(rLbl) && !string.IsNullOrEmpty(rVal)) ? 4 : 0;
        int x = L.ColumnX + L.ColumnW - vw;

        if (!string.IsNullOrEmpty(rLbl))
        {
            PixelFont.Draw(bmp, rLbl, x - lw - gap, ry + 2, Pal.Muted);
        }
        PixelFont.Draw(bmp, rVal, x, ry + 2, Pal.Text);
    }

    private void DrawBar(PixelBitmap bmp, WidgetLayout L, WidgetState st)
    {
        int bx = L.BarX, by = L.BarY, bw = L.BarW, bh = L.BarH;
        bmp.PixelFrame(bx, by, bw, bh, 2, Pal.Ink);

        int innerX = bx + 2;
        int innerY = by + 2;
        int innerW = bw - 4;
        int innerH = bh - 4;
        bmp.Rect(innerX, innerY, innerW, innerH, Pal.PanelLo);

        int cells = 20;
        int gap = 2;
        int cellW = (int)Math.Floor((double)(innerW - (cells - 1) * gap) / cells);
        int x = innerX + (int)Math.Floor((double)(innerW - cells * cellW - (cells - 1) * gap) / 2);

        double filled = st.BarProgress * cells;
        var colors = st.BarColors;

        for (int i = 0; i < cells; i++)
        {
            double f = Math.Clamp(filled - i, 0.0, 1.0);
            if (f > 0)
            {
                int w = Math.Max(2, (int)Math.Floor(f * cellW / 2.0) * 2);
                bmp.Rect(x, innerY, w, innerH, colors.Base);
                bmp.Rect(x, innerY, w, 2, colors.Hi);
                if (w < cellW)
                {
                    bmp.Rect(x + w, innerY, cellW - w, innerH, 0x2A2639);
                }
            }
            else
            {
                bmp.Rect(x, innerY, cellW, innerH, 0x2A2639);
            }
            x += cellW + gap;
        }
    }

    private void DrawReceipt(PixelBitmap bmp, WidgetLayout L, WidgetState st)
    {
        if (L.ReceiptShown <= 0) return;

        int rx = L.ReceiptX;
        int rw = L.ReceiptW;
        int rh = L.ReceiptH;
        int top = L.ReceiptY + L.ReceiptShown - rh;
        int bodyH = rh - 6;

        // Clip region: [L.ReceiptX - 2, L.ReceiptY, rw + 6, L.ReceiptShown + 2]
        // Since we draw in bmp, ensure we clip within receiptShown boundary:
        int clipTop = L.ReceiptY;
        int clipBottom = L.ReceiptY + L.ReceiptShown;

        // Draw shadow and paper body (only the part within clip)
        int drawTop = Math.Max(clipTop, top);
        int drawBottom = Math.Min(clipBottom, top + bodyH);
        if (drawBottom > drawTop)
        {
            int h = drawBottom - drawTop;
            bmp.Rect(rx + 2, drawTop + 2, rw, h, Pal.Ink, 128);
            bmp.Rect(rx, drawTop, rw, h, Pal.Ink);
            bmp.Rect(rx + 2, drawTop, rw - 4, h, Pal.Paper);
        }

        // Draw serrated bottom teeth
        int teethTop = top + bodyH;
        if (teethTop < clipBottom && teethTop + 6 >= clipTop)
        {
            for (int x = rx; x < rx + rw; x += 12)
            {
                int w1 = Math.Min(2, rx + rw - x);
                if (w1 > 0 && teethTop >= clipTop && teethTop < clipBottom) bmp.Rect(x, teethTop, w1, 2, Pal.Ink);

                int w2 = Math.Min(8, rx + rw - (x + 2));
                if (w2 > 0 && teethTop >= clipTop && teethTop < clipBottom) bmp.Rect(x + 2, teethTop, w2, 2, Pal.Paper);

                int w3 = Math.Min(2, rx + rw - (x + 10));
                if (w3 > 0 && teethTop >= clipTop && teethTop < clipBottom) bmp.Rect(x + 10, teethTop, w3, 2, Pal.Ink);

                if (teethTop + 2 >= clipTop && teethTop + 2 < clipBottom)
                {
                    if (rx + rw > x + 2) bmp.Rect(x + 2, teethTop + 2, Math.Min(2, rx + rw - (x + 2)), 2, Pal.Ink);
                    if (rx + rw > x + 4) bmp.Rect(x + 4, teethTop + 2, Math.Min(4, rx + rw - (x + 4)), 2, Pal.Paper);
                    if (rx + rw > x + 8) bmp.Rect(x + 8, teethTop + 2, Math.Min(2, rx + rw - (x + 8)), 2, Pal.Ink);
                }

                if (teethTop + 4 >= clipTop && teethTop + 4 < clipBottom)
                {
                    if (rx + rw > x + 4) bmp.Rect(x + 4, teethTop + 4, Math.Min(4, rx + rw - (x + 4)), 2, Pal.Ink);
                }
            }
        }

        // Now draw receipt text contents if they fall within [clipTop, clipBottom]
        int tx = rx + 10;
        int tr = rx + rw - 10;
        int y = top + 8;

        string title = L10n.T(st.Settings.Language, "工 资 条", "PAY SLIP");
        if (y >= clipTop && y + 14 <= clipBottom)
        {
            PixelFont.Draw(bmp, title, tx, y, Pal.PaperInk);
            if (st.Snap != null)
            {
                string ym = st.Settings.Payday > 0
                    ? PayCore.PeriodRange(st.Snap)
                    : $"{st.Snap.Year}.{st.Snap.Month:D2}";
                int ymw = PixelFont.MeasureWidth(ym);
                PixelFont.Draw(bmp, ym, tr - ymw, y, Pal.PaperFaint);
            }
        }

        y += 16;
        if (y + 2 >= clipTop && y + 4 <= clipBottom)
        {
            DrawDashed(bmp, tx, tr, y + 2);
        }

        y += 8;
        foreach (var (label, value) in st.ReceiptRows)
        {
            if (y >= clipTop && y + 14 <= clipBottom)
            {
                PixelFont.Draw(bmp, label, tx, y, Pal.PaperInk);
                int lw = PixelFont.MeasureWidth(label);
                int vw = PixelFont.MeasureWidth(value);
                PixelFont.Draw(bmp, value, tr - vw, y, Pal.PaperInk);
                DrawDotted(bmp, tx + lw + 6, tr - vw - 6, y + 9);
            }
            y += 16;
        }

        y += 16 * Math.Max(0, 6 - st.ReceiptRows.Count);
        if (y >= clipTop && y + 14 <= clipBottom)
        {
            PixelFont.Draw(bmp, L10n.T(st.Settings.Language, "* 已过的工作日按满勤计", "* Past workdays paid in full"),
                           tx, y, Pal.PaperFaint);
        }

        y += 16;
        if (y + 2 >= clipTop && y + 4 <= clipBottom)
        {
            DrawDashed(bmp, tx, tr, y + 2);
        }

        y += 8;
        if (y >= clipTop && y < clipBottom)
        {
            string tipText = "▶ " + st.Tip;
            PixelFont.DrawWrapped(bmp, tipText, tx, y, tr - tx, L.TipLines, Pal.PaperInk);
        }
    }

    private void DrawDashed(PixelBitmap bmp, int x0, int x1, int y)
    {
        for (int x = x0; x + 4 <= x1; x += 8)
        {
            bmp.Rect(x, y, 4, 2, Pal.PaperLine);
        }
    }

    private void DrawDotted(PixelBitmap bmp, int x0, int x1, int y)
    {
        int startX = (int)Math.Ceiling(x0 / 2.0) * 2;
        for (int x = startX; x + 2 <= x1; x += 4)
        {
            bmp.Rect(x, y, 2, 2, Pal.PaperLine);
        }
    }

    private void DrawLock(PixelBitmap bmp, WidgetLayout L)
    {
        var art = new[]
        {
            ".###.",
            "#...#",
            "#...#",
            "#####",
            "##.##",
            "#####"
        };
        int ox = L.PanelW - 2 * WidgetLayout.U - 12;
        int oy = L.PanelY + 2 * WidgetLayout.U + 2;

        for (int r = 0; r < art.Length; r++)
        {
            string row = art[r];
            for (int c = 0; c < row.Length; c++)
            {
                if (row[c] == '#')
                {
                    bmp.Rect(ox + c * 2, oy + r * 2, 2, 2, Pal.Faint);
                }
            }
        }
    }
}
