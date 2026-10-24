# Architecture

SwiftUI + SwiftData, iOS 26+, Swift 6 strict concurrency. No backend.

## Layout
```
CalorieTracker/
  App/                 app entry, root navigation, dependency container
  Auth/                OpenAI sign-in: PKCE, loopback listener, token store (Keychain), refresh
  AI/                  estimator (prompt, schema, validation, retry), image prep
    LLM/               provider-neutral request/client protocol, JSON builder, schema renderer, settings
    Providers/         ChatGPT (Responses, streaming), Anthropic, OpenAI, Gemini, OpenAI-compatible
  Food/
    Barcode/           VisionKit DataScannerViewController wrapper
    OpenFoodFacts/     product lookup client + mapping to FoodItem
    Photo/             camera / PhotosPicker, image downscaling before upload
  Storage/             SwiftData models, queries, CSV export
  Features/
    Today/             day view
    AddFood/           the three logging flows + review screen
    History/           trends
    Settings/          goals, AI provider (keys, model, test), ChatGPT connection, export
  Shared/              small UI components, formatters, units
  Assets.xcassets/     app icon (drawn by scripts/make_app_icon.py)
CalorieTrackerTests/
scripts/               make_app_icon.py
```

## Data model (SwiftData)
- `FoodItem`: id, name, brand?, barcode?, kcalPer100g, proteinPer100g, carbsPer100g, fatPer100g, servingGrams?, source (`off`, `ai`, `manual`)
- `LogEntry`: id, date, meal, foodName, grams, kcal, protein, carbs, fat, source, `foodItem?` (relationship), `aiConfidence?`
- `DailyGoal`: kcal, protein, carbs, fat, effective-from date
- Entries snapshot their numbers so editing a cached `FoodItem` later doesn't rewrite history.

## Key decisions
- Barcode data comes from Open Food Facts (free, no key). USDA FoodData Central is the backup if coverage is poor, but it needs a free key, so decide when we get there.
- AI is provider-agnostic (`LLMClient`). Each provider gets the same prompt and schema; see `ai-providers.md`.
- Images are downscaled (1568 px long edge) and JPEG-compressed before upload, with metadata stripped. The ChatGPT route is streaming-only, so that client parses SSE and assembles the final JSON.
- AI output is requested as schema-constrained JSON where the provider supports it, and always validated on decode and for physical plausibility. A bad answer is sent back once for repair; after that it's an error state, never a silent partial entry. Providers that reject the schema field are retried without it automatically.
- One `AuthSession` actor owns tokens and refresh so concurrent requests can't race a rotating refresh token.

## Phases
Commit at the end of each. Don't start the next until the current one runs on my phone.

0. **OAuth spike.** Throwaway or minimal app. Complete sign-in on a real iPhone, get an access token with `chatgpt.tokens.use.direct`, make one streaming Responses call with text, then one with an image. Decide between the loopback listener and the paste-back fallback (see `openai-signin.md`). If this fails, stop and revisit the plan; everything else is ordinary iOS work.
1. **Skeleton + manual entry.** SwiftData models, Today view, manual add/edit/delete, goals.
2. **Barcode.** Scanner, Open Food Facts lookup, caching, not-found fallback.
3. **AI photo and text.** Review screen, JSON parsing, error states, usage display.
4. **Polish.** History charts, CSV export, copy-yesterday, settings, accessibility pass.
5. **Optional.** HealthKit, widget, App Intent.

## Testing
Unit tests only where there's real logic: PKCE generation, token refresh and expiry handling, JSON parsing of model output, Open Food Facts mapping, nutrition math. UI is checked by hand on device.

## Running on device
No App Store, so this is a dev-signed build on my own phone. A free Apple ID provisioning profile expires after 7 days and needs a re-install; the paid developer program lasts a year. Building needs Xcode on macOS (see open questions).
