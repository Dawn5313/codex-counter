import Foundation

enum AutoRoutingSwitchReason: String, Codable {
    case manual
    case startupBestAccount = "startup-best-account"
    case autoUnavailable = "auto-unavailable"
    case autoExhausted = "auto-exhausted"
    case autoThreshold = "auto-threshold"

    var isAutomatic: Bool {
        self != .manual
    }

    var isForced: Bool {
        switch self {
        case .autoUnavailable, .autoExhausted:
            return true
        case .manual, .startupBestAccount, .autoThreshold:
            return false
        }
    }
}

enum AutoRoutingPolicy {
    struct Decision {
        let account: TokenAccount
        let reason: AutoRoutingSwitchReason
    }

    nonisolated static func bestCandidate(
        from accounts: [TokenAccount],
        settings: CodexBarAutoRoutingSettings,
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings = .init()
    ) -> TokenAccount? {
        let eligible = accounts.filter { self.isEligible($0, settings: settings) }

        if let pinnedAccountId = settings.pinnedAccountId,
           let pinned = eligible.first(where: { $0.accountId == pinnedAccountId }) {
            return pinned
        }

        return eligible.sorted {
            OpenAIAccountListLayout.accountPrecedes(
                $0,
                $1,
                quotaSortSettings: quotaSortSettings
            )
        }.first
    }

    nonisolated static func hardFailoverReason(for account: TokenAccount) -> AutoRoutingSwitchReason? {
        if account.tokenExpired || account.isSuspended {
            return .autoUnavailable
        }
        if account.quotaExhausted {
            return .autoExhausted
        }
        return nil
    }

    nonisolated static func decision(
        from accounts: [TokenAccount],
        currentAccountID: String?,
        settings: CodexBarAutoRoutingSettings,
        fallbackReason: AutoRoutingSwitchReason,
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings = .init()
    ) -> Decision? {
        guard let candidate = self.bestCandidate(
            from: accounts,
            settings: settings,
            quotaSortSettings: quotaSortSettings
        ) else {
            return nil
        }

        guard let currentAccountID,
              let current = accounts.first(where: { $0.accountId == currentAccountID }) else {
            return Decision(account: candidate, reason: fallbackReason)
        }

        guard current.accountId != candidate.accountId else { return nil }

        if let failoverReason = self.hardFailoverReason(for: current) {
            return Decision(account: candidate, reason: failoverReason)
        }
        return nil
    }

    nonisolated private static func isEligible(
        _ account: TokenAccount,
        settings: CodexBarAutoRoutingSettings
    ) -> Bool {
        guard settings.excludedAccountIds.contains(account.accountId) == false else { return false }
        return account.isAvailableForNextUseRouting
    }
}

@MainActor
final class AutoRoutingCoordinator {
    static let shared = AutoRoutingCoordinator()

    private let store: TokenStore
    private let refreshAllAction: (TokenStore) async -> [WhamRefreshOutcome]

    private var hasStarted = false

    init(
        store: TokenStore? = nil,
        refreshAllAction: @escaping (TokenStore) async -> [WhamRefreshOutcome] = { store in
            await WhamService.shared.refreshAll(store: store)
        }
    ) {
        self.store = store ?? .shared
        self.refreshAllAction = refreshAllAction
    }

    func start() {
        guard self.hasStarted == false else { return }
        self.hasStarted = true

        Task { @MainActor in
            await self.handleAppLaunch()
        }
    }

    func handleAppLaunch() async {
        await self.routeBestAccountOnLaunchIfNeeded()
    }

    func handleAccountInventoryChanged() async {
        await self.maintainNextUseAccountIfNeeded(fallbackReason: .startupBestAccount)
    }

    func handlePostActiveAccountRefresh(accountID: String) async {
        guard self.store.activeAccount()?.accountId == accountID else { return }
        await self.maintainNextUseAccountIfNeeded(fallbackReason: .startupBestAccount)
    }

    func handleUsageSnapshotChanged() async {
        await self.maintainNextUseAccountIfNeeded(fallbackReason: .startupBestAccount)
    }

    private var currentSettings: CodexBarAutoRoutingSettings {
        self.store.config.autoRouting
    }

    private func routeBestAccountOnLaunchIfNeeded() async {
        guard self.currentSettings.enabled else { return }
        guard self.shouldManageOpenAIOAuthAccounts() else { return }

        _ = await self.refreshAllAction(self.store)
        await self.maintainNextUseAccountIfNeeded(fallbackReason: .startupBestAccount)
    }

    private func maintainNextUseAccountIfNeeded(fallbackReason: AutoRoutingSwitchReason) async {
        guard self.currentSettings.enabled else { return }
        guard self.shouldManageOpenAIOAuthAccounts() else { return }
        _ = AutoRoutingPolicy.decision(
            from: self.store.accounts,
            currentAccountID: self.store.activeAccount()?.accountId,
            settings: self.currentSettings,
            fallbackReason: fallbackReason,
            quotaSortSettings: self.store.config.openAI.quotaSort
        )
    }

    private func shouldManageOpenAIOAuthAccounts() -> Bool {
        guard self.store.accounts.isEmpty == false else { return false }
        guard let activeProvider = self.store.activeProvider else { return true }
        return activeProvider.kind == .openAIOAuth
    }
}
