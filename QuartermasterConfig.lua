--[[
    The Quartermaster - Configuration Module
    Modern and organized settings panel
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster
local L = ns.L

-- AceConfig options table
local options = {
    name = L["THE_QUARTERMASTER"],
    type = "group",
    args = {
        -- Header
        header = {
            order = 1,
            type = "description",
            name = L["CFF00CCFFTHE_QUARTERMASTER_R_NVIEW_AND_MANAGE_YOUR_WARBAND_B"],
            fontSize = "medium",
        },
        
        -- ===== GENERAL SETTINGS =====
        generalHeader = {
            order = 10,
            type = "header",
            name = L["GENERAL_SETTINGS"],
        },
        generalDesc = {
            order = 11,
            type = "description",
            name = L["BASIC_ADDON_SETTINGS_AND_MINIMAP_BUTTON_CONFIGURATION_N"],
        },
        enabled = {
            order = 12,
            type = "toggle",
            name = L["ENABLE_ADDON"],
            desc = L["TURN_THE_ADDON_ON_OR_OFF"],
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
            name = L["MINIMAP_BUTTON"],
            desc = L["SHOW_A_BUTTON_ON_THE_MINIMAP_TO_OPEN_THE_QUARTERMASTER"],
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
            name = L["AUTOMATION"],
        },
        automationDesc = {
            order = 31,
            type = "description",
            name = L["CONTROL_WHAT_HAPPENS_AUTOMATICALLY_WHEN_YOU_OPEN_YOUR_WARBAN"],
        },
        autoScan = {
            order = 32,
            type = "toggle",
            name = L["AUTO_SCAN_ITEMS"],
            desc = L["AUTOMATICALLY_SCAN_AND_CACHE_YOUR_WARBAND_BANK_ITEMS_WHEN_YO"],
            width = 1.5,
            get = function() return TheQuartermaster.db.profile.autoScan end,
            set = function(_, value) TheQuartermaster.db.profile.autoScan = value end,
        },
        autoOpenWindow = {
            order = 33,
            type = "toggle",
            name = L["AUTO_OPEN_WINDOW"],
            desc = L["AUTOMATICALLY_OPEN_THE_THE_QUARTERMASTER_WINDOW_WHEN_YOU_OPE"],
            width = 1.5,
            get = function() return TheQuartermaster.db.profile.autoOpenWindow ~= false end,
            set = function(_, value) TheQuartermaster.db.profile.autoOpenWindow = value end,
        },
        autoSaveChanges = {
            order = 34,
            type = "toggle",
            name = L["LIVE_SYNC"],
            desc = L["KEEP_THE_ITEM_CACHE_UPDATED_IN_REAL_TIME_WHILE_THE_BANK_IS_O"],
            width = 1.5,
            get = function() return TheQuartermaster.db.profile.autoSaveChanges ~= false end,
            set = function(_, value) TheQuartermaster.db.profile.autoSaveChanges = value end,
        },
        autoOptimize = {
            order = 35,
            type = "toggle",
            name = L["AUTO_OPTIMIZE_DATABASE"],
            desc = L["AUTOMATICALLY_CLEAN_UP_STALE_DATA_AND_OPTIMIZE_THE_DATABASE"],
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
            name = L["DISPLAY"],
        },
        displayDesc = {
            order = 41,
            type = "description",
            name = L["CUSTOMIZE_HOW_ITEMS_AND_INFORMATION_ARE_DISPLAYED_N"],
        },
        showItemLevel = {
            order = 42,
            type = "toggle",
            name = L["SHOW_ITEM_LEVEL"],
            desc = L["DISPLAY_ITEM_LEVEL_BADGES_ON_EQUIPMENT_IN_THE_ITEM_LIST"],
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
            name = L["SHOW_ITEM_COUNT"],
            desc = L["DISPLAY_STACK_COUNT_NEXT_TO_ITEM_NAMES"],
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
            name = L["THEME_APPEARANCE"],
        },
        themeDesc = {
            order = 51,
            type = "description",
            name = L["CHOOSE_YOUR_PRIMARY_THEME_COLOR_ALL_VARIATIONS_BORDERS_TABS_2"],
        },
        themeMasterColor = {
            order = 52,
            type = "color",
            name = L["MASTER_THEME_COLOR"],
            desc = L["CHOOSE_YOUR_PRIMARY_THEME_COLOR_ALL_VARIATIONS_BORDERS_TABS"],
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
            name = L["PURPLE_THEME"],
            desc = L["CLASSIC_PURPLE_THEME"],
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
            name = L["CLASS_COLOR_THEME"],
            desc = L["USE_YOUR_CURRENT_CHARACTERS_CLASS_COLOR"],
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
            name = L["BLUE_THEME"],
            desc = L["COOL_BLUE_THEME"],
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
            name = L["GREEN_THEME"],
            desc = L["NATURE_GREEN_THEME"],
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
            name = L["RED_THEME"],
            desc = L["FIERY_RED_THEME"],
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
            name = L["ORANGE_THEME"],
            desc = L["WARM_ORANGE_THEME"],
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
            name = L["CYAN_THEME"],
            desc = L["BRIGHT_CYAN_THEME"],
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
            name = L["RESET_TO_DEFAULT_CLASS_COLOR"],
            desc = L["RESET_ALL_THEME_COLORS_TO_YOUR_CURRENT_CHARACTERS_CLASS_COLO"],
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
            name = L["TOOLTIP_ENHANCEMENTS"],
        },
        tooltipDesc = {
            order = 61,
            type = "description",
            name = L["ADD_USEFUL_INFORMATION_TO_ITEM_TOOLTIPS_N"],
        },
        tooltipEnhancement = {
            order = 62,
            type = "toggle",
            name = L["SHOW_ITEM_LOCATIONS"],
            desc = L["ADD_ITEM_LOCATION_INFORMATION_TO_TOOLTIPS_BAGS_PERSONAL_BANK"],
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
            name = L["NOTIFICATIONS"],
        },
        notificationsDesc = {
            order = 71,
            type = "description",
            name = L["CONTROL_IN_GAME_POP_UP_NOTIFICATIONS_AND_REMINDERS_N"],
        },
        notificationsEnabled = {
            order = 72,
            type = "toggle",
            name = L["ENABLE_NOTIFICATIONS"],
            desc = L["MASTER_TOGGLE_FOR_ALL_NOTIFICATION_POP_UPS"],
            width = 1.5,
            get = function() return TheQuartermaster.db.profile.notifications.enabled end,
            set = function(_, value) TheQuartermaster.db.profile.notifications.enabled = value end,
        },
        showUpdateNotes = {
            order = 73,
            type = "toggle",
            name = L["SHOW_UPDATE_NOTES"],
            desc = L["DISPLAY_A_POP_UP_WITH_CHANGELOG_WHEN_ADDON_IS_UPDATED_TO_A_N"],
            width = 1.5,
            disabled = function() return not TheQuartermaster.db.profile.notifications.enabled end,
            get = function() return TheQuartermaster.db.profile.notifications.showUpdateNotes end,
            set = function(_, value) TheQuartermaster.db.profile.notifications.showUpdateNotes = value end,
        },
        showVaultReminder = {
            order = 74,
            type = "toggle",
            name = L["WEEKLY_VAULT_REMINDER"],
            desc = L["SHOW_A_REMINDER_WHEN_YOU_HAVE_UNCLAIMED_WEEKLY_VAULT_REWARDS"],
            width = 1.5,
            disabled = function() return not TheQuartermaster.db.profile.notifications.enabled end,
            get = function() return TheQuartermaster.db.profile.notifications.showVaultReminder end,
            set = function(_, value) TheQuartermaster.db.profile.notifications.showVaultReminder = value end,
        },
        showLootNotifications = {
            order = 75,
            type = "toggle",
            name = L["MOUNT_PET_TOY_LOOT_ALERTS"],
            desc = L["SHOW_A_NOTIFICATION_WHEN_A_NEW_MOUNT_PET_OR_TOY_ENTERS_YOUR"],
            width = 1.5,
            disabled = function() return not TheQuartermaster.db.profile.notifications.enabled end,
            get = function() return TheQuartermaster.db.profile.notifications.showLootNotifications end,
            set = function(_, value) TheQuartermaster.db.profile.notifications.showLootNotifications = value end,
        },
        resetVersionButton = {
            order = 76,
            type = "execute",
            name = L["SHOW_UPDATE_NOTES_AGAIN"],
            desc = L["RESET_THE_LAST_SEEN_VERSION_TO_SHOW_THE_UPDATE_NOTIFICATION"],
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
            name = L["CURRENCY"],
        },
        currencyDesc = {
            order = 81,
            type = "description",
            name = L["CONFIGURE_HOW_CURRENCIES_ARE_DISPLAYED_IN_THE_CURRENCY_TAB_N"],
        },
        currencyFilterMode = {
            order = 82,
            type = "select",
            name = L["FILTER_MODE"],
            desc = L["CHOOSE_WHICH_CURRENCIES_TO_DISPLAY_IN_THE_CURRENCY_TAB"],
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
            name = L["SHOW_ZERO_QUANTITIES"],
            desc = L["DISPLAY_CURRENCIES_EVEN_IF_THEIR_QUANTITY_IS_0"],
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
            name = L["TAB_FILTERING"],
        },
        tabDesc = {
            order = 101,
            type = "description",
            name = L["EXCLUDE_SPECIFIC_WARBAND_BANK_TABS_FROM_SCANNING_USEFUL_IF_Y"],
        },
        ignoredTab1 = {
            order = 102,
            type = "toggle",
            name = L["IGNORE_TAB_1"],
            desc = L["EXCLUDE_THIS_WARBAND_BANK_TAB_FROM_AUTOMATIC_SCANNING"],
            width = 1.2,
            get = function() return TheQuartermaster.db.profile.ignoredTabs[1] end,
            set = function(_, value) TheQuartermaster.db.profile.ignoredTabs[1] = value end,
        },
        ignoredTab2 = {
            order = 103,
            type = "toggle",
            name = L["IGNORE_TAB_2"],
            desc = L["EXCLUDE_THIS_WARBAND_BANK_TAB_FROM_AUTOMATIC_SCANNING"],
            width = 1.2,
            get = function() return TheQuartermaster.db.profile.ignoredTabs[2] end,
            set = function(_, value) TheQuartermaster.db.profile.ignoredTabs[2] = value end,
        },
        ignoredTab3 = {
            order = 104,
            type = "toggle",
            name = L["IGNORE_TAB_3"],
            desc = L["EXCLUDE_THIS_WARBAND_BANK_TAB_FROM_AUTOMATIC_SCANNING"],
            width = 1.2,
            get = function() return TheQuartermaster.db.profile.ignoredTabs[3] end,
            set = function(_, value) TheQuartermaster.db.profile.ignoredTabs[3] = value end,
        },
        ignoredTab4 = {
            order = 105,
            type = "toggle",
            name = L["IGNORE_TAB_4"],
            desc = L["EXCLUDE_THIS_WARBAND_BANK_TAB_FROM_AUTOMATIC_SCANNING"],
            width = 1.2,
            get = function() return TheQuartermaster.db.profile.ignoredTabs[4] end,
            set = function(_, value) TheQuartermaster.db.profile.ignoredTabs[4] = value end,
        },
        ignoredTab5 = {
            order = 106,
            type = "toggle",
            name = L["IGNORE_TAB_5"],
            desc = L["EXCLUDE_THIS_WARBAND_BANK_TAB_FROM_AUTOMATIC_SCANNING"],
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
            name = L["CHARACTER_MANAGEMENT"],
        },
        characterManagementDesc = {
            order = 111,
            type = "description",
            name = L["MANAGE_YOUR_TRACKED_CHARACTERS_YOU_CAN_DELETE_CHARACTER_DATA"],
        },
        deleteCharacterDropdown = {
            order = 112,
            type = "select",
            name = L["SELECT_CHARACTER_TO_DELETE"],
            desc = L["CHOOSE_A_CHARACTER_FROM_THE_LIST_TO_DELETE_THEIR_DATA"],
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
            name = L["DELETE_SELECTED_CHARACTER"],
            desc = L["PERMANENTLY_DELETE_THE_SELECTED_CHARACTERS_DATA"],
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
            name = L["N_N"],
        },
        
        -- ===== ADVANCED =====
        advancedHeader = {
            order = 900,
            type = "header",
            name = L["ADVANCED"],
        },
        advancedDesc = {
            order = 901,
            type = "description",
            name = L["ADVANCED_SETTINGS_AND_DATABASE_MANAGEMENT_USE_WITH_CAUTION_N"],
        },
        debugMode = {
            order = 902,
            type = "toggle",
            name = L["DEBUG_MODE"],
            desc = L["ENABLE_VERBOSE_LOGGING_FOR_DEBUGGING_PURPOSES_ONLY_ENABLE_IF"],
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
            name = L["SHOW_DATABASE_STATISTICS"],
            desc = L["DISPLAY_DETAILED_INFORMATION_ABOUT_YOUR_DATABASE_SIZE_AND_CO"],
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
            name = L["OPTIMIZE_DATABASE_NOW"],
            desc = L["MANUALLY_RUN_DATABASE_OPTIMIZATION_TO_CLEAN_UP_STALE_DATA_AN"],
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
            name = L["CFFFF0000WIPE_ALL_DATA_R"],
            desc = L["DELETE_ALL_ADDON_DATA_CHARACTERS_ITEMS_CURRENCY_REPUTATIONS"],
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
            name = L["SLASH_COMMANDS"],
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
        text = L["CFFFF0000WIPE_ALL_DATA_R_N_N"] ..
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

