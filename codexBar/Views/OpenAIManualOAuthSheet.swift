import SwiftUI

struct OpenAIManualOAuthSheet: View {
    let authURL: String
    let isAuthenticating: Bool
    let errorMessage: String?
    @Binding var callbackInput: String
    let onComplete: (String) -> Void
    let onOpenBrowser: () -> Void
    let onCopyLink: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.openAIOAuthTitle)
                .font(.headline)

            Text(L.openAIOAuthStep1)
                .font(.system(size: 12))
            Text(L.openAIOAuthStep2)
                .font(.system(size: 12))
            Text(L.openAIOAuthStep3)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            ScrollView {
                Text(authURL.isEmpty ? L.authorizationLinkNotReady : authURL)
                    .textSelection(.enabled)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 72)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.08))
            )

            HStack {
                Button(L.openBrowser, action: onOpenBrowser)
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(L.openBrowser)
                    .accessibilityIdentifier("codexbar.oauth.open-browser")
                Button(L.copyLink, action: onCopyLink)
                    .buttonStyle(.bordered)
                    .accessibilityLabel(L.copyLoginLink)
                    .accessibilityIdentifier("codexbar.oauth.copy-link")
            }

            TextEditor(text: $callbackInput)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 110)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .accessibilityLabel(L.oauthCallbackInputLabel)
                .accessibilityIdentifier("codexbar.oauth.callback-input")
                .accessibilityHint(L.oauthCallbackInputHint)

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }

            HStack {
                Spacer()
                Button(L.cancel) {
                    onCancel()
                }
                .accessibilityLabel(L.cancelLogin)
                .accessibilityIdentifier("codexbar.oauth.cancel")
                Button(L.completeLogin) {
                    onComplete(callbackInput)
                }
                .buttonStyle(.borderedProminent)
                .disabled(callbackInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isAuthenticating)
                .accessibilityLabel(L.completeLogin)
                .accessibilityIdentifier("codexbar.oauth.complete-login")
            }
        }
        .padding(16)
        .frame(width: 520)
    }
}
