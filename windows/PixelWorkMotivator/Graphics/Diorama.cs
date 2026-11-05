using System;
using System.Collections.Generic;

namespace PixelWorkMotivator.Graphics;

public enum Pose
{
    Typing,
    Sleeping,
    Fishing,
    Cheering,
    Absent
}

public record struct CoinAnim(double X, double Y, double Age);
public record struct ZeeAnim(double X, double Y);

public class DioramaInput
{
    public Pose Pose { get; set; } = Pose.Absent;
    public double Hour { get; set; } = 12.0; // Local time (hours, fractional)
    public double JarLevel { get; set; } = 0.0; // 0..1
    public double T { get; set; } = 0.0; // Animation time (seconds)
    public List<CoinAnim> Coins { get; set; } = new();
    public List<ZeeAnim> Zzz { get; set; } = new();
    public bool Sparkle { get; set; } = false;
}

public static class Diorama
{
    public const int Size = 24;

    private static readonly IReadOnlyDictionary<char, uint> PalMap = new Dictionary<char, uint>
    {
        ['k'] = 0x1B1726, ['h'] = 0x2E2438, ['H'] = 0x4B3C5C, ['s'] = 0xF2C79E, ['b'] = 0xF29A8C,
        ['m'] = 0xA0503C, ['M'] = 0x6E2A2A, ['L'] = 0xD4D1E3, ['l'] = 0xA29EBB, ['y'] = 0xFFC83D,
        ['o'] = 0xE08A1E, ['Y'] = 0xFFF0B3, ['N'] = 0x7A4A12, ['n'] = 0x8F8AB3, ['g'] = 0xA8DCEF,
        ['c'] = 0x2B2A3F, ['C'] = 0x3D3B57, ['f'] = 0x73EFF7, ['w'] = 0xE8E2F2,
    };

    private static readonly string[] BaseHead = new[]
    {
        "..kkkkkk..",
        ".khhhhhhk.",
        "khhhHHhhhk",
        "khhhhhhhhk",
        "khsshhsshk",
        "kssssssssk",
        "kssessessk",
        "kbssssssbk",
        ".kssmmssk.",
        "..kkkkkk..",
    };

    private static string[] GetHead(bool blink = false, bool happy = false, bool cheer = false)
    {
        var rows = (string[])BaseHead.Clone();
        if (happy)
        {
            rows[5] = "kssksskssk";
            rows[6] = "kskskksksk";
        }
        else if (blink)
        {
            rows[6] = "kssssssssk";
        }
        if (cheer) rows[8] = ".ksMMMMsk.";
        return rows;
    }

    private static readonly string[] SleepyHead = new[]
    {
        "..kkkkkk..",
        ".khhhhhhk.",
        "khhhHHhhhk",
        "khhhhhhhhk",
        "khhhhhhhhk",
    };

    private static readonly string[] LidOpen = new[]
    {
        "kkkkkkkk",
        "kLLLLLlk",
        "kLLyyLlk",
        "kLLooLlk",
        "kLLLLLlk",
        "kkkkkkkk",
    };

    private static readonly string[] LidClosed = new[]
    {
        "kLLLLLLk",
        "kkkkkkkk",
    };

    private static readonly string[] Jar = new[]
    {
        ".kkkk.",
        ".knnk.",
        "g....g",
        "g....g",
        "g....g",
        "g....g",
        "g....g",
        "gggggg",
    };

    private static readonly string[] Phone = new[] { "kkk", "kfk", "kfk", "kkk" };
    private static readonly string[] Fish = new[] { ".ff.f", "fkfff", ".ff.f" };
    private static readonly string[] Zee = new[] { "www", "..w", ".w.", "www" };

    private static readonly string[][] CoinFrames = new[]
    {
        new[] { ".NNN.", "NYyyN", "NyyoN", "NyooN", ".NNN." },
        new[] { "..N..", ".NYN.", ".NyN.", ".NoN.", "..N.." },
        new[] { "..N..", "..y..", "..y..", "..o..", "..N.." },
        new[] { "..N..", ".NYN.", ".NyN.", ".NoN.", "..N.." },
    };

    public static PixelBitmap Render(DioramaInput input)
    {
        var bmp = new PixelBitmap(Size, Size);
        Room(bmp, input.Hour, input.T);
        JarDraw(bmp, input.JarLevel, input.Sparkle);
        Character(bmp, input);

        foreach (var z in input.Zzz)
        {
            bmp.Blit(Zee, (int)Math.Round(z.X), (int)Math.Round(z.Y), PalMap);
        }

        foreach (var c in input.Coins)
        {
            int frameIdx = (int)(c.Age * 14) % CoinFrames.Length;
            if (frameIdx < 0) frameIdx = 0;
            bmp.Blit(CoinFrames[frameIdx], (int)Math.Round(c.X) - 2, (int)Math.Round(c.Y) - 2, PalMap);
        }

        return bmp;
    }

