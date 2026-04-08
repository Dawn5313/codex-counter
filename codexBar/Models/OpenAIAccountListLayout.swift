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

    nonisolated static func groupedAccounts(from accounts: [TokenAccount]) -> [OpenAIAccountGroup] {
        Dictionary(grouping: accounts, by: \.email)
            .map { email, groupedAccounts in
                OpenAIAccountGroup(
                    email: email,
                    accounts: groupedAccounts.sorted(by: accountPrecedes)
                )
            }
            .sorted(by: groupPrecedes)
    }

    nonisolated static func groupedAccounts(
        from accounts: [TokenAccount],
        attribution: OpenAILiveSessionAttribution,
        now: Date = Date()
    ) -> [OpenAIAccountGroup] {
        self.groupedAccounts(
            from: accounts,
            prioritizedAccountIDs: Set(attribution.liveSummary(now: now).inUseSessionCounts.keys)
        )
    }

    nonisolated static func groupedAccounts(
        from accounts: [TokenAccount],
        attribution: OpenAIRunningThreadAttribution
    ) -> [OpenAIAccountGroup] {
        self.groupedAccounts(
            from: accounts,
            prioritizedAccountIDs: Set(attribution.summary.runningThreadCounts.keys)
        )
    }

    nonisolated static func groupedAccounts(
        from accounts: [TokenAccount],
        summary: OpenAIRunningThreadAttribution.Summary
    ) -> [OpenAIAccountGroup] {
        self.groupedAccounts(
            from: accounts,
            prioritizedAccountIDs: Set(summary.runningThreadCounts.keys)
        )
    }

    nonisolated private static func groupedAccounts(
        from accounts: [TokenAccount],
        prioritizedAccountIDs: Set<String>
    ) -> [OpenAIAccountGroup] {
        Dictionary(grouping: accounts, by: \.email)
            .map { email, groupedAccounts in
                OpenAIAccountGroup(
                    email: email,
                    accounts: groupedAccounts.sorted {
                        self.displayAccountPrecedes($0, $1, prioritizedAccountIDs: prioritizedAccountIDs)
                    }
                )
            }
            .sorted { self.displayGroupPrecedes($0, $1, prioritizedAccountIDs: prioritizedAccountIDs) }
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

    nonisolated static func accountPrecedes(_ lhs: TokenAccount, _ rhs: TokenAccount) -> Bool {
        if lhs.sortBucket != rhs.sortBucket {
            return lhs.sortBucket.rawValue < rhs.sortBucket.rawValue
        }

        if lhs.weightedPrimaryRemainingPercent != rhs.weightedPrimaryRemainingPercent {
            return lhs.weightedPrimaryRemainingPercent > rhs.weightedPrimaryRemainingPercent
        }

        if lhs.weightedSecondaryRemainingPercent != rhs.weightedSecondaryRemainingPercent {
            return lhs.weightedSecondaryRemainingPercent > rhs.weightedSecondaryRemainingPercent
        }

        if lhs.planQuotaMultiplier != rhs.planQuotaMultiplier {
            return lhs.planQuotaMultiplier > rhs.planQuotaMultiplier
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
        prioritizedAccountIDs: Set<String>
    ) -> Bool {
        let lhsPriority = self.displayPriority(for: lhs, prioritizedAccountIDs: prioritizedAccountIDs)
        let rhsPriority = self.displayPriority(for: rhs, prioritizedAccountIDs: prioritizedAccountIDs)
        if lhsPriority != rhsPriority {
            return lhsPriority.rawValue < rhsPriority.rawValue
        }

        return self.accountPrecedes(lhs, rhs)
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

    nonisolated private static func groupPrecedes(_ lhs: OpenAIAccountGroup, _ rhs: OpenAIAccountGroup) -> Bool {
        let lhsRepresentative = lhs.accounts.first
        let rhsRepresentative = rhs.accounts.first

        switch (lhsRepresentative, rhsRepresentative) {
        case let (lhsAccount?, rhsAccount?):
            if accountPrecedes(lhsAccount, rhsAccount) {
                return true
            }
            if accountPrecedes(rhsAccount, lhsAccount) {
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
        prioritizedAccountIDs: Set<String>
    ) -> Bool {
        let lhsRepresentative = lhs.accounts.first
        let rhsRepresentative = rhs.accounts.first

        switch (lhsRepresentative, rhsRepresentative) {
        case let (lhsAccount?, rhsAccount?):
            if self.displayAccountPrecedes(lhsAccount, rhsAccount, prioritizedAccountIDs: prioritizedAccountIDs) {
                return true
            }
            if self.displayAccountPrecedes(rhsAccount, lhsAccount, prioritizedAccountIDs: prioritizedAccountIDs) {
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
