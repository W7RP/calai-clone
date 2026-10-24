# Sign in with ChatGPT: what the docs say and what's risky

Checked against OpenAI's docs on 2026-10-23. This is a new, preview-stage feature (announced at DevDay on 2026-09-29), so re-check the pages below before building.

Sources:
- Overview: https://developers.openai.com/siwc/token-sharing-open-source
- Registration and sign-in: https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- Preview limitations: https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations
- Models and inference, token reference, errors and recovery: same path prefix
- DevKit (Node + React, macOS example only): https://github.com/openai/sign-in-with-chatgpt-devkit
- User-side help: https://help.openai.com/en/articles/20001542-using-your-chatgpt-plan-in-other-apps-and-sites

## Eligibility
The quickstart says Sign in with ChatGPT is a limited trial for selected commercial partners, while ChatGPT plan usage is available to all open-source partners and selected private clients. The documented direct flow registers a client dynamically and needs no client secret and no partner API key. The docs frame this path around open-source apps; I found no explicit rule about a personal, unreleased app. Safest assumption: publish the repo publicly (MIT, under W7RP) so it fits the open-source path. Phase 0 will show whether registration works at all.

Plan side: Go, Plus and Pro subscribers can use their plan in participating apps. Usage draws from the plan's existing allowance (shared with ChatGPT and Codex use), the user can set a per-app weekly cap in ChatGPT settings, and usage stops when the cap is hit. Heavy Codex use will eat into what the calorie app has.

## Flow (from the registration doc)
1. First sign-in: open the system browser at `https://auth.openai.com/api/accounts/authorize` with `client_id=dynamic_agent_client`, `agent_name_hint=<app name>`, `response_type=code`, `scope=openid profile email offline_access resource.invoke chatgpt.tokens.use.direct`, `resource=https://api.openai.com/v1`, plus `state`, `nonce`, and PKCE (`S256`).
   The docs also list `ext_agent_host_id`, but on 2026-10-24 auth.openai.com rejected it (`invalid_authorize_request`) and OpenAI's DevKit leaves it out unless `sendHostId` is enabled, so the app doesn't send it.
2. The callback returns `code`, `state`, and an issued `client_id` (looks like `oaiapp_...`). Save that issued ID; never use `dynamic_agent_client` for token exchange.
3. Exchange the code with a form-encoded POST to `https://auth.openai.com/api/accounts/oauth/token` (issued `client_id`, `code`, `code_verifier`, same `redirect_uri`, same `resource`). No secret.
4. Validate the ID token (JWKS signature, issuer, audience = issued client ID, expiry, nonce). Then check the granted scopes include `chatgpt.tokens.use.direct`; a valid ID token alone does not mean plan usage is enabled. `error=access_denied` means the user declined.
5. Store tokens in the Keychain. The refresh token rotates, so replace access token, expiry, scopes and refresh token together after each refresh. Keep the ID token for `id_token_hint` on later sign-ins (skips the account picker).

## The iOS problem (biggest risk)
The docs require an HTTP loopback redirect on `127.0.0.1` (not `localhost`), with the listener started before the browser opens; only the port may vary between sign-ins, and the scheme, host and path must stay fixed. The docs and DevKit target desktop apps. iOS apps normally use a custom URL scheme or universal link, which this flow does not list.

Options to test in Phase 0, in order:
1. **In-app loopback listener.** Start a small listener (Network framework) on 127.0.0.1 inside the app, open the auth URL in `ASWebAuthenticationSession` or `SFSafariViewController`, catch the redirect in the listener, dismiss the browser. Unverified: whether the browser session stays alive and the listener keeps running through the redirect.
2. **Paste-back.** Same auth URL, but let the redirect fail to load, copy the final URL (it contains `code` and `state`), and paste it into the app. Ugly but only needed at first sign-in and re-auth, and it needs no listener.
3. **Mac helper.** Do the sign-in with the DevKit's local Node SDK on a Mac and hand the tokens to the phone. Only worth it if 1 and 2 both fail, and it adds a moving part.

Do not tell the OAuth server a custom-scheme redirect and hope; redirect URIs are matched exactly.

## Responses API constraints on this route (`https://api.openai.com/v1`)
- Must send `store: false` and `stream: true`. No `previous_response_id` over HTTP; send the history you need in `input` each time.
- Use `instructions` or developer messages; explicit `system` role items are rejected.
- Don't send: `background`, `conversation`, `max_output_tokens`, `max_tool_calls`, `metadata`, `moderation`, `multi_agent`, `prompt`, `prompt_cache_retention`, `safety_identifier`, `temperature`, `top_logprobs`, `top_p`, `truncation`, `user`.
- Inputs: text, images and files work when the chosen model accepts them. Audio and video input, the Files upload API, and transcription don't work.
- Not supported: image generation, file search, code interpreter, native computer use, hosted MCP, `tool_search`. Function tools are fine; web search depends on model and account policy.
- Which model to use and how to list the available ones: see the models-and-inference page. Don't hardcode a model name without checking it.

## Errors to handle
Plan use not enabled (user declined or revoked), weekly cap reached, token expired or refresh failed, user removed the app under ChatGPT Settings > Security and login > Sign in with ChatGPT, rate limiting, network loss mid-stream. See the errors-and-recovery page for the exact codes. Each should leave the app usable for manual entry.

## Privacy
Photos of meals go to OpenAI under the user's ChatGPT account. The token only covers Responses API requests, not conversations or an API key. Don't log request bodies.
