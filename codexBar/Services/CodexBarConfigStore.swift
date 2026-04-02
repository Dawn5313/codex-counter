import Foundation

struct LegacyCodexTomlSnapshot {
    var model: String?
    var reviewModel: String?
    var reasoningEffort: String?
    var openAIBaseURL: String?
}

final class CodexBarConfigStore {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let presetProviders: [(id: String, label: String, baseURL: String, envKey: String)] = [
        ("funai", "FunAI", "https://api.funai.vip", "OPENAI_API_KEY"),
        ("s", "S", "https://api.0vo.dev/v1", "S_OAI_KEY"),
        ("htj", "HTJ", "https://rhino.tjhtj.com", "HTJ_OAI_KEY"),
    ]

    func loadOrMigrate() throws -> CodexBarConfig {
        try CodexPaths.ensureDirectories()
        if FileManager.default.fileExists(atPath: CodexPaths.barConfigURL.path) {
            do {
                return try self.load()
            } catch {
                try self.backupForeignConfig()
            }
        }

        let config = try self.migrateFromLegacy()
        try self.save(config)
        return config
    }

    func load() throws -> CodexBarConfig {
        let data = try Data(contentsOf: CodexPaths.barConfigURL)
        return try self.decoder.decode(CodexBarConfig.self, from: data)
    }

    func save(_ config: CodexBarConfig) throws {
        let data = try self.encoder.encode(config)
        try CodexPaths.writeSecureFile(data, to: CodexPaths.barConfigURL)
    }

    private func migrateFromLegacy() throws -> CodexBarConfig {
        let toml = self.readLegacyToml()
        let auth = self.readAuthJSON()
        let envSecrets = self.readProviderSecrets()

        var providers: [CodexBarProvider] = []

        if let oauthProvider = self.makeOAuthProvider(auth: auth) {
            providers.append(oauthProvider)
        }

        for preset in self.presetProviders {
            guard let apiKey = envSecrets[preset.envKey], !apiKey.isEmpty else { continue }
            let account = CodexBarProviderAccount(
                kind: .apiKey,
                label: "Default",
                apiKey: apiKey,
                addedAt: Date()
            )
            providers.append(
                CodexBarProvider(
                    id: preset.id,
                    kind: .openAICompatible,
                    label: preset.label,
                    enabled: true,
                    baseURL: preset.baseURL,
                    activeAccountId: account.id,
                    accounts: [account]
                )
            )
        }

        if let authAPIKey = auth["OPENAI_API_KEY"] as? String,
           !authAPIKey.isEmpty,
           let imported = self.makeImportedProviderIfNeeded(
               baseURL: toml.openAIBaseURL,
               apiKey: authAPIKey,
               existingProviders: providers
           ) {
            providers.append(imported)
        }

        let global = CodexBarGlobalSettings(
            defaultModel: toml.model ?? "gpt-5.4",
            reviewModel: toml.reviewModel ?? toml.model ?? "gpt-5.4",
            reasoningEffort: toml.reasoningEffort ?? "xhigh"
        )

        let active = self.resolveActiveSelection(
            toml: toml,
            auth: auth,
            providers: providers
        )

        return CodexBarConfig(
            version: 1,
            global: global,
            active: active,
            providers: providers
        )
    }

