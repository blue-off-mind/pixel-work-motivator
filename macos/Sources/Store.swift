// 设置和悬浮窗偏好的持久化（UserDefaults）。截图/调试模式下只放内存，不碰用户数据。
import Foundation

enum WidgetSize: String, Codable, CaseIterable {
    case small, medium, large
    var title: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }
}

/// 带薪摸鱼：只在计薪时段里累计。
struct FishState: Codable, Equatable {
    var day = "" // yyyy-MM-dd，跨天清零
    var total: Double = 0 // 今天已摸的计薪秒
    var since: Double? // 正在摸：开始时"今天已干的计薪秒"
}

struct WidgetPrefs: Codable, Equatable {
    var topLeft: CGPoint? // 屏幕坐标里悬浮窗左上角
    var expanded = false // 工资条拉出来了
    var locked = false // 鼠标穿透
    var visible = true
    var size: WidgetSize = .medium
    var opacity: Double = 1
    var fish = FishState()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WidgetPrefs()
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        topLeft = get(.topLeft, d.topLeft)
        expanded = get(.expanded, d.expanded)
        locked = get(.locked, d.locked)
        visible = get(.visible, d.visible)
        size = get(.size, d.size)
        opacity = min(1, max(0.3, get(.opacity, d.opacity)))
        fish = get(.fish, d.fish)
    }
}

@MainActor
final class Store {
    private static let settingsKey = "settings.v1"
    private static let prefsKey = "widget.v1"

    private let defaults: UserDefaults?
    /// nil 表示还没配置过（首次启动）。
    private(set) var settings: PaySettings?
    var prefs: WidgetPrefs {
        didSet { if prefs != oldValue { write(prefs, Store.prefsKey) } }
    }

    init(ephemeral: Bool, settingsJSON: String? = nil) {
        defaults = ephemeral ? nil : .standard
        if let json = settingsJSON {
            settings = try? JSONDecoder().decode(PaySettings.self, from: Data(json.utf8))
        } else if let data = defaults?.data(forKey: Store.settingsKey) {
            settings = try? JSONDecoder().decode(PaySettings.self, from: data)
        }
        if let data = defaults?.data(forKey: Store.prefsKey),
           let p = try? JSONDecoder().decode(WidgetPrefs.self, from: data) {
            prefs = p
        } else {
            prefs = WidgetPrefs()
        }
    }

    func save(settings new: PaySettings) {
        settings = new
        write(new, Store.settingsKey)
    }

    private func write<T: Encodable>(_ value: T, _ key: String) {
        guard let defaults, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

/// 可快进的时钟：调试时用 --now / --speed 模拟一天。
struct Clock {
    var base: Date?
    var speed: Double = 1
    let started = Date()

    func now() -> Date {
        if base == nil && speed == 1 { return Date() }
        return (base ?? started).addingTimeInterval(Date().timeIntervalSince(started) * speed)
    }
}
