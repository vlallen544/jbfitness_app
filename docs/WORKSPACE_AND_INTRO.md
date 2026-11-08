# Coaching workspace and mobile intro

The staff dashboard now has a dark navigation rail, white workspace, red active controls, a coaching overview banner and four concise metrics. Review/customer navigation, session-calendar and membership links lead to actual existing screens. The workload ring reflects open/resolved reviews in the current loaded view; an empty inbox shows no invented percentage. Customer assignment, trainer-only reviews, consent boundaries and explicit workout publication retain their existing behavior. Desktop, tablet and phone layouts are supported. Entry and control animations honor `prefers-reduced-motion`.

The mobile app opens with an original vector athlete performing two controlled barbell squats. The red/white/black launch sequence lasts 2.8 seconds; **Skip intro** and **Let's move** finish it immediately. Account restoration starts at the same time, so the introduction does not postpone connecting to the backend. Afterward, the existing account, onboarding, retry or signed-in screen appears. There are no repeated animations or artificial network progress states.

This introduction appears once per app process, including in the offline preview. It does not reappear on logout, account refresh or tab changes. A new app process shows it again. Reduced-motion mode displays a static athlete and finishes after 300 ms. The layout scrolls on short screens and supports enlarged text. Controllers are stopped/disposed when skipped or removed.

The athlete is drawn with Flutter `CustomPainter` and animated joint positions. The dashboard uses original inline SVG and CSS. No video download, paid animation service, new package or external asset licence is required. This is branded introduction artwork, not an exercise demonstration or coaching instruction video.

## Review artifacts

- [Mobile fitness intro](previews/fitness-intro.png)
- [Animated intro preview](previews/fitness-intro.gif) — loops for review; the app plays it once per launch.
- [Staff sign-in](previews/staff-login.png)
- [Customer assignment](previews/staff-assignments.png)
- [Trainer overview](previews/staff-trainer-inbox.png)
- [Workout review](previews/staff-workout-review.png)
- [Phone dashboard](previews/staff-mobile-inbox.png)

Android preview version: `0.1.2+3`. The downloadable preview still uses labelled in-memory sample records. Hosting does not automatically connect the offline preview to the live database. The normal app entry point uses the configured `API_BASE_URL`; all real AI, billing and video activation constraints still apply.

Verification: 66 mobile tests, including intro completion, immediate skip, reduced motion and enlarged text; clean Flutter analysis; successful dashboard build and nine existing dashboard boundary checks. The actual local browser walkthrough covered cookie sign-in, assignment, trainer feedback, workout publication and a narrow phone layout with isolated fixtures. Intro frames were exported from the real Flutter widget using SDK fonts, not a separate design mockup. Android installation and iOS remain physical-device follow-up work.
