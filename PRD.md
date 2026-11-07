# Product Requirements Document — JB Fitness

**Product:** JB Fitness AI-Powered Online Fitness Coaching Platform\
**Platforms:** iOS and Android customer app; web-based trainer/admin dashboard\
**Status:** Draft for client confirmation\
**Version:** 0.6\
**Prepared:** 5 November 2026

## 1. Product Summary

JB Fitness is a personalized online fitness coaching platform where customers can manage their fitness journey in one place. The mobile app combines AI-guided workout plans, food and nutrition tracking, transformation monitoring, trainer communication, memberships, and supplement purchasing. A web dashboard enables the owner and authorized trainers to manage customers, coaching, memberships, and store operations.

The first release will establish the core coaching experience. Exercise demonstration videos will be generated in advance, stored in a library, and made available to the ₹3,000 Normal plan. On-demand AI video generation and deeper coaching automation will be considered after MVP validation.

## 2. Problem and Opportunity

Fitness customers commonly use separate tools for training plans, diet logs, progress photos, coach communication, and supplement purchases. This fragments the coaching experience and makes progress hard to review.

JB Fitness will offer a single, privacy-conscious service that gives customers personalized daily guidance while enabling the business to deliver and manage coaching at scale.

## 3. Goals

- Provide each paying customer with a personalized, actionable workout and nutrition experience.
- Make daily adherence easy to track: workout completion, meal logging, measurements, and photos.
- Give trainers a practical way to communicate with and review assigned customers.
- Support plan sales, renewals, supplement sales, and basic operational reporting.
- Protect health-related profile data, progress media, and payment-related information.

## 4. Non-goals for the MVP

- Medical diagnosis, treatment, or clinical nutrition advice.
- Fully autonomous coaching that replaces trainer oversight.
- On-demand AI generation of new exercise videos inside the app. Playback of demonstration videos generated in advance is included.
- Complex marketplace capabilities, multi-vendor supplements, or automated logistics integrations unless confirmed.
- Social feeds, public transformation sharing, or community challenges.

## 5. Users and Roles

| Role | Primary needs | Key permissions |
| --- | --- | --- |
| Customer | Follow plans, log meals and progress, reach a coach, shop | Access only their own account, plans, media, orders, and conversations |
| Trainer | Coach assigned customers and review progress | Access only assigned customers and their authorized coaching data |
| Owner/Admin | Operate memberships, customers, trainers, store, and reports | Full operational access, subject to audit and privacy controls |
| Store manager (optional) | Fulfil supplement orders | Manage catalogue, stock, and order fulfilment; no unnecessary access to health data |

## 6. Membership Plans

All three plans last one month. Higher plans include all lower-plan features: Premium includes Normal, and Premium Plus includes Premium. Audio calls are deferred and are not a confirmed launch benefit. Exact expiry calculation, automatic renewal, and video-call rules still require confirmation.

| Working plan name | Indicative price | Benefits captured so far | Items to confirm |
| --- | ---: | --- | --- |
| Normal | ₹3,000 / one month | Stored exercise demonstration videos; in-app AI chat; no live video coaching | Exact AI usage limits and trainer escalation access |
| Premium | ₹10,000 / one month | All Normal-plan features; 10 live video coaching sessions total | Session length, expiry/carry-forward policy, exact AI usage limits |
| Premium Plus | ₹20,000 / one month | All lower-plan features; 25 live video coaching sessions total, replacing the 10-session allowance | Final name, session length, expiry/carry-forward policy |

### Membership requirements

- An admin can create, edit, activate, pause, and retire membership plans without changing historical purchases.
- A customer can view plan price, duration, benefits, inclusions, and applicable terms before payment.
- Payment success activates the membership only after verified payment status is received from the payment provider or approved by an admin.
- The platform records membership start date, end date, status, paid amount, payment reference, remaining included calls, and renewal history.
- Expired or unpaid memberships limit paid-only features while preserving the customer’s account and historical records.
- The app sends configurable expiry and renewal reminders.
- Live call entitlements are tracked per membership, including booked, completed, cancelled, and remaining sessions.

## 7. Functional Requirements

### 7.1 Registration, authentication, and customer profile

Customers must be able to:

- Register and sign in securely using the approved authentication method (phone OTP, email/password, or both — to be confirmed).
- Reset or recover their account securely.
- Complete and edit a profile containing age, height, current weight, gender if collected, fitness goals, experience level, dietary preferences, food allergies/dislikes, and available workout equipment.
- Provide relevant coaching information, such as preferred workout days, workout location, and injuries/limitations with clear health disclaimers.
- Review consent for personal-data processing and progress-photo storage.
- Request export or deletion of their account data, subject to legal and operational retention requirements.

