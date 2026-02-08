# The Quartermaster

**The Quartermaster** is a comprehensive Warband-aware inventory, currency, profession, and character overview addon for World of Warcraft, designed for the *Midnight* / *The War Within* era.

It provides a unified dashboard to track your entire account’s progression, storage, and collectables across all characters — while staying visually aligned with Blizzard’s modern UI style.

---

## ✨ Features

### 🧙 Character Overview
- Full Warband-wide character list.
- Class icons, faction flags, item level, and playtime.
- Profession display for the current character (clickable to open professions).
- Guild membership summary.
- Rested XP, max XP, and fully rested time tracking.

### 🎒 Inventory & Storage
- Inventory, personal bank, and Warband bank views.
- Storage usage overview with progress bars.
- Total slot counts and usage percentages.
- Section-based category grouping with collapsible headers.
- Visual consistency across list and grid views.



### 🔎 Global Search (New in v1.0.13)
- Search **Items + Currency** across all cached characters and storage locations.
- Mode selector: **All / Items / Currency**
- Optional: **Include Guild Bank** (cached).
- **Pin/Unpin** results to a Watchlist (star icon on rows).
- **Right-click** result rows for quick actions (Pin/Unpin, Copy Item Link).

### ⭐ Watchlist (New in v1.0.13)
- Keep a curated list of items and currencies you care about.
- Shows **total owned across your Warband**, with tooltip breakdowns by character/location.
- You can Pin/Unpin from:
  - Global Search results (star or right-click)
  - Items and Storage screens (List or Slot view) via **right-click** row menu

### 💰 Currencies
- Warband-wide currency tracking.
- Unified currency list with filters.
- Blizzard-style buttons and theming.

### 🧪 Professions
- Profession overview for all characters.
- Profession icons and specialisation visibility.
- Direct profession access for the active character.

### 🐾 Companions
- Total companion count (battle pets).
- Warband-wide companion summary.

### 📊 Statistics
- Storage usage breakdown.
- Guild population summary.
- Unguilded character counts.
- Total companions and collectables.

### 🎨 UI & Theming
- Blizzard-style frame layout.
- Class-colored or static theme support.
- Modular UI panels (Characters, Inventory, Bank, Currencies, Professions, Statistics, Experience).
- Consistent button styles and icons.
- Minimap button (LibDataBroker).

### 🔔 Notifications
- Version update notifications.
- Collectable unlock notifications (mounts, pets).
- Loot-related event triggers.
- Themed notification windows.

### ⚙️ Configuration
- Built using Blizzard’s modern Settings API.
- Toggleable features and UI elements.
- Tooltip enhancements.
- Theme customisation.
- Persistent saved variables.

---

## 📦 Installation

1. Download the latest release.
2. Extract the `TheQuartermaster` folder into:

   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```

3. Restart World of Warcraft or reload the UI (`/reload`).

---

## 🧭 Usage

- Open the main window via:
  - The minimap button, or
  - Slash command:
    ```
    /tq
    ```

- Navigate between panels using the footer buttons:
  - Characters
  - Inventory
  - Bank
  - Currencies
  - Professions
  - Statistics
  - Experience

---

## 🧰 Dependencies

- **LibDataBroker-1.1**
- **LibDBIcon-1.0**
- **Ace3** (embedded)

---

## 🛠️ Compatibility

- Retail 11.2.x (*The War Within*)
- Midnight 12.x (Beta)
- Fully Warband-aware.

---

## ❤️ Credits

Created and maintained by **Lanni**.

Special thanks to all beta testers and contributors who helped refine TheQuartermaster during its pre-release phases.

---

## 📝 License

This addon is provided as-is for personal use.
Redistribution or modification without permission is not permitted.


---

## 🧭 Usage Tips
- The Quartermaster builds its database as you play. If something is missing, log into that character and open the relevant UI once (bags/bank/warband bank/guild bank).
- **Pinning to Watchlist**
  - Global Search: click the ⭐ star on a row or right-click the row.
  - Items/Storage: right-click an item row (List or Slot view) → Pin/Unpin.
- **Copy Item Link**: right-click an item row → Copy Item Link (opens it in chat for easy Ctrl+C).

## 📅 Release Notes
- v1.0.13 (2026-02-06) – Global Search + Watchlist, right-click menus, and pinning improvements.

