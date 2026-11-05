using System;
using System.Collections.Generic;

namespace PixelWorkMotivator.Graphics;

public static class Glyphs
{
    public const int Height = 9;

    public record Style(uint[] Bands, uint? Shadow)
    {
        public static readonly Style Gold = new(new[] { Pal.GoldHi, Pal.Gold, Pal.GoldLo }, Pal.Ink);
        public static readonly Style Copper = new(new uint[] { 0xFFD0A8, 0xFF9A5C, 0xD8603A }, Pal.Ink);
        public static readonly Style Dim = new(new uint[] { 0x3A3550, 0x3A3550, 0x3A3550 }, null);
        public static readonly Style Flash = new(new uint[] { 0xFFFFFF, 0xFFF8E0, 0xFFE89A }, Pal.Ink);
    }

    public static readonly IReadOnlyDictionary<char, string[]> Big = new Dictionary<char, string[]>
    {
        ['0'] = new[] { ".####.", "##..##", "##..##", "##..##", "##..##", "##..##", "##..##", "##..##", ".####." },
        ['1'] = new[] { "..##..", ".###..", "####..", "..##..", "..##..", "..##..", "..##..", "..##..", "######" },
        ['2'] = new[] { ".####.", "##..##", "....##", "....##", "...##.", "..##..", ".##...", "##....", "######" },
        ['3'] = new[] { ".####.", "##..##", "....##", "....##", "..###.", "....##", "....##", "##..##", ".####." },
        ['4'] = new[] { "....##", "...###", "..####", ".##.##", "##..##", "######", "....##", "....##", "....##" },
        ['5'] = new[] { "######", "##....", "##....", "#####.", "....##", "....##", "....##", "##..##", ".####." },
        ['6'] = new[] { "..###.", ".##...", "##....", "#####.", "##..##", "##..##", "##..##", "##..##", ".####." },
        ['7'] = new[] { "######", "....##", "....##", "...##.", "...##.", "..##..", "..##..", "..##..", "..##.." },
        ['8'] = new[] { ".####.", "##..##", "##..##", "##..##", ".####.", "##..##", "##..##", "##..##", ".####." },
        ['9'] = new[] { ".####.", "##..##", "##..##", "##..##", ".#####", "....##", "....##", "...##.", ".###.." },
        ['¥'] = new[] { "##..##", "##..##", ".####.", "..##..", "######", "..##..", "######", "..##..", "..##.." },
        ['$'] = new[] { "...#..", ".#####", "##.#..", "##.#..", ".####.", "...###", "...###", "#####.", "...#.." },
        ['€'] = new[] { "..####", ".##...", "##....", "#####.", "##....", "#####.", "##....", ".##...", "..####" },
        ['£'] = new[] { "..###.", ".##.##", ".##...", ".##...", "####..", ".##...", ".##...", ".##...", "######" },
        ['.'] = new[] { "..", "..", "..", "..", "..", "..", "..", "##", "##" },
        [','] = new[] { "...", "...", "...", "...", "...", "...", ".##", ".##", "##." },
    };

    public static int Width(char ch)
    {
        return Big.TryGetValue(ch, out var rows) ? rows[0].Length : 6;
    }

    public static void Draw(char ch, PixelBitmap bmp, int x, int y, Style style)
    {
        if (!Big.TryGetValue(ch, out var rows)) return;

        if (style.Shadow.HasValue)
        {
            uint sh = style.Shadow.Value;
            for (int r = 0; r < rows.Length; r++)
            {
                string row = rows[r];
                for (int c = 0; c < row.Length; c++)
                {
                    if (row[c] == '#')
                        bmp.Set(x + c + 1, y + r + 1, sh);
                }
            }
        }

        for (int r = 0; r < rows.Length; r++)
        {
            uint band = style.Bands[r < 3 ? 0 : r < 6 ? 1 : 2];
            string row = rows[r];
            for (int c = 0; c < row.Length; c++)
            {
                if (row[c] == '#')
                    bmp.Set(x + c, y + r, band);
            }
        }
    }

    public static readonly IReadOnlyDictionary<char, string[]> Tiny = new Dictionary<char, string[]>
    {
        ['0'] = new[] { "###", "#.#", "#.#", "#.#", "###" },
        ['1'] = new[] { ".#.", "##.", ".#.", ".#.", "###" },
        ['2'] = new[] { "###", "..#", "###", "#..", "###" },
        ['3'] = new[] { "###", "..#", "###", "..#", "###" },
        ['4'] = new[] { "#.#", "#.#", "###", "..#", "..#" },
        ['5'] = new[] { "###", "#..", "###", "..#", "###" },
        ['6'] = new[] { "###", "#..", "###", "#.#", "###" },
        ['7'] = new[] { "###", "..#", "..#", "..#", "..#" },
        ['8'] = new[] { "###", "#.#", "###", "#.#", "###" },
        ['9'] = new[] { "###", "#.#", "###", "..#", "###" },
    };
}
