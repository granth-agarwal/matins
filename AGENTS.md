# Morning Brief: build instructions for the coding agent

You are building a native macOS app that shows a calm, editorial "morning brief" once per day, built from the user's Google Calendar, Gmail, Drive (Meet notes) and GitHub. Read this whole file before writing code. Work milestone by milestone (see "Build order") and stop after each one so the user can run it.

## 1. Product in one paragraph

On the first laptop wake at or after a configured time (default 09:00), once per day, the app syncs all sources from saved checkpoints, makes one model call, and opens a window containing the day's brief: a greeting hero, one suggested focus action, a short checklist of to-dos, new updates, and the day's schedule with a prep action per meeting. Before each meeting, a small pop-up appears at the bottom left of the screen with Join, Snooze and Ignore. Nothing else runs during the day.

## 2. Hard constraints (never violate)

1. No model runs except: once in the daily brief run, and on demand when the user clicks a sticker button (Prep me, Let's do it) or Refresh.
2. No periodic polling. One full sync per daily run, plus one single-meeting calendar check at T minus 15 minutes for each meeting, plus a manual Refresh.
3. The only resident process is an idle menu bar agent (no Dock icon). It holds meeting timers, observes wake, and draws pop-ups. Target under 60 MB RSS and near 0% CPU when idle.
4. Read-only access to all user data. Request the narrowest scopes. Never write to Gmail, Calendar or Drive.
5. Privacy: raw email bodies never leave the machine unless the user chose a cloud model. Default model is Apple on-device. No telemetry, no analytics, no network calls except to Google, GitHub and the model provider the user selected.
6. Secrets only in the macOS Keychain. Never in files, logs or UserDefaults.
7. Do not invent API fields. When unsure about a Google, GitHub or Apple API shape, say so and ask the user to paste the official doc section, or write a small isolated probe.
8. No em dashes and no double hyphens in any user-facing copy, comments or docs.

## 3. Platform and stack

- macOS 14 or later, Apple silicon only. Swift 6, SwiftUI, AppKit where SwiftUI cannot do it.
- Swift only. No Python, no Node, no bundled runtimes.
- Networking: URLSession with async/await and Codable. Respect ETags and incremental tokens.
- OAuth: AppAuth for macOS, loopback redirect with PKCE, system browser.
- Storage: SQLite through GRDB. One database in `~/Library/Application Support/MorningBrief/`.
- Launch at login: `SMAppService.mainApp`, toggled in the app.
- Local pop-ups: `NSPanel`. Local notifications fallback: `UNUserNotificationCenter`.
- Optional on-device model: Foundation Models framework, behind a protocol, compiled only if available.
- Package layout: one Xcode project, local Swift packages per module: `Auth`, `Sync`, `Store`, `Brief`, `Models`, `UI`, `Popup`, `Trigger`, `Config`.

## 4. Architecture

```
MenuBarAgent (always idle)
  TriggerService  -> decides when to run the daily run
  DailyRun        -> Sync -> Store -> BriefGenerator -> BriefWindow
  MeetingScheduler-> timers, T-15 recheck, Popup
  Config, Auth, Retention
```

### 4.1 Trigger rules

Run the daily run only if ALL are true:
- Local time is at or after `trigger_after` and before `latest_show_time`.
- `lastShown` date is not today.
- Today is not in `skip_days`.
- The main display is awake and the session is not locked (when `require_unlocked` is true).

Inputs that evaluate the rules: `NSWorkspace.screensDidWakeNotification`, `NSWorkspace.didWakeNotification`, session unlock notification, app launch, and a single `Timer` set for `trigger_after` when the machine is awake. Write `lastShown` only after the window is actually displayed. If conditions fail because the display is asleep, do nothing and let the next event retry. A menu bar item "Show today's brief" opens the brief any time without touching `lastShown`.

### 4.2 Daily run

1. Prune files and rows older than `retention_days` (default 7), except task state.
2. Sync all enabled sources in parallel from their checkpoints. Each source commits its checkpoint only after its rows are saved.
3. Normalize to compact records. Strip quoted replies, signatures and HTML. Truncate each body to 1,200 characters.
4. Summarize each long item with the selected provider's cheap path (Apple on-device when available).
5. One synthesis call returns the Brief JSON (section 6).
6. Save brief JSON, render window, register meeting timers.
7. Failures never block the window. Show whatever succeeded and mark failed sources with a quiet line "Gmail could not sync. Tap to retry."

### 4.3 Sync checkpoints (table `sync_state`)

- Calendar: `syncToken` per calendar. On HTTP 410, drop the token and do a full window sync (yesterday to +7 days).
- Gmail: `historyId`. If history is expired or returns 404, fall back to a query `newer_than:3d` excluding promotions and social.
- Drive: changes `pageToken`, filtered to Meet notes, transcripts and files attached to calendar events.
- GitHub: notifications endpoint with ETag and `since`; plus review requests and assigned issues via search.
- Google Chat: optional, behind a feature flag, only if the account supports it.
- Cap model input to the last 3 days of items; older items are marked backlog and shown only if still open.

### 4.4 Meeting scheduler and pop-ups

- After each daily run, schedule for every upcoming meeting: pop-up at T minus 10 and T minus 2 minutes, and a calendar recheck at T minus 15 (one API call for that event; reschedule or cancel if moved or deleted).
- Pop-up is an `NSPanel`: borderless, non-activating, floating level, `canJoinAllSpaces` and `fullScreenAuxiliary`, never steals focus.
- Position: bottom left of the `visibleFrame` of the screen holding the active window, 20 pt margin.
- Content: title, start time, live countdown, attendee count. Buttons: Join (opens the Meet link in the default browser and dismisses), Snooze 2 min, Ignore (also cancels the 2 minute pop-up).
- Slide and fade in, auto dismiss 5 minutes after start. Stack overlapping meetings, one visible card at a time.
- Custom pop-ups ignore system Focus, so honor an in-app `quiet_mode` and skip pop-ups when `quiet_hours` match.
- If the agent is not running at fire time, a `UNNotification` scheduled in advance acts as fallback with the same actions.

## 5. Auth

- "Sign in with Google" opens the system browser, uses loopback with PKCE, stores the refresh token in the Keychain, requests offline access.
- Scopes (read only): Calendar read-only, Gmail read-only, Drive read-only (Meet notes). Document each scope and why in the first-run screen.
- On `invalid_grant`, show "Sign in again" in the menu bar and in the brief. Never fail silently.
- GitHub: OAuth device flow. No pasted tokens.
- Client ID is read from `Config` so a user can supply their own OAuth client. Document how in the README.
- Support one Google account in v1. Model the data so adding accounts later does not need a migration of core tables (include `account_id` on every synced row).

## 6. Brief JSON schema (the only thing the synthesis call may return)

```json
{
  "date": "2026-10-23",
  "weekday": "Friday",
  "greeting_line": "one calm sentence about the day, max 14 words",
  "focus": { "title": "max 10 words", "detail": "max 12 words", "action": "prep|reply|review|open", "source_id": "..." },
  "todos": [ { "id": "...", "title": "max 9 words", "label": "meeting|reply|pr|deadline|personal|deep-work", "priority": 1, "due": null, "source": "gmail|github|drive|calendar", "source_url": "..." } ],
  "updates": [ { "title": "max 10 words", "detail": "max 10 words", "source": "...", "source_url": "..." } ],
  "schedule": [ { "event_id": "...", "start": "...", "end": "...", "title": "...", "prep": ["max 3 bullets, max 8 words each"], "join_url": "...", "has_prep_action": true } ],
  "replies": [ { "person": "...", "ask": "max 10 words", "thread_url": "..." } ],
  "skip_today": [ "max 6 short items" ],
  "carry_over": [ { "id": "...", "title": "...", "age_days": 2 } ],
  "sources_used": ["calendar","gmail","github"],
  "failed_sources": []
}
```

Validate with Codable plus length checks. On validation failure, retry once with the error message, then fall back to a rule-based brief built from raw records with no model text.

### Model instructions for the synthesis call

- Return JSON only, matching the schema, no prose.
- Use only facts present in the supplied records. Never invent meetings, people, times or numbers.
- Every item must carry the `source_id` or URL of its record.
- Short lines only. No paragraphs. At most: 5 todos, 4 updates, 5 replies, 6 schedule prep bullets per meeting group.
- `greeting_line` is plain, warm, specific to the day (for example mentions free time before the first meeting). No exclamation marks, no emoji, no motivational filler.
- Sort todos by deadline, then by whether a meeting depends on them.
- Never include email text longer than 10 words in any field.

## 7. UI specification

Reference mockup (match it): https://claude.ai/artifact/V99cBBqA4UuSpCXfTPphxi

**Window**: one SwiftUI window, hidden title bar, rounded, dark, closes on Escape, 1100 x 900 default, resizable. Content is a single scrolling column about 900 pt wide, centered.

**Order, top to bottom**
1. Signature image `granth-signature.png` (asset in the catalog), white on transparent, 150 pt wide, centered. Config key `signature` accepts an image path or plain text rendered in the serif italic.
2. Hero, 420 pt tall, rounded 4 pt: palette gradient (two soft radial glows over the ground color) with optional bundled public-domain painting later. Centered title: small italic "The" and large upright "{Weekday} Brief" in the accent color.
3. Caption row: the `greeting_line` in serif italic on the left, a tiny monospace credit line on the right.
4. Vertical date ("23 OCT 2026") on the far left and time ("11:13 AM") on the far right, serif italic 40 pt, scrolling with the page.
5. Sections in a two column grid (left label 1/3, content 2/3): "Push your work forward", "Top to-dos", "New updates", "Your day". Then a centered footer line: "Made for you using Calendar, Gmail, and GitHub."

**Components**
- Focus card: dark card, bold title, grey detail, yellow starburst sticker button "Let's do it" overlapping the lower left edge, rotated about minus 8 degrees. The sticker triggers the focus action (an on-demand model call that produces a short prep note shown in a sheet).
- Todos: custom circle checkbox (accent when checked, text fades and strikes), label pill, source name, tap opens `source_url`. Checking writes immediately to the store.
- Updates: numbered 01, 02 in dim monospace.
- Your day: monospace times list, selected row highlighted; the right panel shows the selected meeting, prep bullets, a Join button (visible from T minus 15), and a sticker "Prep me".
- Empty states: calm one line each ("Nothing new overnight."). Weekend or no meetings: hide Your day and say so in the caption.

**Typography** (bundle fonts, SIL OFL only): Fraunces for serif (italic 300 for labels, 400 for titles), Inter for body, IBM Plex Mono for times, numbers and credits. Body 16 pt, line height 1.55. Section labels 24 pt italic.

**Color**: the page ground is near black `#0E0E0E`, cards `#1A1A1A`, text `#F2EFEA`, muted `#A8A39B`, dim `#8F8A83`. The hero palette rotates daily:

| Name | Ground | Glow 1 | Glow 2 | Accent |
|---|---|---|---|---|
| Forest | #1C2A19 | #46663B | #6E4B2A | #F7EA1B |
| Dusk indigo | #1B2038 | #3C4A7A | #7A5C8C | #F4E3B5 |
| Sea glass | #12302F | #2F6B66 | #6FA39A | #F2F0D8 |
| Clay and ember | #2E1C17 | #6B3A2C | #B26A4A | #FFE9C2 |
| Lavender mist | #261F36 | #5B4B80 | #A58BB8 | #FFF1D6 |
| Moss and sand | #26291A | #5E6B3C | #B5A06A | #F7F2D0 |
| Slate dawn | #1B2630 | #3F5A6B | #C9907A | #FFF0DC |

Palette index is `dayOfYear % count`; if equal to yesterday's, advance by one. Store `lastPaletteIndex`. The accent colors the title, stickers and checkboxes. Palettes are configurable and a pinned palette is allowed.

**Motion**: on open, fade up the hero, then each section with a 60 ms stagger, 500 to 700 ms ease out. Slow drift of the hero glows (20 second loop). Tick draws in on check. All motion disabled when Reduce Motion is on.

**Accessibility**: VoiceOver labels on every control, full keyboard navigation (j and k to move, space to check, e to expand, Escape to close), contrast at least 4.5:1 for body text and 3:1 for large text on every palette (add a unit test that checks all palettes), minimum 44 pt hit targets.

## 8. Config (`config.yaml`, in Application Support, editable and reloaded on open)

```yaml
name: Granth
signature: granth-signature.png     # image path or text
trigger_after: "09:00"
latest_show_time: "16:00"
skip_days: [sat, sun]
require_unlocked: true
retention_days: 7
sources: { calendar: true, gmail: true, drive: true, github: true, chat: false }
gmail: { exclude_categories: [promotions, social], vip: [], ignore: [] }
sections: [focus, todos, updates, schedule]
caps: { todos: 5, updates: 4, replies: 5 }
labels: { meeting: "#...", reply: "#...", pr: "#...", deadline: "#..." }
palette: { mode: auto, pinned: null, list: default }
model: { provider: apple_on_device, synthesis: anthropic }   # apple_on_device | anthropic | openai | ollama
popups: { enabled: true, minutes_before: [10, 2], quiet_hours: [], position: bottom_left }
```

## 9. Data and retention

- Tables: `accounts`, `sync_state`, `events`, `threads`, `github_items`, `drive_files`, `briefs`, `tasks` (checkbox and carry-over state), `meta`.
- A weekly prune deletes `briefs` and cached bodies older than `retention_days`. It runs at the start of the daily run. Task text and state stay. Before pruning a brief, copy its unchecked items into `tasks` so carry-over survives.
- Provide Settings buttons: Delete all data, Sign out of Google, Quit and uninstall (removes login item, caches, Keychain entries).

## 10. Failure and edge cases to handle

Token expired, offline on wake, API quota error, model error or invalid JSON, partial sync, no meetings, weekend, time zone change and DST, all-day events, declined or tentative meetings, recurring event exceptions, cancelled meetings after pop-up scheduling, laptop asleep through a meeting, display attached or removed, multiple Spaces and full screen apps. Write a local log file (no secrets, no email text) the user can attach to a bug report.

## 11. Build order and acceptance criteria

Stop after each milestone and wait for the user.

1. **Skeleton**: menu bar agent, config loading, SQLite store, logging. Accept: app launches, shows a menu item, creates the database.
2. **Auth**: Google sign-in with PKCE, Keychain storage, GitHub device flow. Accept: tokens survive restart, `invalid_grant` shows a re-sign-in prompt.
3. **Calendar sync** with `syncToken`. Accept: today's events printed from the store, second run fetches only changes.
4. **Gmail, Drive, GitHub sync** with checkpoints. Accept: each source resumes from its checkpoint, failure of one source does not stop others.
5. **Brief generation**: provider protocol, Apple on-device and one cloud provider, schema validation, retry, rule-based fallback. Accept: 20 fixture days produce valid JSON with no invented facts (write the fixtures and a checker).
6. **Brief window** matching the mockup, with palettes, signature, checkboxes persisting. Accept: pixel review against the mockup on light and dark system appearance, Reduce Motion tested.
7. **Trigger service** with the full rule set. Accept: manual test matrix (lid closed on power, wake during a call, locked screen, external display only, clock change).
8. **Meeting scheduler and pop-ups**. Accept: pop-up appears bottom left, no focus steal, Join opens the link, moved meetings reschedule via the T minus 15 check.
9. **Sticker actions** (Prep me, Let's do it) as on-demand model calls.
10. **Onboarding, settings, retention, uninstall**.
11. **Release** (later, separate task): hardened runtime, Developer ID signing, notarization, DMG, GitHub Releases.

## 12. Working agreement

- Small commits, one concern each. Explain any dependency before adding it.
- Write tests for sync checkpoints, trigger rules, schema validation, palette selection and contrast.
- Prefer boring, well-documented APIs. Flag any macOS 15 or 26 only API behind an availability check with a fallback.
- When a requirement here conflicts with what is feasible, stop and explain the tradeoff instead of silently changing scope.
- Out of scope for v1: WhatsApp or any personal chat, writing to any service, multiple accounts, Windows or Linux, iOS.