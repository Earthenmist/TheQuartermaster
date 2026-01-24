## 0.2.108 (2026-01-24)
- Options: "Show Item Locations" (Tooltip Enhancements) is now enabled by default.
## 0.2.107 (2026-01-24)
- Items tab: item count label now uses the current theme/class colour.

## v0.2.106 (2026-01-24)
- PvE: Added a 'Great Vault' header to the left card (matching Raid Lockouts styling) and reflowed the vault grid spacing.

## v0.2.105 (2026-01-24)
- PvE: Centred and enlarged the Raid Lockouts card title to match the Overall Score card.

## v0.2.104 (2026-01-24)
- PvE: Replaced the right-side "Work in Progress" card with a Raid Lockouts summary (shows saved raid lockouts with bosses killed and reset timer).

## v0.2.103 (2026-01-24)
- PvE: Removed Great Vault header row (Slot/1/2/3) and reflowed progress rows to avoid empty space.

## 0.2.101 - 2026-01-24
## v0.2.102 (2026-01-24)
- PvE: Improved visibility of Mythic+ dungeon key level overlays (stronger contrast + outlined text).

- PvE: Vault slot tooltips now show **Status: Complete** when progress meets/exceeds requirement (prevents values like 3/1).

## 0.2.100 - 2026-01-24
- PvE: Great Vault progress tooltips now show earned level per individual slot cell (not headers).
- PvE: Removed hover tooltip from Slot column headers.

## v0.2.99 — 2026-01-24
- PvE: Great Vault progress tooltips now show the earned level (e.g. +10) where available and are visible when viewing other characters.

## v0.2.98 — 2026-01-24
- PvE: Fixed a Mythic+ completion error where `GetCharacterKey()` could be missing and a `time` event argument could shadow the global `time()` function.

## v0.2.96 — 2026-01-23
- Currency: Removed the view-mode toggle button and locked Currency tab to **Character Only** view (alts list visible).

## v0.2.93 — 2026-01-23
- Currency: Fixed War Within header name mismatch ("The War Within" vs "War Within") so War Within currencies and Season 3 subheading both display correctly.

## v0.2.92 — 2026-01-23
- Currency: Added missing Season 3 nesting under Legacy → War Within to match Blizzard ordering in both All Warband and Character Only views.

## v0.2.91

- Currency tab: replaced misleading Filter toggle with **All Warband / Character Only** view modes.
- All Warband (default): hides alt list and shows current character currencies plus warband/account-wide currencies.
- Currency headers now render in Blizzard-like order with nested subheadings (Miscellaneous → Timerunning, Legacy → expansions).

## 0.2.90 – 2026-01-23

- Currency: Fixed a bug in the Non-Filtered (Blizzard header) renderer that prevented headers/currencies from displaying.

## 0.2.89 – 2026-01-23

- Currency: Adjusted non-filtered currency header rendering to follow Blizzard header ordering consistently (Retail and Midnight). Season headers are now nested under the current expansion header instead of being promoted to the top.

## 0.2.88 – 2026-01-23

- PvE: Great Vault progress cells (Raid / Dungeons / World) now show Great Vault-style tooltips on hover (matching the corresponding Great Vault tile).
- PvE: Removed slot-number header tooltips (tooltips now live on the actual progress cells).

## v0.2.87 (2026-01-23)

- PvE: Added hover tooltips to Great Vault slot column headers (1/2/3) to mirror Great Vault column meaning (Raid / Dungeons / World).
- PvE: Renamed the M+ tooltip label to “Dungeons” for consistency with the Great Vault UI.

📜 Changelog – Version 0.2.86

📅 Release Date: 2026-01-23

🛠️ Changes & Improvements

– PvE: Renamed the Great Vault header from “Type” to “Slot”
– PvE: Weekly reset timer now reads “Weekly Reset in: <time>”

---

📜 Changelog – Version 0.2.85

📅 Release Date: 2026-01-23

🛠️ Changes & Improvements

– Notifications: Toast titles now follow the active theme (no hard-coded purple)
– Notifications: Fixed rare title-color formatting edge cases that could prevent some toasts from appearing
– Notifications: Update notes can now also show after a /reload (still only once per version)

---

📜 Changelog – Version 0.2.84

📅 Release Date: 2026-01-23

🛠️ Changes & Improvements

– Characters: Clicking a profession icon for your currently logged-in character now opens that profession window
– Version bump housekeeping (TOC + NotificationManager)

---

📜 Changelog – Version 0.2.82

📅 Release Date: 2026-01-23

🛠️ Changes & Improvements

– Rewrote the Information window text to reflect the current addon tabs and features  
– Added a version line to the Information window (reads from addon metadata)  
– Version bump housekeeping (TOC + NotificationManager)

---

📜 Changelog – Version 0.2.81 (Stable Baseline)

🎯 Status: Internal stable build
🛠️ Focus: Stability, performance, and Midnight readiness

– Removed unused libraries and legacy code paths  
– Simplified and hardened settings UI  
– Embedded performance optimisations for bag/bank scanning  
– Reduced API and event spam  
– Improved tooltip efficiency  
– Items list view now starts with categories collapsed  
– General internal cleanup and future-proofing  

⚠️ Notes
This version is the first internal “stable” baseline and is not a public release yet.
