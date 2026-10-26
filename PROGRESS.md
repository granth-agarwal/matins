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

## Milestone 4

Implemented: Gmail history with 404 recovery and category filtering, MIME body normalization, Drive changes and document export, GitHub notifications with ETag/since plus paginated review and assignment searches. All checkpoints commit transactionally. Parallel coordination isolates failed sources. Added source-resume and partial-failure tests.

Fallbacks: optional Chat remains disabled. Drive has no universal Meet-note marker, so name matching plus calendar attachment IDs determines relevance; non-Google-document attachments retain metadata only. Newly discovered Calendar attachments become eligible on the next sync because the sources run in parallel. GitHub private repository search stays excluded for scope safety. Gmail VIP ranking is deferred to deterministic brief ordering; ignore/category filters are implemented.

Manual checks: real source permissions, quota/offline errors, incremental edits and attachment detection in TESTING.md.

Validation: 15 tests passed; development app bundle built successfully.

## Milestone 5

Implemented: complete Codable brief schema, word/count limits and source provenance validation, Apple Foundation Models guarded for macOS 26, Anthropic provider with explicit config model ID and Keychain key, saved JSON and deterministic fallback. Twenty fixture days test valid grounded output; adversarial tests reject invented text and URLs.

Fallbacks: the hard one-model-call limit takes precedence over per-item model summaries and a second validation call. Long text is normalized locally; invalid output falls back immediately. Grounding is intentionally conservative: model prose must be source excerpts, greeting is deterministic, replies/skip/carry-over are reserved empty for synthesis. Apple unavailable, unconfigured Anthropic, OpenAI or Ollama selections yield local rule-based output; only the required one cloud provider is implemented. No automatic cloud fallback occurs. Per-item summaries and retry are not implemented due to the explicit hard limit.

Manual checks: actual on-device availability, explicit cloud consent/configuration, offline/model failures and output review.

Validation: 19 tests passed, including the 20-day fixture checker. Release configuration development bundle built successfully.

## Milestone 6

Implemented: dark editorial window, scrolling hero, seven daily palettes with same-day persistence and pinning, OFL Fraunces/Inter/IBM Plex Mono bundled with licenses, text or local image signature, focus and prep stickers, persistent checkboxes, updates, selectable schedule, source links, empty states, Escape and j/k/space/e navigation, Reduce Motion guards and staggered entrance.

Fallbacks: reference artifact cannot be fetched in this environment and no signature image exists, so the written specification and configured name are used. Pixel comparison is pending. Custom palette lists remain unsupported (built-in palettes and pinning work). The meeting panel stacks beneath its time list at current widths. Sticker content is temporarily stubbed until milestone 9, per build order. Explicitly selected cloud provider setup remains in milestone 10.

Manual checks: pixel review, real font rendering, light/dark system appearance, keyboard/VoiceOver and Reduce Motion in TESTING.md.

Validation: 21 tests passed and development bundle built. The installed macOS 27 SDK shadows the legacy State property wrapper with a macro absent from its CLI tools; a type alias selects the compatible property wrapper without changing the deployment target.

## Milestone 7

Implemented: pure local-time trigger rules, wake/display/session event observers, one nonrepeating timer, timezone/clock rescheduling, persistent lastShown after actual display, concurrent-run exclusion and a daily attempt guard. Cached output is reused if the machine locks during generation. Manual Show does not touch lastShown or run the model. Trigger tests cover all gates, local dates and DST.

Fallback: macOS exposes session switching but no documented public lock-state query. Lock/unlock distributed notifications are observed with a conservative unknown state on cold launch. With require_unlocked enabled, the first automatic run waits for an observed unlock or menu interaction. No private lock-state fields are assumed. Hardware sleep, loginwindow notifications and display configurations require manual checks.

Manual checks: wake/lock/call/external display/clock matrix in TESTING.md.

Validation: all 24 tests passed; development app bundle built successfully.

## Milestone 8

