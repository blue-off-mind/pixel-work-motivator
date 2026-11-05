using System;
using System.Collections.Generic;
using System.Linq;

namespace PixelWorkMotivator.Graphics;

public class Odometer
{
    public const int Pitch = 12; // 9 glyph rows + 3 gap
    public const int CellHeight = 10; // 9 glyph rows + 1 shadow
    public const int Gap = 2;

    public abstract record CellKind;
    public record SymbolCell(char Symbol, int? LitFrom) : CellKind;
    public record DigitCell(int Place) : CellKind;

    public record Cell(CellKind Kind, int X, int Width);

    public List<Cell> Cells { get; private set; } = new();
    public int LogicalWidth { get; private set; }

    private string _key = "";
    private readonly Dictionary<Glyphs.Style, PixelBitmap> _strips = new();
    private readonly Dictionary<string, PixelBitmap> _symbols = new();

    public void Layout(string currency, int intDigits, int decimals)
    {
        string newKey = $"{currency}|{intDigits}|{decimals}";
        if (newKey == _key) return;
        _key = newKey;

        var outCells = new List<Cell>();
        int x = 0;

        void Push(CellKind kind, int width, int extra = 0)
        {
            outCells.Add(new Cell(kind, x, width));
            x += width + Gap + extra;
        }

        char cur = string.IsNullOrEmpty(currency) ? '¥' : currency[0];
        Push(new SymbolCell(cur, null), Glyphs.Width(cur), 2);

        for (int k = Math.Max(1, intDigits) - 1; k >= 0; k--)
        {
            Push(new DigitCell(k), 6);
            if (k > 0 && k % 3 == 0)
            {
                Push(new SymbolCell(',', k), 3);
            }
        }

        Push(new SymbolCell('.', null), 2);

        for (int j = 1; j <= Math.Max(1, decimals); j++)
        {
            Push(new DigitCell(-j), 6);
        }

        Cells = outCells;
        LogicalWidth = x - Gap + 1;
    }

    private PixelBitmap GetStrip(Glyphs.Style style)
    {
        if (_strips.TryGetValue(style, out var cached)) return cached;

        var bmp = new PixelBitmap(7, Pitch * 11);
        for (int i = 0; i <= 10; i++)
        {
            Glyphs.Draw((char)('0' + (i % 10)), bmp, 0, i * Pitch, style);
        }
        _strips[style] = bmp;
        return bmp;
    }

    private PixelBitmap GetSymbol(char ch, Glyphs.Style style)
    {
        string k = $"{ch}-{style.Bands[1]}";
        if (_symbols.TryGetValue(k, out var cached)) return cached;

        var bmp = new PixelBitmap(Glyphs.Width(ch) + 1, CellHeight);
        Glyphs.Draw(ch, bmp, 0, 0, style);
        _symbols[k] = bmp;
        return bmp;
    }

    public void Draw(PixelBitmap dst, int originX, int originY, int scale, double value, int decimals, double speed, bool flash, bool rolling)
    {
        double v = Math.Max(0, value);
        bool moving = rolling && speed > 0;
        int highest = 0;
        foreach (var c in Cells)
        {
            if (c.Kind is DigitCell dc)
                highest = Math.Max(highest, dc.Place);
        }

        var positions = new Dictionary<int, double>();
        double carry = 0;
        for (int place = -decimals; place <= highest; place++)
        {
            double x = v * Math.Pow(10, -place) * (1 + 1e-12) + 1e-9;
            double digit = Math.Floor(x) % 10;
            double pos = (place == -decimals && moving) ? (x % 10) : (digit + carry);
            if (speed / Math.Pow(10, place) > 12)
                pos = Math.Floor(pos);
            positions[place] = pos;
            carry = (moving && pos > 9) ? (pos - 9) : 0;
        }

        foreach (var cell in Cells)
        {
            int cellX = originX + cell.X * scale;
            int cellY = originY;

            switch (cell.Kind)
            {
                case SymbolCell sc:
                {
                    bool lit = sc.LitFrom.HasValue ? v >= Math.Pow(10, sc.LitFrom.Value) : true;
                    var style = flash ? Glyphs.Style.Flash : lit ? Glyphs.Style.Gold : Glyphs.Style.Dim;
                    var symImg = GetSymbol(sc.Symbol, style);
                    dst.BlitScaled(symImg, cellX, cellY, scale);
                    break;
                }
                case DigitCell dc:
                {
                    double pos = positions.TryGetValue(dc.Place, out var p) ? p : 0;
                    int d = ((int)Math.Floor(pos) % 10 + 10) % 10;
                    int offset = (int)Math.Floor((pos - Math.Floor(pos)) * Pitch);

                    bool lit = dc.Place <= 0 || v >= Math.Pow(10, dc.Place);
                    var style = flash ? Glyphs.Style.Flash : !lit ? Glyphs.Style.Dim : dc.Place < -2 ? Glyphs.Style.Copper : Glyphs.Style.Gold;
                    var strip = GetStrip(style);

                    int stripY = d * Pitch + offset;
                    // Draw CellHeight pixels from strip, clipping to [0, CellHeight)
                    for (int dy = 0; dy < CellHeight; dy++)
                    {
                        int srcY = stripY + dy;
                        if (srcY >= 0 && srcY < strip.Height)
                        {
                            for (int dx = 0; dx < strip.Width; dx++)
                            {
                                uint pixel = strip.Pixels[srcY * strip.Width + dx];
                                byte a = (byte)(pixel >> 24);
                                if (a == 0) continue;
                                uint rgb = ((pixel >> 16) & 0xFF) << 16 | ((pixel >> 8) & 0xFF) << 8 | (pixel & 0xFF);
                                dst.Rect(cellX + dx * scale, cellY + dy * scale, scale, scale, rgb, a);
                            }
                        }
                    }
                    break;
                }
            }
        }
    }
}
