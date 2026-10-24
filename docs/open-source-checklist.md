# Before making the repo public

Nothing here has been done; it's the list of things to decide or clean up first.

## Must do
- **Licence.** Add a `LICENSE` file. MIT matches the plan in `openai-signin.md`.
- **Name.** Pick a final repo name before it's public (e.g. EasyCal). The app's display name is already "Calories".
- **Bundle ID.** `com.w7rp.calorietracker` is tied to one person. Fine for a personal fork, but document that builders should change `bundleIdPrefix` in `project.yml`, and the Keychain service names will follow.
- **Secrets scan.** History checked on 2026-10-24: no API keys or tokens found. Run GitHub secret scanning once more right before flipping visibility, since public history can't be taken back.
- **README.** Expand it with: how to pick a provider and where to get a key, what data goes where, and that AI numbers are estimates.

## Should do
- **Personal docs.** `docs/spec.md` and `docs/open-questions.md` are written in the first person about one phone and Quebec groceries. Either rewrite them for contributors or move them out.
- **Privacy note.** One page stating: no backend, no analytics, data stays on device, photos and descriptions go only to the provider the user picks, under their account.
- **Sign in with ChatGPT terms.** Re-read OpenAI's open-source partner terms; the app registers dynamically per install, so no client secret ships, but the app name hint and usage rules apply.
- **Prompt and eval set.** Publish a small set of test photos (own photos only) with expected ranges so contributors can compare providers and prompt changes.
- **CONTRIBUTING and issue templates**, and turn on branch protection for `main`.
- **CI minutes.** macOS minutes are free on public repos, so the 10x cost note in `build.yml` goes away.
