import Foundation
import XCTest

final class CodexBarOAuthAccountServiceTests: CodexBarTestCase {
    func testImportActivatedAccountSynchronizesAuthAndConfig() throws {
        let service = CodexBarOAuthAccountService()
        let account = TokenAccount(
            email: "alice@example.com",
            accountId: "acct_alice",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            idToken: "id-token"
        )

        let result = try service.importAccount(account, activate: true)

        XCTAssertTrue(result.active)
        XCTAssertTrue(result.synchronized)

        let authData = try Data(contentsOf: CodexPaths.authURL)
        let authObject = try XCTUnwrap(JSONSerialization.jsonObject(with: authData) as? [String: Any])
        let tokens = try XCTUnwrap(authObject["tokens"] as? [String: Any])
        XCTAssertEqual(tokens["account_id"] as? String, "acct_alice")
        XCTAssertEqual(tokens["access_token"] as? String, "access-token")

        let configText = try String(contentsOf: CodexPaths.configTomlURL, encoding: .utf8)
        XCTAssertTrue(configText.contains("model_provider = \"openai\""))
        XCTAssertTrue(configText.contains("model = \"gpt-5.4\""))
    }

    func testActivateAccountUpdatesActiveSelection() throws {
        let service = CodexBarOAuthAccountService()

        _ = try service.importAccount(
            TokenAccount(
                email: "first@example.com",
                accountId: "acct_first",
                accessToken: "access-1",
                refreshToken: "refresh-1",
                idToken: "id-1"
            ),
            activate: true
        )
        _ = try service.importAccount(
            TokenAccount(
                email: "second@example.com",
                accountId: "acct_second",
                accessToken: "access-2",
                refreshToken: "refresh-2",
                idToken: "id-2"
            ),
            activate: false
        )

        let activation = try service.activateAccount(accountID: "acct_second")
        XCTAssertTrue(activation.active)

        let accounts = try service.listAccounts()
        XCTAssertEqual(accounts.first(where: { $0.accountID == "acct_second" })?.active, true)
        XCTAssertEqual(accounts.first(where: { $0.accountID == "acct_first" })?.active, false)
    }

    func testImportAccountsUpsertsAndPreservesMetadata() throws {
        let store = CodexBarConfigStore()
        let originalAddedAt = Date(timeIntervalSince1970: 1_234)
        let existingAccount = CodexBarProviderAccount(
            id: "acct_existing",
            kind: .oauthTokens,
            label: "Pinned Label",
            email: "old@example.com",
            openAIAccountId: "acct_existing",
            accessToken: "old-access",
            refreshToken: "old-refresh",
            idToken: "old-id",
            lastRefresh: originalAddedAt,
            addedAt: originalAddedAt,
            planType: "free"
        )
        let provider = CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            enabled: true,
            activeAccountId: existingAccount.id,
            accounts: [existingAccount]
        )
        try store.save(
            CodexBarConfig(
                active: CodexBarActiveSelection(providerId: provider.id, accountId: existingAccount.id),
                providers: [provider]
            )
        )

        let service = CodexBarOAuthAccountService()
        let updatedAccount = try self.makeOAuthAccount(accountID: "acct_existing", email: "new@example.com", isActive: true)

        let result = try service.importAccounts([updatedAccount], activeAccountID: "acct_existing")

        XCTAssertEqual(result.addedCount, 0)
        XCTAssertEqual(result.updatedCount, 1)
        XCTAssertTrue(result.synchronized)

        let reloaded = try store.load()
        let stored = try XCTUnwrap(reloaded.oauthProvider()?.accounts.first(where: { $0.openAIAccountId == "acct_existing" }))
        XCTAssertEqual(stored.label, "Pinned Label")
        XCTAssertEqual(stored.addedAt, originalAddedAt)
        XCTAssertEqual(stored.accessToken, updatedAccount.accessToken)
        XCTAssertEqual(reloaded.active.providerId, "openai-oauth")
        XCTAssertEqual(reloaded.active.accountId, "acct_existing")
    }

    func testImportAccountsActivatesMarkedAccountWhenOpenAIIsActive() throws {
        let service = CodexBarOAuthAccountService()
        let first = try self.makeOAuthAccount(accountID: "acct_first", email: "first@example.com", isActive: true)
        let second = try self.makeOAuthAccount(accountID: "acct_second", email: "second@example.com")

        _ = try service.importAccount(first, activate: true)

        let result = try service.importAccounts([first, second], activeAccountID: "acct_second")

        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.updatedCount, 1)
        XCTAssertTrue(result.activeChanged)
        XCTAssertFalse(result.providerChanged)
        XCTAssertFalse(result.preservedCompatibleProvider)

        let accounts = try service.listAccounts()
        XCTAssertEqual(accounts.first(where: { $0.accountID == "acct_second" })?.active, true)
        XCTAssertEqual(accounts.first(where: { $0.accountID == "acct_first" })?.active, false)
    }

    func testImportAccountsKeepsCompatibleProviderActive() throws {
        let configStore = CodexBarConfigStore()
        let compatibleAccount = CodexBarProviderAccount(
            kind: .apiKey,
            label: "Primary",
            apiKey: "compat-key",
            addedAt: Date(timeIntervalSince1970: 42)
        )
        let compatibleProvider = CodexBarProvider(
            id: "compat-provider",
            kind: .openAICompatible,
            label: "Compatible",
            enabled: true,
            baseURL: "https://example.com/v1",
            activeAccountId: compatibleAccount.id,
            accounts: [compatibleAccount]
        )
        try configStore.save(
            CodexBarConfig(
                active: CodexBarActiveSelection(providerId: compatibleProvider.id, accountId: compatibleAccount.id),
                providers: [compatibleProvider]
            )
        )

        let service = CodexBarOAuthAccountService()
        let imported = try self.makeOAuthAccount(accountID: "acct_imported", email: "imported@example.com")

        let result = try service.importAccounts([imported], activeAccountID: "acct_imported")

        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.updatedCount, 0)
        XCTAssertFalse(result.activeChanged)
        XCTAssertFalse(result.providerChanged)
        XCTAssertTrue(result.preservedCompatibleProvider)
        XCTAssertFalse(result.synchronized)

        let reloaded = try configStore.load()
        XCTAssertEqual(reloaded.active.providerId, compatibleProvider.id)
        XCTAssertEqual(reloaded.active.accountId, compatibleAccount.id)
        XCTAssertEqual(reloaded.oauthProvider()?.accounts.count, 1)
        XCTAssertEqual(reloaded.oauthProvider()?.activeAccountId, "acct_imported")
    }

    func testImportAccountsWithoutActiveMarkerKeepsCurrentOpenAISelection() throws {
        let service = CodexBarOAuthAccountService()
        let first = try self.makeOAuthAccount(accountID: "acct_first", email: "first@example.com", isActive: true)
        let second = try self.makeOAuthAccount(accountID: "acct_second", email: "second@example.com")

        _ = try service.importAccount(first, activate: true)

        let result = try service.importAccounts([first, second], activeAccountID: nil)

        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.updatedCount, 1)
        XCTAssertFalse(result.activeChanged)
        XCTAssertFalse(result.providerChanged)

        let accounts = try service.listAccounts()
        XCTAssertEqual(accounts.first(where: { $0.accountID == "acct_first" })?.active, true)
        XCTAssertEqual(accounts.first(where: { $0.accountID == "acct_second" })?.active, false)
    }
}
