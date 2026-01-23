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
