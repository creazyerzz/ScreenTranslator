import Foundation

@MainActor
final class AppSettings {
    static let shared = AppSettings()
    static let defaults = UserDefaults(suiteName: "local.screentranslator.settings") ?? .standard
    /// 仅作为下拉示例；实际列表优先从所配置接口的 /models 拉取，也支持手动输入任意模型名。
    static let fallbackModels = [
        "gpt-5.4-mini",
        "gpt-5.4",
        "claude-sonnet-5",
        "claude-opus-4-8",
        "gemini-3.5-flash",
        "gemini-3.1-pro-preview"
    ]
    static let defaultModel = "gpt-5.4-mini"
    static let commonTargetLanguages = [
        "中文", "英文", "日文", "韩文",
        "法文", "德文", "西班牙文", "俄文", "葡萄牙文"
    ]

    enum Keys {
        static let baseURL = "baseURL"
        static let model = "model"
        static let targetLanguage = "targetLanguage"
        static let sourceLanguage = "sourceLanguage"
        static let apiKey = "apiKey"
        static let autoCopyTranslation = "autoCopyTranslation"
    }

    var baseURL: String {
        get { Self.defaults.string(forKey: Keys.baseURL) ?? "" }
        set { Self.defaults.set(newValue, forKey: Keys.baseURL) }
    }

    var model: String {
        get {
            Self.normalizedModel(Self.defaults.string(forKey: Keys.model)) ?? Self.defaultModel
        }
        set {
            Self.defaults.set(Self.normalizedModel(newValue) ?? Self.defaultModel, forKey: Keys.model)
        }
    }

    var targetLanguage: String {
        get { Self.defaults.string(forKey: Keys.targetLanguage) ?? "中文" }
        set { Self.defaults.set(newValue, forKey: Keys.targetLanguage) }
    }

    var sourceLanguage: String {
        get { Self.defaults.string(forKey: Keys.sourceLanguage) ?? "auto" }
        set { Self.defaults.set(newValue, forKey: Keys.sourceLanguage) }
    }

    var apiKey: String {
        get { Self.defaults.string(forKey: Keys.apiKey) ?? "" }
        set { Self.defaults.set(newValue, forKey: Keys.apiKey) }
    }

    var autoCopyTranslation: Bool {
        get { Self.defaults.bool(forKey: Keys.autoCopyTranslation) }
        set { Self.defaults.set(newValue, forKey: Keys.autoCopyTranslation) }
    }

    static func normalizedModel(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

}
