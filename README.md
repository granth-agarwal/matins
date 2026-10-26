# Morning Brief

A native macOS menu bar app for a daily brief from Google Calendar, Gmail, Drive meeting notes and GitHub. Milestones 1 to 10 are implemented. This is a development build for Apple silicon on macOS 14 or later.

## Build and run

Use Swift 6.1 or later, then run from the repository root:

```sh
swift Tools/Test.swift
swift Tools/Build.swift
open "build/Morning Brief.app"
```

The sunrise icon appears in the menu bar. First launch opens onboarding and settings. There is no Dock icon. Configure your clients, connect accounts, then choose Save and begin. Refresh brief explicitly syncs and generates again. Show today's brief opens saved output or a local preview without a model call or changing lastShown.

Alternatively, open `MorningBrief.xcodeproj`, select MorningBrief and My Mac, then run. Xcode itself was unavailable during implementation; its project structure was checked, but launch needs the manual checks in TESTING.md.

Tools/Test.swift supplies the Swift Testing plugin path when the installed command line tools omit it. Tools/Build.swift creates and locally signs a development app. Developer ID signing, notarization and distribution are outside this build.

## Connect your accounts

Create a Google Desktop OAuth client in your own Google Cloud project. Enable Calendar, Gmail and Drive APIs and configure its consent screen. Add yourself as a test user while the consent screen is in testing. Create a GitHub OAuth app with device flow enabled.

Enter the public client IDs in Settings or config.yaml:

```yaml
oauth:
  google_client_id: YOUR_GOOGLE_CLIENT_ID
  github_client_id: YOUR_GITHUB_CLIENT_ID
calendars: [primary]
```

Use the sign-in buttons. Google uses AppAuth 1.7.6, a random loopback port, PKCE and offline consent. The Calendar, Gmail and Drive read scopes are requested only for enabled sources. OpenID identifies the connected account so local data cannot mix across account changes. No messages, events or files are written. If your client requires a Google client secret, enter it through the secure Settings field.

GitHub requests the notifications scope. Private repository issue searches would require the broad writable repo scope, so those are excluded. Device authorization polls only during an explicit sign-in, respects provider backoff and stops on success, cancellation or expiry.

Tokens, client secrets and model keys are stored only in macOS Keychain. Sign out of Google removes that account's local rows and tasks and closes its brief. Google credentials can be reconnected from the menu when Sign in again appears.

References: [Google desktop OAuth](https://developers.google.com/identity/protocols/oauth2/native-app), [AppAuth](https://github.com/openid/AppAuth-iOS), [GitHub device flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps).

## Models and privacy

Apple on this Mac is the default. Foundation Models is compiled when its SDK is available and used only on macOS 26 or later with an available on-device model. Otherwise, a deterministic brief uses source records. There is no automatic cloud fallback.

To use Anthropic, select it explicitly in Settings, enter a current model ID, confirm the cloud choice and save its API key in Keychain. Cloud mode sends compact source records, including normalized email text, to Anthropic. The selected provider controls both synthesis and sticker actions. The synthesis preference is retained for compatibility and does not override the provider choice.

The daily run makes at most one synthesis call. A clicked sticker or manual Refresh can make another call. Per-item model summaries and a validation retry would conflict with that hard limit, so invalid output falls back immediately. Source text is treated as untrusted input. Schema keys, word limits, references, times and short source excerpts are checked before display.

Only Apple and Anthropic providers are implemented. Reserved OpenAI or Ollama configuration values yield local fallback. Optional Google Chat is not implemented.

No telemetry or analytics is collected. Authentication uses ephemeral sessions. Source requests use read endpoints, and local logs contain predefined lifecycle messages without source text or secrets.

## Sync and daily behavior

The idle agent observes wake, display and session events and keeps one daily trigger timer. It does not poll sources. A fresh process cannot establish lock state through a documented public query, so require_unlocked conservatively waits for an observed unlock or menu interaction. After a cold launch, unlock once or open the menu and choose Reload config to evaluate the rules.

A daily brief requires an awake display, an eligible local time and day, and no successful display today. The lastShown date is saved only after the brief window appears. A separate daily attempt marker prevents a failed save or repeated wake from making another automatic synthesis call.

Sources run concurrently and commit checkpoints only after their records are saved. Drive listing overlaps Calendar sync, then resolves fresh attachment IDs before committing. Source failures appear as quiet retry lines.

Calendar supports configured calendar IDs with separate tokens. A new local day uses a fresh window from yesterday through seven days ahead so unchanged recurring events cannot fall outside a stale window. Further refreshes that day use syncToken. A 410 replaces the window. This trades one bounded daily Calendar sync for reliable moving-window coverage.

Gmail resumes history and falls back to a three-day query if history expired. Category and ignored-sender filters apply; VIP senders rank ahead of otherwise equal undated items. Drive detects notes and transcripts by names and Calendar attachment IDs. Google documents export as text; other attachment types retain metadata. GitHub resumes notifications with ETag/since and searches accessible review requests and assignments.

Before meetings the agent performs one event recheck and schedules the configured reminder times. Cards do not activate the app and honor quiet mode and quiet hours. Enable notification fallback explicitly in Settings. A stopped agent cannot discover later meeting changes, so a previously scheduled fallback notification can be stale until relaunch.

## Preferences and appearance

Preferences live in:

```text
~/Library/Application Support/MorningBrief/config.yaml
```

Settings writes validated YAML with private permissions. External edits reload when opening the menu or brief. Invalid edits preserve the last valid in-memory configuration.

Fraunces, Inter and IBM Plex Mono are bundled with their OFL licenses. The signature can be plain text or a local image path. No signature image was supplied, so the configured name is the default fallback. The reference artifact could not be fetched in this environment; visual comparison remains manual.

Built-in palettes rotate daily or can be pinned. A custom list is also supported:

```yaml
palette:
  mode: auto
  pinned: null
  list:
    - name: Custom
      ground: "#1C2A19"
      glow_1: "#46663B"
      glow_2: "#6E4B2A"
      accent: "#F7EA1B"
popups:
  enabled: true
  quiet_mode: false
  minutes_before: [10, 2]
  quiet_hours: ["22:00-08:00"]
  position: bottom_left
```

Custom accents must meet contrast requirements on the page. The hero adds sufficient shading for title contrast. Reduce Motion disables entrance and glow animations. Keyboard controls are j/k to select tasks, space to check, e to inspect and Escape to close.

## Retention and removal

At the start of a brief run, old briefs and cached bodies are pruned using retention_days, default seven. Unchecked task text and state survive and appear as carry-over. Completed task state is preserved across regeneration. No retention timer or background source polling is used.

Settings includes launch at login, Google sign-out, Delete all data, and Quit and uninstall. Destructive actions require confirmation in the app. Delete all data clears local accounts, tasks, briefs, credentials and caches, disables launch at login, and resets preferences. Uninstall also moves the development app and its cleared support folder to Trash, then quits. Connected services are never modified. Deleted credentials are not recoverable from Trash.

## Verification and project layout

TESTING.md contains the remaining credential and desktop checks. PROGRESS.md records each milestone, validation and fallback. Automated tests include twenty fixture days, checkpoint rollback and recovery, source isolation, schema grounding, trigger boundaries and DST, palette contrast, task persistence, retention and local deletion.

The nine local Swift packages are Auth, Sync, Store, Brief, Models, UI, Popup, Trigger and Config. App contains the menu agent and orchestration. GRDB 7.11.1 provides SQLite and migrations; Yams 6.2.2 provides Codable YAML; AppAuth 1.7.6 provides Google OAuth. No external runtime is bundled.
