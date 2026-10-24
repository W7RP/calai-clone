# Open questions

Resolve these deliberately; don't let a coding agent pick silently.

1. **Mac access.** Xcode only runs on macOS. Do I have a Mac? If not: rent a cloud Mac, borrow one, or change approach (cross-platform framework, with signing and sideloading from Windows via a tool like Sideloadly or AltStore). The skills and docs in this kit assume native SwiftUI.
2. **Can OAuth work on iOS?** Loopback listener vs. paste-back vs. Mac helper. Answered by Phase 0.
3. **Does registration work for a personal app?** Try dynamic registration in Phase 0. If it's refused, ChatGPT sign-in is out, but AI logging still works through a user-supplied Claude, OpenAI, Gemini or OpenAI-compatible key (decided 2026-10-24).
4. **Apple developer account.** Free (7-day re-sign) or paid (1 year)?
5. **Which model?** Each provider has a suggested default and Settings can list the account's models. Still to do: compare providers on the same real meal and label photos before recommending one in the README.
6. **Structured output on the ChatGPT route.** The client sends `text.format` and falls back to prompt-only JSON if the route rejects it, so either way works. Note which one happens on the first device test.
7. **Barcode coverage.** Test Open Food Facts on the groceries I actually buy in Quebec; decide if a backup source is needed.
8. **HealthKit.** Write calories to Apple Health, yes or no?
9. **Open source.** Licence, name (the repo says "calai-clone"; Cal AI is someone else's product name), and what to strip from the docs before the repo goes public. See `open-source-checklist.md`.
