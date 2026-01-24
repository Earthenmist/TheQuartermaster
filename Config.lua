--[[
    The Quartermaster - Configuration Module
    Modern and organized settings panel
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster
local L = ns.L

-- AceConfig options table
local options = {
    name = "The Quartermaster",
    type = "group",
    args = {
        -- Header
        header = {
            order = 1,
            type = "description",
            name = "|cff00ccffThe Quartermaster|r\nView and manage your Warband Bank items from anywhere.\n\n",
            fontSize = "medium",
        },
        
        -- ===== GENERAL SETTINGS =====
        generalHeader = {
            order = 10,
            type = "header",
            name = "General Settings",
        },
        generalDesc = {
            order = 11,
            type = "description",
            name = "Basic addon settings and minimap button configuration.\n",
        },
        enabled = {
            order = 12,
            type = "toggle",
            name = "Enable Addon",
            desc = "Turn the addon on or off.",
            width = 1.5,
            get = function() return TheQuartermaster.db.profile.enabled end,
            set = function(_, value)
                TheQuartermaster.db.profile.enabled = value
                if value then
                    TheQuartermaster:OnEnable()
                else
                    TheQuartermaster:OnDisable()
                end
            end,
        },
        minimapIcon = {
            order = 13,
            type = "toggle",
            name = "Minimap Button",
            desc = "Show a button on the minimap to open The Quartermaster.",
            width = 1.5,
            get = function() return not TheQuartermaster.db.profile.minimap.hide end,
            set = function(_, value)
                if TheQuartermaster.SetMinimapButtonVisible then
                    TheQuartermaster:SetMinimapButtonVisible(value)
                else
                    TheQuartermaster.db.profile.minimap.hide = not value
                end
            end,
        },
        currentLanguageInfo = {
            order = 14,
            type = "description",
            name = function()
                local locale = GetLocale() or "enUS"
                local localeNames = {
                    enUS = "English (US)",
                    enGB = "English (GB)",
                    deDE = "Deutsch",
                    esES = "Español (EU)",
                    esMX = "Español (MX)",
                    frFR = "Français",
                    itIT = "Italiano",
                    koKR = "한국어",
                    ptBR = "Português",
                    ruRU = "Русский",
                    zhCN = "简体中文",
                    zhTW = "繁體中文",
                }
                local localeName = localeNames[locale] or locale
                return "|cff00ccffCurrent Language:|r " .. localeName .. "\n\n" ..
                       "|cffaaaaaa" ..
                       "Addon uses your WoW game client's language automatically. " ..
                       "Common text (Search, Close, Settings, Quality names, etc.) " ..
                       "uses Blizzard's built-in localized strings.\n\n" ..
                       "To change language, change your game client's language in Battle.net settings.|r\n"
            end,
            fontSize = "medium",
        },
        
        -- ===== AUTOMATION =====
        automationHeader = {
            order = 30,
            type = "header",
            name = "Automation",
        },
        automationDesc = {
            order = 31,
            type = "description",
            name = "Control what happens automatically when you open your Warband Bank.\n",
        },
        autoScan = {
            order = 32,
            type = "toggle",
            name = "Auto-Scan Items",
            desc = "Automatically scan and cache your Warband Bank items when you open the bank.",
            width = 1.5,
            get = function() return TheQuartermaster.db.profile.autoScan end,
            set = function(_, value) TheQuartermaster.db.profile.autoScan = value end,
        },
        autoOpenWindow = {
            order = 33,
            type = "toggle",
            name = "Auto-Open Window",
            desc = "Automatically open the The Quartermaster window when you open your Warband Bank.",
            width = 1.5,
            get = function() return TheQuartermaster.db.profile.autoOpenWindow ~= false end,
            set = function(_, value) TheQuartermaster.db.profile.autoOpenWindow = value end,
        },
        autoSaveChanges = {
            order = 34,
            type = "toggle",
            name = "Live Sync",
            desc = "Keep the item cache updated in real-time while the bank is open. This lets you see accurate data even when away from the bank.",
            width = 1.5,
            get = function() return TheQuartermaster.db.profile.autoSaveChanges ~= false end,
            set = function(_, value) TheQuartermaster.db.profile.autoSaveChanges = value end,
        },
        autoOptimize = {
            order = 35,
            type = "toggle",
            name = "Auto-Optimize Database",
            desc = "Automatically clean up stale data and optimize the database every 7 days.",
            width = 1.5,
            get = function() return TheQuartermaster.db.profile.autoOptimize ~= false end,
            set = function(_, value) TheQuartermaster.db.profile.autoOptimize = value end,
        },
        spacer3 = {
            order = 39,
            type = "description",
            name = "\n",
        },
        
        -- ===== DISPLAY =====
        displayHeader = {
            order = 40,
            type = "header",
            name = "Display",
        },
        displayDesc = {
            order = 41,
            type = "description",
            name = "Customize how items and information are displayed.\n",
        },
        showItemLevel = {
            order = 42,
            type = "toggle",
            name = "Show Item Level",
            desc = "Display item level badges on equipment in the item list.",
            width = 1.5,
            get = function() return TheQuartermaster.db.profile.showItemLevel end,
            set = function(_, value)
                TheQuartermaster.db.profile.showItemLevel = value
                if TheQuartermaster.RefreshUI then
                    TheQuartermaster:RefreshUI()
                end
            end,
        },
        showItemCount = {
            order = 43,
            type = "toggle",
            name = "Show Item Count",
            desc = "Display stack count next to item names.",
            width = 1.5,
            get = function() return TheQuartermaster.db.profile.showItemCount end,
            set = function(_, value)
                TheQuartermaster.db.profile.showItemCount = value
                if TheQuartermaster.RefreshUI then
                    TheQuartermaster:RefreshUI()
                end
            end,
        },
        spacer4 = {
            order = 49,
            type = "description",
            name = "\n",
        },
        
        -- ===== THEME & APPEARANCE =====
        themeHeader = {
            order = 50,
            type = "header",
            name = "Theme & Appearance",
        },
        themeDesc = {
            order = 51,
            type = "description",
            name = "Choose your primary theme color. All variations (borders, tabs, highlights) will be automatically generated. Changes apply in real-time!\n",
        },
        themeMasterColor = {
            order = 52,
            type = "color",
            name = "Master Theme Color",
            desc = "Choose your primary theme color. All variations (borders, tabs, highlights) will be automatically generated.",
            hasAlpha = false,
            width = "full",
            get = function()
                local c = TheQuartermaster.db.profile.themeColors.accent
                return c[1], c[2], c[3]
            end,
            set = function(_, r, g, b)
                
                local finalColors = ns.UI_CalculateThemeColors(r, g, b)
                TheQuartermaster.db.profile.themeMode = 'static'
                TheQuartermaster.db.profile.themeColor = { r = r, g = g, b = b }
                TheQuartermaster.db.profile.themeColors = finalColors
                
                if ns.UI_RefreshColors then
                    ns.UI_RefreshColors()
                end
            end,
        },
        themePresetPurple = {
            order = 54,
            type = "execute",
            name = "Purple Theme",
            desc = "Classic purple theme",
            width = 0.5,
            func = function()
                if TheQuartermaster.ShowMainWindow then
                    TheQuartermaster:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(0.40, 0.20, 0.58)
                TheQuartermaster.db.profile.themeMode = 'static'
                TheQuartermaster.db.profile.themeColor = { r = 0.40, g = 0.20, b = 0.58 }
                TheQuartermaster.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                TheQuartermaster:Print("Purple theme applied!")
            end,
        },

        themePresetClass = {
            order = 53,
            type = "execute",
            name = "Class Color Theme",
            desc = "Use your current character's class color",
            width = 0.5,
            func = function()
                if TheQuartermaster.ShowMainWindow then
                    TheQuartermaster:ShowMainWindow()
                end

                TheQuartermaster.db.profile.themeMode = 'class'
                -- Apply dynamic class theme for the currently logged-in character
                if TheQuartermaster.ApplyThemeFromMode then
                    TheQuartermaster:ApplyThemeFromMode()
                elseif ns.UI_RefreshColors then
                    ns.UI_RefreshColors()
                end

                TheQuartermaster:Print('Class color theme enabled!')
            end,
        },
        themePresetBlue = {
            order = 55,
            type = "execute",
            name = "Blue Theme",
            desc = "Cool blue theme",
            width = 0.5,
            func = function()
                if TheQuartermaster.ShowMainWindow then
                    TheQuartermaster:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(0.30, 0.65, 1.0)
                TheQuartermaster.db.profile.themeMode = 'static'
                TheQuartermaster.db.profile.themeColor = { r = 0.30, g = 0.65, b = 1.0 }
                TheQuartermaster.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                TheQuartermaster:Print("Blue theme applied!")
            end,
        },
        themePresetGreen = {
            order = 56,
            type = "execute",
            name = "Green Theme",
            desc = "Nature green theme",
            width = 0.5,
            func = function()
                if TheQuartermaster.ShowMainWindow then
                    TheQuartermaster:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(0.32, 0.79, 0.40)
                TheQuartermaster.db.profile.themeMode = 'static'
                TheQuartermaster.db.profile.themeColor = { r = 0.32, g = 0.79, b = 0.40 }
                TheQuartermaster.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                TheQuartermaster:Print("Green theme applied!")
            end,
        },
        themePresetRed = {
            order = 57,
            type = "execute",
            name = "Red Theme",
            desc = "Fiery red theme",
            width = 0.5,
            func = function()
                if TheQuartermaster.ShowMainWindow then
                    TheQuartermaster:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(1.0, 0.34, 0.34)
                TheQuartermaster.db.profile.themeMode = 'static'
                TheQuartermaster.db.profile.themeColor = { r = 1.0, g = 0.34, b = 0.34 }
                TheQuartermaster.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                TheQuartermaster:Print("Red theme applied!")
            end,
        },
        themePresetOrange = {
            order = 58,
            type = "execute",
            name = "Orange Theme",
            desc = "Warm orange theme",
            width = 0.5,
            func = function()
                if TheQuartermaster.ShowMainWindow then
                    TheQuartermaster:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(1.0, 0.65, 0.30)
                TheQuartermaster.db.profile.themeMode = 'static'
                TheQuartermaster.db.profile.themeColor = { r = 1.0, g = 0.65, b = 0.30 }
                TheQuartermaster.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                TheQuartermaster:Print("Orange theme applied!")
            end,
        },
        themePresetCyan = {
            order = 59,
            type = "execute",
            name = "Cyan Theme",
            desc = "Bright cyan theme",
            width = 0.5,
            func = function()
                if TheQuartermaster.ShowMainWindow then
                    TheQuartermaster:ShowMainWindow()
                end
                local colors = ns.UI_CalculateThemeColors(0.00, 0.80, 1.00)
                TheQuartermaster.db.profile.themeMode = 'static'
                TheQuartermaster.db.profile.themeColor = { r = 0.00, g = 0.80, b = 1.00 }
                TheQuartermaster.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                TheQuartermaster:Print("Cyan theme applied!")
            end,
        },
        themeResetButton = {
            order = 59,
            type = "execute",
            name = "Reset to Default (Class Color)",
            desc = "Reset all theme colors to your current character's class color.",
            width = "full",
            func = function()
                if TheQuartermaster.ShowMainWindow then
                    TheQuartermaster:ShowMainWindow()
                end

                TheQuartermaster.db.profile.themeMode = 'class'
                if TheQuartermaster.ApplyThemeFromMode then
                    TheQuartermaster:ApplyThemeFromMode()
                elseif ns.UI_RefreshColors then
                    ns.UI_RefreshColors()
                end

                TheQuartermaster:Print('Theme reset to dynamic class color!')
            end,
        },
        spacer5 = {
            order = 59.5,
            type = "description",
            name = "\n",
        },
        
        -- ===== TOOLTIP ENHANCEMENTS =====
        tooltipHeader = {
            order = 60,
            type = "header",
            name = "Tooltip Enhancements",
        },
        tooltipDesc = {
            order = 61,
            type = "description",
            name = "Add useful information to item tooltips.\n",
        },
        tooltipEnhancement = {
            order = 62,
            type = "toggle",
            name = "Show Item Locations",
            desc = "Add item location information to tooltips (Bags, Personal Bank, Warband Bank).",
            width = 1.5,
            get = function() return TheQuartermaster.db.profile.tooltipEnhancement end,
            set = function(_, value)
                TheQuartermaster.db.profile.tooltipEnhancement = value
                if value then
                    TheQuartermaster:Print("Tooltip enhancement enabled")
                else
                    TheQuartermaster:Print("Tooltip enhancement disabled")
                end
            end,
        },
        spacer6 = {
            order = 69,
            type = "description",
            name = "\n",
        },
        
        -- ===== NOTIFICATIONS =====
        notificationsHeader = {
            order = 70,
            type = "header",
            name = "Notifications",
        },
        notificationsDesc = {
            order = 71,
            type = "description",
            name = "Control in-game pop-up notifications and reminders.\n",
        },
        notificationsEnabled = {
            order = 72,
            type = "toggle",
            name = "Enable Notifications",
            desc = "Master toggle for all notification pop-ups.",
            width = 1.5,
            get = function() return TheQuartermaster.db.profile.notifications.enabled end,
            set = function(_, value) TheQuartermaster.db.profile.notifications.enabled = value end,
        },
        showUpdateNotes = {
            order = 73,
            type = "toggle",
            name = "Show Update Notes",
            desc = "Display a pop-up with changelog when addon is updated to a new version.",
            width = 1.5,
            disabled = function() return not TheQuartermaster.db.profile.notifications.enabled end,
            get = function() return TheQuartermaster.db.profile.notifications.showUpdateNotes end,
            set = function(_, value) TheQuartermaster.db.profile.notifications.showUpdateNotes = value end,
        },
        showVaultReminder = {
            order = 74,
            type = "toggle",
            name = "Weekly Vault Reminder",
            desc = "Show a reminder when you have unclaimed Weekly Vault rewards on login.",
            width = 1.5,
            disabled = function() return not TheQuartermaster.db.profile.notifications.enabled end,
            get = function() return TheQuartermaster.db.profile.notifications.showVaultReminder end,
            set = function(_, value) TheQuartermaster.db.profile.notifications.showVaultReminder = value end,
        },
        showLootNotifications = {
            order = 75,
            type = "toggle",
            name = "Mount/Pet/Toy Loot Alerts",
            desc = "Show a notification when a NEW mount, pet, or toy enters your bag. Triggers when item is looted/bought, not when learned. Only shows for uncollected items.",
            width = 1.5,
            disabled = function() return not TheQuartermaster.db.profile.notifications.enabled end,
            get = function() return TheQuartermaster.db.profile.notifications.showLootNotifications end,
            set = function(_, value) TheQuartermaster.db.profile.notifications.showLootNotifications = value end,
        },
        resetVersionButton = {
            order = 76,
            type = "execute",
            name = "Show Update Notes Again",
            desc = "Reset the 'last seen version' to show the update notification again on next login.",
            width = 1.5,
            func = function()
                TheQuartermaster.db.profile.notifications.lastSeenVersion = "0.0.0"
                TheQuartermaster:Print("Update notification will show on next login.")
            end,
        },
        spacer7 = {
            order = 79,
            type = "description",
            name = "\n",
        },
        
        -- ===== CURRENCY =====
        currencyHeader = {
            order = 80,
            type = "header",
            name = "Currency",
        },
        currencyDesc = {
            order = 81,
            type = "description",
            name = "Configure how currencies are displayed in the Currency tab.\n",
        },
        currencyFilterMode = {
            order = 82,
            type = "select",
            name = "Filter Mode",
            desc = "Choose which currencies to display in the Currency tab.",
            width = 1.5,
            values = {
                filtered = "Important Only (Recommended)",
                nonfiltered = "Show All Currencies",
            },
            get = function() return TheQuartermaster.db.profile.currencyFilterMode or "filtered" end,
            set = function(_, value)
                TheQuartermaster.db.profile.currencyFilterMode = value
                if TheQuartermaster.RefreshUI then
                    TheQuartermaster:RefreshUI()
                end
            end,
        },
        currencyShowZero = {
            order = 83,
            type = "toggle",
            name = "Show Zero Quantities",
            desc = "Display currencies even if their quantity is 0.",
            width = 1.5,
            get = function() return TheQuartermaster.db.profile.currencyShowZero end,
            set = function(_, value)
                TheQuartermaster.db.profile.currencyShowZero = value
                if TheQuartermaster.RefreshUI then
                    TheQuartermaster:RefreshUI()
                end
            end,
        },
        spacer8 = {
            order = 89,
            type = "description",
            name = "\n",
        },
        
        -- ===== TAB FILTERING =====
        tabHeader = {
            order = 100,
            type = "header",
            name = "Tab Filtering",
        },
        tabDesc = {
            order = 101,
            type = "description",
            name = "Exclude specific Warband Bank tabs from scanning. Useful if you want to ignore certain tabs.\n",
        },
        ignoredTab1 = {
            order = 102,
            type = "toggle",
            name = "Ignore Tab 1",
            desc = "Exclude this Warband Bank tab from automatic scanning",
            width = 1.2,
            get = function() return TheQuartermaster.db.profile.ignoredTabs[1] end,
            set = function(_, value) TheQuartermaster.db.profile.ignoredTabs[1] = value end,
        },
        ignoredTab2 = {
            order = 103,
            type = "toggle",
            name = "Ignore Tab 2",
            desc = "Exclude this Warband Bank tab from automatic scanning",
            width = 1.2,
            get = function() return TheQuartermaster.db.profile.ignoredTabs[2] end,
            set = function(_, value) TheQuartermaster.db.profile.ignoredTabs[2] = value end,
        },
        ignoredTab3 = {
            order = 104,
            type = "toggle",
            name = "Ignore Tab 3",
            desc = "Exclude this Warband Bank tab from automatic scanning",
            width = 1.2,
            get = function() return TheQuartermaster.db.profile.ignoredTabs[3] end,
            set = function(_, value) TheQuartermaster.db.profile.ignoredTabs[3] = value end,
        },
        ignoredTab4 = {
            order = 105,
            type = "toggle",
            name = "Ignore Tab 4",
            desc = "Exclude this Warband Bank tab from automatic scanning",
            width = 1.2,
            get = function() return TheQuartermaster.db.profile.ignoredTabs[4] end,
            set = function(_, value) TheQuartermaster.db.profile.ignoredTabs[4] = value end,
        },
        ignoredTab5 = {
            order = 106,
            type = "toggle",
            name = "Ignore Tab 5",
            desc = "Exclude this Warband Bank tab from automatic scanning",
            width = 1.2,
            get = function() return TheQuartermaster.db.profile.ignoredTabs[5] end,
            set = function(_, value) TheQuartermaster.db.profile.ignoredTabs[5] = value end,
        },
        spacer9 = {
            order = 109,
            type = "description",
            name = "\n",
        },
        
        -- ===== CHARACTER MANAGEMENT =====
        characterManagementHeader = {
            order = 110,
            type = "header",
            name = "Character Management",
        },
        characterManagementDesc = {
            order = 111,
            type = "description",
            name = "Manage your tracked characters. You can delete character data that you no longer need.\n\n|cffff9900Warning:|r Deleting a character removes all saved data (gold, professions, PvE progress, etc.). This action cannot be undone.\n",
        },
        deleteCharacterDropdown = {
            order = 112,
            type = "select",
            name = "Select Character to Delete",
            desc = "Choose a character from the list to delete their data",
            width = "full",
            values = function()
                local chars = {}
                local allChars = TheQuartermaster:GetAllCharacters()
                
                local currentPlayerName = UnitName("player")
                local currentPlayerRealm = GetRealmName()
                local currentPlayerKey = currentPlayerName .. "-" .. currentPlayerRealm
                
                for _, char in ipairs(allChars) do
                    local key = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
                    if key ~= currentPlayerKey then
                        chars[key] = string.format("%s (%s) - Level %d", 
                            char.name or "Unknown", 
                            char.classFile or "?", 
                            char.level or 0)
                    end
                end
                
                return chars
            end,
            get = function() 
                return TheQuartermaster.selectedCharacterToDelete 
            end,
            set = function(_, value)
                TheQuartermaster.selectedCharacterToDelete = value
            end,
        },
        deleteCharacterButton = {
            order = 113,
            type = "execute",
            name = "Delete Selected Character",
            desc = "Permanently delete the selected character's data",
            width = "full",
            disabled = function()
                return not TheQuartermaster.selectedCharacterToDelete
            end,
            confirm = function()
                if not TheQuartermaster.selectedCharacterToDelete then
                    return false
                end
                local char = TheQuartermaster.db.global.characters[TheQuartermaster.selectedCharacterToDelete]
                if char then
                    return string.format(
                        "Are you sure you want to delete |cff00ccff%s|r?\n\n" ..
                        "This will remove:\n" ..
                        "• Gold data\n" ..
                        "• Personal bank cache\n" ..
                        "• Profession info\n" ..
                        "• PvE progress\n" ..
                        "• All statistics\n\n" ..
                        "|cffff0000This action cannot be undone!|r",
                        char.name or "this character"
                    )
                end
                return "Delete this character?"
            end,
            func = function()
                if TheQuartermaster.selectedCharacterToDelete then
                    local success = TheQuartermaster:DeleteCharacter(TheQuartermaster.selectedCharacterToDelete)
                    if success then
                        TheQuartermaster.selectedCharacterToDelete = nil
                        local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
                        AceConfigRegistry:NotifyChange("The Quartermaster")
                        if TheQuartermaster.RefreshUI then
                            TheQuartermaster:RefreshUI()
                        end
                    else
                        TheQuartermaster:Print("|cffff0000Failed to delete character. Character may not exist.|r")
                    end
                end
            end,
        },
        spacer10 = {
            order = 899,
            type = "description",
            name = "\n\n",
        },
        
        -- ===== ADVANCED =====
        advancedHeader = {
            order = 900,
            type = "header",
            name = "Advanced",
        },
        advancedDesc = {
            order = 901,
            type = "description",
            name = "Advanced settings and database management. Use with caution!\n",
        },
        debugMode = {
            order = 902,
            type = "toggle",
            name = "Debug Mode",
            desc = "Enable verbose logging for debugging purposes. Only enable if troubleshooting issues.",
            width = 1.5,
            get = function() return TheQuartermaster.db.profile.debugMode end,
            set = function(_, value)
                TheQuartermaster.db.profile.debugMode = value
                if value then
                    TheQuartermaster:Print("|cff00ff00Debug mode enabled|r")
                else
                    TheQuartermaster:Print("|cffff9900Debug mode disabled|r")
                end
            end,
        },
        databaseStatsButton = {
            order = 903,
            type = "execute",
            name = "Show Database Statistics",
            desc = "Display detailed information about your database size and content.",
            width = 1.5,
            func = function()
                if TheQuartermaster.PrintDatabaseStats then
                    TheQuartermaster:PrintDatabaseStats()
                else
                    TheQuartermaster:Print("Database optimizer not loaded")
                end
            end,
        },
        optimizeDatabaseButton = {
            order = 904,
            type = "execute",
            name = "Optimize Database Now",
            desc = "Manually run database optimization to clean up stale data and reduce file size.",
            width = 1.5,
            func = function()
                if TheQuartermaster.RunOptimization then
                    TheQuartermaster:RunOptimization()
                else
                    TheQuartermaster:Print("Database optimizer not loaded")
                end
            end,
        },
        spacerAdvanced = {
            order = 905,
            type = "description",
            name = "\n",
        },
        wipeAllData = {
            order = 999,
            type = "execute",
            name = "|cffff0000Wipe All Data|r",
            desc = "DELETE ALL addon data (characters, items, currency, reputations, settings). Cannot be undone!\n\n|cffff9900You will be prompted to type 'Accept' to confirm (case insensitive).|r",
            width = "full",
            confirm = false,  -- We use custom confirmation
            func = function()
                TheQuartermaster:ShowWipeDataConfirmation()
            end,
        },
        spacer11 = {
            order = 949,
            type = "description",
            name = "\n",
        },
        
        -- ===== SLASH COMMANDS =====
        commandsHeader = {
            order = 950,
            type = "header",
            name = "Slash Commands",
        },
        commandsDesc = {
            order = 951,
            type = "description",
            name = [[
|cff00ccff/tq show|r - Toggle the main window
|cff00ccff/tq options|r - Open this settings panel
]],
            fontSize = "medium",
        },
    },
}

--[[
    Show Wipe Data Confirmation Popup
]]
function TheQuartermaster:ShowWipeDataConfirmation()
    StaticPopupDialogs["TheQuartermaster_WIPE_CONFIRM"] = {
        text = "|cffff0000WIPE ALL DATA|r\n\n" ..
               "This will permanently delete ALL data:\n" ..
               "• All tracked characters\n" ..
               "• All cached items\n" ..
               "• All currency data\n" ..
               "• All reputation data\n" ..
               "• All PvE progress\n" ..
               "• All settings\n\n" ..
               "|cffffaa00This action CANNOT be undone!|r\n\n" ..
               "Type |cff00ccffAccept|r to confirm:",
        button1 = "Cancel",
        button2 = nil,
        hasEditBox = true,
        maxLetters = 10,
        OnAccept = function(self)
            local text = self.editBox:GetText()
            if text and text:lower() == "accept" then
                TheQuartermaster:WipeAllData()
            else
                TheQuartermaster:Print("|cffff6600You must type 'Accept' to confirm.|r")
            end
        end,
        OnShow = function(self)
            self.editBox:SetFocus()
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            local text = self:GetText()
            if text and text:lower() == "accept" then
                TheQuartermaster:WipeAllData()
                parent:Hide()
            else
                TheQuartermaster:Print("|cffff6600You must type 'Accept' to confirm.|r")
            end
        end,
        EditBoxOnEscapePressed = function(self)
            self:GetParent():Hide()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    
    StaticPopup_Show("TheQuartermaster_WIPE_CONFIRM")
end

--[[
    Initialize configuration
]]
function TheQuartermaster:InitializeConfig()
    local AceConfig = LibStub("AceConfig-3.0")
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")
    
    -- Register main options
    AceConfig:RegisterOptionsTable(ADDON_NAME, options)
    
    -- Add to Blizzard Interface Options
    self.optionsFrame, self.optionsCategoryID = AceConfigDialog:AddToBlizOptions(ADDON_NAME, "The Quartermaster")

	-- NOTE:
	-- AceConfigDialog:AddToBlizOptions already registers with the modern Settings panel
	-- (Dragonflight/Midnight+) when available. Registering again will create a duplicate
	-- "The Quartermaster" entry in the AddOns options tree.
end

--[[
    Open the options panel
]]
function TheQuartermaster:OpenOptions()
    -- Dragonflight/Midnight+ uses the Settings panel.
    if Settings then
        -- Fallback: numeric category ID
        if type(self.optionsCategoryID) == "number" and Settings.OpenToCategory then
            Settings.OpenToCategory(self.optionsCategoryID)
            return
        end

        -- Fallback: resolve by name (some client builds accept this via GetCategory)
        if Settings.GetCategory and Settings.OpenToCategory then
            local ok, cat = pcall(function()
                return Settings.GetCategory("The Quartermaster")
            end)
            if ok and cat and cat.ID then
                Settings.OpenToCategory(cat.ID)
                return
            end
        end
    end

    -- Legacy interface options fallback (older clients)
    if InterfaceOptionsFrame_OpenToCategory and self.optionsFrame then
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
    end
end

