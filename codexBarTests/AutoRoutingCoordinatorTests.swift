import Foundation
import XCTest

final class AutoRoutingCoordinatorTests: CodexBarTestCase {
    func testConfigDecodesMissingDesktopWithDefaults() throws {
        let json = """
        {
          "version": 1,
          "global": {
            "defaultModel": "gpt-5.4",
            "reviewModel": "gpt-5.4",
            "reasoningEffort": "xhigh"
          },
          "active": {},
          "providers": []
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let config = try JSONDecoder().decode(CodexBarConfig.self, from: data)

        XCTAssertFalse(config.autoRouting.enabled)
        XCTAssertEqual(config.autoRouting.urgentThresholdPercent, 5)
        XCTAssertEqual(config.autoRouting.switchThresholdPercent, 10)
        XCTAssertNil(config.desktop.preferredCodexAppPath)
        XCTAssertEqual(config.openAI.usageDisplayMode, .used)
        XCTAssertEqual(config.openAI.quotaSort.plusRelativeWeight, 10)
        XCTAssertEqual(config.openAI.quotaSort.teamRelativeToPlusMultiplier, 1.5)
        XCTAssertEqual(config.openAI.accountOrder, [])
        XCTAssertEqual(config.openAI.accountOrderingMode, .quotaSort)
        XCTAssertEqual(config.openAI.manualActivationBehavior, .updateConfigOnly)
    }

    func testConfigDecodesLegacyPromptFieldsWithoutUsingThem() throws {
        let json = """
        {
          "version": 1,
          "global": {
            "defaultModel": "gpt-5.4",
            "reviewModel": "gpt-5.4",
            "reasoningEffort": "xhigh"
          },
          "active": {},
          "autoRouting": {
            "enabled": true,
            "switchThresholdPercent": 15,
            "promptMode": "remindOnly"
          },
          "openAI": {
            "accountOrder": ["acct_a"],
            "popupAlertThresholdPercent": 25
          },
          "desktop": {},
          "providers": []
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let config = try JSONDecoder().decode(CodexBarConfig.self, from: data)

        XCTAssertTrue(config.autoRouting.enabled)
        XCTAssertEqual(config.autoRouting.switchThresholdPercent, 15)
        XCTAssertEqual(config.openAI.accountOrder, ["acct_a"])
        XCTAssertEqual(config.openAI.usageDisplayMode, .used)
        XCTAssertEqual(config.openAI.quotaSort.plusRelativeWeight, 10)
        XCTAssertEqual(config.openAI.quotaSort.teamRelativeToPlusMultiplier, 1.5)
        XCTAssertEqual(config.openAI.accountOrderingMode, .quotaSort)
        XCTAssertEqual(config.openAI.manualActivationBehavior, .updateConfigOnly)
        XCTAssertNil(config.desktop.preferredCodexAppPath)
    }

    func testPreferredDisplayAccountOrderOnlyAppliesInManualMode() {
        var settings = CodexBarOpenAISettings(
            accountOrder: ["acct_b", "acct_a"],
            accountOrderingMode: .quotaSort
        )

        XCTAssertEqual(settings.preferredDisplayAccountOrder, [])

        settings.accountOrderingMode = .manual
        XCTAssertEqual(settings.preferredDisplayAccountOrder, ["acct_b", "acct_a"])
    }

    @MainActor
    func testSaveDesktopSettingsRejectsInvalidCodexAppPath() throws {
        let invalidURL = try self.makeDirectory(named: "Invalid/Codex.app")
        TokenStore.shared.load()

        XCTAssertThrowsError(
            try TokenStore.shared.saveDesktopSettings(
                DesktopSettingsUpdate(preferredCodexAppPath: invalidURL.path)
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                TokenStoreError.invalidCodexAppPath.localizedDescription
            )
        }
    }

    func testBestCandidatePrefersUsableAccountWithMostPrimaryQuota() {
        let settings = CodexBarAutoRoutingSettings(enabled: true)
        let low = self.makeAccount(accountId: "acct_low", primaryUsedPercent: 60, secondaryUsedPercent: 10)
        let high = self.makeAccount(accountId: "acct_high", primaryUsedPercent: 20, secondaryUsedPercent: 90)
        let exhausted = self.makeAccount(accountId: "acct_exhausted", primaryUsedPercent: 100, secondaryUsedPercent: 0)

        let best = AutoRoutingPolicy.bestCandidate(from: [low, exhausted, high], settings: settings)

        XCTAssertEqual(best?.accountId, "acct_high")
    }

    func testBestCandidatePrefersWeightedPlusOverFreeWhenQuotaValueTies() {
        let settings = CodexBarAutoRoutingSettings(enabled: true)
        let free = self.makeAccount(
            accountId: "acct_free",
            planType: "free",
            primaryUsedPercent: 0,
            secondaryUsedPercent: 0
        )
        let plus = self.makeAccount(
            accountId: "acct_plus",
            planType: "plus",
            primaryUsedPercent: 90,
            secondaryUsedPercent: 90
        )

        let best = AutoRoutingPolicy.bestCandidate(from: [free, plus], settings: settings)

        XCTAssertEqual(best?.accountId, "acct_plus")
    }

    func testBestCandidateTreatsUnknownPlanTypeAsFree() {
        let settings = CodexBarAutoRoutingSettings(enabled: true)
        let unknown = self.makeAccount(
            accountId: "acct_unknown",
            planType: "enterprise",
            primaryUsedPercent: 0,
            secondaryUsedPercent: 0
        )
        let plus = self.makeAccount(
            accountId: "acct_plus",
            planType: "plus",
            primaryUsedPercent: 90,
            secondaryUsedPercent: 90
        )

        let best = AutoRoutingPolicy.bestCandidate(from: [unknown, plus], settings: settings)

        XCTAssertEqual(unknown.planQuotaMultiplier, 1.0)
        XCTAssertEqual(best?.accountId, "acct_plus")
    }

    func testBestCandidateRespectsPinnedUsableAccount() {
        let settings = CodexBarAutoRoutingSettings(enabled: true, pinnedAccountId: "acct_pinned")
        let pinned = self.makeAccount(accountId: "acct_pinned", primaryUsedPercent: 45, secondaryUsedPercent: 10)
        let healthier = self.makeAccount(accountId: "acct_healthier", primaryUsedPercent: 10, secondaryUsedPercent: 10)

        let best = AutoRoutingPolicy.bestCandidate(from: [healthier, pinned], settings: settings)

        XCTAssertEqual(best?.accountId, "acct_pinned")
    }

    func testAccountIsMarkedDegradedAtEightyPercent() {
        XCTAssertTrue(
            self.makeAccount(accountId: "acct_degraded", primaryUsedPercent: 80, secondaryUsedPercent: 10)
                .isDegradedForNextUseRouting
        )
        XCTAssertFalse(
            self.makeAccount(accountId: "acct_healthy", primaryUsedPercent: 79, secondaryUsedPercent: 10)
                .isDegradedForNextUseRouting
        )
    }

    func testDecisionKeepsHealthyCurrentNextUseAccount() {
        let settings = CodexBarAutoRoutingSettings(enabled: true)
        let current = self.makeAccount(accountId: "acct_current", primaryUsedPercent: 70, secondaryUsedPercent: 20)
        let better = self.makeAccount(accountId: "acct_better", primaryUsedPercent: 10, secondaryUsedPercent: 10)

        let decision = AutoRoutingPolicy.decision(
            from: [current, better],
            currentAccountID: "acct_current",
            settings: settings,
            fallbackReason: .startupBestAccount
        )

        XCTAssertNil(decision)
    }

    func testDecisionDoesNotAutoSwitchForDegradedButStillUsableCurrentAccount() {
        let settings = CodexBarAutoRoutingSettings(enabled: true)
        let current = self.makeAccount(accountId: "acct_current", primaryUsedPercent: 80, secondaryUsedPercent: 20)
        let better = self.makeAccount(accountId: "acct_better", primaryUsedPercent: 10, secondaryUsedPercent: 10)

        let decision = AutoRoutingPolicy.decision(
            from: [current, better],
            currentAccountID: "acct_current",
            settings: settings,
            fallbackReason: .startupBestAccount
        )

        XCTAssertNil(decision)
    }

    func testDecisionDoesNotPromoteMixedPlanCandidateWhenCurrentIsOnlyDegraded() {
        let settings = CodexBarAutoRoutingSettings(enabled: true)
        let current = self.makeAccount(
            accountId: "acct_current",
            planType: "free",
            primaryUsedPercent: 80,
            secondaryUsedPercent: 0
        )
        let better = self.makeAccount(
            accountId: "acct_better",
            planType: "plus",
            primaryUsedPercent: 90,
            secondaryUsedPercent: 90
        )

        let decision = AutoRoutingPolicy.decision(
            from: [current, better],
            currentAccountID: "acct_current",
            settings: settings,
            fallbackReason: .startupBestAccount
        )

        XCTAssertNil(decision)
    }

    func testDecisionUsesForcedFailoverWhenCurrentTokenExpired() {
        let settings = CodexBarAutoRoutingSettings(enabled: true)
        let current = self.makeAccount(
            accountId: "acct_current",
            primaryUsedPercent: 30,
            secondaryUsedPercent: 10,
            tokenExpired: true
        )
        let better = self.makeAccount(accountId: "acct_better", primaryUsedPercent: 10, secondaryUsedPercent: 10)

        let decision = AutoRoutingPolicy.decision(
            from: [current, better],
            currentAccountID: "acct_current",
            settings: settings,
            fallbackReason: .startupBestAccount
        )

        XCTAssertEqual(decision?.account.accountId, "acct_better")
        XCTAssertEqual(decision?.reason, .autoUnavailable)
    }

    func testDecisionUsesForcedFailoverWhenCurrentQuotaIsExhausted() {
        let settings = CodexBarAutoRoutingSettings(enabled: true)
        let current = self.makeAccount(
            accountId: "acct_current",
            primaryUsedPercent: 100,
            secondaryUsedPercent: 0
        )
        let better = self.makeAccount(accountId: "acct_better", primaryUsedPercent: 10, secondaryUsedPercent: 10)

        let decision = AutoRoutingPolicy.decision(
            from: [current, better],
            currentAccountID: "acct_current",
            settings: settings,
            fallbackReason: .startupBestAccount
        )

        XCTAssertEqual(decision?.account.accountId, "acct_better")
        XCTAssertEqual(decision?.reason, .autoExhausted)
    }

    func testHardFailoverReasonUsesUnavailableBeforeExhausted() {
        let unavailable = self.makeAccount(
            accountId: "acct_unavailable",
            primaryUsedPercent: 100,
            secondaryUsedPercent: 100,
            tokenExpired: true
        )
        let exhausted = self.makeAccount(accountId: "acct_exhausted", primaryUsedPercent: 100, secondaryUsedPercent: 0)

        XCTAssertEqual(AutoRoutingPolicy.hardFailoverReason(for: unavailable), .autoUnavailable)
        XCTAssertEqual(AutoRoutingPolicy.hardFailoverReason(for: exhausted), .autoExhausted)
    }

    func testBestCandidateExcludesUnavailableAndExhaustedAccounts() {
        let settings = CodexBarAutoRoutingSettings(enabled: true)
        let suspended = self.makeAccount(
            accountId: "acct_suspended",
            planType: "team",
            primaryUsedPercent: 10,
            secondaryUsedPercent: 10,
            isSuspended: true
        )
        let expired = self.makeAccount(
            accountId: "acct_expired",
            planType: "plus",
            primaryUsedPercent: 10,
            secondaryUsedPercent: 10,
            tokenExpired: true
        )
        let exhausted = self.makeAccount(
            accountId: "acct_exhausted",
            primaryUsedPercent: 100,
            secondaryUsedPercent: 0
        )
        let healthy = self.makeAccount(
            accountId: "acct_healthy",
            planType: "free",
            primaryUsedPercent: 10,
            secondaryUsedPercent: 5
        )

        let best = AutoRoutingPolicy.bestCandidate(
            from: [suspended, expired, exhausted, healthy],
            settings: settings
        )

        XCTAssertEqual(best?.accountId, "acct_healthy")
    }

    private func makeDirectory(named relativePath: String) throws -> URL {
        let url = CodexPaths.realHome.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeAccount(
        accountId: String,
        planType: String = "free",
        primaryUsedPercent: Double,
        secondaryUsedPercent: Double,
        tokenExpired: Bool = false,
        isSuspended: Bool = false
    ) -> TokenAccount {
        TokenAccount(
            email: "\(accountId)@example.com",
            accountId: accountId,
            accessToken: "access-\(accountId)",
            refreshToken: "refresh-\(accountId)",
            idToken: "id-\(accountId)",
            planType: planType,
            primaryUsedPercent: primaryUsedPercent,
            secondaryUsedPercent: secondaryUsedPercent,
            isActive: false,
            isSuspended: isSuspended,
            tokenExpired: tokenExpired
        )
    }
}
