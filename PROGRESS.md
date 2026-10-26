# Build progress

Scope: milestones 1 to 10, on branch `build/v0.1`. Release is excluded.

## Milestone 1

Implemented: existing menu bar skeleton, merged YAML configuration, private SQLite database, redacted rotating lifecycle log and config/store tests reviewed and adopted as the initial milestone.

Skipped: GUI acceptance requires a user session. No implementation stubs in this milestone.

Manual checks: launch the bundle, find the sunrise menu, verify database creation and restart persistence. See TESTING.md.

Validation: `swift test` passed all 3 tests including 6 invalid-config cases. `swift Tools/Build.swift` produced the signed development bundle. Xcode is not installed; its project will be maintained, but Xcode launch remains manual.

## Milestone 2

Implemented: AppAuth loopback PKCE, Google offline tokens in Keychain, GitHub device flow with bounded polling and backoff, cancellation, persisted authorization, config client IDs, menu sign-in and quiet error handling. Added auth policy tests.

Fallback: GitHub private issue searches are excluded because OAuth offers no read-only private repository scope. Device-flow token polling is the necessary exception to the source polling prohibition, active only during user sign-in. Client secrets are optional Keychain values, never config fields.

Manual checks: credentialed sign-in, restart, consent revocation and Keychain denial in TESTING.md. These cannot be verified without user accounts.

Validation: 5 tests passed. Swift 6.4 command line tools omit the Testing macro search path; Tools/Test.swift supplies it. The native engine was also tried but cannot locate Testing.framework on this installation. The app builds with the default engine.

## Milestone 3

Implemented: typed Calendar responses, time zones and all-day dates, pagination, sync tokens, 410 replacement, cancelled/declined removal, source/account-scoped atomic SQLite commits and a manual Calendar refresh showing today's stored events. Tests cover pagination, rollback, token expiry, cancellation and all-day parsing.

Fallback: the menu currently syncs the primary calendar; the engine accepts any calendar ID and keeps separate checkpoints. Events are displayed locally instead of printed into a log to avoid leaking calendar contents. The initial window is yesterday through seven days ahead, as specified; an unchanged event beyond that initial window may require a later full sync when the window advances. This will be addressed in the daily-run integration.

Manual checks: credentialed incremental refresh and recurring-event cases in TESTING.md.

Validation: 9 tests passed, including page failure leaving no rows or checkpoint and 410 recovery. Development bundle build passed before commit.
