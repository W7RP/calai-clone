# Calorie tracker (iOS, personal use)

Native SwiftUI calorie tracker. Three ways to log food: barcode scan, photo, manual entry. AI is bring-your-own: the user signs in with ChatGPT (OAuth, uses their plan) or enters their own Claude, OpenAI, Gemini or OpenAI-compatible key. No subscription, no backend. Not going on the App Store.

Read these before doing anything non-trivial:
- `docs/spec.md` — what the app does and what it doesn't
- `docs/architecture.md` — modules, data model, build phases
- `docs/openai-signin.md` — OAuth flow, Responses API limits, known iOS risk
- `docs/ai-providers.md` — the provider layer, prompt, schema, validation and retry
- `docs/open-questions.md` — unresolved decisions; don't silently pick one

## Hard rules
- No bundled keys or secrets (no `OPENAI_API_KEY` in code, config or CI). Credentials are the user's own: the ChatGPT OAuth token set and any provider keys they paste in. Both live only in the Keychain.
- Never log tokens, refresh tokens, ID tokens, API keys, or request bodies. Keys go in headers, never URLs.
- Target iOS 26+, Swift 6 strict concurrency, SwiftUI + SwiftData. No third-party packages unless there's a real reason; ask first.
- Metric units by default (g, kg, ml, kcal).
- AI numbers are estimates. Every AI-produced entry is shown for review and editable before it's saved.
- Build in the phases from `docs/architecture.md`. Finish and commit a phase before starting the next. Phase 0 (OAuth spike) gates everything else.

## Skills in `.claude/skills/`
- `swiftui-pro` — run on any SwiftUI view work
- `swift-concurrency-pro` — run on auth, networking, streaming code
- `swiftdata-pro` — run on the data layer
- `swiftui-gotchas` — consult before animation, navigation, or concurrency-diagnostic work

## Commands
- The Xcode project is generated from `project.yml` by XcodeGen and is not committed. On a Mac: `brew install xcodegen && xcodegen generate`, then open `CalorieTracker.xcodeproj`.
- CI (`.github/workflows/build.yml`) builds an unsigned `.ipa` on every PR and push to `main` and uploads it as an artifact.
- No Mac is the main workstation (Windows). Builds reach the phone by sideloading with AltStore; see `docs/testing-on-iphone.md`. No paid Apple developer account, so no TestFlight.
- macOS CI minutes count 10x on this private repo: don't add jobs or matrix builds without a reason.

Commit format, README tone, comment style, and test policy come from my global `~/.claude/CLAUDE.md`; don't restate them here.
