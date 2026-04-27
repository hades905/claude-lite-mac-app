# Tuzi API Integration Notes

## Verified on 2026-04-21

Base URL:

- `https://api.tu-zi.com`

Local developer config:

- `.local/tuzi-config.json`

## Working endpoints

### `GET /v1/models`

Observed behavior:

- Requires `Authorization: Bearer <model-api-key>`
- Returns a JSON object with a `data` array
- The array includes many providers and many non-Claude models
- Client-side filtering is required for a Claude-only picker

Implementation note:

- Use this endpoint for startup connectivity checks
- Use the same response to populate the model selector

### `POST /v1/messages`

Observed behavior:

- Requires `Authorization: Bearer <model-api-key>`
- Accepts Claude-style payloads with:
  - `model`
  - `messages`
  - `max_tokens` optional
  - `stream`
- A verified request to `claude-opus-4-7` returned a valid assistant message
- MCP OpenAPI checked on 2026-04-26 lists only `model` and `messages` as required; the app omits `max_tokens` so it does not impose its own 1024-token output cap

Observed response shape:

- Top-level fields include `id`, `type`, `role`, `model`, `content`, `stop_reason`, and `usage`
- `content` is an array
- Text replies appear as items like:
  - `{ "type": "text", "text": "ok" }`

Implementation note:

- The chat client should parse `content` as a typed content array, not as a single flat string

## Account endpoint note

### `GET /api/user/self`

Observed behavior:

- The provided user key alone was not enough
- The server responded that `Rix-Api-User` was missing

Implementation note:

- This endpoint is not required for the current V1 chat flow
- Keep the user key stored locally for future use, but do not block app startup on it

## Attachment risk

Current OpenAPI material clearly documents:

- `GET /v1/models`
- `POST /v1/messages`
- `POST /v1/files`

What is still unclear:

- The exact request contract for sending uploaded files or images inside Claude message requests through this gateway

Implementation approach:

- Build a stable local attachment model in the app
- Keep transport logic isolated behind an attachment adapter
- Ship working file/image picking and attachment persistence first
- Only couple final upload-to-message wiring once the gateway contract is confirmed
