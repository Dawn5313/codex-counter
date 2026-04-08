import Foundation

enum OpenAIAccountSortBucket: Int {
    case usable
    case unavailableNonExhausted
    case exhausted
}

private enum OpenAIAccountDisplayPriority: Int {
    case prioritized
    case standard
}

struct OpenAIAccountGroup: Identifiable {
    let email: String
    let accounts: [TokenAccount]

    var id: String { email }
}

extension OpenAIAccountGroup {
    nonisolated var representativeAccount: TokenAccount? {
        accounts.first
    }

    nonisolated func headerQuotaRemark(now: Date = Date()) -> String? {
        representativeAccount?.headerQuotaRemark(now: now)
    }
}

enum OpenAIAccountListLayout {
    static let visibleGroupLimit = 4

    nonisolated static func groupedAccounts(
        from accounts: [TokenAccount],
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings = .init(),
        preferredAccountOrder: [String] = []
    ) -> [OpenAIAccountGroup] {
        _ = preferredAccountOrder
        return Dictionary(grouping: accounts, by: \.email)
            .map { email, groupedAccounts in
                OpenAIAccountGroup(
                    email: email,
                    accounts: groupedAccounts.sorted {
                        self.accountPrecedes(
                            $0,
                            $1,
                            quotaSortSettings: quotaSortSettings
                        )
                    }
                )
            }
            .sorted {
                self.groupPrecedes(
                    $0,
                    $1,
                    quotaSortSettings: quotaSortSettings
                )
            }
    }

    nonisolated static func groupedAccounts(
        from accounts: [TokenAccount],
        attribution: OpenAILiveSessionAttribution,
        now: Date = Date(),
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings = .init(),
        preferredAccountOrder: [String] = []
    ) -> [OpenAIAccountGroup] {
        self.groupedAccounts(
            from: accounts,
            prioritizedAccountIDs: Set(attribution.liveSummary(now: now).inUseSessionCounts.keys),
            quotaSortSettings: quotaSortSettings,
            preferredAccountOrder: preferredAccountOrder
        )
    }

    nonisolated static func groupedAccounts(
        from accounts: [TokenAccount],
        attribution: OpenAIRunningThreadAttribution,
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings = .init(),
        preferredAccountOrder: [String] = []
    ) -> [OpenAIAccountGroup] {
        self.groupedAccounts(
            from: accounts,
            prioritizedAccountIDs: Set(attribution.summary.runningThreadCounts.keys),
            quotaSortSettings: quotaSortSettings,
            preferredAccountOrder: preferredAccountOrder
        )
    }

    nonisolated static func groupedAccounts(
        from accounts: [TokenAccount],
        summary: OpenAIRunningThreadAttribution.Summary,
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings = .init(),
        preferredAccountOrder: [String] = []
    ) -> [OpenAIAccountGroup] {
        self.groupedAccounts(
            from: accounts,
            prioritizedAccountIDs: Set(summary.runningThreadCounts.keys),
            quotaSortSettings: quotaSortSettings,
            preferredAccountOrder: preferredAccountOrder
        )
    }

    nonisolated private static func groupedAccounts(
        from accounts: [TokenAccount],
        prioritizedAccountIDs: Set<String>,
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings,
        preferredAccountOrder: [String]
    ) -> [OpenAIAccountGroup] {
        _ = preferredAccountOrder
        return Dictionary(grouping: accounts, by: \.email)
            .map { email, groupedAccounts in
                OpenAIAccountGroup(
                    email: email,
                    accounts: groupedAccounts.sorted {
                        self.displayAccountPrecedes(
                            $0,
                            $1,
                            prioritizedAccountIDs: prioritizedAccountIDs,
                            quotaSortSettings: quotaSortSettings
                        )
                    }
                )
            }
            .sorted {
                self.displayGroupPrecedes(
                    $0,
                    $1,
                    prioritizedAccountIDs: prioritizedAccountIDs,
                    quotaSortSettings: quotaSortSettings
                )
            }
    }

    nonisolated static func visibleGroups(
        from groups: [OpenAIAccountGroup],
        maxAccounts: Int
    ) -> [OpenAIAccountGroup] {
        guard maxAccounts > 0 else { return [] }

        var remaining = maxAccounts
        var visible: [OpenAIAccountGroup] = []

        for group in groups where remaining > 0 {
            let accounts = Array(group.accounts.prefix(remaining))
            guard accounts.isEmpty == false else { continue }
            visible.append(OpenAIAccountGroup(email: group.email, accounts: accounts))
            remaining -= accounts.count
        }

        return visible
    }

