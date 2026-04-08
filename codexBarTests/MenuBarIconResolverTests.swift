import XCTest

final class MenuBarIconResolverTests: XCTestCase {
    func testCompatibleProviderUsesNetworkIconWhenOAuthWarningsExist() {
        let accounts = [
            TokenAccount(
                email: "alice@example.com",
                accountId: "acct_alice",
                secondaryUsedPercent: 100
            )
        ]

        let icon = MenuBarIconResolver.iconName(
            accounts: accounts,
            activeProviderKind: .openAICompatible
        )

        XCTAssertEqual(icon, "network")
    }

    func testActiveOAuthAccountStillDrivesWarningIcon() {
        let accounts = [
            TokenAccount(
                email: "alice@example.com",
                accountId: "acct_alice",
                secondaryUsedPercent: 100,
                isActive: true
            )
        ]

        let icon = MenuBarIconResolver.iconName(
            accounts: accounts,
            activeProviderKind: .openAIOAuth
        )

        XCTAssertEqual(icon, "exclamationmark.triangle.fill")
    }

    func testPopupAlertThresholdControlsBoltWarningIcon() {
        let accounts = [
            TokenAccount(
                email: "alice@example.com",
                accountId: "acct_alice",
                primaryUsedPercent: 85,
                secondaryUsedPercent: 10,
                isActive: true
            )
        ]

        let relaxed = MenuBarIconResolver.iconName(
            accounts: accounts,
            activeProviderKind: .openAIOAuth,
            popupAlertThresholdPercent: 10
        )
        let strict = MenuBarIconResolver.iconName(
            accounts: accounts,
            activeProviderKind: .openAIOAuth,
            popupAlertThresholdPercent: 20
        )

        XCTAssertEqual(relaxed, "terminal.fill")
        XCTAssertEqual(strict, "bolt.circle.fill")
    }
}
