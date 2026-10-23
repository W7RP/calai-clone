# Open questions

Resolve these deliberately; don't let a coding agent pick silently.

1. **Mac access.** Xcode only runs on macOS. Do I have a Mac? If not: rent a cloud Mac, borrow one, or change approach (cross-platform framework, with signing and sideloading from Windows via a tool like Sideloadly or AltStore). The skills and docs in this kit assume native SwiftUI.
2. **Can OAuth work on iOS?** Loopback listener vs. paste-back vs. Mac helper. Answered by Phase 0.
3. **Does registration work for a personal app?** Try dynamic registration in Phase 0. If it's refused, the AI features need another route (own API key is ruled out, so the fallback would be a different provider or manual-only).
4. **Apple developer account.** Free (7-day re-sign) or paid (1 year)?
5. **Which model?** Check the models-and-inference docs and test vision quality on real meal and label photos before committing.
6. **Structured output.** Does schema-constrained JSON work on this route, or do we parse free-form JSON and validate?
7. **Barcode coverage.** Test Open Food Facts on the groceries I actually buy in Quebec; decide if a backup source is needed.
8. **HealthKit.** Write calories to Apple Health, yes or no?
