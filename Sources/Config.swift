import Foundation

struct AgentConfig: Codable, Equatable {
    var language: String
    var autoRetryEnabled: Bool
    var launchAtLogin: Bool
    var automaticUpdates: Bool
    var showQuotaInMenuBar: Bool

    init(
        language: String = "auto",
        autoRetryEnabled: Bool = true,
        launchAtLogin: Bool = true,
        automaticUpdates: Bool = true,
        showQuotaInMenuBar: Bool = true
    ) {
        self.language = language
        self.autoRetryEnabled = autoRetryEnabled
        self.launchAtLogin = launchAtLogin
        self.automaticUpdates = automaticUpdates
        self.showQuotaInMenuBar = showQuotaInMenuBar
    }

    private enum CodingKeys: String, CodingKey {
        case language
        case autoRetryEnabled
        case launchAtLogin
        case automaticUpdates
        case showQuotaInMenuBar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "auto"
        autoRetryEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoRetryEnabled) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        automaticUpdates = try container.decodeIfPresent(Bool.self, forKey: .automaticUpdates) ?? true
        showQuotaInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showQuotaInMenuBar) ?? true
    }
}

final class ConfigStore {
    let supportURL: URL
    let configURL: URL
    private let fileManager = FileManager.default

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        supportURL = home.appendingPathComponent("Library/Application Support/CodexHelper", isDirectory: true)
        configURL = supportURL.appendingPathComponent("config.json")
        try? fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true)
        migrateLegacyConfigurationIfNeeded()
        if !fileManager.fileExists(atPath: configURL.path) {
            save(AgentConfig())
        }
    }

    func load() -> AgentConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AgentConfig.self, from: data) else {
            return AgentConfig()
        }
        return config
    }

    func save(_ config: AgentConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    func isChinese() -> Bool {
        let language = load().language.lowercased()
        if language == "zh" || language == "zh-cn" { return true }
        if language == "en" { return false }
        return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    private func migrateLegacyConfigurationIfNeeded() {
        guard !fileManager.fileExists(atPath: configURL.path) else { return }
        let legacyURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexAutoRetry/config.json")
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }
        try? fileManager.copyItem(at: legacyURL, to: configURL)
    }
}