### 7.2 AI workout planner

The system must:

- Generate daily and weekly workout schedules using the customer’s profile, fitness goals, experience, equipment, activity history, and available days.
- Show each exercise with instructions, sets, repetitions, planned load or intensity when relevant, rest time in seconds, and demonstration media.
- Provide exercise-linked playback from the stored demonstration-video library to active members of all three plans through inherited benefits. Videos are prepared in advance; selecting an exercise does not generate a new video.
- Provide a safe fallback for unavailable equipment and a way to report pain, inability, or exercise substitution.
- Allow customers to mark individual exercises or an entire workout as completed, skipped, or modified, with optional actual reps/weight/notes.
- Display workout history and adherence.
- Refresh or recommend adjustments based on recorded progress, feedback, and trainer changes. Material plan changes should remain reviewable by a trainer/admin when that workflow is enabled.
- Clearly state that AI recommendations are general fitness guidance and not medical advice.

### 7.3 AI diet and nutrition tracker

Customers must be able to:

- Record foods and quantity in grams, organized as breakfast, lunch, dinner, or snacks.
- Search/select food items from the approved nutrition database and edit serving quantities.
- View calculated calories, protein, carbohydrates, fats, fiber, and other available nutrients.
- Set or receive daily nutrition targets and compare logged totals with those targets.
- View daily summaries, recent history, and AI-generated meal suggestions aligned with their target and dietary preferences.
- Correct or delete a food entry.
- Upload a dish photo, type a description, or combine both to receive approximate calories and nutrients. For example, “a bowl of rice and dal” produces editable portion estimates and cooking assumptions, without requiring every ingredient first.
- Review and correct estimated foods, grams and nutrient values before explicitly saving. Ask for clarification only when no useful meal estimate is possible. Preserve the AI estimate label in saved entries and daily totals.

The system should label nutrition estimates appropriately and avoid presenting them as medical advice. The source and regional suitability of the food database must be confirmed; Indian food coverage is recommended.

### 7.4 Body progress tracking

Customers must be able to:

- Upload progress photos with date, optional notes, and front/side/back category if used.
- Record body weight and measurements including waist, chest, arms, and thighs; the admin may configure additional fields.
- Review chronological records, charts, and date-to-date comparisons.
- Choose whether authorized assigned trainers can review their progress photos and measurements, subject to the privacy policy.

The dashboard must allow authorized trainers/admins to review progress in a customer timeline and leave feedback where enabled. Photos must be privately stored and never publicly visible by default.

### 7.5 Coaching, support, and communication

- In-app chat is the primary support channel. AI handles routine workout, nutrition, habit, and progress conversations; distinguish AI responses from trainer responses.
- Escalate unresolved or flagged cases to the assigned trainer with a summary and authorized context. Finalize escalation criteria and customer-requested handoff rules.
- Customers and assigned trainers can exchange one-to-one messages on escalated cases; routine messages are handled by AI.
- Messages show delivery/read status where supported and generate push notifications.
- Customers with an eligible plan can view, book, reschedule, or cancel live coaching calls according to configured rules.
- The video-call experience supports the approved video provider and displays upcoming call details, join links, and session status.
- Audio-call support is deferred. Do not include it as a confirmed launch entitlement; revisit availability and limits later.
- An AI fitness assistant can answer general workout and nutrition questions using the customer’s available context. It must not diagnose conditions or override emergency/medical guidance.
- Trainers can share feedback and exercise demonstration links/media with assigned customers.

### 7.6 Supplement store

Customers must be able to:

- Browse a product catalogue with photos, description, ingredients, prices, available stock, and relevant product information.
- Search and filter the catalogue.
- Add products to a cart, update quantities, provide delivery details, and complete payment.
- View order history, order status, and delivery updates.

Admins/store managers must be able to:

- Create, update, activate/deactivate, and categorize products.
- Manage price, product images, ingredient information, and stock levels.
- Review, update, and fulfil orders; record tracking details where delivery integration is not automated.
- Prevent checkout for unavailable stock and maintain an order status history.

### 7.7 Notifications and reminders

The app will support in-app and push notifications, with user consent and preferences where required, for:

