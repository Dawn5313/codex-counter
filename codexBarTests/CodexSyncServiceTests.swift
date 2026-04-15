import Foundation
import XCTest

final class CodexSyncServiceTests: CodexBarTestCase {
    func testSynchronizeRestoresPreviousFilesWhenConfigWriteFails() throws {
        try CodexPaths.ensureDirectories()

        let originalAuth = Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"old"}}"#.utf8)
        let originalToml = Data("model = \"gpt-5.4-mini\"\n".utf8)
        try CodexPaths.writeSecureFile(originalAuth, to: CodexPaths.authURL)
        try CodexPaths.writeSecureFile(originalToml, to: CodexPaths.configTomlURL)

        let account = CodexBarProviderAccount(
            id: "acct_new",
            kind: .oauthTokens,
            label: "new@example.com",
            email: "new@example.com",
            openAIAccountId: "acct_new",
            accessToken: "access-new",
            refreshToken: "refresh-new",
            idToken: "id-new"
        )
        let provider = CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            activeAccountId: account.id,
            accounts: [account]
        )
        let config = CodexBarConfig(
            active: CodexBarActiveSelection(providerId: provider.id, accountId: account.id),
            providers: [provider]
        )

        var configWriteAttempts = 0
        let service = CodexSyncService(
            writeSecureFile: { data, url in
                if url == CodexPaths.configTomlURL {
                    configWriteAttempts += 1
                    if configWriteAttempts == 1 {
                        throw SyncFailure.configWriteFailed
                    }
                }
                try CodexPaths.writeSecureFile(data, to: url)
            }
        )

        XCTAssertThrowsError(try service.synchronize(config: config)) { error in
            XCTAssertEqual(error as? SyncFailure, .configWriteFailed)
        }

        XCTAssertEqual(try Data(contentsOf: CodexPaths.authURL), originalAuth)
        XCTAssertEqual(try Data(contentsOf: CodexPaths.configTomlURL), originalToml)
    }

    func testSynchronizePreservesChatGPTAuthAndServiceTierWhenAggregateModeIsEnabled() throws {
        try CodexPaths.ensureDirectories()
        try CodexPaths.writeSecureFile(
            Data(
                """
                service_tier = "fast"
                preferred_auth_method = "chatgpt"
                model = "gpt-5.4-mini"
                """.utf8
            ),
            to: CodexPaths.configTomlURL
        )

        let account = CodexBarProviderAccount(
            id: "acct_pool",
            kind: .oauthTokens,
            label: "pool@example.com",
            email: "pool@example.com",
            openAIAccountId: "acct_pool",
            accessToken: "access-pool",
            refreshToken: "refresh-pool",
            idToken: "id-pool"
        )
        let provider = CodexBarProvider(
            id: "openai-oauth",
            kind: .openAIOAuth,
            label: "OpenAI",
            activeAccountId: account.id,
            accounts: [account]
        )
        let config = CodexBarConfig(
            active: CodexBarActiveSelection(providerId: provider.id, accountId: account.id),
            openAI: CodexBarOpenAISettings(accountUsageMode: .aggregateGateway),
            providers: [provider]
        )

        try CodexSyncService().synchronize(config: config)

        let authText = try String(contentsOf: CodexPaths.authURL, encoding: .utf8)
        let tomlText = try String(contentsOf: CodexPaths.configTomlURL, encoding: .utf8)

        XCTAssertTrue(authText.contains(#""auth_mode" : "chatgpt""#))
        XCTAssertTrue(authText.contains("access-pool"))
        XCTAssertFalse(authText.contains("codexbar-local-gateway"))
        XCTAssertTrue(tomlText.contains(#"model_provider = "ccodexr-openai-gateway""#))
        XCTAssertTrue(tomlText.contains(#"[model_providers.ccodexr-openai-gateway]"#))
        XCTAssertTrue(tomlText.contains(#"base_url = "http://localhost:1456/v1""#))
        XCTAssertTrue(tomlText.contains("requires_openai_auth = true"))
        XCTAssertTrue(tomlText.contains("supports_websockets = false"))
        XCTAssertTrue(tomlText.contains(#"service_tier = "fast""#))
        XCTAssertFalse(tomlText.contains("preferred_auth_method"))
        XCTAssertFalse(tomlText.contains("openai_base_url"))
    }

    func testSynchronizeWritesManagedCustomProviderBlockForCompatibleProvider() throws {
        try CodexPaths.ensureDirectories()

        let account = CodexBarProviderAccount(
            id: "acct_custom",
            kind: .apiKey,
            label: "Default",
            apiKey: "sk-test-custom"
        )
        let provider = CodexBarProvider(
            id: "provider-custom",
            kind: .openAICompatible,
            label: "My Relay",
            baseURL: "https://example.invalid/v1",
            activeAccountId: account.id,
            accounts: [account]
        )
        let config = CodexBarConfig(
            active: CodexBarActiveSelection(providerId: provider.id, accountId: account.id),
            providers: [provider]
        )

        try CodexSyncService().synchronize(config: config)

        let authText = try String(contentsOf: CodexPaths.authURL, encoding: .utf8)
        let tomlText = try String(contentsOf: CodexPaths.configTomlURL, encoding: .utf8)

        XCTAssertTrue(authText.contains(#""OPENAI_API_KEY" : "sk-test-custom""#))
        XCTAssertTrue(tomlText.contains(#"model_provider = "ccodexr-compatible""#))
        XCTAssertTrue(tomlText.contains(#"[model_providers.ccodexr-compatible]"#))
        XCTAssertTrue(tomlText.contains(#"name = "My Relay""#))
        XCTAssertTrue(tomlText.contains(#"base_url = "https://example.invalid/v1""#))
        XCTAssertTrue(tomlText.contains(#"env_key = "OPENAI_API_KEY""#))
        XCTAssertTrue(tomlText.contains(#"wire_api = "responses""#))
        XCTAssertTrue(tomlText.contains("supports_websockets = false"))
        XCTAssertFalse(tomlText.contains("openai_base_url"))
    }

    private enum SyncFailure: Error, Equatable {
        case configWriteFailed
    }
}
