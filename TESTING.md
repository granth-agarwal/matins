# Manual acceptance checklist

## 1. Skeleton

- [ ] Run `swift Tools/Build.swift` and open `build/Morning Brief.app`.
- [ ] Confirm sunrise menu icon, no Dock icon, and Ready status.
- [ ] Open data folder and confirm config, SQLite database and log exist.
- [ ] Quit and relaunch. Confirm data persists.
- [ ] Edit name in config and reopen menu. Confirm greeting changes.
- [ ] Enter invalid YAML, verify quiet error, correct YAML and reload.
