# 01 · Product vision

## Problem
macOS's *Storage settings* lump most usage into vague buckets like "System Data," "Other," and "Applications." That's not enough to answer simple questions:

- **Which app** is actually using my storage, counting its caches, containers, and support files as well as the `.app` itself?
- What is safe to delete?

Some technical users now ask an AI agent like Claude to inspect their disk and draw a chart of the results. That works well, but most people don't have, or don't want, an agent with shell access to their Mac.

## Vision
A native, standalone Mac app that does the same job:

1. Scans the disk quickly.
2. Shows storage **per app, with the app's own icon**, in a simple visual way.
3. Shows the whole disk as an interactive map.
4. Lets you clean up **safely**: a review step first, everything goes to the Trash, and system paths are never touched.

## Target users
- **Everyday Mac users** whose disk is full and who don't know why.
- **Developers**, whose disks fill up with Xcode, simulators, `node_modules`, Docker, and package caches.
- **Creative professionals** with large app suites (Adobe, DaVinci, Unity) and their caches.

## MVP scope
- Per-app storage: bundle size plus Library data, with icons and confidence labels.
- Leftovers from uninstalled apps.
- Disk map: an interactive sunburst with drill-down and a synced list.
- Smart categories: developer junk, caches and logs, large files, old downloads, iOS backups, the Trash.
- Cleanup that moves files to the Trash after a review sheet.
- Onboarding for Full Disk Access, and a limited mode if it's declined.
- Scan snapshots, to show growth since the last scan.
- Auto-update through Sparkle.

## Non-goals (for now)
- Mac App Store distribution, because the sandbox would block the core feature.
- Deleting files permanently (bypassing the Trash).
- Cloud features, accounts, or telemetry.
- Duplicate-file detection or photo similarity.
- Managing the internals of Time Machine snapshots or Docker volumes. These are shown for information only.

## Success criteria
- A full scan of a typical 500 GB disk finishes in under 60 seconds on Apple silicon.
- Per-app totals are within 5% of `du` for the same paths.
- Nothing is ever removed without a review step, and nothing ever bypasses the Trash.