- Scheduled workout reminders.
- Meal/food logging reminders.
- Daily progress reminders.
- New trainer messages and upcoming calls.
- Membership activation, expiry, and renewal reminders.
- Order confirmation, fulfilment, shipment, and delivery updates.

Users can manage non-essential notification preferences. Transactional and safety notices follow applicable policy and consent requirements.

### 7.8 Admin and trainer web dashboard

The dashboard must support:

- Customer list, profile review, search, filters, membership status, and account-management actions.
- Trainer creation and assignment to customers.
- Membership plan configuration, payment review/verification, renewal management, and membership history.
- Workout-plan oversight, manual edits, and trainer assignment workflows.
- Authorized progress review and customer feedback.
- Messaging and call-session oversight for assigned customers.
- Product, stock, order, and fulfilment management.
- Basic reports for active memberships, membership revenue, supplement sales, orders, and customer growth.
- Role-based access so trainers only see authorized customer information.

### 7.9 Daily habit tracker

Reference: client-supplied habit-tracker screenshots dated 5 November 2026. Reproduce the habit goals, daily checkmarks, weekly groupings, and completion summaries as mobile-friendly screens on iOS and Android.

- Provide a Today checklist as the primary interaction, a weekly view, and a horizontally scrollable monthly grid with habits as rows and dates as columns.
- Customers can create, edit, archive, and reorder habits, select scheduled days, set an optional monthly completion goal, and configure reminder times.
- Suggested habits include completing a workout, logging meals, drinking water, meeting a sleep routine, walking, and recording progress. Customers may add private custom habits.
- Record each scheduled date as completed, missed, or not yet logged; unscheduled/future dates are not failures. Support undo and corrections to historical entries.
- Show completed versus scheduled/elapsed opportunities, monthly goal progress, current/best streaks, and daily/weekly completion charts. Label each denominator clearly; future days must not reduce adherence to date.
- Calculate streaks from consecutive scheduled opportunities using the customer's timezone. Store an explicit local habit date and preserve historical dates when timezone or schedule settings change.
- Link eligible app events to habits (for example, workout completion or meal logging) with the customer's choice; avoid duplicate completions and keep manual correction available.
- Assigned trainers can suggest habits and review shared adherence; personal habit visibility must be configurable by the customer.
- Save checkmarks locally for temporary offline use, sync when connectivity returns, and resolve repeated updates without duplicate entries.
- MVP acceptance: create a habit with a 25-day monthly goal, check/undo dated completions, restart the app without losing data, and verify Today, weekly, monthly, and summary totals agree.

## 8. Core Customer Journeys

### 8.1 New customer onboarding

1. Customer registers and verifies their account.
2. Customer agrees to privacy/health guidance and completes profile questions.
3. Customer reviews and purchases a membership plan.
4. Verified payment activates the appropriate benefits.
5. The app generates the initial workout plan and nutrition targets/suggestions.
6. Customer starts logging workouts, food, and progress.

### 8.2 Daily coaching journey

1. Customer receives a reminder and opens the day’s workout or meal log.
2. Customer follows the workout, views exercise instructions, and records completion.
3. Customer logs meals by food and grams and sees target progress.
4. Customer optionally logs measurements or a photo and asks the trainer/AI assistant a question.
5. AI/trainer insights inform future recommendations within the agreed coaching workflow.

### 8.3 Supplement purchase

1. Customer browses products and adds selected items to cart.
2. Customer confirms delivery address and payment.
3. The platform creates an order after payment confirmation and adjusts reserved/available stock according to the inventory policy.
4. The customer receives status updates until delivery/completion.

## 9. AI Requirements and Guardrails

### MVP AI capabilities

- Personalized workout-plan generation.
- General nutrition and meal suggestions.
- General fitness Q&A assistant.
- Progress summaries and recommendations based on recorded data.
- Recommendation adjustments using workout completion, food logging, and progress data.

### AI routine review and workout orchestration

Confirmed direction: automate most routine coaching through AI, including an LLM review of the customer's routine followed by a personalized workout, with minimal trainer messages. Proposed execution:

1. Collect goals, current routine, experience, equipment, available days/session time, limitations, and recent workout feedback. Ask for essential missing details.
2. A routine-review LLM assesses consistency, feasibility, recovery, and fit with the customer's goals, producing constraints for the planner.
3. A planning LLM creates a schedule using approved exercise identifiers linked to stored demonstration videos.
4. Backend checks enforce required fields, exercise availability, equipment restrictions, schedule constraints, and configured training limits. An LLM reviewer checks the draft against customer context; LLM review alone does not establish safety or correctness.
5. Revise failed drafts with explicit feedback and a configured retry limit. Ask follow-up questions for missing information; escalate repeated failures or flagged concerns to a trainer.
6. Publish passing plans automatically under the agreed launch policy, retain plan versions, and explain the routine. Routine human approval is not intended; exact publishing checks remain to be finalized.
7. Trigger subsequent reviews from completion, difficulty feedback, routine changes, and progress rather than regenerating on every chat message.