    nonisolated static func accountPrecedes(
        _ lhs: TokenAccount,
        _ rhs: TokenAccount,
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings = .init()
    ) -> Bool {
        if lhs.sortBucket != rhs.sortBucket {
            return lhs.sortBucket.rawValue < rhs.sortBucket.rawValue
        }

        let lhsWeightedPrimary = lhs.weightedPrimaryRemainingPercent(using: quotaSortSettings)
        let rhsWeightedPrimary = rhs.weightedPrimaryRemainingPercent(using: quotaSortSettings)
        if lhsWeightedPrimary != rhsWeightedPrimary {
            return lhsWeightedPrimary > rhsWeightedPrimary
        }

        let lhsWeightedSecondary = lhs.weightedSecondaryRemainingPercent(using: quotaSortSettings)
        let rhsWeightedSecondary = rhs.weightedSecondaryRemainingPercent(using: quotaSortSettings)
        if lhsWeightedSecondary != rhsWeightedSecondary {
            return lhsWeightedSecondary > rhsWeightedSecondary
        }

        let lhsPlanMultiplier = lhs.planQuotaMultiplier(using: quotaSortSettings)
        let rhsPlanMultiplier = rhs.planQuotaMultiplier(using: quotaSortSettings)
        if lhsPlanMultiplier != rhsPlanMultiplier {
            return lhsPlanMultiplier > rhsPlanMultiplier
        }

        if lhs.primaryRemainingPercent != rhs.primaryRemainingPercent {
            return lhs.primaryRemainingPercent > rhs.primaryRemainingPercent
        }

        if lhs.secondaryRemainingPercent != rhs.secondaryRemainingPercent {
            return lhs.secondaryRemainingPercent > rhs.secondaryRemainingPercent
        }

        let lhsEmail = lhs.email.localizedLowercase
        let rhsEmail = rhs.email.localizedLowercase
        if lhsEmail != rhsEmail {
            return lhsEmail < rhsEmail
        }

        return lhs.accountId < rhs.accountId
    }

    nonisolated private static func displayAccountPrecedes(
        _ lhs: TokenAccount,
        _ rhs: TokenAccount,
        prioritizedAccountIDs: Set<String>,
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings
    ) -> Bool {
        let lhsPriority = self.displayPriority(for: lhs, prioritizedAccountIDs: prioritizedAccountIDs)
        let rhsPriority = self.displayPriority(for: rhs, prioritizedAccountIDs: prioritizedAccountIDs)
        if lhsPriority != rhsPriority {
            return lhsPriority.rawValue < rhsPriority.rawValue
        }

        return self.accountPrecedes(
            lhs,
            rhs,
            quotaSortSettings: quotaSortSettings
        )
    }

    nonisolated private static func displayPriority(
        for account: TokenAccount,
        prioritizedAccountIDs: Set<String>
    ) -> OpenAIAccountDisplayPriority {
        if account.isActive || prioritizedAccountIDs.contains(account.accountId) {
            return .prioritized
        }
        return .standard
    }

    nonisolated private static func groupPrecedes(
        _ lhs: OpenAIAccountGroup,
        _ rhs: OpenAIAccountGroup,
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings
    ) -> Bool {
        let lhsRepresentative = lhs.accounts.first
        let rhsRepresentative = rhs.accounts.first

        switch (lhsRepresentative, rhsRepresentative) {
        case let (lhsAccount?, rhsAccount?):
            if self.accountPrecedes(
                lhsAccount,
                rhsAccount,
                quotaSortSettings: quotaSortSettings
            ) {
                return true
            }
            if self.accountPrecedes(
                rhsAccount,
                lhsAccount,
                quotaSortSettings: quotaSortSettings
            ) {
                return false
            }
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            break
        }

        return lhs.email.localizedLowercase < rhs.email.localizedLowercase
    }

    nonisolated private static func displayGroupPrecedes(
        _ lhs: OpenAIAccountGroup,
        _ rhs: OpenAIAccountGroup,
        prioritizedAccountIDs: Set<String>,
        quotaSortSettings: CodexBarOpenAISettings.QuotaSortSettings
    ) -> Bool {
        let lhsRepresentative = lhs.accounts.first
        let rhsRepresentative = rhs.accounts.first

        switch (lhsRepresentative, rhsRepresentative) {
        case let (lhsAccount?, rhsAccount?):
            if self.displayAccountPrecedes(
                lhsAccount,
                rhsAccount,
                prioritizedAccountIDs: prioritizedAccountIDs,
                quotaSortSettings: quotaSortSettings
            ) {
                return true
            }
            if self.displayAccountPrecedes(
                rhsAccount,
                lhsAccount,
                prioritizedAccountIDs: prioritizedAccountIDs,
                quotaSortSettings: quotaSortSettings
            ) {
                return false
            }
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            break
        }

        return lhs.email.localizedLowercase < rhs.email.localizedLowercase
    }
}