    private static void Room(PixelBitmap bmp, double hour, double t)
    {
        bmp.Rect(0, 0, 24, 12, 0x3D3A5C); // 墙
        bmp.Rect(0, 12, 24, 1, 0x4A4565); // 护墙线
        bmp.Rect(0, 13, 24, 7, 0x34314F);
        Sky(bmp, hour, t);

        uint frame = 0x8F8AB3;
        bmp.Rect(1, 1, 8, 1, frame);
        bmp.Rect(1, 7, 8, 1, frame);
        bmp.Rect(1, 1, 1, 7, frame);
        bmp.Rect(8, 1, 1, 7, frame);
        bmp.Rect(0, 8, 10, 1, 0xA9A4C8); // 窗台
        bmp.Rect(0, 20, 24, 1, 0xD08D55); // 桌面
        bmp.Rect(0, 21, 24, 1, 0xB0703F);
        bmp.Rect(0, 22, 24, 2, 0x6B3F25);
    }

    private static void Sky(PixelBitmap bmp, double h, double t)
    {
        uint[] bands;
        bool night = h < 5.5 || h >= 19.5;
        if (h < 5.5) bands = new uint[] { 0x0E1030, 0x151A42, 0x1C2350 };
        else if (h < 7) bands = new uint[] { 0x4A5AA8, 0xE08A8A, 0xF6C07A };
        else if (h < 16) bands = new uint[] { 0x3D9BE0, 0x6CB8EC, 0xA8DCF5 };
        else if (h < 18) bands = new uint[] { 0x5A6AB8, 0xE0907A, 0xF6B26B };
        else if (h < 19.5) bands = new uint[] { 0x2A2660, 0x5A3A7A, 0xA0527A };
        else bands = new uint[] { 0x0E1030, 0x151A42, 0x1C2350 };

        bmp.Rect(2, 2, 6, 1, bands[0]);
        bmp.Rect(2, 3, 6, 2, bands[1]);
        bmp.Rect(2, 5, 6, 2, bands[2]);

        if (night)
        {
            var stars = new[] { (3, 2), (7, 3), (2, 5), (6, 6) };
            for (int i = 0; i < stars.Length; i++)
            {
                if (((int)(t * 1.2) + i) % 4 != 0)
                {
                    bmp.Set(stars[i].Item1, stars[i].Item2, 0xFFF6D5);
                }
            }
            bmp.Set(5, 3, 0xF4F0D0); // 月牙
            bmp.Set(5, 4, 0xF4F0D0);
            bmp.Set(6, 4, 0xF4F0D0);
        }
        else if (h >= 7 && h < 18)
        {
            int sx = 2 + (int)Math.Round((h - 7) / 11 * 4);
            bmp.Rect(Math.Min(6, sx), 3, 2, 2, 0xFFE27Au);

            int cx = 1 + (int)(t / 2.5) % 9; // 云从左飘到右
            var cloudDeltas = new[] { (0, 5), (1, 5), (2, 5), (1, 4) };
            foreach (var (dx, dy) in cloudDeltas)
            {
                int x = cx + dx;
                if (x >= 2 && x <= 7) bmp.Set(x, dy, 0xF4F8FF);
            }
        }
    }

    private static void JarDraw(PixelBitmap bmp, double level, bool sparkle)
    {
        bmp.Rect(2, 14, 4, 5, 0x2D3A5Cu); // 玻璃里面
        int rows = (int)Math.Round(Math.Clamp(level, 0, 1) * 5);
        for (int r = 0; r < rows; r++)
        {
            int y = 18 - r;
            for (int x = 2; x <= 5; x++)
            {
                bmp.Set(x, y, (x + y) % 2 == 0 ? 0xFFC83Du : 0xE08A1Eu);
            }
            if (r == rows - 1) bmp.Set(3, y, 0xFFF0B3u);
        }
        if (rows < 4) bmp.Set(2, 14, 0xE6F7FDu);
        if (rows < 3) bmp.Set(2, 15, 0xE6F7FDu);

        bmp.Blit(Jar, 1, 12, PalMap);

        if (sparkle)
        {
            var sparkPoints = new[] { (3, 10), (4, 10), (3, 9), (4, 11), (2, 10), (5, 10) };
            foreach (var (x, y) in sparkPoints)
            {
                bmp.Set(x, y, 0xFFF0B3u);
            }
        }
    }