    private func makeOAuthProvider(auth: [String: Any]) -> CodexBarProvider? {
        var importedAccounts: [CodexBarProviderAccount] = []

        if let data = try? Data(contentsOf: CodexPaths.tokenPoolURL),
           let pool = try? self.decoder.decode(TokenPool.self, from: data) {
            importedAccounts = pool.accounts.map { account in
                CodexBarProviderAccount.fromTokenAccount(account, existingID: account.accountId)
            }
        }

        if let tokens = auth["tokens"] as? [String: Any],
           let imported = self.accountFromAuthTokens(tokens) {
            if importedAccounts.contains(where: { $0.openAIAccountId == imported.openAIAccountId }) == false {
                importedAccounts.append(imported)
            }
        }

        guard importedAccounts.isEmpty == false else { return nil }

        let activeAccountId = importedAccounts.first?.id
        return CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            enabled: true,
            baseURL: nil,
            activeAccountId: activeAccountId,
            accounts: importedAccounts
        )
    }

    private func accountFromAuthTokens(_ tokens: [String: Any]) -> CodexBarProviderAccount? {
        guard let accessToken = tokens["access_token"] as? String,
              let refreshToken = tokens["refresh_token"] as? String,
              let idToken = tokens["id_token"] as? String,
              let accountId = tokens["account_id"] as? String else { return nil }

        let idClaims = AccountBuilder.decodeJWT(idToken)
        let email = idClaims["email"] as? String
        let authClaims = idClaims["https://api.openai.com/auth"] as? [String: Any] ?? [:]
        let activeUntil = authClaims["chatgpt_subscription_active_until"] as? String
        let formatter = ISO8601DateFormatter()
        let lastRefresh = formatter.date(from: activeUntil ?? "")

        return CodexBarProviderAccount(
            id: accountId,
            kind: .oauthTokens,
            label: email ?? String(accountId.prefix(8)),
            email: email,
            openAIAccountId: accountId,
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            lastRefresh: lastRefresh,
            addedAt: Date(),
            planType: "free"
        )
    }

    private func makeImportedProviderIfNeeded(
        baseURL: String?,
        apiKey: String,
        existingProviders: [CodexBarProvider]
    ) -> CodexBarProvider? {
        let normalizedBaseURL = baseURL ?? "https://api.openai.com/v1"
        if existingProviders.contains(where: { $0.baseURL == normalizedBaseURL }) {
            return nil
        }

        let label = URL(string: normalizedBaseURL)?.host ?? "Imported"
        let account = CodexBarProviderAccount(
            kind: .apiKey,
            label: "Imported",
            apiKey: apiKey,
            addedAt: Date()
        )
        return CodexBarProvider(
            id: self.slug(from: label),
            kind: .openAICompatible,
            label: label,
            enabled: true,
            baseURL: normalizedBaseURL,
            activeAccountId: account.id,
            accounts: [account]
        )
    }

    private func resolveActiveSelection(
        toml: LegacyCodexTomlSnapshot,
        auth: [String: Any],
        providers: [CodexBarProvider]
    ) -> CodexBarActiveSelection {
        if let baseURL = toml.openAIBaseURL,
           let provider = providers.first(where: { $0.baseURL == baseURL }) {
            return CodexBarActiveSelection(providerId: provider.id, accountId: provider.activeAccount?.id)
        }

        if let tokens = auth["tokens"] as? [String: Any],
           let accountId = tokens["account_id"] as? String,
           let provider = providers.first(where: { $0.kind == .openAIOAuth }) {
            let selected = provider.accounts.first(where: { $0.openAIAccountId == accountId }) ?? provider.activeAccount
            return CodexBarActiveSelection(providerId: provider.id, accountId: selected?.id)
        }

        if let openAIAPIKey = auth["OPENAI_API_KEY"] as? String,
           !openAIAPIKey.isEmpty,
           let provider = providers.first(where: { $0.kind == .openAICompatible }) {
            return CodexBarActiveSelection(providerId: provider.id, accountId: provider.activeAccount?.id)
        }

        let fallbackProvider = providers.first
        return CodexBarActiveSelection(providerId: fallbackProvider?.id, accountId: fallbackProvider?.activeAccount?.id)
    }

    private func readLegacyToml() -> LegacyCodexTomlSnapshot {
        guard let text = try? String(contentsOf: CodexPaths.configTomlURL, encoding: .utf8) else {
            return LegacyCodexTomlSnapshot()
        }
        return LegacyCodexTomlSnapshot(
            model: self.matchValue(for: "model", in: text),
            reviewModel: self.matchValue(for: "review_model", in: text),
            reasoningEffort: self.matchValue(for: "model_reasoning_effort", in: text),
            openAIBaseURL: self.matchOpenAIBaseURL(in: text)
        )
    }

    private func matchValue(for key: String, in text: String) -> String? {
        let pattern = #"(?m)^\#(key)\s*=\s*"([^"]+)""#
        let resolved = pattern.replacingOccurrences(of: "#(key)", with: NSRegularExpression.escapedPattern(for: key))
        guard let regex = try? NSRegularExpression(pattern: resolved) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }

    private func matchOpenAIBaseURL(in text: String) -> String? {
        if let explicitBaseURL = self.matchValue(for: "openai_base_url", in: text) {
            return explicitBaseURL
        }

        return self.matchBaseURLInProviderBlock(in: text, key: "OpenAI")
            ?? self.matchBaseURLInProviderBlock(in: text, key: "openai")
    }

    private func matchBaseURLInProviderBlock(in text: String, key: String) -> String? {
        guard let blockRegex = try? NSRegularExpression(
            pattern: #"(?ms)^\[model_providers\.#(key)\]\n(.*?)(?=^\[|\Z)"#
                .replacingOccurrences(of: "#(key)", with: NSRegularExpression.escapedPattern(for: key))
        ),
        let baseRegex = try? NSRegularExpression(pattern: #"(?m)^base_url\s*=\s*"([^"]+)""#) else { return nil }

        let range = NSRange(text.startIndex..., in: text)
        guard let block = blockRegex.firstMatch(in: text, range: range),
              let blockRange = Range(block.range(at: 1), in: text) else { return nil }
        let body = String(text[blockRange])
        let bodyRange = NSRange(body.startIndex..., in: body)
        guard let baseMatch = baseRegex.firstMatch(in: body, range: bodyRange),
              let valueRange = Range(baseMatch.range(at: 1), in: body) else { return nil }
        return String(body[valueRange])
    }

    private func readAuthJSON() -> [String: Any] {
        guard let data = try? Data(contentsOf: CodexPaths.authURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private func readProviderSecrets() -> [String: String] {
        guard let text = try? String(contentsOf: CodexPaths.providerSecretsURL, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("export ") else { continue }
            let body = String(line.dropFirst("export ".count))
            let parts = body.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0]
            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }
        return values
    }

    private func slug(from label: String) -> String {
        let lowered = label.lowercased()
        let slug = lowered.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: "-",
            options: .regularExpression
        ).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "provider-\(UUID().uuidString.lowercased())" : slug
    }

    private func backupForeignConfig() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = CodexPaths.codexBarRoot.appendingPathComponent("config.foreign-backup-\(stamp).json")
        try CodexPaths.backupFileIfPresent(from: CodexPaths.barConfigURL, to: backupURL)
        try? FileManager.default.removeItem(at: CodexPaths.barConfigURL)
    }
}
