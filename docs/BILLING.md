# Membership and billing foundation

## Implemented

- Customer-authenticated `GET /api/v1/me/membership`: current and next periods, history, expiry state, session totals/completed/remaining, and effective feature entitlements.
- Immutable plan snapshots for each membership period; prices and 0/10/25 video allowances come from the server catalogue.
- PostgreSQL receipt/event records deduplicate both payment references and event IDs. Transactions lock the customer row so concurrent deliveries cannot create overlapping periods.
- Completed-call ledger deduplicates session references, checks ownership/active dates, and serializes deductions so balances cannot go negative.
- `MembershipService.requireEntitlement` is ready for future workout/AI/media endpoints. Historical profile data remains accessible without an active membership.
- Flutter Plans page: active/expired/empty/error states, dates, balance, queued renewal, history, pull-to-refresh and app-resume refresh. Network failures are not displayed as “no membership”.

## Development-only defaults — awaiting client confirmation

Each plan lasts one month. For development fixtures this means one calendar month, clamped to the last day of shorter months, preserving UTC time. Manual renewal of the same plan queues the new period after the existing period. Expired renewal starts from the new grant time. Sessions do not carry forward in these fixtures. Plan changes are rejected until upgrade/downgrade rules are agreed.

These defaults are provisional and exposed as such in the API/UI. No automatic charging exists. Real provider-confirmed billing periods may become authoritative once the provider and commercial rules are finalized.

## What is not connected

No Apple/Google/gateway adapter, receipt verification, webhook endpoint, real checkout, refunds or automatic billing is connected. Session reservations now hold credits; completion, policy-defined late cancellation and no-show outcomes consume them once. Owner policy confirmation, staff attendance and cancellation software are implemented, but actual client rules and the video provider remain unconfigured, so customer booking stays disabled. See [SESSIONS.md](SESSIONS.md).

There is deliberately no customer endpoint to declare a payment successful, activate a membership, or deduct a coaching session. An ordinary mobile request cannot grant paid access. Real billing must use a separately implemented server-verified provider adapter; the development fixture is not that adapter or a provider sandbox.

Digital feature access and one-to-one coaching require payment packaging review before implementation. Apple distinguishes real-time one-to-one fitness services from digital access; Google Play's policy generally requires its billing system for digital in-app purchases, subject to stated exceptions. See [Apple payment guidelines](https://developer.apple.com/app-store/review/guidelines/) and [Google Play payments policy](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en).

## Preview a test membership

Register a test customer in the mobile preview. Then, from the project root:

```sh
ENABLE_DEV_MEMBERSHIPS=true npm run dev:membership --workspace @jbfitness/api -- --email customer@example.test --plan premium
```

Choose `normal`, `premium`, or `premium-plus`. The command grants a development fixture to that existing customer only, using canonical prices; it collects no payment. Refresh Plans to see the result. Repeat with the same plan to preview a queued renewal.

The opt-in flag is required on the command. `NODE_ENV=production` rejects the fixture regardless of that flag. Production membership reads and entitlement checks exclude development grants. Existing test records remain labelled “no payment collected” in development.

## Verification

Database tests cover concurrent duplicate receipts/events, mismatched references/prices, inherited benefits, 10/25 total allowances, duplicate and concurrent completed calls, early renewal, expiry, new-period balances, customer isolation, restart persistence, and production exclusion. Calendar-month unit tests cover leap years and month ends. Flutter tests cover states, prices, disabled checkout, refresh/resume, errors and expired authentication.

With the local API/preview and dedicated QA Chromium on port 9234 running, `node --env-file=apps/api/.env scripts/browser-account-smoke.mjs --membership` creates one temporary test customer, uses the opt-in CLI grant, checks the actual browser screen/session, and deletes only its own account and cascading fixture records afterwards.
