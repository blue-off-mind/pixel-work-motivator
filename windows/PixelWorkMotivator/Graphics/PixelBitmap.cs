using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace PixelWorkMotivator.Graphics;

public class PixelBitmap
{
    public int Width { get; }
    public int Height { get; }
    public uint[] Pixels { get; } // 0xAARRGGBB (Bgra32 format as uint on little-endian: B in bits 0..7, G in 8..15, R in 16..23, A in 24..31)

    public PixelBitmap(int width, int height)
    {
        Width = Math.Max(1, width);
        Height = Math.Max(1, height);
        Pixels = new uint[Width * Height];
    }

    public static uint MakeBgra(uint rgb, byte alpha = 255)
    {
        // rgb: 0xRRGGBB
        uint r = (rgb >> 16) & 0xFF;
        uint g = (rgb >> 8) & 0xFF;
        uint b = rgb & 0xFF;
        // On Little Endian: uint memory representation is [B, G, R, A]
        return (uint)b | ((uint)g << 8) | ((uint)r << 16) | ((uint)alpha << 24);
    }

    public void Clear()
    {
        Array.Clear(Pixels, 0, Pixels.Length);
    }

    public void Set(int x, int y, uint rgb, byte alpha = 255)
    {
        if (x < 0 || y < 0 || x >= Width || y >= Height) return;
        int idx = y * Width + x;
        if (alpha == 255)
        {
            Pixels[idx] = MakeBgra(rgb, 255);
        }
        else if (alpha > 0)
        {
            Blend(idx, rgb, alpha);
        }
    }

    private void Blend(int idx, uint rgb, byte srcA)
    {
        uint dst = Pixels[idx];
        byte dstB = (byte)(dst & 0xFF);
        byte dstG = (byte)((dst >> 8) & 0xFF);
        byte dstR = (byte)((dst >> 16) & 0xFF);
        byte dstA = (byte)((dst >> 24) & 0xFF);

        byte srcR = (byte)((rgb >> 16) & 0xFF);
        byte srcG = (byte)((rgb >> 8) & 0xFF);
        byte srcB = (byte)(rgb & 0xFF);

        float aNorm = srcA / 255f;
        float dstANorm = dstA / 255f;
        float outA = aNorm + dstANorm * (1f - aNorm);

        if (outA <= 0.0001f) return;

        byte r = (byte)Math.Clamp((srcR * aNorm + dstR * dstANorm * (1f - aNorm)) / outA, 0, 255);
        byte g = (byte)Math.Clamp((srcG * aNorm + dstG * dstANorm * (1f - aNorm)) / outA, 0, 255);
        byte b = (byte)Math.Clamp((srcB * aNorm + dstB * dstANorm * (1f - aNorm)) / outA, 0, 255);
        byte a = (byte)Math.Clamp(outA * 255f, 0, 255);

        Pixels[idx] = (uint)b | ((uint)g << 8) | ((uint)r << 16) | ((uint)a << 24);
    }

    public void Rect(int x, int y, int w, int h, uint rgb, byte alpha = 255)
    {
        int x0 = Math.Max(0, x);
        int y0 = Math.Max(0, y);
        int x1 = Math.Min(Width, x + w);
        int y1 = Math.Min(Height, y + h);

        uint color = MakeBgra(rgb, alpha);
        if (alpha == 255)
        {
            for (int cy = y0; cy < y1; cy++)
            {
                int row = cy * Width;
                for (int cx = x0; cx < x1; cx++)
                {
                    Pixels[row + cx] = color;
                }
            }
        }
        else if (alpha > 0)
        {
            for (int cy = y0; cy < y1; cy++)
            {
                int row = cy * Width;
                for (int cx = x0; cx < x1; cx++)
                {
                    Blend(row + cx, rgb, alpha);
                }
            }
        }
    }

    public void Blit(IReadOnlyList<string> art, int x, int y, IReadOnlyDictionary<char, uint> palette)
    {
        for (int r = 0; r < art.Count; r++)
        {
            string row = art[r];
            for (int c = 0; c < row.Length; c++)
            {
                char ch = row[c];
                if (ch != '.' && ch != ' ')
                {
                    if (palette.TryGetValue(ch, out uint hex))
                    {
                        Set(x + c, y + r, hex);
                    }
                }
            }
        }
    }

    public void Blit(PixelBitmap src, int dstX, int dstY)
    {
        for (int y = 0; y < src.Height; y++)
        {
            int sy = dstY + y;
            if (sy < 0 || sy >= Height) continue;
            for (int x = 0; x < src.Width; x++)
            {
                int sx = dstX + x;
                if (sx < 0 || sx >= Width) continue;
                uint p = src.Pixels[y * src.Width + x];
                byte a = (byte)(p >> 24);
                if (a == 255)
                {
                    Pixels[sy * Width + sx] = p;
                }
                else if (a > 0)
                {
                    uint rgb = ((p >> 16) & 0xFF) << 16 | ((p >> 8) & 0xFF) << 8 | (p & 0xFF);
                    Blend(sy * Width + sx, rgb, a);
                }
            }
        }
    }

    /// <summary>
    /// Scaled blit using nearest-neighbor
    /// </summary>
    public void BlitScaled(PixelBitmap src, int dstX, int dstY, int scale)
    {
        if (scale <= 1)
        {
            Blit(src, dstX, dstY);
            return;
        }

        for (int sy = 0; sy < src.Height; sy++)
        {
            for (int sx = 0; sx < src.Width; sx++)
            {
                uint p = src.Pixels[sy * src.Width + sx];
                byte a = (byte)(p >> 24);
                if (a == 0) continue;

                uint rgb = ((p >> 16) & 0xFF) << 16 | ((p >> 8) & 0xFF) << 8 | (p & 0xFF);
                Rect(dstX + sx * scale, dstY + sy * scale, scale, scale, rgb, a);
            }
        }
    }

    /// <summary>
    /// 四边粗 t、四角缺口的像素边框
    /// </summary>
    public void PixelFrame(int x, int y, int w, int h, int t, uint hex, byte alpha = 255)
    {
        Rect(x + t, y, w - 2 * t, t, hex, alpha);
        Rect(x + t, y + h - t, w - 2 * t, t, hex, alpha);
        Rect(x, y + t, t, h - 2 * t, hex, alpha);
        Rect(x + w - t, y + t, t, h - 2 * t, hex, alpha);
    }

    /// <summary>
    /// 四角各缺一格的实心块
    /// </summary>
    public void PixelBlock(int x, int y, int w, int h, int t, uint hex, byte alpha = 255)
    {
        Rect(x + t, y, w - 2 * t, h, hex, alpha);
        Rect(x, y + t, t, h - 2 * t, hex, alpha);
        Rect(x + w - t, y + t, t, h - 2 * t, hex, alpha);
    }

    public BitmapSource ToBitmapSource()
    {
        int stride = Width * 4;
        var bmp = BitmapSource.Create(
            Width, Height,
            96, 96,
            PixelFormats.Bgra32,
            null,
            Pixels,
            stride
        );
        bmp.Freeze();
        return bmp;
    }

    public void UpdateWriteableBitmap(WriteableBitmap wbm)
    {
        wbm.WritePixels(new Int32Rect(0, 0, Width, Height), Pixels, Width * 4, 0);
    }
}
