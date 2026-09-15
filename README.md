# The Quartermaster

The Quartermaster is a modern Warband and character management addon for Retail
World of Warcraft, built to make keeping track of your account easier.

It brings together characters, storage, professions, weekly activities, reputations,
currencies and collections in one place. Find a crafting reagent, check an alt's
equipment or decide what to work on next without switching through every character.

***

## ✨ Features

The Quartermaster gives you a useful overview of your Warband and the characters
you play.

You can:

* Browse your characters, set favourites and keep a shared character order.
* Check equipment, profession gear, rested XP, played time and guild membership.
* Find cached items across bags, banks, the Warband Bank and guild banks.
* Search recipes and materials, then build separate crafting watchlists.
* Review supported weekly activities, Great Vault progress, Mythic+ and raid lockouts.
* Browse reputations and currencies across your characters.
* See collection, gold, storage and character summaries in Account totals.
* Search cached mail attachments and review expiry reminders.
* Hide gold with Discretion Mode and adjust the window size and scale.

***

## 🧭 Main Sections

| Section | What you can do |
| --- | --- |
| **Dashboard** | Start with character, Vault and gold summaries, a compact roster preview, weekly follow-ups and shortcuts. |
| **Characters** | Browse your roster, set favourites and drag names to reorder them. Check rested XP, played time, guilds, equipped gear and collection setup. |
| **Storage** | Find items across inventories, personal banks, the Warband Bank and cached guild banks. Browse grouped lists or switch Bags & banks to Slot View. |
| **Professions** | Browse learned/unlearned recipes and learning instructions, plan ingredients, filter materials, compare profession gear, concentration and cooldowns, and track expansion-specific Knowledge balances and sources. |
| **Progression** | Review supported weekly activities, Great Vault progress, Mythic+ and raid lockouts. Switch characters with the dropdown, or browse reputations, currencies and dated offline accepted quest logs. |
| **Account totals** | See gold, collections, character milestones, play time, equipment, storage capacity and guild summaries. Hover for each total's scope. |
| **Wealth** | Follow daily gold history and rank recorded item earnings by period, character or vendor/auction source. Click an item for its earnings graph and recent transactions. History starts when tracking begins; auction proceeds are dated when collected, and unclassified changes stay separate. |
| **Auctions** | Browse recorded owned listings under Storage and find them in Global Search. Open the Auction House on each seller to refresh; listed items remain separate from available crafting stock and earned gold. |
| **Search** | Search cached items, reagents and currencies, with optional guild bank results and completed mailbox snapshots. |
| **Watchlist** | Keep general pins or separate recipe crafting lists, set craft quantities, review shortages and locate ingredients. |

Storage, reputation and currency groups start collapsed. Opening another group at
the same level closes the previous one. The shared character order follows you
between character lists.

***

## 📚 Profession Knowledge

Open **Professions → Knowledge**, then open your own Midnight or The War Within profession
with recipe collection enabled. Choose a scanned crafter and expansion to see unspent
Knowledge, specialization progress and a source checklist. Click sources for guidance
and treasure waypoints; filter to First crafts for recorded learned opportunities.

Snapshots are dated. Weekly observations need refreshing after reset. Some sources
remain guidance-only while their rules are verified, and catch-up tracker values do
not guarantee available points. Treasure completion records collection, so remember
to use the item.

## 🧪 Crafting & Watchlists

Enable recipe tracking in Settings, then open each crafter's **own** profession
window, including Cooking. Leave it open until collection finishes; The Quartermaster
can be closed or on another page while recipes and ingredients are collected.
Linked and guild profession views are not saved as that character's recipes.

Choose **Learned**, **Unlearned** or **All recipes**, then filter by crafter,
profession or expansion. Unlearned on the all-crafter view means no scanned crafter
knows the recipe; characters without a scan are not counted as missing. Expand a
recipe for the learning instructions provided by the profession window.

