# 上班激励器 · 像素悬浮窗（Windows 版）

桌面上的像素风悬浮窗。填好工资和上下班时间，实时将「今天已经赚了多少」一格一格地滚给你看。
本项目为 [pixel-work-motivator](https://github.com/blue-off-mind/pixel-work-motivator) 的原生 Windows (C# + WPF / .NET 8) 移植版本。

## 功能特性

- **机械里程表式像素滚轮金额**：实时滚动展示今日收入，低位飞快进位，暗色前导零，三位小数后以铜色区分。
- **24×24 像素小办公室**：
  - 窗外天色实时跟随系统时间变化（昼夜、太阳白云、月亮星辰）。
  - 打工人敲键盘、眨眼点头；午休时趴桌睡觉打呼（Zzz）；下班撒彩纸欢呼。
  - 金币沿二次贝塞尔曲线飞入存钱罐，罐内金币随工时进度蓄满。
- **单击拉出工资条**：
  - 从出纸口滑出锯齿撕边纸质工资条。
  - 展示本期/本月已赚、今日满勤、时薪、今日进度、发薪日倒计时、带薪摸鱼金额及购买力提示语句。
- **系统托盘金币**：
  - 16×16 原生像素金币托盘图标。
  - 悬浮提示实时收入或倒计时。
  - 右键菜单集成全部操作与明细。
- **带薪摸鱼计时**：独立累计摸鱼时间与收益。
- **锁定（鼠标穿透）**：支持快捷锁定为鼠标穿透窗口（`WS_EX_TRANSPARENT`），点击直达底层窗口。
- **三档大小与透明度调节**：小号、中号、大号，透明度自由滑动调节。
- **开机自启**：一键设置 Windows 用户自启动注册表项。
- **8-bit 金币音效**：内存动态合成方波音频，无外置音频文件依赖。
- **中英文界面**：简体中文与 English 自由切换。
- **总在最前且不抢焦点**：原生 `WS_EX_TOOLWINDOW` 与 `WS_EX_NOACTIVATE`，不抢占当前编码或游戏焦点。

---

## 快速使用

### 运行独立单文件可执行程序
直接运行发布目录下的单文件版本（已内嵌 .NET 8 运行时，无需安装任何依赖）：
```powershell
.\windows\publish\PixelWorkMotivator.exe
```

---

## 开发与构建

本项目基于 .NET 8 WPF 编写，纯原生实现，无第三方重量级依赖。

### 运行测试
验证计算核心 17 组用例（与 macOS 版逻辑完全对齐）：
```powershell
.\windows\build.ps1 test
```

### 编译 Debug 版本
```powershell
.\windows\build.ps1 build
```

### 编译并直接运行
```powershell
.\windows\build.ps1 run
```

### 发布独立单文件 Exe
生成独立无需安装 .NET 的单个 `PixelWorkMotivator.exe`：
```powershell
.\windows\build.ps1 publish
```
输出位于 `windows\publish\PixelWorkMotivator.exe`。

---

## 目录结构

```
windows/
  PixelWorkMotivator/
    Core/
      PayCore.cs           # 计算核心逻辑（日薪、计薪秒、倒计时、心愿单等）
      Localization.cs      # 中英双语支持
      Store.cs             # 配置与偏好管理（%APPDATA%\PixelWorkMotivator\settings.json）
      Sound.cs             # 8-bit 方波音频内存合成
    Graphics/
      Pal.cs               # 像素配色板
      Glyphs.cs            # 6×9 与 3×5 粗体像素数字字形
      PixelBitmap.cs       # 32位像素位图缓冲区与高速渲染引擎
      PixelFont.cs         # 缝合像素字体渲染（OFL-1.1）
      Diorama.cs           # 24×24 像素小办公室与动画
      Odometer.cs          # 机械滚轮里程表算法
      WidgetRenderer.cs    # 悬浮窗面板、进度条与工资条绘制器
    UI/
      WidgetWindow.xaml    # 悬浮窗原生 WPF 窗口（置顶、穿透、平滑拖拽）
      SettingsWindow.xaml  # 原生设置窗口（实时日薪折算预览、心愿单等）
      TrayManager.cs       # 系统托盘图标与上下文菜单
    Resources/
      Fonts/               # 像素字体文件
      app.ico              # 应用程序像素金币图标
    PixelWorkMotivator.csproj
  Tests/
    Program.cs             # 17 组测试用例验证
    Tests.csproj
  build.ps1                # 综合构建脚本
```
