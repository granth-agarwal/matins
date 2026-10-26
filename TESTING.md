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
- [ ] Confirm Google consent grants enabled read scopes plus account identity, browser returns via loopback, and tokens survive app restart.
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
- [ ] Check Drive note matching and Calendar attachments, including a newly attached document in the same run.

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

- [ ] Cold launch while unlocked: open the menu and choose Reload config to establish unlock state, or lock and unlock; confirm exactly one eligible daily run.
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

## 9. Sticker actions

- [ ] Click Prep me and Let's do it; verify a short note appears in a sheet for the selected source.
- [ ] Verify no model call occurs until the click, one call occurs per click, and rapid duplicate clicks do not overlap.
- [ ] Check prep uses only the selected source and linked Drive documents.
- [ ] Disable the model or network and verify useful source-note fallback.
- [ ] Close the sheet with Done or Escape and check keyboard focus returns to the brief.

## 10. Onboarding, settings and data

- [ ] First launch shows read-scope explanations and the on-device default. Close onboarding and verify no automatic sync occurs before Save and begin.
- [ ] Enter your client IDs, connect accounts and save. Restart and verify preferences and credentials survive.
- [ ] Change time, skip days, sources, Calendar IDs, quiet mode and palette settings. Verify saved YAML is reloaded and disabled sources are excluded from cached briefs and sticker context.
- [ ] Switch to Anthropic only after reading and confirming the cloud disclosure. Verify the key is only in Keychain and the model ID comes from config.
- [ ] Toggle launch at login in an installed app bundle. Check System Settings approval and restart behavior.
- [ ] Enable and deny notification authorization; verify permission status and scheduled fallback actions.
- [ ] Leave a task unchecked for another day and complete a second task. Verify carry-over and completed state after retention and Refresh.
- [ ] Sign out of Google, including during an expired-grant recovery. Verify Google local rows and credentials are removed, GitHub remains available, and the app does not make another automatic model call that day.
- [ ] Connect a different Google account after sign-out. Verify old account records and tasks do not appear.
- [ ] Use Delete all data on disposable local data. Verify credentials, tasks, briefs, caches, login registration and preferences are removed/reset, without changes to remote accounts.
- [ ] Use Quit and uninstall on a disposable app copy. Verify login registration and Keychain entries are removed, the app quits, and its bundle/support folder move to Trash. Deleted credentials cannot be restored from Trash.
- [ ] Inspect the local log for useful lifecycle diagnostics without tokens or source text.
- [ ] On macOS 14 and a Foundation Models-capable Mac, verify runtime compatibility and the appropriate model path.
- [ ] With every app window closed, measure RSS and idle CPU in Activity Monitor. Target under 60 MB RSS and near zero CPU; record actual values. Repeat after opening and closing a brief and prep sheet.

## Automated verification completed

- Fixture-backed source checkpoint, rollback, recovery and isolation tests run without credentials.
- Twenty fixture days pass the brief schema and grounding checker.
- Trigger boundaries, local dates, DST, reminder timing, quiet hours, palette contrast and persistent task checks are covered.
- Settings save, retention, account-scoped deletion and data reset are exercised only in isolated temporary stores.
- The app bundle builds, its plist/project syntax validates, and its executable uses system libraries with a weak Foundation Models dependency.

Unchecked items above are not claimed as verified. No user account was connected and no real user data was deleted during development.
