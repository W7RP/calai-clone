# Architecture

SwiftUI + SwiftData, iOS 26+, Swift 6 strict concurrency. No backend.

## Layout
```
CalorieTracker/
  App/                 app entry, root navigation, dependency container
  Auth/                OpenAI sign-in: PKCE, loopback listener, token store (Keychain), refresh
  AI/                  Responses API client (streaming), prompts, response parsing
  Food/
    Barcode/           VisionKit DataScannerViewController wrapper
    OpenFoodFacts/     product lookup client + mapping to FoodItem
    Photo/             camera / PhotosPicker, image downscaling before upload
  Storage/             SwiftData models, queries, CSV export
  Features/
    Today/             day view
    AddFood/           the three logging flows + review screen
    History/           trends
    Settings/          goals, ChatGPT connection status and usage, export
  Shared/              small UI components, formatters, units
CalorieTrackerTests/
```

## Data model (SwiftData)
- `FoodItem`: id, name, brand?, barcode?, kcalPer100g, proteinPer100g, carbsPer100g, fatPer100g, servingGrams?, source (`off`, `ai`, `manual`)
- `LogEntry`: id, date, meal, foodName, grams, kcal, protein, carbs, fat, source, `foodItem?` (relationship), `aiConfidence?`
- `DailyGoal`: kcal, protein, carbs, fat, effective-from date
- Entries snapshot their numbers so editing a cached `FoodItem` later doesn't rewrite history.

## Key decisions
- Barcode data comes from Open Food Facts (free, no key). USDA FoodData Central is the backup if coverage is poor, but it needs a free key, so decide when we get there.
- Images are downscaled and JPEG-compressed before upload; the Responses API route here is streaming-only, so the client parses SSE and assembles the final JSON.
- AI output is requested as strict JSON and validated on decode. A decode failure is an error state, never a silent partial entry. Whether schema-constrained output works on this route is untested; check in Phase 0.
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
