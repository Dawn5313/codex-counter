import Foundation

enum CodexSyncError: LocalizedError {
    case missingActiveProvider
    case missingActiveAccount
    case missingOAuthTokens
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .missingActiveProvider: return "未找到当前激活的 provider"
        case .missingActiveAccount: return "未找到当前激活的账号"
        case .missingOAuthTokens: return "当前 OAuth 账号缺少必要 token"
        case .missingAPIKey: return "当前 API Key 账号缺少密钥"
        }
    }
}

struct CodexSyncService {
    func synchronize(config: CodexBarConfig) throws {
        guard let provider = config.activeProvider() else { throw CodexSyncError.missingActiveProvider }
        guard let account = config.activeAccount() else { throw CodexSyncError.missingActiveAccount }

        try CodexPaths.ensureDirectories()
        try CodexPaths.backupFileIfPresent(from: CodexPaths.configTomlURL, to: CodexPaths.configBackupURL)
        try CodexPaths.backupFileIfPresent(from: CodexPaths.authURL, to: CodexPaths.authBackupURL)

        let authData = try self.renderAuthJSON(provider: provider, account: account)
        try CodexPaths.writeSecureFile(authData, to: CodexPaths.authURL)

        let renderedToml = self.renderConfigTOML(
            existingText: (try? String(contentsOf: CodexPaths.configTomlURL, encoding: .utf8)) ?? "",
            global: config.global,
            provider: provider
        )
        guard let tomlData = renderedToml.data(using: .utf8) else { return }
        try CodexPaths.writeSecureFile(tomlData, to: CodexPaths.configTomlURL)
    }

    private func renderAuthJSON(provider: CodexBarProvider, account: CodexBarProviderAccount) throws -> Data {
        let object: [String: Any]
        switch provider.kind {
        case .openAIOAuth:
            guard let accessToken = account.accessToken,
                  let refreshToken = account.refreshToken,
                  let idToken = account.idToken,
                  let accountId = account.openAIAccountId else {
                throw CodexSyncError.missingOAuthTokens
            }

            object = [
                "auth_mode": "chatgpt",
                "OPENAI_API_KEY": NSNull(),
                "last_refresh": ISO8601DateFormatter().string(from: Date()),
                "tokens": [
                    "access_token": accessToken,
                    "refresh_token": refreshToken,
                    "id_token": idToken,
                    "account_id": accountId,
                ],
            ]

        case .openAICompatible:
            guard let apiKey = account.apiKey, apiKey.isEmpty == false else {
                throw CodexSyncError.missingAPIKey
            }
            object = [
                "OPENAI_API_KEY": apiKey,
            ]
        }

        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private func renderConfigTOML(
        existingText: String,
        global: CodexBarGlobalSettings,
        provider: CodexBarProvider
    ) -> String {
        var text = existingText

        text = self.upsertSetting(text, key: "model_provider", value: "\"OpenAI\"")
        text = self.upsertSetting(text, key: "model", value: self.quote(global.defaultModel))
        text = self.upsertSetting(text, key: "review_model", value: self.quote(global.reviewModel))
        text = self.upsertSetting(text, key: "model_reasoning_effort", value: self.quote(global.reasoningEffort))

        text = self.removeSetting(text, key: "service_tier")
        text = self.removeSetting(text, key: "oss_provider")
        text = self.removeSetting(text, key: "model_catalog_json")
        text = self.removeSetting(text, key: "preferred_auth_method")
        text = self.removeBlock(text, key: "OpenAI")

        if provider.kind == .openAICompatible, let baseURL = provider.baseURL {
            let block = [
                "[model_providers.OpenAI]",
                "name = \"OpenAI\"",
                "base_url = \(self.quote(baseURL))",
                "wire_api = \"responses\"",
                "requires_openai_auth = true",
            ].joined(separator: "\n")
            text = self.appendManagedBlock(text, block: block)
        }

        return text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func quote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func upsertSetting(_ text: String, key: String, value: String) -> String {
        let line = "\(key) = \(value)"
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^#(key)\s*=.*$"#.replacingOccurrences(of: "#(key)", with: NSRegularExpression.escapedPattern(for: key))) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        if regex.firstMatch(in: text, range: range) != nil {
            return regex.stringByReplacingMatches(in: text, range: range, withTemplate: line)
        }
        return line + "\n" + text
    }

    private func removeSetting(_ text: String, key: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^#(key)\s*=.*$\n?"#.replacingOccurrences(of: "#(key)", with: NSRegularExpression.escapedPattern(for: key))) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private func removeBlock(_ text: String, key: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?ms)^\[model_providers\.#(key)\]\n.*?(?=^\[|\Z)"#.replacingOccurrences(of: "#(key)", with: NSRegularExpression.escapedPattern(for: key))) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private func appendManagedBlock(_ text: String, block: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return block + "\n"
        }
        return trimmed + "\n\n" + block + "\n"
    }
}