Implemented: nonactivating floating NSPanel reminders, active-screen bottom-left placement, live countdown while visible, overlap queue, Join/Snooze/Ignore, expiration, quiet policy and persisted reminder state. The scheduler registers one T minus 15 recheck and configured popup timers, replacing moved meetings and removing cancelled meetings. Notification fallback categories and actions are scheduled in advance; foreground banners are suppressed to avoid duplicates. No resident countdown runs when the card is closed.

Fallbacks: notification permission is requested explicitly from Settings in milestone 10. A stopped agent cannot recheck changed meetings, so already scheduled fallback notifications can be stale until relaunch. This is inherent to the idle-agent and no-extra-process constraints. Custom popup placement and system Focus behavior require a real desktop session to verify.

Manual checks: placement, focus, Spaces, notification permissions/actions and moved meetings in TESTING.md.

Validation: 27 tests passed and development bundle built. Cancellation now removes every scheduled lead time, async notification registrations use generation IDs, and fallback actions restore the selected meeting from SQLite on relaunch.

## Milestone 9

Implemented: Prep me and Let's do it now run one explicit provider call with selected-source and attached-document context, show a note sheet, reject invented or oversized excerpts and fall back to source notes. Duplicate action calls are gated. Tests cover one-call behavior, context isolation, invalid notes and missing sources.

Fallback: prep text is restricted to grounded short excerpts, matching the conservative validation used for synthesis. No source service is written to and no draft is sent.

Manual checks: sticker interactions, real model output and sheet accessibility in TESTING.md.

Validation: 29 tests passed; development app bundle built successfully. The temporary sticker placeholder is removed.

## Milestone 10

Implemented: first-run scope/privacy disclosure, validated settings saves, public OAuth client fields, secure Keychain credential entry, explicit Anthropic choice, notification authorization, launch at login, local sign-out, data reset and confirmed uninstall. Uninstall clears local credentials/data and login registration, trashes the app/support folder and quits. Retention runs before brief generation, strips old cached bodies, removes expired briefs and preserves unchecked carry-over and completed task state. Account identity comes from Google's OpenID token; account switches and disabled sources cannot mix records into the current brief.

Integration completed: configurable Calendar IDs, fresh daily rolling windows with same-day incremental tokens, same-run Drive attachment resolution, Gmail VIP ranking, reply provenance, strict JSON field checks, explicit null due values, conservative model labels, custom palettes with contrast shading, side-by-side schedule details, all-day labels, live Join activation with a one-shot wait, tick drawing and released window content when closed. Authentication sessions are ephemeral. The build helper signs without forcing replacement.

Fallbacks and tradeoffs: Calendar does a bounded full window sync on each new local day to keep recurring instances covered; additional same-day syncs use saved tokens. The hard one-call model limit still excludes per-item model summaries and validation retries. Generated text remains short source excerpts. Optional Chat and reserved OpenAI/Ollama providers are not implemented; they do not cause network calls. Drive exports Google documents and uses metadata for other file types. The absent signature uses configured text, and the inaccessible mockup still requires a manual pixel comparison. Cold-launch lock-state conservatism and stale fallback notifications when the agent is stopped remain as documented above.

Resolved earlier temporary gaps: custom palettes, schedule detail placement, sticker actions, model credential settings, Gmail VIP ranking, reply/skip validation, Calendar window advancement and new Drive attachments are implemented. Carry-over comes from durable local task state, outside model synthesis.

Manual checks: onboarding and credential flows, launch at login, notification actions, wake/lock/display behavior, pixel/accessibility review, idle RSS/CPU, older macOS runtime and confirmed deletion/uninstall. All are listed in TESTING.md. No real credentials or account data were used for validation.

Validation: final authentication cancellation guards passed the complete suite: 38 tests in 11 suites, including the 20-day fixture checker. The development app bundle built successfully, its code signature verifies, plist/project syntax validates, and Foundation Models is confirmed weak-linked. Font names were checked with CoreText. No real account data was changed. Vendor OFL license texts remain verbatim, including their original punctuation; authored UI and documentation avoid the prohibited punctuation. Milestone 11 is excluded.
