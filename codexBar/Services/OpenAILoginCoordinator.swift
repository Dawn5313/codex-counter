import AppKit
import Foundation
import SwiftUI

extension Notification.Name {
    static let openAILoginDidSucceed = Notification.Name("lzl.codexbar.openai-login.did-succeed")
    static let openAILoginDidFail = Notification.Name("lzl.codexbar.openai-login.did-fail")
}

private struct OpenAILoginWindowView: View {
    @ObservedObject private var oauth = OAuthManager.shared

    var body: some View {
        OpenAIManualOAuthSheet(
            authURL: oauth.pendingAuthURL ?? "",
            isAuthenticating: oauth.isAuthenticating,
            errorMessage: oauth.errorMessage
        ) { input in
            oauth.completeOAuth(from: input)
        } onOpenBrowser: {
            guard let authURL = oauth.pendingAuthURL, let url = URL(string: authURL) else { return }
            NSWorkspace.shared.open(url)
        } onCopyLink: {
            guard let authURL = oauth.pendingAuthURL else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(authURL, forType: .string)
        } onCancel: {
            oauth.cancel()
            DetachedWindowPresenter.shared.close(id: OpenAILoginCoordinator.windowID)
        }
    }
}

@MainActor
final class OpenAILoginCoordinator {
    static let shared = OpenAILoginCoordinator()

    static let windowID = "oauth-login"
    static let loginURLScheme = "com.codexbar.oauth"
    static let loginHost = "login"

    private init() {}

    func start() {
        let oauth = OAuthManager.shared

        oauth.startOAuth(openBrowser: true, activate: false) { result in
            switch result {
            case .success(let completion):
                let store = TokenStore.shared
                store.load()
                Task { await WhamService.shared.refreshOne(account: completion.account, store: store) }
                DetachedWindowPresenter.shared.close(id: Self.windowID)
                NotificationCenter.default.post(
                    name: .openAILoginDidSucceed,
                    object: nil,
                    userInfo: [
                        "active": completion.active,
                        "message": completion.active
                            ? "Updated Codex configuration. Changes apply to new sessions."
                            : "Saved OpenAI account.",
                    ]
                )
            case .failure(let error):
                NotificationCenter.default.post(
                    name: .openAILoginDidFail,
                    object: nil,
                    userInfo: ["message": error.localizedDescription]
                )
            }
        }

        self.openWindow()
    }

    private func openWindow() {
        DetachedWindowPresenter.shared.show(
            id: Self.windowID,
            title: "OpenAI OAuth",
            size: CGSize(width: 560, height: 420)
        ) {
            OpenAILoginWindowView()
        }
    }
}

enum CodexBarURLRouter {
    @MainActor
    static func handle(_ url: URL) {
        guard url.scheme?.caseInsensitiveCompare(OpenAILoginCoordinator.loginURLScheme) == .orderedSame else { return }

        let host = url.host?.lowercased()
        let path = url.path.lowercased()
        if host == OpenAILoginCoordinator.loginHost || path == "/\(OpenAILoginCoordinator.loginHost)" {
            OpenAILoginCoordinator.shared.start()
        }
    }
}
