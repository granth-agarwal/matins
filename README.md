# Morning Brief

A native macOS menu bar app. Milestone 1 implements the idle agent, YAML config, SQLite storage, and local logging. macOS 14 or later on Apple silicon is required.

## Build and run

With a Swift 6.1 or later toolchain installed, run these commands from the repository root:

```sh
swift test
swift Tools/Build.swift
```

Open `build/Morning Brief.app` in Finder. A sunrise icon appears in the menu bar, with no Dock icon or initial window. Click it to see the ready status, open or reload config, open the data folder, or quit.

Alternatively, open `MorningBrief.xcodeproj` in Xcode 16.3 or later, choose the MorningBrief scheme and My Mac, and run. The Xcode project and Swift package use the same app sources and local modules. The command line builder creates an app bundle and signs it locally for development. Release signing is a later milestone.

## Verify Milestone 1

1. Launch the app and find the sunrise menu bar icon.
2. Confirm the menu says “Ready, Granth” and the app has no Dock icon.
3. Choose Open data folder. Confirm `config.yaml`, `morning-brief.sqlite`, and `morning-brief.log` exist in `~/Library/Application Support/MorningBrief/`.
4. Quit and reopen the app. Confirm the database persists.
5. Change `name` in `config.yaml`, save, and reopen the menu. The greeting updates. Invalid YAML shows a quiet error and leaves the file available for correction.

No timers, network clients, model calls, or authentication run in this milestone. Future modules have empty local package targets. The brief window arrives in Milestone 6.

## Config and diagnostics

The first launch writes the bundled default YAML. Partial configs inherit defaults, including nested settings. Config reloads when the menu opens or Reload config is selected. Invalid edits preserve the previous valid in-memory config and show an error. Correct the file and reload to recover.

The model provider defaults to `apple_on_device`. The `synthesis: anthropic` setting mirrors AGENTS.md and does not enable a cloud provider or cause model calls in this milestone.

The application folder is owner-only, and config, database and logs use owner read/write permissions. The log contains only predefined lifecycle messages with timestamps. It rotates at 256 KiB, keeping one previous file. Startup errors stay visible in the menu, and filesystem logging failures also go to the macOS unified log. Secrets are never accepted by the logging API or stored in the database schema.

The initial migration creates `accounts`, `sync_state`, and `meta`. Checkpoints are keyed by account, source and scope, with an account foreign key. Domain tables will be added with their sync milestones.

## Dependencies and layout

[GRDB 7.11.1](https://github.com/groue/GRDB.swift/tree/v7.11.1) provides SQLite access and migrations. [Yams 6.2.2](https://github.com/jpsim/Yams/tree/6.2.2) provides YAML parsing through Codable. Yams includes its LibYAML parser; no external runtime is bundled. Dependency versions are pinned in the manifests and `Package.resolved`.

`App` contains the SwiftUI entry point, AppKit menu bar delegate, and local logger. `Packages/Config` owns typed configuration and application paths. `Packages/Store` owns the GRDB database. Local packages `Auth`, `Sync`, `Brief`, `Models`, `UI`, `Popup`, and `Trigger` reserve the remaining module boundaries. `Tests` checks config creation, editing, validation, and database reopen behavior.

OAuth client configuration will be documented when Auth is implemented in Milestone 2.
