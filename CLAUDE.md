# Calorie tracker (iOS, personal use)

Native SwiftUI calorie tracker for my own iPhone. Three ways to log food: barcode scan, photo, manual entry. AI calls run on my ChatGPT plan through Sign in with ChatGPT (OAuth). Not going on the App Store.

Read these before doing anything non-trivial:
- `docs/spec.md` — what the app does and what it doesn't
- `docs/architecture.md` — modules, data model, build phases
- `docs/openai-signin.md` — OAuth flow, Responses API limits, known iOS risk
- `docs/open-questions.md` — unresolved decisions; don't silently pick one

## Hard rules
- No API keys anywhere (no `OPENAI_API_KEY`, no bundled secrets). The only credential is the OAuth token set, stored in the Keychain.
- Never log tokens, refresh tokens, or ID tokens.
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
Fill in once the Xcode project exists (build, test, run on device).

Commit format, README tone, comment style, and test policy come from my global `~/.claude/CLAUDE.md`; don't restate them here.
