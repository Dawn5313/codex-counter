import Foundation
import XCTest

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(self.request)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        } catch {
            self.client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

class CodexBarTestCase: XCTestCase {
    private var originalHome: String?
    private var temporaryHome: URL?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.temporaryHome = tempDir
        self.originalHome = ProcessInfo.processInfo.environment["CODEXBAR_HOME"]
        setenv("CODEXBAR_HOME", tempDir.path, 1)
        MockURLProtocol.handler = nil
    }

    override func tearDownWithError() throws {
        if let originalHome {
            setenv("CODEXBAR_HOME", originalHome, 1)
        } else {
            unsetenv("CODEXBAR_HOME")
        }

        if let temporaryHome {
            try? FileManager.default.removeItem(at: temporaryHome)
        }
        MockURLProtocol.handler = nil
        try super.tearDownWithError()
    }

    func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func makeJWT(payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let header = Data(#"{"alg":"none","typ":"JWT"}"#.utf8)
        return "\(self.base64URL(header)).\(self.base64URL(data)).signature"
    }

    func makeOAuthAccount(
        accountID: String,
        email: String,
        refreshToken: String? = nil,
        isActive: Bool = false,
        planType: String = "plus",
        localAccountID: String? = nil
    ) throws -> TokenAccount {
        let resolvedLocalAccountID = localAccountID ?? accountID
        let resolvedUserID: String
        if let userComponent = resolvedLocalAccountID.split(separator: "__").first, userComponent.hasPrefix("user-") {
            resolvedUserID = String(userComponent)
        } else {
            resolvedUserID = "user-\(resolvedLocalAccountID)"
        }
        let accessToken = try self.makeJWT(
            payload: [
                "exp": Date(timeIntervalSinceNow: 3_600).timeIntervalSince1970,
                "https://api.openai.com/auth": [
                    "chatgpt_account_id": accountID,
                    "chatgpt_account_user_id": resolvedLocalAccountID,
                    "chatgpt_user_id": resolvedUserID,
                    "user_id": resolvedUserID,
                    "chatgpt_plan_type": planType,
                ],
            ]
        )
        let idToken = try self.makeJWT(
            payload: [
                "email": email,
                "https://api.openai.com/auth": [
                    "chatgpt_subscription_active_until": "2026-12-31T00:00:00Z",
                ],
            ]
        )
        var account = AccountBuilder.build(
            from: OAuthTokens(
                accessToken: accessToken,
                refreshToken: refreshToken ?? "refresh-\(accountID)",
                idToken: idToken
            )
        )
        account.isActive = isActive
        return account
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
