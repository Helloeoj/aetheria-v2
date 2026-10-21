# Sentinel explanations and personal ChatGPT connection

Sentinel now has an **Explain & chat** tab. It gives a basic local explanation
immediately and optionally talks through the selected incident using your
personal ChatGPT account.

## Connect

1. Open **Aetheria Sentinel** from the desktop shortcut. Select an incident and
   **Explain this**, or use **Explain latest** on the Companion tab.
2. On **Explain & chat**, select **Continue with ChatGPT**. In your browser,
   choose your personal ChatGPT account and review **Use your ChatGPT plan**.
   Complete sign-in yourself; Sentinel never asks you to paste passwords,
   tokens, browser cookies, or Codex credentials.
3. After permission is granted, Sentinel loads models available to that exact
   account. GPT-5.6 Sol is preferred if present; other available models remain
   selectable. No account-specific availability is assumed in advance.
4. Select **Explain with ChatGPT**, then ask follow-up questions in the composer.
   On later launches with a saved connection, use **Load models** first.

**Account sign-in is implemented, but live account authorization and model
inference still require the owner to complete this flow.** Synthetic tests do
not establish that a particular account is eligible for the preview.

## The important account/usage distinction

OpenAI supports direct ChatGPT plan usage for eligible local/open-source apps
through **Sign in with ChatGPT**. Sentinel calls the documented Responses
endpoint directly and does not invoke a Work/Codex agent or reuse their login
files.

However, OpenAI counts these requests against the allowance shared with
**ChatGPT Work and Codex**, not ordinary Chat message usage. Eligible Plus/Pro
plans and OpenAI's current account/preview policies apply. This integration
does not add another allowance. **Manage usage** opens ChatGPT's settings for
app limits and any permitted credit use. Sentinel does not enable credit
spillover, purchase credits, upgrade a plan or fall back to API-key billing.

It does not gain access to your ChatGPT conversations or memories. Follow-up
context comes from the incident and the short conversation in Sentinel.

## What leaves the computer

Monitoring, breadcrumbs and local explanations remain local. There are **no
automatic background AI requests**. Sign-in makes identity/authentication and
model-catalog requests to OpenAI. Clicking Explain with ChatGPT or sending a
follow-up sends the selected compact report, bounded incident evidence and
the necessary short conversation to OpenAI. Native raw logs and game source
files are not automatically uploaded. Local home-directory prefixes are
replaced with `<user>` in evidence sent to the model.

Inference uses `store=false` and `stream=true` as required by the plan route.
The app accepts an answer as complete only after `response.completed`;
interrupted/failed/usage-limited streams are clearly marked incomplete.
Completed initial explanations are cached in memory for the same incident
occurrence count and model, avoiding duplicate requests. Context is bounded;
analysis never executes tools or changes the game or incident resolution.

For a missing-shutdown-marker incident, both the local explanation and AI
instructions explicitly distinguish a suspected abnormal stop from a proven
native crash. Nearby equipment/monster actions are context, not a proven cause.

Local explanations lead with the affected gameplay feature and everyday meaning;
they do not repeat filenames or raw errors as an explanation. Known inventory
display, missing-file, unavailable-object, list and startup errors have conservative
translations. Unfamiliar errors explicitly remain unexplained until investigated
or discussed with ChatGPT. Applicable ADC resolution notes are shown and included
in requested AI evidence; a later occurrence does not reuse an older fix as proof.
Technical evidence remains available behind a toggle and in Copy for Codex.

## Sign-in storage and controls

ChatGPT credentials and account metadata are encrypted with Windows user DPAPI
under `%LOCALAPPDATA%/AetheriaSentinel/identity/accounts.dpapi`, outside all ADC
report folders. They are never added to logs, source control, report exports,
browser storage or the monitor's activity stream. Only a temporary loopback
callback listener is opened during sign-in; it is bound to `127.0.0.1` and closed
after completion/cancellation/timeout.

The flow uses fresh state, nonce and PKCE; validates signed ID tokens with
PyJWT against OpenAI's published signing keys; checks issuer, audience, expiry,
nonce and account identity; and verifies granted plan-usage permission.
Each account/client registration is separate. Refresh tokens rotate together
with access tokens in protected atomic writes. The opaque host ID persists
across app restarts and sign-ins.

Use **Add account**, the account picker, **Cancel**, and **Sign out** as needed.
Sign out attempts remote session revocation, clears local tokens and retains
the registration/host mapping for later sign-in. If revocation cannot be
confirmed, the interface says so and points you to ChatGPT's own settings.

The optional sign-in dependency is PyJWT with cryptographic support. PyJWT
2.15.1 is installed in the per-user Sentinel dependency directory; the existing
runtime supplies cryptography. To recreate dependencies after moving runtimes:

```powershell
./tools/setup_sentinel_chatgpt.ps1
```

Monitoring and local explanations continue if the optional sign-in dependency
is unavailable. No API key is required for this documented sign-in route.

## Validation

Automated checks use synthetic tokens, signed test JWTs, mocked OpenAI replies
and a real local callback listener. They cover DPAPI protection, stable host
identity, multiple accounts, PKCE/callback validation, identity signature and
claims, declined consent, refresh rotation, model filtering, incomplete and
usage-limited streams, request schema, sign-out failure, evidence redaction,
non-invented local explanations, UI model selection and response caching.
**37/37 integration checks passed**, including cross-process refresh locking
and the full-window chat control layout.
The existing 22 process/monitor/UI tests also passed after the integration.
Live personal-account sign-in and inference are **not yet verified** and must
not be represented as tested. No report was sent to OpenAI during validation.

Implementation: `tools/sentinel_chatgpt.py`, `sentinel_chat_panel.py`, and the
integration in `sentinel.py`. Tests: `tools/test_sentinel_chatgpt.py`.
Local evidence: the task workspace's ignored
`work/diagnostics/chatgpt-validation-final/validation.json` and
`work/diagnostics/sentinel-with-chatgpt-validation/validation.json`.

Verified official documentation (2026-10-19):

* [Sign in with ChatGPT and plan usage](https://learn.chatgpt.com/docs/sign-in-with-chatgpt)
* [Local/open-source plan-usage flow](https://developers.openai.com/siwc/token-sharing-open-source)
* [Registration and identity validation](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
* [Account-specific models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
* [Preview request limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
