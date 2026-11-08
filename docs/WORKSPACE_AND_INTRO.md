# Coaching workspace and feature walkthrough

The staff dashboard uses a dark navigation rail, white workspace, red active controls, a coaching overview and four record-based metrics. The workload ring reflects reviews currently loaded; empty records do not create invented results. Customer assignment, trainer-only reviews, sharing consent and explicit workout publication retain their existing behavior. Dashboard entry transitions honor reduced-motion settings.

## Current mobile walkthrough — 0.1.3

The original timed athlete splash was replaced with four feature explanations:

1. **Your training:** preferences become a routine; exercise cards appear with sets, reps and durations.
2. **Your meals:** a meal preview transitions into estimated calories/macros, with a reminder to review portions before saving.
3. **Habits and progress:** weekday checks fill and a sample weight chart draws over time.
4. **Coaching support:** an example conversation introduces fitness questions, trainer feedback and membership-dependent sessions.

Every scene is labelled **Feature preview · example data**. The food numbers and weight trend are examples, not estimates made from a real upload or promised health results. No backend request or AI call is made by the walkthrough.

Pages advance only when the customer taps **Next** or swipes. **Back** revisits the previous explanation. **Skip intro** and **Already have an account? Log in** open the account flow immediately; the last page has **Continue to login**. There is no auto-dismiss timer, forced viewing period or automatic page advance. Each scene animates once and then stays visible for reading.

Completion/skip is remembered on the device under a dedicated walkthrough preference, separately from authentication. The next launch uses normal login/session restoration. Signed-out customers can replay it with **Explore app features** on the login page. The optional offline entry point uses an in-memory tour preference for repeatable design reviews.

Reduced-motion mode shows the complete scene without movement. Explanatory text supports enlarged fonts and scrolls on small screens; the controls remain available below the page. The scene itself scales as an illustration and has its own accessible description. Account restoration runs concurrently. Preference-storage failure does not block login.

## Review artifacts

- [Workouts](previews/walkthrough-workouts.png)
- [Meal estimates](previews/walkthrough-nutrition.png)
- [Habits and progress](previews/walkthrough-progress.png)
- [Coaching](previews/walkthrough-coaching.png)
- [Animated walkthrough](previews/fitness-intro.gif) — the review clip changes pages to show all four; the app waits for the user.
- [Staff overview](previews/staff-trainer-inbox.png)
- [Customer assignments](previews/staff-assignments.png)
- [Staff phone layout](previews/staff-mobile-inbox.png)

The scenes use native Flutter widgets and a drawn progress chart, with no video download, new package or paid animation service. Review frames were rendered from the actual widgets with SDK fonts. The previous 0.1.2 splash remains in its historical GitHub release.

The current Android demo uses the **connected** entry point and hosted backend. It does not open a sample customer automatically. See [connected demo instructions](CONNECTED_DEMO.md). AI, billing, video and membership activation remain separate features to configure; the walkthrough does not activate them.
