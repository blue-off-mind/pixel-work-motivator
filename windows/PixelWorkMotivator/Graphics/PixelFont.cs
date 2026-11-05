using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;

namespace PixelWorkMotivator.Graphics;

public static class PixelFont
{
    private static PrivateFontCollection? _fontCollection;
    private static System.Drawing.FontFamily? _family;
    private static Font? _font12;

    public static bool IsLoaded => _family != null;

    static PixelFont()
    {
        Init();
    }

    private static void Init()
    {
        try
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string fontPath = Path.Combine(baseDir, "Resources", "Fonts", "fusion-pixel-12px-monospaced-zh_hans.otf");

            if (!File.Exists(fontPath))
            {
                // Fallback check in parent directories
                string alt = Path.Combine(baseDir, "..", "..", "..", "Resources", "Fonts", "fusion-pixel-12px-monospaced-zh_hans.otf");
                if (File.Exists(alt)) fontPath = Path.GetFullPath(alt);
            }

            if (File.Exists(fontPath))
            {
                _fontCollection = new PrivateFontCollection();
                _fontCollection.AddFontFile(fontPath);
                if (_fontCollection.Families.Length > 0)
                {
                    _family = _fontCollection.Families[0];
                    _font12 = new Font(_family, 12, FontStyle.Regular, GraphicsUnit.Pixel);
                    return;
                }
            }
        }
        catch
        {
            // Ignore and fallback
        }

