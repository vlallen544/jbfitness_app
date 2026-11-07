# Approximate meal estimates

Open **Today → Open food diary → Estimate from photo or text**. Describe a dish, upload a photo, or use both. On mobile, camera capture is also available. Nothing is sent for analysis until **Estimate meal** is tapped.

For example, a customer enters “a bowl of cooked rice and dal.” AI proposes foods, approximate grams and nutrients, and explains assumptions about bowl size and oil. The customer changes rice from 150 g to 200 g, checks the recalculated total, selects a meal and explicitly saves. Uploading or receiving a draft never logs food automatically.

## What is implemented

- Editable food names, grams and nutrient values; remove unwanted components before saving.
- Approximate calories, protein, carbohydrates, fat and available fiber, sugars and sodium. Unknown optional nutrients remain unknown.
- Qualitative uncertainty and assumptions, with clarification only when a useful estimate cannot be made. Uncertainty is not a calibrated accuracy score.
- Saved entries retain **AI estimate** provenance after edits; daily totals show when estimates are included. Nutrient densities come from the model, not verified USDA records.
- Active membership checks, customer isolation, validated output, a 24-hour draft access window and atomic, duplicate-safe diary saves.
- Photo/text analysis and save retries use separate references. Failed save retries retain the reviewed payload. Analysis is never automatically retried against the provider.

## Activation

In the API's ignored environment configuration, set `ENABLE_MEAL_AI=true`, `OPENAI_API_KEY` and `MEAL_AI_MODEL`. Select a model supporting image input and strict structured outputs. No model is silently selected; the feature reports unavailable while configuration is missing. Credentials stay on the server. Restart the API after configuration changes.

The implementation uses the [OpenAI Responses image-input format](https://developers.openai.com/api/docs/guides/images-vision) and [strict structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs). It makes one bounded request with a 45-second provider timeout and no external tools. Do not enable customers until representative dishes, portion uncertainty, Indian-food coverage, cost and latency have been evaluated.

## Limits and data handling

- Provisional limit: 10 analysis attempts per active customer per Asia/Kolkata day, including failed attempts. Cached retries of the same successful request do not call the model again. Confirm this allowance before launch.
- One pending analysis per customer, with a two-minute stale-pending window. New analysis requires a new request reference after a failed attempt.
- Photos: JPEG, PNG or WebP, up to 4 MB and 16 million decoded pixels, single frame. The server corrects orientation, resizes within 1,600 pixels and encodes JPEG without original metadata.
- Uploaded photo bytes and the original description are not persisted by this feature. Hashes, generated drafts, model identifiers and token usage are stored. The mobile picker may retain its own temporary file cache; this is not a guarantee of zero device storage.
- Photo/text content is transmitted to the configured AI provider for analysis. `store:false` disables stored Responses application state; it does not guarantee zero provider retention. Review provider account data controls and disclose this processing before launch.
- Draft expiry blocks new saves after 24 hours. It is not automatic database deletion; a retention cleanup policy remains launch work. Existing saved diary entries remain available under normal diary rules.
- At most eight meal components per estimate. Existing diary date, portion and daily-entry limits still apply. Saved estimates are snapshots; later draft changes cannot rewrite historical nutrition totals.

## API and verification

| Method | Route after `/api/v1` | Purpose |
|---|---|---|
| GET | `/me/meal-estimates/status` | Configuration, entitlement and remaining attempts |
| POST | `/me/meal-estimates` | JSON text input or multipart `description`, `requestId`, optional `photo`; returns a draft |
| POST | `/me/meal-estimates/:id/save` | Reviewed date, meal, items and a save request reference; atomically creates diary entries |

Database-backed checks cover ownership, entitlement, limits, request deduplication, actual image decoding/metadata removal, Unicode combined input, invalid uploads, structured-output rejection, expiry and duplicate-safe saves. A stubbed HTTP transport verifies the provider request format without calling OpenAI. Flutter tests cover text review, photo selection, unavailable service, editing, explicit save, retained retry references and narrow/enlarged-text layout.

Verified project totals: 56 integration checks and 32 Flutter tests pass; Flutter analysis is clean, and API compilation and the Flutter web build succeed.

`scripts/browser-meal-estimate-preview.mjs` uses a generated solid-color upload and fixture AI/API responses to inspect the real file picker and review/save flow. It cannot establish food-recognition accuracy. Live provider quality/cost and native camera/gallery behavior remain unverified; Android/iOS builds and physical-device checks are still pending.
