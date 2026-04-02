import Foundation

enum CodexBarProviderKind: String, Codable {
    case openAIOAuth = "openai_oauth"
    case openAICompatible = "openai_compatible"
}

enum CodexBarAccountKind: String, Codable {
    case oauthTokens = "oauth_tokens"
    case apiKey = "api_key"
}

struct CodexBarGlobalSettings: Codable {
    var defaultModel: String
    var reviewModel: String
    var reasoningEffort: String

    init(defaultModel: String = "gpt-5.4", reviewModel: String = "gpt-5.4", reasoningEffort: String = "xhigh") {
        self.defaultModel = defaultModel
        self.reviewModel = reviewModel
        self.reasoningEffort = reasoningEffort
    }
}

struct CodexBarActiveSelection: Codable {
    var providerId: String?
    var accountId: String?
}

struct CodexBarProviderAccount: Codable, Identifiable, Equatable {
    var id: String
    var kind: CodexBarAccountKind
    var label: String

    var email: String?
    var openAIAccountId: String?
    var accessToken: String?
    var refreshToken: String?
    var idToken: String?
    var lastRefresh: Date?

    var apiKey: String?
    var addedAt: Date?

    // Runtime quota snapshot for OAuth accounts.
    var planType: String?
    var primaryUsedPercent: Double?
    var secondaryUsedPercent: Double?
    var primaryResetAt: Date?
    var secondaryResetAt: Date?
    var lastChecked: Date?
    var isSuspended: Bool?
    var tokenExpired: Bool?
    var organizationName: String?

    init(
        id: String = UUID().uuidString,
        kind: CodexBarAccountKind,
        label: String,
        email: String? = nil,
        openAIAccountId: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        idToken: String? = nil,
        lastRefresh: Date? = nil,
        apiKey: String? = nil,
        addedAt: Date? = nil,
        planType: String? = nil,
        primaryUsedPercent: Double? = nil,
        secondaryUsedPercent: Double? = nil,
        primaryResetAt: Date? = nil,
        secondaryResetAt: Date? = nil,
        lastChecked: Date? = nil,
        isSuspended: Bool? = nil,
        tokenExpired: Bool? = nil,
        organizationName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.email = email
        self.openAIAccountId = openAIAccountId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.lastRefresh = lastRefresh
        self.apiKey = apiKey
        self.addedAt = addedAt
        self.planType = planType
        self.primaryUsedPercent = primaryUsedPercent
        self.secondaryUsedPercent = secondaryUsedPercent
        self.primaryResetAt = primaryResetAt
        self.secondaryResetAt = secondaryResetAt
        self.lastChecked = lastChecked
        self.isSuspended = isSuspended
        self.tokenExpired = tokenExpired
        self.organizationName = organizationName
    }

    var maskedAPIKey: String {
        guard let apiKey, apiKey.count > 8 else { return apiKey ?? "" }
        return String(apiKey.prefix(6)) + "..." + String(apiKey.suffix(4))
    }

    func asTokenAccount(isActive: Bool) -> TokenAccount? {
        guard self.kind == .oauthTokens,
              let accountId = self.openAIAccountId,
              let accessToken = self.accessToken,
              let refreshToken = self.refreshToken,
              let idToken = self.idToken else { return nil }

        return TokenAccount(
            email: self.email ?? self.label,
            accountId: accountId,
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            expiresAt: nil,
            planType: self.planType ?? "free",
            primaryUsedPercent: self.primaryUsedPercent ?? 0,
            secondaryUsedPercent: self.secondaryUsedPercent ?? 0,
            primaryResetAt: self.primaryResetAt,
            secondaryResetAt: self.secondaryResetAt,
            lastChecked: self.lastChecked,
            isActive: isActive,
            isSuspended: self.isSuspended ?? false,
            tokenExpired: self.tokenExpired ?? false,
            organizationName: self.organizationName
        )
    }

    static func fromTokenAccount(_ account: TokenAccount, existingID: String? = nil) -> CodexBarProviderAccount {
        CodexBarProviderAccount(
            id: existingID ?? account.accountId,
            kind: .oauthTokens,
            label: account.email.isEmpty ? account.accountId : account.email,
            email: account.email,
            openAIAccountId: account.accountId,
            accessToken: account.accessToken,
            refreshToken: account.refreshToken,
            idToken: account.idToken,
            lastRefresh: Date(),
            addedAt: Date(),
            planType: account.planType,
            primaryUsedPercent: account.primaryUsedPercent,
            secondaryUsedPercent: account.secondaryUsedPercent,
            primaryResetAt: account.primaryResetAt,
            secondaryResetAt: account.secondaryResetAt,
            lastChecked: account.lastChecked,
            isSuspended: account.isSuspended,
            tokenExpired: account.tokenExpired,
            organizationName: account.organizationName
        )
    }
}

struct CodexBarProvider: Codable, Identifiable, Equatable {
    var id: String
    var kind: CodexBarProviderKind
    var label: String
    var enabled: Bool
    var baseURL: String?
    var activeAccountId: String?
    var accounts: [CodexBarProviderAccount]

    init(
        id: String,
        kind: CodexBarProviderKind,
        label: String,
        enabled: Bool = true,
        baseURL: String? = nil,
        activeAccountId: String? = nil,
        accounts: [CodexBarProviderAccount] = []
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.enabled = enabled
        self.baseURL = baseURL
        self.activeAccountId = activeAccountId
        self.accounts = accounts
    }

    var activeAccount: CodexBarProviderAccount? {
        if let activeAccountId, let found = self.accounts.first(where: { $0.id == activeAccountId }) {
            return found
        }
        return self.accounts.first
    }

    var hostLabel: String {
        guard let baseURL,
              let host = URL(string: baseURL)?.host,
              !host.isEmpty else { return self.label }
        return host
    }
}

struct CodexBarConfig: Codable {
    var version: Int
    var global: CodexBarGlobalSettings
    var active: CodexBarActiveSelection
    var providers: [CodexBarProvider]

    init(
        version: Int = 1,
        global: CodexBarGlobalSettings = CodexBarGlobalSettings(),
        active: CodexBarActiveSelection = CodexBarActiveSelection(),
        providers: [CodexBarProvider] = []
    ) {
        self.version = version
        self.global = global
        self.active = active
        self.providers = providers
    }

    func provider(id: String?) -> CodexBarProvider? {
        guard let id else { return nil }
        return self.providers.first(where: { $0.id == id })
    }

    func activeProvider() -> CodexBarProvider? {
        self.provider(id: self.active.providerId)
    }

    func activeAccount() -> CodexBarProviderAccount? {
        self.activeProvider()?.accounts.first(where: { $0.id == self.active.accountId }) ?? self.activeProvider()?.activeAccount
    }

    func oauthProvider() -> CodexBarProvider? {
        self.providers.first(where: { $0.kind == .openAIOAuth })
    }
}

