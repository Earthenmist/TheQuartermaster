--[[
    The Quartermaster - Defaults
    Centralized AceDB defaults table.
]]

local ADDON_NAME, ns = ...

-- NOTE: Keep this table as data-only to make the core module smaller and easier to maintain.
ns.DEFAULTS = {
    profile = {
        enabled = true,
        suppressPlayedTimeChat = true,
        minimap = {
            hide = false,
            minimapPos = 220,
            lock = false,
        },

        -- Bank addon conflict resolution (per-addon choices)
        bankConflictChoices = {},

        -- Track which addons were toggled by user's choice
        toggledAddons = {}, -- { ["ElvUI"] = "disabled", ["Bagnon"] = "enabled" }

        -- Behavior settings
        autoScan = true, -- Auto-scan when bank opens
        autoOpenWindow = true, -- Auto-open addon window when bank opens
        autoSaveChanges = true, -- Live sync while bank is open
		-- View-only: we do not replace Blizzard bank UI or support item movement.
		replaceDefaultBank = false, -- Replace default bank UI with addon
		bankModuleEnabled = false, -- Enable bank UI replacement features (conflict checks, UI suppression, etc.)
        debugMode = false, -- Debug logging (verbose)

        -- Currency settings
        currencyFilterMode = "filtered", -- "filtered" or "nonfiltered"
        currencyShowZero = true, -- Show currencies with 0 quantity

        -- Reputation settings
        reputationExpanded = {}, -- Collapse/expand state for reputation headers

        -- Display settings
        showItemLevel = true,

        -- Theme Colors (RGB 0-1 format) - All calculated from master color
        -- Theme mode
        --   'class'  = dynamic, uses the currently logged-in character's class colour each session
        --   'static' = fixed colour saved in themeColor
        themeMode = 'class',

        -- Static theme colour (only used when themeMode == 'static')
        themeColor = { r = 0.40, g = 0.20, b = 0.58 },

        themeColors = {
            accent = { 0.40, 0.20, 0.58 }, -- Master theme color (purple)
            accentDark = { 0.28, 0.14, 0.41 }, -- Darker variation (0.7x)
            border = { 0.20, 0.20, 0.25 }, -- Desaturated border
            tabActive = { 0.20, 0.12, 0.30 }, -- Active tab background (0.5x)
            tabHover = { 0.24, 0.14, 0.35 }, -- Hover tab background (0.6x)
        },
        showItemCount = true,
        -- Tooltip enhancements
        tooltipEnhancement = true, -- Show item locations in tooltips by default
        tooltipGuildCounts = true, -- Show cached guild bank counts in tooltips by default

        -- Watchlist (account-wide pins)
        watchlist = {
            items = {},       -- { [itemID] = true }
            currencies = {},  -- { [currencyID] = true }
            includeGuildBank = true,
        },

        -- Gold settings
        goldReserve = 0, -- Minimum gold to keep when depositing

        -- Privacy
        discretionMode = false, -- When enabled, hide gold amounts throughout the UI

        -- Items tab (Personal Bank)
        -- 'list'  = grouped list view
        -- 'slots' = slot + tab view similar to the default bank
        personalBankViewMode = "slots",
        personalBankSlotTab = 1,
        inventoryViewMode = "slots",
        inventorySlotTab = 1,

        -- Items tab (Warband Bank)
        -- 'list'  = grouped list view
        -- 'slots' = slot + tab view similar to the default bank
        warbandBankViewMode = "slots",
        warbandBankSlotTab = 1,

        -- Items tab (Guild Bank)
        guildBankViewMode = "slots",
        guildBankSlotTab = 1,

        -- Tab filtering (true = ignored)
        ignoredTabs = {
            [1] = false,
            [2] = false,
            [3] = false,
            [4] = false,
            [5] = false,
        },

        -- Storage tab expanded state
        storageExpanded = {
            warband = false, -- Warband Bank expanded by default
            personal = false, -- Personal collapsed by default
            categories = {}, -- { ["warband_TradeGoods"] = true, ["personal_CharName_TradeGoods"] = false }
        },

        -- Character list sorting preferences
        characterSort = {
            key = nil, -- nil = no sorting (default order), "name", "level", "gold", "lastSeen"
            ascending = true, -- true = ascending, false = descending
        },

        -- PvE list sorting preferences
        pveSort = {
            key = nil, -- nil = no sorting (default order)
            ascending = true,
        },

        -- Notification settings
        notifications = {
            enabled = true, -- Master toggle
            showUpdateNotes = true, -- Show changelog on new version
            showVaultReminder = true, -- Show vault reminder
            showLootNotifications = true, -- Show mount/pet/toy loot notifications
            lastSeenVersion = "0.0.0", -- Last addon version seen
            lastVaultCheck = 0, -- Last time vault was checked
            dismissedNotifications = {}, -- Array of dismissed notification IDs
        },
    },
    global = {
        -- Warband bank cache (SHARED across all characters)
        warbandBank = {
            items = {}, -- { [bagID] = { [slotID] = itemData } }
            gold = 0, -- Warband bank gold
            lastScan = 0, -- Last scan timestamp
        },

        -- All tracked characters
        -- Key: "CharacterName-RealmName"
        characters = {},

        -- Favorite characters (always shown at top)
        -- Array of "CharacterName-RealmName" keys
        favoriteCharacters = {},

        -- Collection tracking cache
        collections = {
            mounts = {},
            pets = {},
            toys = {},
            heirlooms = {},
            lastScan = 0,
        },

        -- Per-character last scan timestamps
        lastScans = {},

        -- PvE cache
        pve = {
            lastScan = 0,
            weeklyVault = {},
            raids = {},
            mythicPlus = {},
        },

        -- Currency cache
        currencies = {
            lastScan = 0,
            perCharacter = {},
        },

        -- Reputation cache
        reputation = {
            lastScan = 0,
            perCharacter = {},
        },

        -- Statistics tracking
        statistics = {
            lastScan = 0,
            perCharacter = {},
        },

        -- Mail cache (requires opening a mailbox on that character)
        mail = {
            perCharacter = {},
        },

        -- Window size persistence
        window = {
            width = 700,
            height = 550,
        },
    },
    char = {
        -- Personal bank cache (per-character)
        personalBank = {
            items = {},
            bagSizes = {}, -- { [bagIndex] = numSlots }
            bagIDs = {},   -- { [bagIndex] = bagID }
            lastScan = 0,
        },

        -- Inventory cache (per-character)
        inventory = {
            items = {},
            bagSizes = {},
            bagIDs = {},
            usedSlots = 0,
            totalSlots = 0,
            lastScan = 0,
        },

        lastKnownGold = 0,
    },
}
