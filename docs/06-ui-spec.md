# 06 · UI spec

The main window is a `NavigationSplitView`. The sidebar has: **Overview · Apps · Disk Map · Cleanup**. There is no toolbar scan button. Instead, a **scan panel** at the bottom of the sidebar is visible on every screen: it shows when the last scan ran with a **Scan Disk**/**Rescan** button, and while a scan runs, its progress with a **Stop Scan** button. The menu bar has the same commands (**Scan › Rescan** ⌘R, **Stop Scan** ⌘.). Before the first scan, the Overview's start screen also has a large **Scan Disk** button. Screens that need a scan show the same "No scan yet" page with **Scan Disk**, or with progress and **Stop Scan** while one runs.

## Look and feel
"Warm modern": native macOS chrome (sidebar, toolbar, sheets, controls) with a warm, editorial content area. All tokens live in `Spacera/Shared/Theme/Theme.swift`, and each one has a light and a dark value.
- **Surfaces:** a paper background behind every screen, a slightly lighter surface for the few raised panels, and warm hairlines instead of grey dividers.
- **Colour:** muted mid-century tones taken from the app icon (slate, rust, sage, mustard, mauve, teal, peach, walnut). The accent is rust, set as `AccentColor` in the asset catalog, so native controls use it too. Safety levels: safe is sage, review is mustard, your data is rust, info is stone.
- **Type:** New York (the system serif) for headline numbers and section headings; SF Pro for everything else. Coloured text is mixed toward the ink (`Color.readable`) so it stays legible on paper.
- **Layout:** the Overview is a page, not a grid of cards. Sections are separated by space and hairlines; cards are kept for banners and expandable groups.

## Onboarding (at launch, when Full Disk Access is missing)
Shown at each launch without Full Disk Access, unless the last scan was already a limited one (the user chose that, and the Overview still offers access). If access is revoked after a full scan, it comes back.
1. A welcome screen: "See what's using your Mac's storage."
2. An explanation of why Full Disk Access is needed and what Spacera never does (no uploads, no permanent deletes), with an **Open System Settings** button.
3. Spacera checks for access automatically when the app comes back to the foreground. Once access is granted: "All set → Start scan."
4. **Continue with limited scan** skips this; the app then shows a persistent banner.

## Overview
- **Capacity bar** (Swift Charts, horizontal stacked bar), split into Apps, App Data, Developer, Documents & Media, System & Other, and Free. Purgeable space is shown with a hatched pattern.
- **Top apps:** the five apps using the most space, each with its icon, name, total size, and a small stacked bar. "See all" opens Apps.
- **Reclaimable** card: the total of the *safe* cleanup items, with a **Review cleanup** button.
- **Since last scan:** after a second scan, the change in used space and the biggest app and category changes (50 MB or more).

## Apps
- Switch between a grid (large icons, size under each) and a list (icon, name, size bar, bundle/data split).
- Always sorted largest first; there is no search or sort control. Filter tabs (All Apps · Leftovers · Background Items) sit on the right of the toolbar, so the screen title stays on the left like every other screen.
- Before a scan has run in this session, the list shows app sizes from the last saved scan summary.
- **App detail**, as a sheet or a pushed view:
  - A header with the icon, name, version, and total.
  - Entries grouped by kind (App, Containers, Caches, Support, Logs, Preferences). Each row shows the path, size, a confidence label (exact or likely), a safety badge, a checkbox, and **Reveal in Finder**.
  - A footer with **Move selected to Trash**, which opens the review sheet.

## Disk Map
- A **treemap** on the left: the current folder's children as rounded blocks, each with an area proportional to its size, laid out "squarified" so blocks stay close to square.
  - A child keeps its own block if it's at least 0.4% of the folder or at least a quarter the size of the largest child, so a folder of many similar items isn't merged away. The rest (and anything past the 200th) share one "smaller items" block in stone; a single leftover child is drawn on its own. Merged children are stone in the list too, and hovering one there lights the "smaller items" block.
  - Sorting and merging is done once per folder and cached in `DiskMapViewModel`; only the placement is recomputed when the chart resizes.
  - Each block has its own colour from the series, softened toward the paper so the name and size (in the serif) read on it. Labels appear only on blocks big enough to hold them; app bundles also show their icon.
  - **Hover:** the block lifts and the others fade back; a tooltip gives the name and size.
  - **Click:** opens that folder. **Right-click:** Open · Reveal in Finder · Copy Path · Move to Trash….
- A **breadcrumb** trail sits above the chart, with the current folder's total beside it on the right (never over the crumbs). Deep trails open scrolled to the end, so the current folder is visible. The back button goes up one level.
- A fixed-width **list** on the right shows the same children, largest first, in the same colours, and stays in sync with the chart's hover.

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
- Every chart has an equivalent list, so VoiceOver users get the same information. Treemap blocks are exposed as accessibility elements.
- Dynamic Type is supported. Every theme colour has a light and a dark value, so the app works in both modes.
- Keyboard: ⌘R rescan, ⌫ add the selection to cleanup, ⌘↑ go up one level in the Disk Map.
- Sizes are formatted with `ByteCountFormatter` in `.file` style (decimal units, the same as Finder).