        _family = System.Drawing.FontFamily.GenericMonospace;
        _font12 = new Font(_family, 12, FontStyle.Regular, GraphicsUnit.Pixel);
    }

    public static Font GetFont(float size = 12)
    {
        if (Math.Abs(size - 12) < 0.1f && _font12 != null) return _font12;
        return new Font(_family ?? System.Drawing.FontFamily.GenericMonospace, size, FontStyle.Regular, GraphicsUnit.Pixel);
    }

    private static readonly Bitmap _measureBmp = new(10, 10, PixelFormat.Format32bppArgb);
    private static readonly System.Drawing.Graphics _measureGraphics = System.Drawing.Graphics.FromImage(_measureBmp);
    private static readonly StringFormat _measureFormat = new(StringFormat.GenericTypographic)
    {
        FormatFlags = StringFormatFlags.MeasureTrailingSpaces
    };

    public static int MeasureWidth(string s, float size = 12)
    {
        if (string.IsNullOrEmpty(s)) return 0;
        var font = GetFont(size);
        bool shouldDispose = !ReferenceEquals(font, _font12);
        try
        {
            lock (_measureGraphics)
            {
                _measureGraphics.TextRenderingHint = TextRenderingHint.SingleBitPerPixel;
                var sz = _measureGraphics.MeasureString(s, font, PointF.Empty, _measureFormat);
                return (int)Math.Ceiling(sz.Width);
            }
        }
        finally
        {
            if (shouldDispose) font.Dispose();
        }
    }

    public static void Draw(PixelBitmap bmp, string s, int x, int y, uint rgb, float size = 12)
    {
        if (string.IsNullOrEmpty(s)) return;
        var font = GetFont(size);
        bool shouldDispose = !ReferenceEquals(font, _font12);

        int textW = Math.Max(1, MeasureWidth(s, size) + 4);
        int textH = Math.Max(1, (int)(size * 1.5f));

        try
        {
            using var memBmp = new Bitmap(textW, textH, PixelFormat.Format32bppArgb);
            using (var g = System.Drawing.Graphics.FromImage(memBmp))
            {
                g.Clear(System.Drawing.Color.Transparent);
                g.TextRenderingHint = TextRenderingHint.SingleBitPerPixel;
                g.InterpolationMode = InterpolationMode.NearestNeighbor;
                g.PixelOffsetMode = PixelOffsetMode.None;

                var drawColor = System.Drawing.Color.FromArgb(
                    (int)((rgb >> 16) & 0xFF),
                    (int)((rgb >> 8) & 0xFF),
                    (int)(rgb & 0xFF)
                );
                using var brush = new SolidBrush(drawColor);
                using var fmt = new StringFormat(StringFormat.GenericTypographic)
                {
                    FormatFlags = StringFormatFlags.MeasureTrailingSpaces
                };
                g.DrawString(s, font, brush, 0, 0, fmt);
            }

            // Blit memBmp into bmp
            var data = memBmp.LockBits(new Rectangle(0, 0, textW, textH), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                unsafe
                {
                    uint* ptr = (uint*)data.Scan0;
                    int stride = data.Stride / 4;
                    for (int dy = 0; dy < textH; dy++)
                    {
                        int dstY = y + dy;
                        if (dstY < 0 || dstY >= bmp.Height) continue;
                        for (int dx = 0; dx < textW; dx++)
                        {
                            int dstX = x + dx;
                            if (dstX < 0 || dstX >= bmp.Width) continue;

                            uint val = ptr[dy * stride + dx];
                            byte a = (byte)(val >> 24);
                            if (a > 64)
                            {
                                bmp.Set(dstX, dstY, rgb);
                            }
                        }
                    }
                }
            }
            finally
            {
                memBmp.UnlockBits(data);
            }
        }
        finally
        {
            if (shouldDispose) font.Dispose();
        }
    }

    public static void DrawOutlined(PixelBitmap bmp, string s, int x, int y, uint rgb, uint outline = Pal.Ink)
    {
        var deltas = new[] { (-1, 0), (1, 0), (0, -1), (0, 1), (1, 1) };
        foreach (var (dx, dy) in deltas)
        {
            Draw(bmp, s, x + dx, y + dy, outline);
        }
        Draw(bmp, s, x, y, rgb);
    }

    public static void DrawWrapped(PixelBitmap bmp, string s, int x, int y, int width, int maxLines, uint rgb, float size = 12, int lineHeight = 16)
    {
        if (string.IsNullOrEmpty(s)) return;
        var font = GetFont(size);
        bool shouldDispose = !ReferenceEquals(font, _font12);

        int textH = Math.Max(1, maxLines * lineHeight + 4);
        try
        {
            using var memBmp = new Bitmap(width, textH, PixelFormat.Format32bppArgb);
            using (var g = System.Drawing.Graphics.FromImage(memBmp))
            {
                g.Clear(System.Drawing.Color.Transparent);
                g.TextRenderingHint = TextRenderingHint.SingleBitPerPixel;

                var drawColor = System.Drawing.Color.FromArgb(
                    (int)((rgb >> 16) & 0xFF),
                    (int)((rgb >> 8) & 0xFF),
                    (int)(rgb & 0xFF)
                );
                using var brush = new SolidBrush(drawColor);

                var sf = new StringFormat(StringFormat.GenericTypographic)
                {
                    FormatFlags = StringFormatFlags.LineLimit,
                    Trimming = StringTrimming.EllipsisWord
                };

                var rect = new RectangleF(0, 0, width, textH);
                g.DrawString(s, font, brush, rect, sf);
            }

            var data = memBmp.LockBits(new Rectangle(0, 0, width, textH), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                unsafe
                {
                    uint* ptr = (uint*)data.Scan0;
                    int stride = data.Stride / 4;
                    for (int dy = 0; dy < textH; dy++)
                    {
                        int dstY = y + dy;
                        if (dstY < 0 || dstY >= bmp.Height) continue;
                        for (int dx = 0; dx < width; dx++)
                        {
                            int dstX = x + dx;
                            if (dstX < 0 || dstX >= bmp.Width) continue;

                            uint val = ptr[dy * stride + dx];
                            byte a = (byte)(val >> 24);
                            if (a > 64)
                            {
                                bmp.Set(dstX, dstY, rgb);
                            }
                        }
                    }
                }
            }
            finally
            {
                memBmp.UnlockBits(data);
            }
        }
        finally
        {
            if (shouldDispose) font.Dispose();
        }
    }
}