Use this review/validation pattern for routine chat where useful. Keep payment activation, permissions, nutrient calculations, habit totals, and orders governed by explicit application rules and authorized actions. Track retry counts, costs, latency, recommendation quality, and escalation reasons during the pilot.

### Guardrails

- AI output must be framed as general wellness/fitness information, not medical, diagnostic, or emergency advice.
- Surface escalation guidance for injury, severe symptoms, eating-disorder concerns, pregnancy/postpartum considerations, or other high-risk situations.
- Store the AI prompt context and response metadata needed for quality review without exposing it to unauthorized users.
- Give admins a way to disable or limit AI features if the service is unavailable or unsafe.
- Approved exercise demonstrations are generated in advance, reviewed, and stored for playback in MVP, including access through the ₹3,000 Normal plan. On-demand AI video generation is a future enhancement.

## 10. Data and Integrations

### Proposed AI services (recommendations, not purchased or integrated)

- **OpenAI Responses API:** proposed primary AI integration for workout drafts, general coaching Q&A, meal suggestions, habit suggestions, and weekly summaries. Text/image inputs, structured outputs, and function calling support these workflows. Validate generated workouts against the approved exercise library and application rules before saving them. Select a model after evaluating output quality, latency, and cost on representative client cases.
- **fatsecret Platform API:** proposed nutrition-data integration for food search and nutrient values. This is a food-data service rather than a general AI model. Confirm Indian-food coverage, commercial licensing, and pricing before selection. Calculate nutrients from confirmed food records and grams in backend code.
- **Confirmed meal estimation:** photo, text or combined input with approximate portions/nutrients, visible assumptions and editable review before saving. Image recognition must not claim exact food weight, calorie counts, or body-fat measurements from a photo. Speech input and voice coaching remain later features.
- **Habit intelligence:** use deterministic code for checkmarks, streaks, percentages, and reminders. AI may suggest a routine or summarize adherence using the recorded totals; it must not invent completions.
- **Integration workflow:** mobile app → authenticated backend → minimum required user context → AI/food-data provider → validation → database → mobile app. Keep API keys on the server, apply usage limits, cache reusable results where appropriate, and record per-feature costs.
- **Launch recommendation:** one general AI provider plus one nutrition database; curated exercise demonstration videos. Generate plans on onboarding or meaningful changes and summaries weekly to control recurring costs.