    private static void ChairBack(PixelBitmap bmp)
    {
        uint k = PalMap['k'], c = PalMap['c'], hi = PalMap['C'];
        bmp.Rect(13, 9, 8, 1, k);
        bmp.Set(12, 10, k);
        bmp.Rect(13, 10, 8, 1, c);
        bmp.Set(21, 10, k);
        for (int y = 11; y <= 18; y++)
        {
            bmp.Set(11, y, k);
            bmp.Set(12, y, hi);
            bmp.Rect(13, y, 9, 1, c);
            bmp.Set(22, y, k);
        }
        bmp.Rect(11, 19, 12, 1, k);
    }

    private static uint Plaid(int x, int y)
    {
        bool vx = x % 3 == 0, hy = y % 3 == 0;
        if (vx && hy) return 0xE9806A;
        if (vx || hy) return 0x8A2C36;
        return 0xC8463F;
    }

    private static void Torso(PixelBitmap bmp)
    {
        bmp.Rect(13, 13, 8, 1, PalMap['k']);
        for (int y = 14; y <= 19; y++)
        {
            for (int x = 12; x <= 21; x++)
            {
                bmp.Set(x, y, Plaid(x, y));
            }
        }
        bmp.Set(12, 14, PalMap['k']);
        bmp.Set(21, 14, PalMap['k']);
    }

    private static void Arms(PixelBitmap bmp, int leftDown, int rightDown)
    {
        uint k = PalMap['k'];
        var armsData = new[] { (11, leftDown, 11), (21, rightDown, 22) };
        foreach (var (x0, down, outer) in armsData)
        {
            int top = 14 + down;
            bmp.Rect(x0, top - 1, 2, 1, k);
            for (int y = top; y <= 19; y++)
            {
                bmp.Set(outer, y, k);
                bmp.Set(outer == 11 ? 12 : 21, y, Plaid(x0, y));
            }
        }
    }

    private static void RaisedArms(PixelBitmap bmp)
    {
        uint k = PalMap['k'], s = PalMap['s'];
        bmp.Rect(10, 5, 2, 2, s);
        bmp.Rect(22, 5, 2, 2, s);
        for (int y = 7; y <= 14; y++)
        {
            bmp.Set(10, y, k);
            bmp.Set(11, y, Plaid(11, y));
            bmp.Set(22, y, Plaid(22, y));
            bmp.Set(23, y, k);
        }
    }

    private static void Character(PixelBitmap bmp, DioramaInput input)
    {
        double t = input.T;
        switch (input.Pose)
        {
            case Pose.Absent:
                ChairBack(bmp);
                bmp.Blit(LidClosed, 13, 18, PalMap);
                break;

            case Pose.Typing:
                ChairBack(bmp);
                Torso(bmp);
                int beat = (int)(t * 5) % 2;
                Arms(bmp, beat, 1 - beat);
                bool blink = (t % 3.4) < 0.15;
                int nod = (t % 2.6) < 0.3 ? 1 : 0;
                bmp.Blit(GetHead(blink: blink), 12, 3 + nod, PalMap);
                bmp.Blit(LidOpen, 13, 14, PalMap);
                break;

            case Pose.Fishing:
                ChairBack(bmp);
                Torso(bmp);
                Arms(bmp, 0, 0);
                bmp.Blit(GetHead(happy: true), 12, 3, PalMap);
                bmp.Blit(LidOpen, 13, 14, PalMap);
                bmp.Blit(Phone, 15, 11, PalMap);
                bmp.Set(14, 13, PalMap['s']);
                bmp.Set(18, 13, PalMap['s']);
                bmp.Blit(Fish, 18, (int)(t * 2) % 2, PalMap);
                break;

            case Pose.Cheering:
                ChairBack(bmp);
                Torso(bmp);
                RaisedArms(bmp);
                int hop = (int)(t * 4) % 2;
                bmp.Blit(GetHead(happy: true, cheer: true), 12, 3 - hop, PalMap);
                bmp.Blit(LidOpen, 13, 14, PalMap);
                break;

            case Pose.Sleeping:
                ChairBack(bmp);
                for (int y = 16; y <= 19; y++)
                {
                    for (int x = 10; x <= 23; x++)
                    {
                        bmp.Set(x, y, Plaid(x, y));
                    }
                }
                bmp.Rect(10, 15, 14, 1, PalMap['k']);
                bmp.Rect(10, 16, 1, 4, PalMap['k']);
                bmp.Rect(23, 16, 1, 4, PalMap['k']);
                int breathe = (t % 2.0) < 1.0 ? 0 : 1;
                bmp.Blit(SleepyHead, 12, 11 + breathe, PalMap);
                break;
        }
    }
}
