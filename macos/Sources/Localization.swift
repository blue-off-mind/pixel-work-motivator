// 应用内语言。默认保留简体中文，英文由设置窗口显式选择。
import Foundation

enum AppLanguage: String, Codable, CaseIterable {
    case zhHans = "zh-Hans"
    case en
}

enum L10n {
    static func t(_ language: AppLanguage, _ zh: String, _ en: String) -> String {
        language == .en ? en : zh
    }
}
