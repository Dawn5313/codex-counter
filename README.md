# CodexAppBar

A macOS menu bar app for switching Codex providers and accounts without breaking your shared Codex session history.

CodexAppBar is designed for people who use:

- OpenAI OAuth accounts for Codex quota tracking
- custom OpenAI-compatible providers
- multiple API keys under the same provider
- one shared `~/.codex` session pool with Codex Desktop

It updates the active Codex provider/account for new sessions while leaving existing session history in place.

## Highlights

- OpenAI OAuth account management for Codex
- Custom OpenAI-compatible provider support
- Multiple API-key accounts per provider
- Provider/account switching for new Codex sessions
- Shared `~/.codex` session history with Codex Desktop
- Local cost and token history from Codex session logs
- Daily breakdown plus all-time totals
- OpenAI quota tracking for OAuth-backed accounts

## What It Does

CodexAppBar keeps its own config in `~/.codexbar/config.json`, then synchronizes the currently selected provider/account into:

- `~/.codex/config.toml`
- `~/.codex/auth.json`

It does **not** move or split your Codex sessions. That means:

- Codex Desktop keeps using the same `~/.codex/sessions`
- old sessions stay resumable
- switching provider only changes future requests

## What It Does Not Bundle

CodexAppBar does **not** ship with any private providers, API keys, or preconfigured accounts.

You bring your own:

- provider base URLs
- API keys
- OpenAI OAuth accounts

The app can import what already exists on your machine, but the repository itself does not hard-bind any personal provider setup.

## Current OAuth Flow

OpenAI OAuth uses a browser-based flow with manual callback completion:

1. Click `Login OpenAI`
2. Open the generated authorization link in your browser
3. Finish authorization
4. When the browser lands on `http://localhost:1455/auth/callback?...`, copy the full URL
5. Paste that URL back into CodexAppBar
6. CodexAppBar exchanges the code and imports the account

This avoids depending on a fragile localhost callback race with other processes.

## Cost And Billing Notes

Cost history is derived from local Codex session logs under `~/.codex/sessions` and `~/.codex/archived_sessions`.

- Token totals are based on Codex session log events.
- Cost is an estimate derived from model pricing.
- For custom OpenAI-compatible providers, the displayed dollar value may differ from your provider's real billing unless their pricing matches OpenAI.

If you care about exact provider-side billing, treat the cost section as a usage estimate rather than an invoice.

## Requirements

- macOS 13+
- [Codex Desktop / CLI](https://github.com/openai/codex)
- Xcode 15+ to build locally

## Build

```sh
git clone https://github.com/lizhelang/codexappbar.git
cd codexappbar
open codexBar.xcodeproj
```

Then:

1. Select your signing team in Xcode
2. Build and run the `codexBar` target

## Roadmap

- Better provider-specific pricing configuration
- Cleaner provider/account billing attribution
- Improved OpenAI account import from existing Codex auth
- More polished detached settings windows

## Acknowledgements

CodexAppBar was built with ideas and adapted implementation from these MIT-licensed projects:

- [xmasdong/codexbar](https://github.com/xmasdong/codexbar)
- [steipete/CodexBar](https://github.com/steipete/CodexBar)

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attribution details.

## License

[MIT](LICENSE)

