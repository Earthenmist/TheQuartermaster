# The Quartermaster  
**Account-Wide Inventory, Warband & Character Overview for World of Warcraft (Midnight-Ready)**

---

## Overview

**The Quartermaster** is a modern, Blizzard-styled account dashboard addon for World of Warcraft that gives you a unified view of:

- All your characters  
- Their inventories, banks, Warband banks, and currencies  
- Item storage and free slot usage  
- Guild membership and reputation  
- Experience, rested XP, and playtime  
- Account-level statistics and summaries  

Built around Warbands and Midnight API changes, The Quartermaster replaces the need for multiple “altoholic-style” addons with a single, clean, expandable UI that stays visually consistent with Blizzard’s default interface.

---

## Key Features

### 📦 Unified Storage View
- View **Inventory**, **Personal Bank**, **Warband Bank**, and **Bags** per character  
- See:
  - Used slots  
  - Free slots  
  - Total capacity  
- Toggle between **List View** and **Grid View**  
- Category sections (collapsed by default)  
- Search and filter items  
- Item tooltips with full details  
- Visual storage usage indicators  

---

### 👤 Character Dashboard
- Account-wide list of all characters  
- Displays:
  - Character name  
  - Level  
  - Class  
  - Faction  
  - Server  
  - Last online  
  - Gold  
  - Guild  
  - Guild rank  
  - Guild reputation  
- Class icons and faction flags  
- Blizzard-styled rows and headers  

---

### 🏦 Warband-Aware
- Fully integrated with Warband systems  
- Supports:
  - Warband Bank storage  
  - Warband currencies  
  - Cross-character tracking  
- Designed for Midnight and post-TWW architecture  

---

### 💰 Currency Tracking
- View all tracked currencies per character  
- Account-wide totals  
- Blizzard iconography  
- Clean, scrollable layout  
- Filterable currency list  

---

### 📊 Account Statistics
- High-level summaries including:
  - Total gold across all characters  
  - Total items stored  
  - Storage usage  
  - Total companions (battle pets)  
  - Mounts (where available)  
- Storage breakdown:
  - Inventory slots  
  - Bank slots  
  - Warband slots  
  - Total free space  

---

### 🎮 Experience UI
- Per-character experience tracking  
- Displays:
  - Total played time  
  - Rested XP (percentage or max level)  
  - Maximum rested XP  
  - Time until fully rested  
- Blizzard-style information boxes  
- Theme-aware colors  
- Tooltips on:
  - Rested XP  
  - Max XP  
  - Fully Rested In  

---

### 🛡 Guild Overview
- Account-wide guild visibility  
- Shows:
  - Character name  
  - Level  
  - Guild  
  - Guild rank  
  - Guild reputation  
  - Server  
- Faction icon next to character name  
- Server column for cross-realm clarity  

---

### 🎨 UI & Theming
- Blizzard-styled frame  
- Gold borders and textured backgrounds  
- Theme color support  
- Clean tab-based navigation  
- Footer-based controls  
- Consistent spacing and typography  
- Responsive resizing  

---

### ⚙️ Settings & Configuration
- Built-in options panel  
- Controls for:
  - Theme color  
  - UI scaling  
  - Display toggles  
  - Minimap button  
  - Auto refresh behavior  
- Persistent saved variables  
- No external config dependency  

---

### 🔔 Notifications & Refresh Logic
- Controlled refresh behavior  
- Avoids spam on:
  - Zone change  
  - Hearthstone  
  - Channel swaps  
- Manual refresh support  
- Midnight-safe timing logic  

---

### 🧭 Minimap Integration
- LibDataBroker support  
- Toggle main window  
- Tooltip with summary info  
- Drag-to-move minimap icon  

---

## Midnight Compatibility

The Quartermaster is fully hardened for **Midnight**:

- Handles “secret” API values safely  
- Avoids restricted calls during combat  
- Suppresses UI actions when prohibited  
- Uses validated cooldown and timing logic  
- Compatible with:
  - Retail 11.2.x  
  - Midnight 12.x  

No configuration reset required.

---

## Why The Quartermaster Exists

The Quartermaster is not a clone of Altoholic.

It is designed to be:

- Lightweight  
- Blizzard-styled  
- Warband-first  
- Expandable  
- Midnight-safe  
- Account-centric  

It replaces the need for:

- Multiple inventory trackers  
- Separate currency addons  
- Basic altoholic dashboards  
- Manual storage spreadsheets  

---

## Installation

1. Download the latest release `.zip`  
2. Extract into:

```
World of Warcraft/_retail_/Interface/AddOns/TheQuartermaster
```

3. Restart the game or reload the UI  

---

## Usage

- Open the main window using:
  - The minimap button  
  - The UI button in the footer  
- Navigate using the top tabs:
  - Characters  
  - Inventory  
  - Bank  
  - Warband  
  - Currencies  
  - Experience  
  - Statistics  
  - Guild  
- Use:
  - Search boxes  
  - View toggles  
  - Expand/collapse sections  

---

## Development Status

**Current Version:** 0.2.81  
**Status:** Stable Baseline  
**Expansion:** The War Within / Midnight  

This version represents the stable foundation for:

- UI polish  
- Feature expansion  
- Performance tuning  
- Additional modules  

---

## Planned Enhancements

- Upgrade highlighting  
- Item source tracking  
- BiS tagging  
- Raid & dungeon loot integration  
- Exportable summaries  
- Guild-wide inventory snapshots  

---

## Credits

- Developed by **Lanni Alonsus**  
- Powered by **Ace3**  
- Blizzard-styled UI framework  
- Warband & Midnight API support  

---

## Support & Feedback

If you encounter issues or have feature suggestions:

- Please include:
  - Version number  
  - Error logs  
  - Screenshots (if UI related)  

Feature requests and feedback are welcome.
