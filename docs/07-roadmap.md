# 07 · Roadmap

## MVP build order
| Step | Milestone | Done when |
|---|---|---|
| 0 | Repo, docs, and CLAUDE.md | First commit |
| 1 | Project skeleton: XcodeGen `project.yml`, app + test targets, folder structure | `xcodegen generate`, `xcodebuild build`, and `xcodebuild test` all pass |
| 2 | `Core/Models` + Scanning service (`DiskScanner`, `VolumeInfo`) | Tests on fixture trees pass: sizes, hard links, cancellation |
| 3 | Apps service (`AppCatalog`, `AppFootprintResolver`, overrides) | Fixture tests pass; results check out against the real `/Applications` |
| 4 | Cleanup service (rules, `SafetyGuard`, `Trasher`, `ActionLog`) | Tests confirm blocked paths are rejected and items end up in the Trash |
| 5 | Features: Overview → Apps + Detail → Disk Map → Cleanup + Review → Onboarding | Each ViewModel is tested with fake services; manual run looks right |
| 6 | Snapshot persistence and growth view | The second launch shows the previous results instantly |
| 7 | `scripts/release.sh` | An ad-hoc signed `.dmg` is produced in `build/<version>/` |

## After the MVP
- A menu bar item showing free space, with an alert when the disk is low.
- Scheduled background scans (`SMAppService` login item).
- Duplicate-file finder.
- Localization.
- Optional per-app "Uninstall completely": the app bundle plus all of its data, after a review step.
