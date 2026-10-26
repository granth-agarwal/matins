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
