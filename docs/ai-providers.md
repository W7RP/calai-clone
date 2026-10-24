# AI providers

The app never ships a key. The user picks one provider in Settings → AI provider and brings their own account or key.

| Provider | Auth | Endpoint | Structured output | Suggested model (2026-10-24) |
|---|---|---|---|---|
| ChatGPT plan | Sign in with ChatGPT (OAuth) | Responses API, `stream: true`, `store: false` | `text.format` json_schema, falls back to prompt-only | picked from the account's list |
| Claude | Anthropic API key (`x-api-key`) | `POST /v1/messages`, `anthropic-version: 2026-10-21` | `output_config.format` json_schema | `claude-opus-5-5` |
| OpenAI | API key (Bearer) | `POST /v1/responses`, `store: false` | `text.format` json_schema, strict | `gpt-6-sol` |
| Gemini | AI Studio key (`x-goog-api-key` header) | `POST /v1beta/models/{model}:generateContent` | `responseSchema` (OpenAPI dialect) | `gemini-3.8-flash` |
| OpenAI-compatible | optional Bearer key | `POST {base}/chat/completions` | `response_format` json_schema → json_object → none | none, user picks |

Suggested models are only starting points; "Load available models" lists what the key can use. Cheaper choices that still read photos well: `claude-haiku-5-5`, `gpt-6-luna`, a Gemini flash-lite model. For Claude Opus 5.5, Fable 5.x and Sonnet 5.5 the request also turns on server-side refusal fallback (`fallbacks: "default"`, beta `server-side-fallback-2026-07-01`), so a false-positive safety decline reruns on another model instead of failing.

## Layout
- `AI/LLM/LLMClient.swift`: `LLMRequest` (system, messages, schema), `LLMClient`, `HTTPTransport` (the test seam).
- `AI/LLM/JSONValue.swift`: ordered JSON builder. Request bodies are built with it so schema properties keep their order (`analysis` is generated before the numbers).
- `AI/LLM/OutputSchema.swift`: one schema tree, rendered as JSON Schema or Gemini's dialect. All fields required, objects closed, no nulls or numeric bounds, so every provider accepts it.
- `AI/Providers/*`: one file per provider. Each maps its own stop reasons and errors to `AIError`.
- `AI/FoodPrompt.swift`: the prompt and schema. `AI/FoodEstimator.swift`: orchestration.

## What the estimator does
1. Sends the photo (if any) first, then the text, with the shared system prompt and schema.
2. Transient errors (rate limit, overloaded, 5xx, network) are retried twice with backoff (1.5 s, 4 s). Key, quota and model errors are not.
3. A cut-off answer is retried once.
4. The reply is decoded strictly, then checked by `EstimateValidator`:
   - hard: more than 9.3 kcal/g, protein+carbs+fat heavier than the item, energy without weight, over 4 kg or 6000 kcal for one item, over 30 items. The bad answer and the problem go back to the model once; if it's still wrong, the user sees an error.
   - soft: kcal more than 25 % (and 40 kcal) away from 4/4/9 Atwater. Shown as a warning on the review screen.
5. Empty items show the model's note ("No food in the photo").

Nothing is saved without the review screen. The model's `analysis` is shown there under "How this was estimated".

## Prompt choices
- Label vs plate: label values are read exactly and scaled to the amount eaten; bilingual Canadian labels are spelled out.
- Portions: edible cooked weight, with concrete scale references (plate, bowl, fork, can) and depth, not just area. A stated amount overrides the photo.
- Hidden energy (oil, butter, dressing, sugar in drinks) is listed as its own item when likely over ~40 kcal.
- Confidence has explicit criteria so "high" means something.

## Privacy
Photos are re-encoded, which drops EXIF including GPS. Keys and tokens are in the Keychain (`ThisDeviceOnly`), never logged, never in URLs. The settings screen only ever shows a masked key.

## Adding a provider
Write a struct conforming to `LLMClient` that takes an `HTTPTransport`, map its errors through `AIError.fromProviderHTTP` (or its own codes), add a case to `ProviderKind` and `LLMClientFactory`, and add mocked-transport tests like the ones in `AIProviderTests.swift`. If it speaks `/chat/completions`, the OpenAI-compatible option already covers it.
