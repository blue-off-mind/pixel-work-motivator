using System;
using System.IO;
using System.Media;
using System.Text;

namespace PixelWorkMotivator.Core;

public static class Sound
{
    private static SoundPlayer? _coinPlayer;
    private static SoundPlayer? _fanfarePlayer;

    static Sound()
    {
        try
        {
            var coinData = MakeWav(new[] { (987.77, 0.07), (1318.51, 0.3) });
            _coinPlayer = new SoundPlayer(new MemoryStream(coinData));
            _coinPlayer.Load();

            var fanfareData = MakeWav(new[]
            {
                (523.25, 0.09), (659.25, 0.09), (783.99, 0.09), (1046.5, 0.18), (783.99, 0.09), (1046.5, 0.45)
            });
            _fanfarePlayer = new SoundPlayer(new MemoryStream(fanfareData));
            _fanfarePlayer.Load();
        }
        catch
        {
            // Ignore sound setup errors if audio device is unavailable
        }
    }

    private static byte[] MakeWav((double freq, double dur)[] notes, double volume = 0.16)
    {
        int rate = 22050;
        using var ms = new MemoryStream();
        using var bw = new BinaryWriter(ms);

        // Pre-count samples
        int totalSamples = 0;
        foreach (var note in notes)
        {
            totalSamples += (int)(rate * note.dur);
        }

        // RIFF header
        bw.Write(Encoding.ASCII.GetBytes("RIFF"));
        bw.Write(36 + totalSamples * 2);
        bw.Write(Encoding.ASCII.GetBytes("WAVE"));

        // fmt chunk
        bw.Write(Encoding.ASCII.GetBytes("fmt "));
        bw.Write(16); // subchunk1size (16 for PCM)
        bw.Write((short)1); // audio format (1 = PCM)
        bw.Write((short)1); // num channels (1 = mono)
        bw.Write(rate); // sample rate
        bw.Write(rate * 2); // byte rate
        bw.Write((short)2); // block align
        bw.Write((short)16); // bits per sample

        // data chunk
        bw.Write(Encoding.ASCII.GetBytes("data"));
        bw.Write(totalSamples * 2);

        foreach (var note in notes)
        {
            int n = (int)(rate * note.dur);
            for (int i = 0; i < n; i++)
            {
                double t = (double)i / rate;
                double env = 1.0 - (double)i / n;
                double square = Math.Sin(2.0 * Math.PI * note.freq * t) >= 0 ? 1.0 : -1.0;
                short sample = (short)(square * env * volume * short.MaxValue);
                bw.Write(sample);
            }
        }

        bw.Flush();
        return ms.ToArray();
    }

    public static void Coin()
    {
        try
        {
            _coinPlayer?.Play();
        }
        catch { }
    }

    public static void Fanfare()
    {
        try
        {
            _fanfarePlayer?.Play();
        }
        catch { }
    }
}
