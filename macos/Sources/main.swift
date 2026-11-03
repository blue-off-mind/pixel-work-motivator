import AppKit

// 顶层代码本来就跑在主线程，这里告诉编译器一声
MainActor.assumeIsolated {
    let options = LaunchOptions.parse(CommandLine.arguments)
    let app = NSApplication.shared
    let delegate = AppDelegate(options: options)
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // 菜单栏 + 悬浮窗程序，平时不占程序坞
    app.run()
}
