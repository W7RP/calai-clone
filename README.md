# Calorie tracker

Native SwiftUI calorie tracker for iOS 26+. Log food by barcode scan, photo, or manual entry. AI estimates are bring-your-own: sign in with ChatGPT (uses your plan) or paste your own Claude, OpenAI, Gemini or OpenAI-compatible key. No subscription, no backend.

## Docs
- `docs/spec.md`: what the app does and what it doesn't
- `docs/architecture.md`: modules, data model, build phases
- `docs/openai-signin.md`: ChatGPT sign-in flow and its limits
- `docs/ai-providers.md`: provider layer, prompt, schema, validation and retry
- `docs/open-questions.md`: unresolved decisions
- `docs/testing-on-iphone.md`: getting a build onto the phone

## Rules
- No bundled keys or secrets. The ChatGPT token set and any pasted keys live only in the Keychain.
- Never log tokens, API keys or request bodies. Keys go in headers, never URLs.
- iOS 26+, Swift 6 strict concurrency, SwiftUI + SwiftData. No third-party packages without a real reason.
- Metric units by default.
- AI numbers are estimates. Every AI-produced entry is shown for review and is editable before it's saved.

## Building
The Xcode project is generated from `project.yml` by XcodeGen and isn't committed. On a Mac: `brew install xcodegen && xcodegen generate`, then open `CalorieTracker.xcodeproj`.

CI (`.github/workflows/build.yml`) builds an unsigned `.ipa` on every PR and push to `main` and uploads it as an artifact. macOS minutes count 10x on a private repo, so keep it to one job.
