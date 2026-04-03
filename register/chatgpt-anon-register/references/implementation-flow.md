# Implementation Flow

This is the rough flow used to get from a fresh anonymous relay address to a registered ChatGPT account on the same Mac.

## 1. Create a fresh relay address in System Settings

- Open `System Settings`
- Navigate to Apple Account `iCloud`
- Enter `隐藏邮件地址`
- Choose `创建新地址`
- Read the generated `@icloud.com` relay address from the creation sheet
- Fill a synthetic label and confirm the creation

Why this uses OCR:

- `System Settings` does not expose a stable public API for this flow
- its accessibility tree is inconsistent enough that plain AppleScript selectors are not reliable on their own
- OCR plus `cliclick` is a practical way to recover the correct on-screen targets

## 2. Start the site signup in a real browser

- Open `chat.com`
- Follow the free-signup entry point that lands on `chatgpt.com` / `auth.openai.com`
- Submit the fresh relay address
- Generate and submit a strong password

Why this uses Playwright CLI:

- semantic locators are more stable than screen coordinates
- the same browser session can be resumed while the verification mail is fetched
- the stop condition is easy to verify from page URL and onboarding state

## 3. Pull the verification code from Mail.app

- Trigger a mail refresh in `Mail.app`
- Inspect only recent inbox items
- Filter to OpenAI / ChatGPT verification mail
- Extract the newest six-digit code from the subject line

Why this uses AppleScript:

- it keeps the search scoped to the local mail client
- it avoids opening unrelated messages by hand
- it can be called directly from the registration shell script

## 4. Finish the account profile without real identity data

- Fill a synthetic full name
- Fill a synthetic adult birthday
- Submit the final account-creation form

Guardrail:

- this flow is only appropriate when the user explicitly wants a pseudonymous account and has asked not to use their real identity

## 5. Stop once registration is complete

Treat the registration as complete when one of these appears:

- the main ChatGPT app shell
- the onboarding question set
- an authenticated profile menu / avatar

Do not keep clicking through optional onboarding unless the user asks.

## Failure Stops

Stop and report instead of guessing when:

- the site requires phone verification
- the site asks for payment or billing setup
- the UI language changes enough to break selectors
- `System Settings` no longer exposes the expected `隐藏邮件地址` view
- the verification code mail does not arrive in the expected inbox window
