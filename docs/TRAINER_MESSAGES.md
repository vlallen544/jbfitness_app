# Trainer messages

Customers can open **Profile → Message your trainer**, choose an assigned trainer, confirm sharing and send a text question. The trainer signs into the web dashboard and opens **Trainer messages** to reply. Both sides can reopen the saved conversation and load older messages.

Example: a customer asks, “Can you check my squat technique at our next session?” Their trainer replies, “Yes, we can review it together.” These messages are written by people. The AI coach remains a separate conversation.

## Rules

- All active membership tiers can send messages. No payment bypass or development membership activation is added. Expired customers retain read access to their history; neither side can send until membership is active again.
- Only current assigned trainers can receive new messages. Customers initiate conversations; trainers cannot initiate unsolicited conversations.
- Before sending, the customer explicitly confirms sharing this conversation with that trainer. This does not share their profile, body photos, food diary or AI chat, and does not change existing consent flags. Multiple assigned trainers have separate conversations.
- Administrators manage assignments but cannot read messages through these routes. A former trainer loses API access as soon as the assignment is removed. The customer retains their own previous conversation as read-only history. Reassigning the same trainer restores access to that same pair's retained history; clearing the conversation removes it.
- Text only, 1–2,000 characters. Saved sender messages in the preceding 24 hours are capped at 100; this is a basic abuse bound, not a complete production rate-limiting system. Attachments, typing status, read receipts, real-time subscriptions and push alerts are not implemented.
- Both interfaces refresh explicitly, and mobile refreshes when resumed. There is no promise of immediate trainer availability. The latest 50 messages load first; older messages use numeric sequence cursors. Inbox lists are bounded to 200 conversations.
- Failed or uncertain sends retain the same request reference for retry while the screen stays open. The same reference cannot create a second saved message or be reused for changed text. There is no offline send queue or persisted draft.
- Customers can confirm **Clear messages** to delete this pair's messages for both sides, including after membership expiry or assignment removal. It does not delete AI coaching, workout records or trainer review feedback. A trainer cannot clear history or restart a cleared conversation until the customer sends again. Clearing cannot retract copies a recipient already made.

## Implementation

Migration `013_trainer_messages.sql` stores conversations as customer/trainer message pairs, with account foreign keys, sender request uniqueness, chronological indexes and RLS enabled without public client policies. The existing backend accesses PostgreSQL; Firebase and Cloudinary are not involved. Messages are never included in AI prompts by this feature.

Authenticated routes:

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/v1/me/trainer-messages` | Current assigned trainers and the customer's previous conversations; trainers see customer-initiated conversations only. |
| GET | `/api/v1/me/trainer-messages/:peerId?before=sequence` | Read a permitted thread, send permission and older-history cursor. |
| POST | `/api/v1/me/trainer-messages/:peerId` | `{text,requestId,shareWithTrainer:true}`; customer or assigned trainer sends. |
| DELETE | `/api/v1/me/trainer-messages/:trainerId` | Customer clears their conversation. |

The dashboard proxies allowlisted paths through its existing HttpOnly staff cookie and validates Origin before mutations. Customer-row locks serialize sends, clearing and admin assignment changes; a sender advisory lock serializes duplicate requests across conversations. Membership reads inside sends reuse the existing transaction connection.

## Validation and rollout

Run the API build, messaging integration test, dashboard production build and dashboard integration tests. Flutter tests cover explicit sharing, retry references, reopening history, deletion confirmation, empty/read-only states and enlarged narrow-phone layout. Physical-device testing remains separate.

Verified locally on 9 November 2026: API and dashboard production builds, clean Flutter analysis, 118 API integration checks, 10 dashboard checks, 4 API unit-test files and all 87 Flutter tests passed. These checks use local development/test data, not hosted customer accounts.

The normal API deployment runs migrations before startup. Deploy the updated API and dashboard, then install an APK built from this source. No new service accounts or hosting services are needed. A real trainer assignment and active membership are required to demonstrate sending; provider-verified billing remains a separate unfinished milestone.
