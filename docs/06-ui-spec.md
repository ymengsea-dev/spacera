# 06 · UI spec

The main window is a `NavigationSplitView`. The sidebar has: **Overview · Apps · Disk Map · Cleanup**. The toolbar has **Scan / Rescan**, scan progress, and search.

## Onboarding (first launch, or when Full Disk Access is missing)
1. A welcome screen: "See what's using your Mac's storage."
2. An explanation of why Full Disk Access is needed and what Spacera never does (no uploads, no permanent deletes), with an **Open System Settings** button.
3. Spacera checks for access automatically when the app comes back to the foreground. Once access is granted: "All set → Start scan."
4. **Continue with limited scan** skips this; the app then shows a persistent banner.

## Overview
- **Capacity bar** (Swift Charts, horizontal stacked bar), split into Apps, App Data, Developer, Documents & Media, System & Other, and Free. Purgeable space is shown with a hatched pattern.
- **Top apps:** the five apps using the most space, each with its icon, name, total size, and a small stacked bar. "See all" opens Apps.
- **Reclaimable** card: the total of the *safe* cleanup items, with a **Review cleanup** button.
- **Growth since last scan:** the top apps and categories that grew, shown as up/down changes.

## Apps
- Switch between a grid (large icons, size under each) and a list (icon, name, size bar, bundle/data split).
- Sort by total size, data size, or name. Filters: All · Leftovers · Running.
- **App detail**, as a sheet or a pushed view:
  - A header with the icon, name, version, and total.
  - Entries grouped by kind (App, Containers, Caches, Support, Logs, Preferences). Each row shows the path, size, a confidence label (exact or likely), a safety badge, a checkbox, and **Reveal in Finder**.
  - A footer with **Move selected to Trash**, which opens the review sheet.

## Disk Map
- A **sunburst** in the centre, drawn with `Canvas`:
  - The rings show folder depth, up to 5 levels at a time.
  - Each segment's angle is proportional to its size; segments smaller than 0.5° are merged into "Smaller items."
  - Colour comes from the top-level category, getting lighter on deeper rings.
  - **Hover:** a tooltip with the name, size, and percentage of the parent folder.
  - **Click:** drills into that folder, with an animation.
  - **Click the centre:** goes up one level.
  - **Right-click:** Reveal in Finder · Add to Cleanup · Copy Path.
  - When a segment belongs to an app, the app's icon is drawn on it if it's big enough.
- A **breadcrumb** trail sits above the chart.
- A **list** on the right shows the children of the current folder, sorted by size, and stays in sync with the chart's hover and selection.

## Cleanup
- **Category cards** in a grid. Each card has an SF Symbol, title, total size, number of items, and a safety colour. Expand a card to see its item list with checkboxes.
- A sticky footer shows "Selected: 12.4 GB" and a **Review…** button.
- The **review sheet** has:
  - A list grouped by safety level.
  - Warnings (app running, item changed).
  - The confirmation checkbox for `userData` items.
  - A **Move to Trash** button.
- Afterwards it shows "Moved 12.4 GB to Trash. Empty the Trash to free the space." with **Open Trash**.
- **History:** recent batches from the `ActionLog`, with Put Back.

## Accessibility and polish
- Every chart has an equivalent list, so VoiceOver users get the same information. Sunburst segments are exposed as accessibility elements.
- Dynamic Type is supported, and the app uses only semantic system colours, so it works in light and dark mode.
- Keyboard: ⌘R rescan, ⌘F search, ⌫ add the selection to cleanup, ⌘↑ go up one level in the Disk Map.
- Sizes are formatted with `ByteCountFormatter` in `.file` style (decimal units, the same as Finder).
