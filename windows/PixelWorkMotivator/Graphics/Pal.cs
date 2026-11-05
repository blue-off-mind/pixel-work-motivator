using System;
using System.Windows.Media;

namespace PixelWorkMotivator.Graphics;

public static class Pal
{
    public const uint Ink = 0x14121C;
    public const uint Panel = 0x2A2639;
    public const uint PanelHi = 0x3D3756;
    public const uint PanelLo = 0x1C1927;
    public const uint Text = 0xF1ECF7;
    public const uint Muted = 0xA39CBA;
    public const uint Faint = 0x6F6889;
    public const uint Gold = 0xFFC83D;
    public const uint GoldHi = 0xFFF0B3;
    public const uint GoldLo = 0xE08A1E;
    public const uint Red = 0xE2463F;
    public const uint Green = 0x7BD66A;
    public const uint GreenHi = 0xC4F5B4;
    public const uint GreenLo = 0x3F9A45;
    public const uint Sky = 0x63B6EC;
    public const uint Lilac = 0xB896E6;
    public const uint Cyan = 0x73EFF7;
    public const uint Paper = 0xF3EAD3;
    public const uint PaperInk = 0x3A2F2A;
    public const uint PaperLine = 0xC4B38C;
    public const uint PaperFaint = 0x8A7B62;

    public static uint Status(Core.PaySnapshot.StatusEnum s, bool fishing = false)
    {
        if (fishing && s == Core.PaySnapshot.StatusEnum.Working) return Cyan;
        return s switch
        {
            Core.PaySnapshot.StatusEnum.Working => Green,
            Core.PaySnapshot.StatusEnum.Lunch => Sky,
            Core.PaySnapshot.StatusEnum.After => Gold,
            Core.PaySnapshot.StatusEnum.Off => Lilac,
            Core.PaySnapshot.StatusEnum.Setup => Red,
            _ => Muted
        };
    }

    public static System.Windows.Media.Color ToColor(uint hex, double alpha = 1.0)
    {
        byte r = (byte)((hex >> 16) & 0xFF);
        byte g = (byte)((hex >> 8) & 0xFF);
        byte b = (byte)(hex & 0xFF);
        byte a = (byte)Math.Clamp((int)(alpha * 255), 0, 255);
        return System.Windows.Media.Color.FromArgb(a, r, g, b);
    }

    public static SolidColorBrush ToBrush(uint hex, double alpha = 1.0)
    {
        var brush = new SolidColorBrush(ToColor(hex, alpha));
        brush.Freeze();
        return brush;
    }
}
