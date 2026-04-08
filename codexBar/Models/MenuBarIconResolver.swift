import Foundation

enum MenuBarIconResolver {
    static func iconName(
        accounts: [TokenAccount],
        activeProviderKind: CodexBarProviderKind?,
        popupAlertThresholdPercent: Double = 20
    ) -> String {
        if let active = accounts.first(where: { $0.isActive }) {
            return self.iconName(
                for: [active],
                fallbackProviderKind: activeProviderKind,
                popupAlertThresholdPercent: popupAlertThresholdPercent
            )
        }

        if activeProviderKind == .openAICompatible {
            return "network"
        }

        return self.iconName(
            for: accounts,
            fallbackProviderKind: activeProviderKind,
            popupAlertThresholdPercent: popupAlertThresholdPercent
        )
    }

    private static func iconName(
        for accounts: [TokenAccount],
        fallbackProviderKind: CodexBarProviderKind?,
        popupAlertThresholdPercent: Double
    ) -> String {
        if accounts.contains(where: { $0.isBanned }) {
            return "xmark.circle.fill"
        }
        if accounts.contains(where: { $0.secondaryExhausted }) {
            return "exclamationmark.triangle.fill"
        }
        if accounts.contains(where: { $0.quotaExhausted || $0.isBelowPopupAlertThreshold(popupAlertThresholdPercent) }) {
            return "bolt.circle.fill"
        }
        if fallbackProviderKind == .openAICompatible {
            return "network"
        }
        return "terminal.fill"
    }
}
