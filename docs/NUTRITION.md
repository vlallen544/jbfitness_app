# Food diary and nutrition

Open **Today → Open food diary**. Log breakfast, lunch, dinner and snacks by selecting a saved food or USDA search result and entering its edible weight in grams. Customers can also create private foods from known label/recipe values per 100 g. No foods, meals or recommended targets are silently invented or seeded.

## Implemented

- Daily energy, protein, carbohydrates, fat, fiber, sugar and sodium totals; nutrient units are kcal, grams and sodium milligrams.
- Food label entry with a source/reference note. Calories, protein, carbohydrates and fat are required; optional nutrients can remain unknown.
- Reusable saved foods and optional USDA search/import, with source provenance retained.
- Decimal gram quantities with a live energy preview, meal grouping, quantity/meal edits and removal with confirmation.
- Date selection and persisted diary history, using the server's Asia/Kolkata calendar. Future dates and dates before 2020 are rejected.
- User-entered daily targets and neutral above/below comparisons. Targets start today and carry forward until changed; earlier dates retain their applicable target. The app does not generate or prescribe a calorie deficit or macro target.
- Active membership gates writes. Expiry preserves customer-owned diary reads.

Photo/text AI meal estimation is implemented as a separate editable review flow; live use requires backend provider configuration. These values are estimates, not verified food-database records. See [MEAL_ESTIMATES.md](MEAL_ESTIMATES.md). Barcode scanning, serving/cup conversion, recipe calculation, AI meal recommendations and trainer nutrition-management screens remain follow-up work, as do individual timezones and offline queuing.

## Calculations and unknown data

For each nutrient: `per100g × grams / 100`. Calculations use the stored food snapshot; daily totals sum values before rounding to two decimal places. Display rounding never replaces the stored per-100-g data.

Optional missing values remain `null`. Each daily nutrient total returns `{known,complete,missingEntries}`. If any food lacks that nutrient, Flutter labels the known subtotal **At least …** and displays the number of incomplete entries. It does not claim that missing fiber, sugar or sodium is zero or compare an incomplete subtotal as a complete daily target result. An empty day has zero recorded intake.

Each meal entry contains a snapshot of its food, source and nutrients. Changing a source record later cannot recalculate historical meals. Grams are positive, up to 10,000 per entry, with at most two decimal places. Per-day entry count is capped at 200; saved foods at 1,000 per customer. These are software input limits, not dietary guidance.

## Data source and configuration

[USDA FoodData Central API guide](https://fdc.nal.usda.gov/api-guide/) and [official data documentation](https://fdc.nal.usda.gov/data-documentation/) are the provider references. FoodData Central data are CC0; source attribution is retained and displayed. API access needs a key configured as `USDA_API_KEY` in the backend environment. No key is included in mobile builds, response payloads, source provenance or committed configuration.

Without a key, label-based logging and saved foods remain usable; the picker explicitly identifies live database search as not connected. No account or key was provisioned automatically. A two-request development smoke check with USDA's public `DEMO_KEY` verified real food search and full-detail normalization; this did not configure live search for customers or use a private client key.

The adapter searches Foundation, SR Legacy and Survey/FNDDS foods, then fetches full details. It uses food composition `foodNutrients` per 100 g, never per-serving `labelNutrients`. Nutrient IDs: energy 1008, with 2047/2048 fallbacks; protein 1003; carbohydrates 1005; fat 1004; fiber 1079; sugars 2000/1063; sodium 1093. Units are checked. Missing required core nutrients reject an import rather than becoming zero. Branded foods and their serving/volume ambiguities are not imported in this milestone. Food names preserve preparation details so the customer can match raw/cooked state.

Imported USDA foods are cached per customer with source ID, data type, retrieval time and public source URL. Importing the same ID reuses that saved food; automatic provider refresh is not implemented. Provider calls have an eight-second timeout and generic failures that do not expose keys. Search failures retain local results. Search caching/rate limiting and Indian-food coverage assessment remain launch integration work.

## API and persistence

All routes use authenticated customer identity; submitted owner IDs are rejected by strict schemas.

| Method | Route | Use |
| --- | --- | --- |
| GET | `/api/v1/me/nutrition?date=YYYY-MM-DD` | Entries, totals, targets, server calendar and edit permission. Omit date for today. |
| GET | `/api/v1/me/nutrition/foods?q=…` | Saved food matches and optional USDA search results. |
| POST | `/api/v1/me/nutrition/foods` | `{name,sourceNote,nutrients,requestId}` creates a private label food. |
| POST | `/api/v1/me/nutrition/foods/usda/:fdcId` | Empty object imports a provider food after fetching full details. |
| POST | `/api/v1/me/nutrition/entries` | `{foodId,date,meal,grams,requestId}` logs a food snapshot. |
| PUT | `/api/v1/me/nutrition/entries/:id` | `{grams,meal,revision,requestId,deleted?}` edits or removes an entry. |
| PUT | `/api/v1/me/nutrition/targets` | `{date,nutrients,revision,requestId}` saves targets for the current server date. |

Migration `005_nutrition.sql` adds owner-scoped foods, versioned meal entries and dated target records. Removals use tombstones; account deletion cascades. Food/entry creation references deduplicate retries and reject reused references with different payloads. Row locks and revisions protect edits/removals; target writes use a customer-row lock and today's revision (zero when inheriting an earlier target). A date mismatch on target save requires refresh, protecting midnight retries. A day read uses a repeatable-read snapshot for consistent entries/targets/totals.

Flutter preserves the same save reference for transient retry failures. Failed writes do not appear as successful food logs. Conflicts require refresh. Offline storage, queued mutations and restoring pending retries after app termination are not implemented.

## Verification

- 47 passing database-backed integration checks across the project, including food provenance, calculations, unknown values, snapshots, strict input, ownership, duplicate creation, edit/delete revisions, target history, provider mapping/outage, restart and expiry behavior.
- 28 passing Flutter tests, including logging/editing/removing, label validation, null optional values, enlarged-text read-only layout and target retries.
- Clean Flutter analysis, successful API compilation and Flutter web build.
- Provider mapping tests use controlled fixtures; the public USDA demo smoke check verifies real search/details separately. Native device testing remains pending.

`scripts/browser-nutrition-preview.mjs` uses sample API responses to inspect the diary, picker, portion preview and saved daily totals. It does not replace database integration or native testing.
