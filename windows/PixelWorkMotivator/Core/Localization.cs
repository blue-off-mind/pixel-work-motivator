using System;

namespace PixelWorkMotivator.Core;

public enum AppLanguage
{
    ZhHans,
    En
}

public static class L10n
{
    public static string T(AppLanguage language, string zh, string en)
    {
        return language == AppLanguage.En ? en : zh;
    }
}
