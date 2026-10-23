# Spec

## Goal
Log what I eat in a few seconds, get a calorie and macro total for the day, and have the AI do the tedious estimation. Single user, single device.

## Logging modes
1. **Barcode.** Scan with the camera, look up the product in Open Food Facts, show per-100g and per-serving values, let me set the amount, save. If the product isn't found, fall back to photo or manual entry with the barcode attached so it's cached next time.
2. **Photo.** Take or pick a photo of a meal or a nutrition label. The model returns a list of identified items with portion guesses and kcal/protein/carbs/fat per item. I review, edit, save. Label photos should read the printed values rather than estimate.
3. **Manual.** Name, amount, kcal, optional macros. Also a free-text box ("two eggs and toast with butter") that the model turns into items.

## Day view
- Calorie total vs. goal, macro totals, list of entries grouped by meal (breakfast, lunch, dinner, snack).
- Edit or delete any entry. Copy yesterday's meal.
- Weekly trend (calories and, optionally, weight) with Swift Charts.

## Data
- Everything local in SwiftData. No server, no accounts, no analytics.
- Foods I've logged before are cached so repeat items don't need a scan or an AI call.
- Export to CSV.

## AI behavior
- Input is a photo and/or text; output is a strict JSON list of items (name, grams or serving, kcal, protein, carbs, fat, confidence).
- The prompt asks the model to say when it's guessing and to use label values when a label is visible.
- Failures (plan cap reached, token expired, no network) show a clear message and leave manual entry working. The app is usable with no AI at all.

## Non-goals
App Store release, multi-user, cloud sync, social features, meal plans, a backend of any kind.

## Maybe later
HealthKit write (dietary energy), home-screen widget with today's total, Siri/App Intent for quick-add, Apple Watch glance.
