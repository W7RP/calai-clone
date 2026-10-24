# Calorie tracker

Native SwiftUI calorie tracker for iOS. Log food by barcode scan, photo, or manual entry. Photo and text logging use an AI model you bring yourself: sign in with ChatGPT (uses your plan) or paste your own Claude, OpenAI, Gemini or OpenAI-compatible key. No subscription, no backend. Personal use, not on the App Store.

## Status
Phases 0 to 4 from `docs/architecture.md` are built and pass the unit tests in CI. None of it has run on a real iPhone yet, and no real provider API has been called. ChatGPT sign-in (Phase 0) is the first thing to check on a device; see `docs/open-questions.md`.

## Prerequisites
- A Mac with Xcode 26 and XcodeGen (`brew install xcodegen`)
- An iPhone on iOS 26 for device testing
- Optional: a ChatGPT account or an API key from one of the providers above

## Build and run
The Xcode project is generated from `project.yml` and isn't committed.

```
xcodegen generate
open CalorieTracker.xcodeproj
```

Pick your Personal Team under Signing, then run on the phone. `docs/testing-on-iphone.md` covers installing without a Mac.

CI (`.github/workflows/build.yml`) builds an unsigned `.ipa` on every PR and push to `main` and uploads it as an artifact. macOS minutes count 10x on a private repo, so keep it to one job.

## Test
Unit tests run on a simulator in CI. Locally, press Cmd+U in Xcode, or:

```
xcodebuild test -project CalorieTracker.xcodeproj -scheme CalorieTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

## Layout
```
CalorieTracker/
  AI/          prompt, output schema, validation, provider clients
  App/         app entry point
  Auth/        ChatGPT sign-in (OAuth with PKCE), token storage
  Features/    SwiftUI screens: Today, add food, history, settings
  Food/        barcode scanner, Open Food Facts, camera
  Shared/      Keychain, nutrition math, dates
  Storage/     SwiftData models, food cache, CSV export
CalorieTrackerTests/
docs/          spec, architecture, sign-in notes, providers, open questions
project.yml    XcodeGen spec
```

## Ground rules
- No bundled keys or secrets. The ChatGPT tokens and any pasted keys live only in the Keychain.
- Tokens, keys and request bodies are never logged. Keys go in headers, never URLs.
- iOS 26+, Swift 6 strict concurrency, SwiftUI and SwiftData, no third-party packages.
- Metric units by default.
- AI numbers are estimates. Every AI entry is shown for review and can be edited before it's saved.