**Concentration** shows discovered profession pools with their caps and recharge
estimates. Open each character's own crafting professions to refresh them. Offline
amounts are estimates from the last recorded rate; shared expansion pools are
counted once. Select **All expansions** to include older supported pools.

Track a recipe to create its own crafting list. Choose the number of crafts, review
ingredient targets and shortages, and decide whether to include cached guild bank
holdings. General pins remain separate. Pin items and currencies from Search using
the star or right-click menu. With Auctionator loaded, **Export (Auctionator)** prepares
a shopping-list import.

***

## 📚 How Your Data Is Collected

The Quartermaster builds snapshots as you play. Offline characters are shown from
their latest saved data; the addon does not remotely refresh their bags or banks.
Open the relevant window on that character when a snapshot needs updating. Tracking
options in Settings control which sources are collected.

- **Unknown or unverified weekly progress** does not mean an activity is incomplete
  or available. Old weekly periods are distinguished from current observations.
- **Vault unlocks** describe recorded progress this week, not a reward waiting to be
  claimed from a previous week.
- **Collection totals** come from the journals and are not guaranteed obtainable
  maximums. Pet collections count unique species.
- **Storage capacity** distinguishes the current character's bags and personal bank
  from the shared Warband Bank.
- **Mail attachments** rely on completed mailbox scans. Expiry indicators and
  reminders help identify cached mail that needs attention.

Hover the **Data coverage** footer for source details, or click it to open Setup.
Item movement and currency transfers use Blizzard's own interfaces.

***

## 🚀 Getting Started

Once installed, open The Quartermaster with `/tq` or the minimap button.

1. Log into each character you want to track.
2. Visit their personal and Warband banks, open guild bank tabs, and open their
   mailbox to collect those snapshots.
3. Enable recipe tracking and open each crafter's own profession window to collect
   their recipes and ingredients.
4. Use **Characters → Setup** to check missing scans and collection dates.

Resize the window or use the footer scale control. Settings contains collection,
display, notification and data-management options. The **Information** page provides
an in-game guide.

***

## 💬 Slash Commands

| Command | What it does |
| --- | --- |
| `/tq` | Open The Quartermaster. |
| `/quartermaster` | Alias for `/tq`. |
| `/thequartermaster` | Alias for `/tq`. |
| `/tq options` | Open Settings. |
| `/tq help` | Show available commands. |

***

## 📦 Installation

### Addon Manager

Install the available release through your addon manager, or download its archive
for manual installation.

### Manual Installation

1. Download The Quartermaster addon archive.
2. Extract it into `World of Warcraft/_retail_/Interface/AddOns/`.
3. Make sure the folder is named `TheQuartermaster` and contains
   `TheQuartermaster.toc` directly, with no extra nested folder.
4. Restart World of Warcraft if it is already running.

***

## 🧩 Compatibility

* **Game:** Retail World of Warcraft.
* **Era:** Midnight.
* **Declared interfaces:** `120100, 120105`.
* **Current build:** `2.0.1-Release`; tested successfully on 12.1.5.
* **Dependencies:** Required libraries are included with the addon.
* **Optional integration:** Auctionator enables the Watchlist shopping-list export.

***

## 💬 Support

For bug reports, feature suggestions and build feedback, join the addon community:

**Earthenmist - Addon Hub**

[https://discord.gg/U8mKfHpeeP](https://discord.gg/U8mKfHpeeP)

Include the addon version, game build, affected page, steps to reproduce the problem
and any Lua error text. Screenshots help with layout issues.

[The Quartermaster on GitHub](https://github.com/Earthenmist/TheQuartermaster)

***

## 📜 License

Copyright © 2026 Earthenmist. All Rights Reserved.

See [LICENSE](LICENSE) for the terms of use.

***

## ❤️ Credits

**Author:** Earthenmist

Thank you to everyone testing the addon and sharing feedback.