Sources: [OpenAI Responses API](https://developers.openai.com/api/reference/responses/overview), [structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs), [fatsecret Platform API](https://platform.fatsecret.com/platform-api).

| Area | Data/integration need |
| --- | --- |
| Authentication | Phone/email identity provider, secure sessions, account recovery |
| Payments | Payment gateway supporting INR, webhooks/payment verification, refunds if required |
| AI | Model/API provider, prompt safety controls, usage monitoring, fallback states |
| Nutrition | Licensed or approved nutrition database, ideally with Indian foods and macro/micronutrient data |
| Media | Secure object storage/CDN for progress photos, product images, and exercise videos |
| Messaging | In-app real-time messaging service and push notifications |
| Video calls | Approved video communication provider with calendar/session support if required |
| Notifications | APNs/FCM push delivery; optional SMS/WhatsApp only if confirmed |
| Delivery | Manual tracking in MVP; shipping/courier integration only if confirmed |

## 11. Non-functional Requirements

### Security and privacy

- Use encrypted transport (HTTPS/TLS) and encryption at rest where supported for sensitive data and private media.
- Implement role-based access control and server-side authorization for every protected resource.
- Use secure payment-provider workflows; do not store raw card details in the app or backend.
- Provide privacy notice, consent records, account deletion request flow, and data-access controls.
- Maintain audit logs for meaningful admin actions involving payments, memberships, customer assignments, and access to private progress records.
- Define media retention, deletion, backup, and access policies before launch.

### Reliability and usability

- Clearly communicate loading, offline, payment-failure, and AI-unavailable states.
- Design mobile flows for common device sizes and accessible text, contrast, and touch targets.
- Use image compression and resumable upload strategies for progress media where practical.
- Back up critical transactional data and monitor service errors and payment webhooks.

### Performance targets (to validate during technical design)

- Typical app/dashboard screens should load meaningful content within 3 seconds on a standard mobile connection, excluding large media downloads.
- Standard workout, meal-log, and status updates should provide an acknowledgement within 2 seconds under normal operating conditions.
- AI responses should stream or provide a clear progress state; define an acceptable response target with the selected provider.

## 12. MVP Scope and Prioritization

| Priority | Included capability |
| --- | --- |
| Must have | Registration/login, profile onboarding, plans/payments and verification, membership status, AI workout review/planning loops, nutrition logging, daily habit checklist and weekly/monthly tracker, body measurements/photos, AI coaching chat with trainer escalation, assigned-trainer access, plan-specific live video sessions and entitlement tracking, supplement catalogue/cart/orders, admin dashboard, core notifications |
| Should have | Expanded workout history, richer nutrition summaries, enhanced progress comparisons/charts |
| Later release | On-demand AI video generation, advanced coaching automation, courier integrations, sophisticated analytics, social/community features |

## 13. MVP Acceptance Criteria

The MVP is ready for launch review when:

- A new customer can register, complete a profile, purchase a plan, and see active membership status after verified payment.
- An active customer can view a personalized workout, record completion, and access exercise demonstrations.
- A customer can log food quantities in grams and see daily calories/macros compared with targets.
- A customer can securely upload and review dated progress photos, weight, and measurements.
- An assigned trainer can access only authorized assigned-customer information and exchange messages.
- Routine coaching chat is handled by AI; unresolved or flagged cases reach the trainer with authorized context.
- Eligible members can book and join live video sessions against the 10-session or 25-session total allowance.
- An admin can manage plans, memberships, customers, trainers, workout oversight, store products, stock, and orders.
- A customer can purchase an in-stock supplement and see order status after payment.
- Reminders/notifications are sent for core workout, messaging, membership, and order events when enabled.
- Unauthorized accounts cannot access another customer’s personal data, private progress media, messages, orders, or payment information.

## 14. Open Decisions Required Before Development

1. All plans last one month. Confirm calendar-month versus fixed-day expiry and manual versus automatic renewal.
2. Higher plans inherit lower-plan features. Confirm final plan names and AI usage limits. Video allowances are 10 sessions for ₹10,000 and 25 sessions for ₹20,000, per one-month membership.
3. Confirm video-session duration, booking policy, cancellation rule, and expiry/carry-forward policy.
4. Audio calls are deferred; revisit inclusion, availability, and usage rules later.
5. AI handles routine coaching and workout orchestration. Confirm automatic-publishing checks, escalation criteria, and trainer handoff rules.
6. Will progress review be performed by the owner, trainers, or both? What consent model is required for photos and measurements?
7. What authentication methods and payment methods are required? Is manual payment verification needed?
8. Which supplement fulfilment model will be used, and which locations, delivery charges, tax/invoice requirements, and return/refund rules apply?
9. Which languages, regions, and nutrition database coverage are required at launch?
10. What are the target launch date, development budget, hosting/AI budget, maintenance plan, and support ownership?

## 15. Success Metrics

- Registration-to-paid-membership conversion rate.
- Active paying members and membership renewal rate.
- Weekly workout completion rate per active customer.
- Meal logging frequency and nutrition-target adherence.
- Percentage of active customers recording progress at least weekly.
- Trainer first-response time and customer satisfaction.
- Supplement-store conversion rate, average order value, and fulfilment time.
- AI feature usage, response quality feedback, safety escalations, and cost per active customer.

## 16. Recommended Delivery Phases

1. **Discovery and confirmation:** resolve all open decisions; finalize UX, content, policies, and technical architecture.
2. **MVP build:** mobile app, dashboard, memberships/payments, workout/nutrition/progress, messaging, store, and notifications.
3. **Pilot launch:** onboard a controlled group, validate plan operations, AI quality, payment flows, media privacy, and fulfilment.
4. **Iteration:** refine coaching automation and reporting from pilot feedback.
5. **Future enhancements:** on-demand AI video generation and additional advanced capabilities after a safe, costed validation.

## 17. Expected Outcome

JB Fitness will be a complete online fitness-coaching platform in which customers receive personalized workout and nutrition guidance, track their transformation, communicate with coaches, and purchase supplements. The owner operates the service through a single secure dashboard with visibility into memberships, customers, coaching, sales, stock, and orders.
