# Manual acceptance checklist

## 1. Skeleton

- [ ] Run `swift Tools/Build.swift` and open `build/Morning Brief.app`.
- [ ] Confirm sunrise menu icon, no Dock icon, and Ready status.
- [ ] Open data folder and confirm config, SQLite database and log exist.
- [ ] Quit and relaunch. Confirm data persists.
- [ ] Edit name in config and reopen menu. Confirm greeting changes.
- [ ] Enter invalid YAML, verify quiet error, correct YAML and reload.

## 2. Authentication

- [ ] Configure your own client IDs and use both sign-in menu actions.
- [ ] Confirm Google consent grants only enabled read scopes, browser returns via loopback, and tokens survive app restart.
- [ ] Revoke Google consent externally, then refresh. Confirm Sign in again appears.
- [ ] Verify GitHub device code, cancellation and expiry. Restart and confirm token works.
- [ ] Deny Keychain access and verify a quiet error with no token in logs or files.

## 3. Calendar

- [ ] Refresh Calendar and compare today's stored events with Google Calendar.
- [ ] Refresh again and verify the saved sync token advances using incremental changes.
- [ ] Move, decline and cancel events, including a recurring exception; refresh and compare.
- [ ] Check all-day events across a timezone change and DST boundary.

## 4. Other sources

- [ ] Refresh all sources twice; confirm Gmail history, Drive token and GitHub checkpoint advance.
- [ ] Add then delete a message and meeting note; verify incremental changes.
- [ ] Verify promotions, social, ignored senders and trashed documents are excluded.
- [ ] Disable network or revoke one service permission; confirm others finish and the failure remains visible.
- [ ] Verify GitHub review requests and assignments in accessible repositories.
- [ ] Check Drive note matching and Calendar attachments, including a newly attached document on the next run.

## 5. Brief generation

- [ ] Generate with Apple Intelligence enabled on supported macOS; verify one synthesis call and grounded contents.
- [ ] On older macOS or with Apple Intelligence disabled, verify useful local fallback.
- [ ] Configure Anthropic explicitly with a valid model ID and Keychain key in Settings; verify only that provider receives data.
- [ ] Test invalid key, offline mode and provider failure; verify the brief still appears from source records.
- [ ] Review all generated text and links against your source records.

## 6. Brief window

- [ ] Compare against the reference artifact at 1100 x 900 in light and dark system appearance.
- [ ] Verify all three bundled font families and your signature path/text.
- [ ] Check a task, close and reopen, then restart; verify persistence.
- [ ] Test j/k, space, e, Tab, VoiceOver labels and Escape.
- [ ] Enable Reduce Motion before opening; verify entrance and glow animations stop.
- [ ] Check all seven palettes, same-day reopen and pinned selection.
- [ ] Inspect schedule selection and Join visibility at 15 minutes before start.

## 7. Daily trigger

- [ ] Cold launch while unlocked: open the menu once to establish unlock state, or lock and unlock; confirm exactly one eligible daily run.
- [ ] Wake before trigger time, remain awake through it, and verify one window at the configured time.
- [ ] Wake after trigger time but before latest show time; verify one brief.
- [ ] Wake with lid closed on power and an external display, and with external display only.
- [ ] Wake during a call; verify the brief once, then no repeated sync on further wake events.
- [ ] Lock the session while sync is running; confirm it does not reveal the window until an eligible unlock.
- [ ] Wake after latest show time and on skip days; confirm no automatic brief.
- [ ] Change timezone, move the clock forward/back, and cross DST; verify local-date rules and no duplicate daily model call.
- [ ] Open Show today's brief at any time; confirm it does not update lastShown or make a model call.
- [ ] Quit and restart after a successful daily display; verify no automatic second run.

## 8. Meeting reminders

- [ ] Create a meeting at least 16 minutes ahead, refresh, and verify one T minus 15 calendar recheck.
- [ ] Move it before recheck, verify old timers and fallback notifications are replaced; delete it and verify cancellation.
- [ ] Check T minus 10 and T minus 2 cards appear 20 points from bottom left on the active window's screen.
- [ ] Type into another app while a card appears; verify focus and typing stay in that app.
- [ ] Test multiple Spaces, full screen, external display removal, and the Dock on different edges.
- [ ] Test Join, Snooze 2 min, Ignore, overlap queueing and dismissal five minutes after start.
- [ ] Verify quiet_mode, overnight quiet_hours, screen lock and display sleep suppress cards.
- [ ] Enable notifications in Settings, quit before a scheduled reminder, and verify fallback Join/Snooze/Ignore actions after relaunch.
- [ ] Deny notification permission, sleep through a meeting and restart; confirm no stale cards or crashes.
