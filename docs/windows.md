# Windows 版移植说明

macOS 版是原生 Swift/AppKit，没有网页界面。Windows 版也照这个思路写原生壳，推荐 **C# + WPF（.NET 8）**：透明置顶窗口、托盘图标、像素绘制、开机自启都是现成能力，打包成单个 exe 也方便。

## 能原样搬过去的

- **计算规则**：照 `macos/Sources/PayCore.swift` 和 [计算规则.md](计算规则.md) 写一份 `PayCore.cs`，再把 `macos/Tests/main.swift` 里的 17 组用例改成 xUnit，确保两边算出来一模一样。
- **像素数据**：`PixelKit.swift` 里的数字字形、`Diorama.swift` 里的人物、笔记本、存钱罐、金币帧，`WidgetView.swift` 里的布局常量，都是字符串和数字，直接复制。
- **调色板**：`Pal` 里的十六进制颜色。
- **字体**：`macos/Resources/Fonts/` 里的 OTF 和许可证。
- **设置格式**：同一份 JSON 字段，两边可以互相导入。

## 对照表

| macOS | Windows（WPF） |
|---|---|
| `NSPanel` 无边框、`.floating`、不抢焦点 | `Window`：`WindowStyle=None`、`AllowsTransparency=True`、`Background=Transparent`、`Topmost=True`、`ShowInTaskbar=False`；加 `WS_EX_NOACTIVATE`、`WS_EX_TOOLWINDOW` 扩展样式 |
| 锁定（鼠标穿透） | 扩展样式加 `WS_EX_TRANSPARENT` |
| CoreGraphics 画像素、最近邻放大 | `WriteableBitmap` 画 24×24 场景和数字条，`RenderOptions.BitmapScalingMode="NearestNeighbor"`；或者 `DrawingVisual` 填矩形 |
| 处理 Retina | 用每台显示器的 DPI（`VisualTreeHelper.GetDpi`）把像素对齐到整数物理像素 |
| `performDrag` 拖动 | `DragMove()`，按下后移动超过 3 像素才算拖动，否则当单击 |
| 右键菜单 | `ContextMenu` |
| `NSStatusItem` 菜单栏金额 | 托盘图标（`System.Windows.Forms.NotifyIcon` 或 H.NotifyIcon）。托盘放不下长文字，金额放在 Tooltip；也可以用 16×16 像素数字画进图标 |
| `UserDefaults` | `%APPDATA%\PixelWorkMotivator\settings.json` |
| `SMAppService` 开机自启 | 注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` |
| 方波现场合成 WAV + `NSSound` | 同样的 WAV 字节放进 `MemoryStream`，用 `SoundPlayer` 播放 |
| `Timer` 自适应 8 / 20 / 30fps | `DispatcherTimer` 或 `CompositionTarget.Rendering` 计数限帧 |
| 减少动态效果 | `SystemParameters.ClientAreaAnimation` |
| 原生设置窗口 | 普通 WPF 窗口；时间用 `TextBox` 加格式校验，或者 MahApps 的 TimePicker |
| `.dmg` | 单文件发布 `dotnet publish -r win-x64 -p:PublishSingleFile=true --self-contained`，需要安装包再用 Inno Setup |

## 建议步骤

1. `PayCore.cs` 加测试，先跑通 17 组用例。
2. 只画大数字：透明置顶窗口 + 滚轮数字，确认像素清晰、CPU 低。
3. 加小办公室、进度条、出纸口和工资条。
4. 托盘菜单、设置窗口、开机自启、音效。
5. 在 100%、125%、150% 三种缩放下检查像素对齐。125% 时 2pt 像素会落在 2.5 物理像素上，这一档建议整体按物理像素取整。

## 注意

- 这台 Mac 没有 Windows 环境，Windows 版需要在 Windows（Visual Studio 2022 或 `dotnet` CLI）上开发和测试。
- 像素字体 12px 在 125% 缩放下不是整数倍，标签文字会略糊。可以只对像素画做整数缩放，文字跟系统缩放走。
