--[[
    The Quartermaster - Core Module
    Main addon initialization and control logic
    
    A modern and functional Warband management system for World of Warcraft
]]

local ADDON_NAME, ns = ...

---@class TheQuartermaster : AceAddon, AceEvent-3.0, AceConsole-3.0, AceTimer-3.0, AceBucket-3.0
local TheQuartermaster = LibStub("AceAddon-3.0"):NewAddon(
    ADDON_NAME,
    "AceEvent-3.0",
    "AceConsole-3.0",
    "AceTimer-3.0",
    "AceBucket-3.0"
)

-- Store in namespace for module access
-- Keep ns.TheQuartermaster as a compatibility alias (many modules reference it)
ns.TheQuartermaster = TheQuartermaster
ns.Addon = TheQuartermaster

-- Localization
-- Note: Language override is applied in OnInitialize (after DB loads)
-- At this point, we use default game locale
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
ns.L = L

-- Shared constants/tables (loaded from Core/Constants.lua)
local WARBAND_TAB_COUNT = ns.WARBAND_TAB_COUNT
local ENABLE_GUILD_BANK = ns.ENABLE_GUILD_BANK
local WARBAND_BAGS = ns.WARBAND_BAGS
local PERSONAL_BANK_BAGS = ns.PERSONAL_BANK_BAGS
local ITEM_CATEGORIES = ns.ITEM_CATEGORIES

-- Performance: Local function references
local format = string.format
local floor = math.floor
local date = date
local time = time

--[[
    Database Defaults
    Profile-based structure for per-character settings
    Global structure for cross-character data (Warband cache)
]]
local defaults = ns.DEFAULTS

-- Local theme color calculator (kept here to avoid load-order issues)
-- Mirrors Modules/UI/SharedWidgets.lua CalculateThemeColors()
local function CalculateThemeColorsCore(masterR, masterG, masterB)
    local function Desaturate(r, g, b, amount)
        local gray = (r + g + b) / 3
        return r + (gray - r) * amount,
               g + (gray - g) * amount,
               b + (gray - b) * amount
    end

    local function AdjustBrightness(r, g, b, factor)
        return math.min(1, r * factor),
               math.min(1, g * factor),
               math.min(1, b * factor)
    end

    local darkR, darkG, darkB = AdjustBrightness(masterR, masterG, masterB, 0.7)
    local borderR, borderG, borderB = Desaturate(masterR * 0.5, masterG * 0.5, masterB * 0.5, 0.6)
    local activeR, activeG, activeB = AdjustBrightness(masterR, masterG, masterB, 0.5)
    local hoverR, hoverG, hoverB = AdjustBrightness(masterR, masterG, masterB, 0.6)

    return {
        accent = { masterR, masterG, masterB },
        accentDark = { darkR, darkG, darkB },
        border = { borderR, borderG, borderB },
        tabActive = { activeR, activeG, activeB },
        tabHover = { hoverR, hoverG, hoverB },
    }
end

local function GetPlayerClassRGB()
    local _, classFile = UnitClass("player")
    if not classFile then return nil end

    -- Prefer modern API when available
    if C_ClassColor and C_ClassColor.GetClassColor then
        local classColor = C_ClassColor.GetClassColor(classFile)
        if classColor then
            return classColor.r, classColor.g, classColor.b
        end
    end

    -- Fallback
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b
    end

    return nil
end

local function IsDefaultPurpleAccent(accent)
    if not accent then return false end
    return math.abs((accent[1] or 0) - 0.40) < 0.001
        and math.abs((accent[2] or 0) - 0.20) < 0.001
        and math.abs((accent[3] or 0) - 0.58) < 0.001
end

-- Apply theme colours based on the user's theme mode (class/static)
function TheQuartermaster:ApplyThemeFromMode()
    if not self.db or not self.db.profile then return end

    local p = self.db.profile
    local function Calc(r, g, b)
        if ns.UI_CalculateThemeColors then
            return ns.UI_CalculateThemeColors(r, g, b)
        end
        return CalculateThemeColorsCore(r, g, b)
    end

    if p.themeMode == 'class' then
        local r, g, b = GetPlayerClassRGB()
        if not (r and g and b) then
            r, g, b = 0.40, 0.20, 0.58
        end
        p.themeColors = Calc(r, g, b)
    else
        local c = p.themeColor or { r = 0.40, g = 0.20, b = 0.58 }
        local r = c.r or c[1] or 0.40
        local g = c.g or c[2] or 0.20
        local b = c.b or c[3] or 0.58
        p.themeColors = Calc(r, g, b)
    end

    if ns.UI_RefreshColors then
        ns.UI_RefreshColors()
    end
end

--[[
    Initialize the addon
    Called when the addon is first loaded
]]
function TheQuartermaster:OnInitialize()
    -- Initialize database with defaults
    self.db = LibStub("AceDB-3.0"):New("TheQuartermasterDB", defaults, true)

    -- View-only bank browsing (no bank UI replacement / no item movement).
    -- If older profiles had these enabled, force-disable to match current design.
    do
        local p = self.db.profile
        p.replaceDefaultBank = false
        p.bankModuleEnabled = false
    end
    
    -- Register database callbacks for profile changes
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

    -- Theme migration / behaviour
    -- themeMode governs whether the theme is dynamic (class) or fixed (static).
    -- If upgrading from older versions that only stored themeColors, we infer the intent:
    --   - default purple => switch to class mode
    --   - custom colour  => keep as static
    do
        local p = self.db.profile
        local accent = p.themeColors and p.themeColors.accent

        if p.themeMode == nil then
            if accent and (not IsDefaultPurpleAccent(accent)) then
                p.themeMode = 'static'
            else
                p.themeMode = 'class'
            end
        end

        if p.themeColor == nil then
            if accent and accent[1] and accent[2] and accent[3] then
                p.themeColor = { r = accent[1], g = accent[2], b = accent[3] }
            else
                p.themeColor = { r = 0.40, g = 0.20, b = 0.58 }
            end
        end

        -- Ensure themeColors reflects the current session's mode (class mode updates per-character login)
        self:ApplyThemeFromMode()
    end

    
    -- Ensure theme colors are fully calculated (for migration from old versions)
    if self.db.profile.themeColors then
        local colors = self.db.profile.themeColors
        -- If missing calculated variations, regenerate them
        if not colors.accentDark or not colors.tabHover then
            if ns.UI_CalculateThemeColors and colors.accent then
                local accent = colors.accent
                self.db.profile.themeColors = ns.UI_CalculateThemeColors(accent[1], accent[2], accent[3])
            end
        end
    end
    
    -- Initialize configuration (defined in Config.lua)
    self:InitializeConfig()
    
    -- Setup slash commands
    self:RegisterChatCommand("tq", "SlashCommand")
    self:RegisterChatCommand("quartermaster", "SlashCommand")
    self:RegisterChatCommand("thequartermaster", "SlashCommand")
    
    -- Initialize minimap button (LibDBIcon)
    C_Timer.After(1, function()
        if TheQuartermaster and TheQuartermaster.InitializeMinimapButton then
            TheQuartermaster:InitializeMinimapButton()
        end
    end)
    
end

--[[
    Enable the addon
    Called when the addon becomes enabled
]]
function TheQuartermaster:OnEnable()
    if not self.db.profile.enabled then
        return
    end
    
    -- Reset session-only flags
    self.classicModeThisSession = false
    -- Apply theme for this session (class mode updates per character login)
    self:ApplyThemeFromMode()

    -- Combat-end hook for deferred reload prompts (e.g., /tq resetrep)
    self:RegisterEvent("PLAYER_REGEN_ENABLED")

	-- 12.0+ safety: Blizzard tooltips may pass "secret" money values into SetTooltipMoney.
	-- Coerce to a plain number to avoid MoneyFrame_Update arithmetic errors.
	if not self._tooltipMoneyFixApplied and type(SetTooltipMoney) == "function" then
		local origSetTooltipMoney = SetTooltipMoney
		SetTooltipMoney = function(frame, money, ...)
			if type(money) ~= "number" then
				money = tonumber(money) or 0
			end
			return origSetTooltipMoney(frame, money, ...)
		end
		self._tooltipMoneyFixApplied = true
	end
    
    -- CRITICAL: Check for addon conflicts immediately on enable (only if bank module enabled)
    -- This runs on both initial login AND /reload
    -- Detect if user re-enabled conflicting addons/modules
    C_Timer.After(0.5, function()
        if not TheQuartermaster or not TheQuartermaster.db or not TheQuartermaster.db.profile then
            return
        end
        
        -- Skip conflict detection if bank module is disabled
        if not TheQuartermaster.db.profile.bankModuleEnabled then
            return
        end
        
        -- Check if there are existing conflict choices
        local hasConflictChoices = next(TheQuartermaster.db.profile.bankConflictChoices) ~= nil
        
        -- Detect all currently conflicting addons
        local conflicts = TheQuartermaster:DetectBankAddonConflicts()
        
        -- Reset choices for re-enabled addons (if conflict exists AND choice was useWarband)
        if conflicts and #conflicts > 0 and TheQuartermaster.db.profile.bankConflictChoices then
            for _, addonName in ipairs(conflicts) do
                local choice = TheQuartermaster.db.profile.bankConflictChoices[addonName]
                
                if choice == "useWarband" then
                    -- User chose Warband but addon is back, reset choice
                    TheQuartermaster.db.profile.bankConflictChoices[addonName] = nil
                    TheQuartermaster:Print("|cffffaa00" .. addonName .. " was re-enabled! Choose again...|r")
                end
            end
        end
        
        -- Call CheckBankConflictsOnLogin if:
        -- 1. No choices exist yet (fresh enable or choices were reset)
        -- 2. OR conflicts detected that need resolution
        if not hasConflictChoices or (conflicts and #conflicts > 0) then
            C_Timer.After(1, function()
                if TheQuartermaster and TheQuartermaster.CheckBankConflictsOnLogin then
                    TheQuartermaster:CheckBankConflictsOnLogin()
                end
            end)
        end
    end)
    
    -- Initialize conflict queue and guards
    self._conflictQueue = {}
    self._isProcessingConflict = false
    
    -- Session flag to prevent duplicate saves
    self.characterSaved = false
    
    -- Register events
    self:RegisterEvent("ADDON_LOADED", "OnAddonLoaded") -- Detect when conflicting addons are loaded
    self:RegisterEvent("BANKFRAME_OPENED", "OnBankOpened")
    self:RegisterEvent("BANKFRAME_CLOSED", "OnBankClosed")
    self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", "OnBagUpdate") -- Personal bank slot changes
    
    -- Guild Bank events (disabled by default, set ENABLE_GUILD_BANK=true to enable)
    if ENABLE_GUILD_BANK then
        self:RegisterEvent("GUILDBANKFRAME_OPENED", "OnGuildBankOpened")
        self:RegisterEvent("GUILDBANKFRAME_CLOSED", "OnGuildBankClosed")
        self:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED", "OnBagUpdate") -- Guild bank slot changes
    end
    
    self:RegisterEvent("PLAYER_MONEY", "OnMoneyChanged")
    self:RegisterEvent("ACCOUNT_MONEY", "OnMoneyChanged") -- Warband Bank gold changes
    self:RegisterEvent("CURRENCY_DISPLAY_UPDATE", "OnCurrencyChanged") -- Currency changes
    self:RegisterEvent("UPDATE_FACTION", "OnReputationChanged") -- Reputation changes
    self:RegisterEvent("PLAYER_GUILD_UPDATE", "OnGuildChanged") -- Guild name/rank changes
    self:RegisterEvent("GUILD_ROSTER_UPDATE", "OnGuildChanged") -- Rank/roster changes
    self:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "OnReputationChanged") -- Renown level changes
    self:RegisterEvent("MAJOR_FACTION_UNLOCKED", "OnReputationChanged") -- Renown unlock
    self:RegisterEvent("QUEST_LOG_UPDATE", "OnReputationChanged") -- Quest completion (unlocks)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("PLAYER_LEVEL_UP", "OnPlayerLevelUp")
    self:RegisterEvent("PLAYER_XP_UPDATE", "OnPlayerXPChanged")
    self:RegisterEvent("PLAYER_UPDATE_RESTING", "OnPlayerXPChanged")
    -- Character metadata
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecializationChanged")
    self:RegisterEvent("TIME_PLAYED_MSG", "OnTimePlayedMsg")
    
    -- M+ completion events (for cache updates)
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED")  -- Fires when M+ run completes
    self:RegisterEvent("MYTHIC_PLUS_NEW_WEEKLY_RECORD")  -- Fires when new best time
    
    -- Combat protection for UI (taint prevention)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart") -- Entering combat
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")  -- Leaving combat
    
    -- PvE tracking events are now managed by EventManager (throttled versions)
    -- See Modules/EventManager.lua InitializeEventManager()
    
    -- Collection tracking events are now managed by EventManager (debounced versions)
    -- See Modules/EventManager.lua InitializeEventManager()
    
    -- Register bucket events for bag updates (fast refresh for responsive UI)
    self:RegisterBucketEvent("BAG_UPDATE", 0.15, "OnBagUpdate")
    
    -- Setup BankFrame suppress hook
    -- This prevents BankFrame from showing when bank is opened
    C_Timer.After(1, function()
        if TheQuartermaster and TheQuartermaster.SetupBankFrameHook then
            TheQuartermaster:SetupBankFrameHook()
        end
    end)
    
    -- Hook container clicks to ensure UI refreshes on item move
    -- Note: ContainerFrameItemButton_OnModifiedClick was removed in TWW (11.0+)
    -- We now rely on BAG_UPDATE_DELAYED event for UI updates
    if not self.containerHooked then
        self.containerHooked = true
    end
    
    -- Initialize advanced modules
    -- API Wrapper: Initialize first (other modules may use it)
    if self.InitializeAPIWrapper then
        self:InitializeAPIWrapper()
    end
    
    -- Cache Manager: Smart caching for performance
    if self.WarmupCaches then
        C_Timer.After(2, function()
            if TheQuartermaster and TheQuartermaster.WarmupCaches then
                TheQuartermaster:WarmupCaches()
            end
        end)
    end
    
    -- Event Manager: Throttled/debounced event handling
    if self.InitializeEventManager then
        C_Timer.After(0.5, function()
            if TheQuartermaster and TheQuartermaster.InitializeEventManager then
                TheQuartermaster:InitializeEventManager()
            end
        end)
    end
    
    -- Tooltip Enhancer: Add item locations to tooltips
    if self.InitializeTooltipEnhancer then
        C_Timer.After(0.5, function()
            if TheQuartermaster and TheQuartermaster.InitializeTooltipEnhancer then
                TheQuartermaster:InitializeTooltipEnhancer()
            end
        end)
    end
    
    -- Tooltip Click Handler
    -- Removed: We no longer auto-open/search the addon when Shift is held over
    -- item links. This behaviour was tied to the old "Show click hint" option.
    
    -- Error Handler: Wrap critical functions for production safety
    -- NOTE: This must run AFTER all other modules are loaded
    if self.InitializeErrorHandler then
        C_Timer.After(1.5, function()
            if TheQuartermaster and TheQuartermaster.InitializeErrorHandler then
                TheQuartermaster:InitializeErrorHandler()
            end
        end)
    end
    
    -- Database Optimizer: Auto-cleanup and optimization
    if self.InitializeDatabaseOptimizer then
        C_Timer.After(5, function()
            if TheQuartermaster and TheQuartermaster.InitializeDatabaseOptimizer then
                TheQuartermaster:InitializeDatabaseOptimizer()
            end
        end)
    end

    -- Collection Tracking: Mount/Pet/Toy detection
    -- CollectionManager handles bag scanning and event registration
    C_Timer.After(1, function()
        if TheQuartermaster and TheQuartermaster.InitializeCollectionTracking then
            TheQuartermaster:InitializeCollectionTracking()
        else
            TheQuartermaster:Print("|cffff0000ERROR: InitializeCollectionTracking not found!|r")
        end
    end)

    -- Print loaded message
    self:Print(L["ADDON_LOADED"])
end

--[[
    Save character data - called once per login
]]
function TheQuartermaster:SaveCharacter()
    -- Prevent duplicate saves
    if self.characterSaved then
        return
    end
    
    local success, err = pcall(function()
        self:SaveCurrentCharacterData()
    end)
    
    if success then
        self.characterSaved = true
    else
        self:Print("Error saving character: " .. tostring(err))
    end
end


--[[
    Disable the addon
    Called when the addon becomes disabled
]]
function TheQuartermaster:OnDisable()
    -- Unregister all events
    self:UnregisterAllEvents()
    self:UnregisterAllBuckets()
end

--[[
    Handle profile changes
    Refresh settings when profile is changed/copied/reset
]]
function TheQuartermaster:OnProfileChanged()
    -- Refresh UI elements if they exist
    if self.RefreshUI then
        self:RefreshUI()
    end
    
end

--[[
    Slash command handler
    @param input string The command input
]]
function TheQuartermaster:SlashCommand(input)
    local cmd = self:GetArgs(input, 1)
    
    -- No command - open addon window
    if not cmd or cmd == "" then
        self:ShowMainWindow()
        return
    end
    
    -- Help command - show available commands
    if cmd == "help" then
        self:Print("|cff00ccffThe Quartermaster|r - Available commands:")
        self:Print("  |cff00ccff/tq|r - Open addon window")
        self:Print("  |cff00ccff/tq options|r - Open settings")
        self:Print("  |cff00ccff/tq cleanup|r - Remove inactive characters (90+ days)")
        self:Print("  |cff00ccff/tq resetrep|r - Reset reputation data (rebuild from API)")
        return
    end
    
    -- Public commands (always available)
    if cmd == "show" or cmd == "toggle" or cmd == "open" then
        self:ShowMainWindow()
        return
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        self:OpenOptions()
        return
    elseif cmd == "cleanup" then
        if self.CleanupStaleCharacters then
            local removed = self:CleanupStaleCharacters(90)
            if removed == 0 then
                self:Print("|cff00ff00No inactive characters found (90+ days)|r")
            else
                self:Print("|cff00ff00Removed " .. removed .. " inactive character(s)|r")
            end
        end
        return
    elseif cmd == "resetrep" then
        -- Reset reputation data (clear old structure, rebuild from API)
        self:Print("|cffff9900Resetting reputation data...|r")
        
        -- Clear old metadata
        if self.db.global.factionMetadata then
            self.db.global.factionMetadata = {}
        end
        
        -- Clear reputation data for current character
        local playerKey = UnitName("player") .. "-" .. GetRealmName()
        if self.db.global.characters[playerKey] then
            self.db.global.characters[playerKey].reputations = {}
            self.db.global.characters[playerKey].reputationHeaders = {}
        end
        
        -- Invalidate cache
        if self.InvalidateReputationCache then
            self:InvalidateReputationCache(playerKey)
        end
        
        -- Rebuild metadata and scan
        if self.BuildFactionMetadata then
            self:BuildFactionMetadata()
        end
        
        if self.ScanReputations then
            C_Timer.After(0.5, function()
                self.currentTrigger = "CMD_RESET"
                self:ScanReputations()
                self:Print("|cff00ff00Reputation data reset complete! A UI reload is required to fully apply the reset.|r")

                -- Refresh UI (best-effort without reload)
                if self.RefreshUI then
                    self:RefreshUI()
                end

                -- Offer a user-confirmed reload (avoids protected Reload() calls / taint)
                if InCombatLockdown and InCombatLockdown() then
                    self._pendingReloadPopup = true
                    self:Print("|cffff6600In combat - reload prompt will appear when combat ends.|r")
                else
                    if self.ShowReloadPopup then
                        self:ShowReloadPopup()
                    else
                        self:Print("|cffffaa00Please type |r|cff00ff00/reload|r|cffffaa00 to complete the reset.|r")
                    end
                end
end)
        end
        
        return
    elseif cmd == "debug" then
        -- Hidden debug mode toggle (for developers)
        self.db.profile.debugMode = not self.db.profile.debugMode
        if self.db.profile.debugMode then
            self:Print("|cff00ff00Debug mode enabled|r")
        else
            self:Print("|cffff9900Debug mode disabled|r")
        end
        return
    end
    
    -- Debug commands (only work when debug mode is enabled)
    if not self.db.profile.debugMode then
        self:Print("|cffff6600Unknown command. Type |r|cff00ccff/tq help|r|cffff6600 for available commands.|r")
        return
    end
    
    -- Debug mode active - process debug commands
    if cmd == "scan" then
        self:ScanWarbandBank()
    elseif cmd == "scancurr" then
        -- Scan ALL currencies from the game
        self:Print("=== Scanning ALL Currencies ===")
        if not C_CurrencyInfo then
            self:Print("|cffff0000C_CurrencyInfo API not available!|r")
            return
        end
        
        local etherealFound = {}
        local totalScanned = 0
        
        -- Scan by iterating through possible currency IDs (brute force for testing)
        for id = 3000, 3200 do
            local info = C_CurrencyInfo.GetCurrencyInfo(id)
            if info and info.name and info.name ~= "" then
                totalScanned = totalScanned + 1
                
                -- Look for Ethereal or Season 3 related
                if info.name:match("Ethereal") or info.name:match("Season") then
                    table.insert(etherealFound, format("[%d] %s (qty: %d)", 
                        id, info.name, info.quantity or 0))
                end
            end
        end
        
        if #etherealFound > 0 then
            self:Print("|cff00ff00Found Ethereal/Season 3 currencies:|r")
            for _, line in ipairs(etherealFound) do
                self:Print(line)
            end
        else
            self:Print("|cffffcc00No Ethereal currencies found in range 3000-3200|r")
        end
        
        self:Print(format("Total currencies scanned: %d", totalScanned))
    elseif cmd == "chars" or cmd == "characters" then
        self:PrintCharacterList()
    elseif cmd == "storage" or cmd == "browse" then
        -- Show Storage tab directly
        self:ShowMainWindow()
        if self.UI and self.UI.mainFrame then
            self.UI.mainFrame.currentTab = "storage"
            if self.PopulateContent then
                self:PopulateContent()
            end
        end
    elseif cmd == "pve" then
        -- Show PvE tab directly
        self:ShowMainWindow()
        if self.UI and self.UI.mainFrame then
            self.UI.mainFrame.currentTab = "pve"
            if self.PopulateContent then
                self:PopulateContent()
            end
        end
    elseif cmd == "pvedata" or cmd == "pveinfo" then
        -- Print current character's PvE data
        self:PrintPvEData()
    elseif cmd == "enumcheck" then
        -- Debug: Check Enum values
        self:Print("=== Enum.WeeklyRewardChestThresholdType Values ===")
        if Enum and Enum.WeeklyRewardChestThresholdType then
            self:Print("  Raid: " .. tostring(Enum.WeeklyRewardChestThresholdType.Raid))
            self:Print("  Activities (M+): " .. tostring(Enum.WeeklyRewardChestThresholdType.Activities))
            self:Print("  RankedPvP: " .. tostring(Enum.WeeklyRewardChestThresholdType.RankedPvP))
            self:Print("  World: " .. tostring(Enum.WeeklyRewardChestThresholdType.World))
        else
            self:Print("  Enum.WeeklyRewardChestThresholdType not available")
        end
        self:Print("=============================================")
        -- Also collect and show current vault activities
        if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
            local activities = C_WeeklyRewards.GetActivities()
            if activities and #activities > 0 then
                self:Print("Current Vault Activities:")
                for i, activity in ipairs(activities) do
                    self:Print(string.format("  [%d] type=%s, index=%s, progress=%s/%s", 
                        i, tostring(activity.type), tostring(activity.index),
                        tostring(activity.progress), tostring(activity.threshold)))
                end
            else
                self:Print("No current vault activities")
            end
        end
    elseif cmd == "dumpbank" then
        -- Debug command to dump BankFrame structure
        if self.DumpBankFrameInfo then
            self:DumpBankFrameInfo()
        else
            self:Print("DumpBankFrameInfo not available")
        end
    elseif cmd == "cache" or cmd == "cachestats" then
        if self.PrintCacheStats then
            self:PrintCacheStats()
        else
            self:Print("CacheManager not loaded")
        end
    elseif cmd == "events" or cmd == "eventstats" then
        if self.PrintEventStats then
            self:PrintEventStats()
        else
            self:Print("EventManager not loaded")
        end
    elseif cmd == "resetprof" then
        if self.ResetProfessionData then
            self:ResetProfessionData()
            self:Print("Profession data reset.")
        else
            -- Manual fallback
            local name = UnitName("player")
            local realm = GetRealmName()
            local key = name .. "-" .. realm
            if self.db.global.characters and self.db.global.characters[key] then
                self.db.global.characters[key].professions = nil
                self:Print("Profession data manually reset")
            end
        end
    elseif cmd == "currency" or cmd == "curr" then
        -- Debug currency data
        local name = UnitName("player")
        local realm = GetRealmName()
        local key = name .. "-" .. realm
        
        self:Print("=== Currency Debug ===")
        if self.db.global.characters and self.db.global.characters[key] then
            local char = self.db.global.characters[key]
            if char.currencies then
                local count = 0
                local etherealCurrencies = {}
                
                for currencyID, currency in pairs(char.currencies) do
                    count = count + 1
                    
                    -- Look for Ethereal currencies
                    if currency.name and currency.name:match("Ethereal") then
                        table.insert(etherealCurrencies, format("  [%d] %s: %d/%d (expansion: %s)", 
                            currencyID, currency.name, 
                            currency.quantity or 0, currency.maxQuantity or 0,
                            currency.expansion or "Unknown"))
                    end
                end
                
                if #etherealCurrencies > 0 then
                    self:Print("|cff00ff00Ethereal Currencies Found:|r")
                    for _, info in ipairs(etherealCurrencies) do
                        self:Print(info)
                    end
                else
                    self:Print("|cffffcc00No Ethereal currencies found!|r")
                end
                
                self:Print(format("Total currencies collected: %d", count))
            else
                self:Print("|cffff0000No currency data found!|r")
                self:Print("Running UpdateCurrencyData()...")
                if self.UpdateCurrencyData then
                    self:UpdateCurrencyData()
                    self:Print("|cff00ff00Currency data collected!|r")
                end
            end
        else
            self:Print("|cffff0000Character not found in database!|r")
        end
    elseif cmd == "minimap" then
        if self.ToggleMinimapButton then
            self:ToggleMinimapButton()
        else
            self:Print("Minimap button module not loaded")
        end
    
    elseif cmd == "bankcheck" then
        -- Check for bank addon conflicts
        local conflicts = self:DetectBankAddonConflicts()
        
        self:Print("=== Bank Conflict Status ===")
        
        if conflicts and #conflicts > 0 then
            self:Print("Conflicting addons detected:")
            for _, addonName in ipairs(conflicts) do
                local choice = self.db.profile.bankConflictChoices[addonName]
                if choice == "useWarband" then
                    self:Print(string.format("  |cff00ccff%s|r: |cff00ff00Using The Quartermaster|r", addonName))
                elseif choice == "useOther" then
                    self:Print(string.format("  |cff00ccff%s|r: |cff888888Using %s|r", addonName, addonName))
                else
                    self:Print(string.format("  |cff00ccff%s|r: |cffff9900Not resolved yet|r", addonName))
                end
            end
            self:Print("")
            self:Print("To reset: Type |cff00ccff/tq bankreset|r")
        else
            self:Print("|cff00ff00✓ No conflicts detected|r")
            self:Print("The Quartermaster is managing your bank UI!")
        end
        
        self:Print("==========================")
    
    elseif cmd == "bankreset" then
        -- Reset ALL bank conflict choices
        self.db.profile.bankConflictChoices = {}
        self:ClearConflictCache()
        self:Print("|cff00ff00All bank conflict choices reset!|r")
        self:Print("Type |cff00ccff/reload|r to see conflict popups again.")
    
    elseif cmd == "vaultcheck" or cmd == "testvault" then
        -- Test vault notification system
        if self.TestVaultCheck then
            self:TestVaultCheck()
        else
            self:Print("Vault check module not loaded")
        end
    
    elseif cmd == "testloot" then
        -- Test loot notification system
        -- Parse the type argument (mount/pet/toy or nil for all)
        local typeArg = input:match("^testloot%s+(%w+)") -- Extract word after "testloot "
        self:Print("|cff888888[DEBUG] testloot command: typeArg = " .. tostring(typeArg) .. "|r")
        if self.TestLootNotification then
            self:TestLootNotification(typeArg)
        else
            self:Print("|cffff0000Loot notification module not loaded!|r")
            self:Print("|cffff6600Attempting to initialize...|r")
            if self.InitializeLootNotifications then
                self:InitializeLootNotifications()
                self:Print("|cff00ff00Manual initialization complete. Try /tq testloot again.|r")
            else
                self:Print("|cffff0000InitializeLootNotifications function not found!|r")
            end
        end
    
    elseif cmd == "initloot" then
        -- Debug: Force initialize loot notifications
        self:Print("|cff00ccff[DEBUG] Forcing InitializeLootNotifications...|r")
        if self.InitializeLootNotifications then
            self:InitializeLootNotifications()
        else
            self:Print("|cffff0000ERROR: InitializeLootNotifications not found!|r")
        end

    -- Hidden/Debug commands
    elseif cmd == "errors" then
        local subCmd = self:GetArgs(input, 2, 1)
        if subCmd == "full" or subCmd == "all" then
            self:PrintRecentErrors(20)
        elseif subCmd == "clear" then
            if self.ClearErrorLog then
                self:ClearErrorLog()
            end
        elseif subCmd == "stats" then
            if self.PrintErrorStats then
                self:PrintErrorStats()
            end
        elseif subCmd == "export" then
            if self.ExportErrorLog then
                local log = self:ExportErrorLog()
                self:Print("Error log exported. Check chat for full log.")
                -- Print full log (only in debug mode for cleanliness)
                if self.db.profile.debugMode then
                    print(log)
                end
            end
        elseif tonumber(subCmd) then
            if self.ShowErrorDetails then
                self:ShowErrorDetails(tonumber(subCmd))
            end
        else
            if self.PrintRecentErrors then
                self:PrintRecentErrors(5)
            end
        end
    elseif cmd == "recover" or cmd == "emergency" then
        if self.EmergencyRecovery then
            self:EmergencyRecovery()
        end
    elseif cmd == "dbstats" or cmd == "dbinfo" then
        if self.PrintDatabaseStats then
            self:PrintDatabaseStats()
        end
    elseif cmd == "optimize" or cmd == "dboptimize" then
        if self.RunOptimization then
            self:RunOptimization()
        end
    elseif cmd == "apireport" or cmd == "apicompat" then
        if self.PrintAPIReport then
            self:PrintAPIReport()
        end
    elseif cmd == "suppress" then
        -- Manual suppress - force hide Blizzard bank UI
        self:Print("=== Manual Suppress ===")
        if self.SuppressDefaultBankFrame then
            self:SuppressDefaultBankFrame()
            self:Print("SuppressDefaultBankFrame() called")
        else
            self:Print("|cffff0000Function not found!|r")
        end
    elseif cmd == "bankstatus" or cmd == "bankinfo" then
        -- Debug: Print bank frame status
        self:Print("=== Bank Frame Status ===")
        self:Print("bankFrameSuppressed: " .. tostring(self.bankFrameSuppressed))
        self:Print("bankFrameHooked: " .. tostring(self.bankFrameHooked))
        self:Print("bankIsOpen: " .. tostring(self.bankIsOpen))
        self:Print("replaceDefaultBank setting: " .. tostring(self.db.profile.replaceDefaultBank))
        
        if BankFrame then
            self:Print("BankFrame exists: true")
            self:Print("BankFrame:IsShown(): " .. tostring(BankFrame:IsShown()))
            self:Print("BankFrame:GetAlpha(): " .. tostring(BankFrame:GetAlpha()))
            local point, relativeTo, relativePoint, xOfs, yOfs = BankFrame:GetPoint()
            self:Print("BankFrame position: " .. tostring(xOfs) .. ", " .. tostring(yOfs))
        else
            self:Print("BankFrame exists: false")
        end
        
        -- TWW: Check BankPanel
        if BankPanel then
            self:Print("BankPanel exists: true")
            self:Print("BankPanel:IsShown(): " .. tostring(BankPanel:IsShown()))
            self:Print("BankPanel:GetAlpha(): " .. tostring(BankPanel:GetAlpha()))
            local point, relativeTo, relativePoint, xOfs, yOfs = BankPanel:GetPoint()
            self:Print("BankPanel position: " .. tostring(xOfs or "nil") .. ", " .. tostring(yOfs or "nil"))
        else
            self:Print("BankPanel exists: false")
        end
        self:Print("========================")
    else
        self:Print("|cffff6600Unknown command:|r " .. cmd)
    end
end

--[[
    Print list of tracked characters
]]
function TheQuartermaster:PrintCharacterList()
    self:Print("=== Tracked Characters ===")
    
    local chars = self:GetAllCharacters()
    if #chars == 0 then
        self:Print("No characters tracked yet.")
        return
    end
    
    for _, char in ipairs(chars) do
        local lastSeenText = ""
        if char.lastSeen then
            local diff = time() - char.lastSeen
            if diff < 60 then
                lastSeenText = "now"
            elseif diff < 3600 then
                lastSeenText = math.floor(diff / 60) .. "m ago"
            elseif diff < 86400 then
                lastSeenText = math.floor(diff / 3600) .. "h ago"
            else
                lastSeenText = math.floor(diff / 86400) .. "d ago"
            end
        end
        
        self:Print(string.format("  %s (%s Lv%d) - %s",
            char.name or "?",
            char.classFile or "?",
            char.level or 0,
            lastSeenText
        ))
    end
    
    self:Print("Total: " .. #chars .. " characters")
    self:Print("==========================")
end

-- InitializeDataBroker() moved to Modules/MinimapButton.lua (now InitializeMinimapButton)

--[[
    Event Handlers
]]

function TheQuartermaster:OnBankOpened()
    self.bankIsOpen = true
    
    -- Check if in Classic Mode for this session
    if self.classicModeThisSession then
        -- Don't suppress Blizzard UI
        -- Don't auto-open The Quartermaster
        -- Just scan data in background
        if self.db.profile.autoScan then
            if self.ScanPersonalBank then
                self:ScanPersonalBank()
            end
        end
        return
    end
    
    -- Check if bank module UI features are enabled
    local bankModuleEnabled = self.db.profile.bankModuleEnabled
    
    -- Check if ANY conflict addon was chosen as "useOther" (background mode)
    local useOtherAddon = self:IsUsingOtherBankAddon()
    
    -- Only manage bank UI if module is enabled AND no other addon is in use
    if bankModuleEnabled and not useOtherAddon then
        -- Normal mode: TheQuartermaster manages bank UI
        
        -- CRITICAL: Suppress Blizzard's bank frame immediately
        self:SuppressDefaultBankFrame()
        
        -- Read which tab Blizzard selected when bank opened
        local blizzardSelectedTab = nil
        if BankFrame then
            blizzardSelectedTab = BankFrame.selectedTab or BankFrame.activeTabIndex
            if not blizzardSelectedTab and BankFrame.TabSystem then
                blizzardSelectedTab = BankFrame.TabSystem.selectedTab
            end
        end
        
        local warbandTabID = BankFrame and BankFrame.accountBankTabID or 2
        
        -- Determine bank type: Default to Personal Bank unless Warband tab is selected
        if blizzardSelectedTab == warbandTabID then
            self.currentBankType = "warband"
        else
            self.currentBankType = "personal"
        end
        
        -- Open player bags (only in normal mode)
        if OpenAllBags then
            OpenAllBags()
        end
    end
    
    -- PERFORMANCE: Batch scan operations
    if self.db.profile.autoScan then
        if self.ScanPersonalBank then
            self:ScanPersonalBank()
        end
    end
    
    -- PERFORMANCE: Single delayed callback instead of nested timers
    C_Timer.After(0.3, function()
        if not TheQuartermaster then return end
        
        -- Check Warband bank accessibility
        local firstBagID = Enum.BagIndex.AccountBankTab_1
        local numSlots = C_Container.GetContainerNumSlots(firstBagID)
        
        if numSlots and numSlots > 0 then
            TheQuartermaster.warbandBankIsOpen = true
            
            -- Scan warband bank
            if TheQuartermaster.db.profile.autoScan and TheQuartermaster.ScanWarbandBank then
                TheQuartermaster:ScanWarbandBank()
            end
        end
        
        -- CRITICAL: Check for addon conflicts when bank opens (only if module enabled)
        -- This catches runtime changes (user opened ElvUI bags settings, re-enabled module, etc.)
        if TheQuartermaster.db.profile.bankModuleEnabled and TheQuartermaster and TheQuartermaster.db and TheQuartermaster.db.profile and TheQuartermaster.db.profile.bankConflictChoices then
            local conflicts = TheQuartermaster:DetectBankAddonConflicts()
            if conflicts and #conflicts > 0 then
                -- Check each conflict to see if user previously chose "useWarband"
                -- If so, they've re-enabled the addon/module and need to choose again
                local choicesReset = false
                
                for _, addonName in ipairs(conflicts) do
                    local choice = TheQuartermaster.db.profile.bankConflictChoices[addonName]
                    
                    if choice == "useWarband" then
                        -- User previously chose Warband but addon/module is enabled again!
                        -- RESET the choice so popup will show
                        TheQuartermaster.db.profile.bankConflictChoices[addonName] = nil
                        choicesReset = true
                    end
                end
                
                -- If we reset any choices OR there are new conflicts, show popup
                if choicesReset or not next(TheQuartermaster.db.profile.bankConflictChoices) then
                    -- Use CheckBankConflictsOnLogin which has throttling built-in
                    if TheQuartermaster.CheckBankConflictsOnLogin then
                        TheQuartermaster:CheckBankConflictsOnLogin()
                    end
                end
            end
        end
        
        -- Auto-open window ONLY if bank module enabled AND using TheQuartermaster mode
        local useOther = TheQuartermaster:IsUsingOtherBankAddon()
        if TheQuartermaster.db.profile.bankModuleEnabled and not useOther and TheQuartermaster.db.profile.autoOpenWindow ~= false then
            if TheQuartermaster and TheQuartermaster.ShowMainWindowWithItems then
                TheQuartermaster:ShowMainWindowWithItems(TheQuartermaster.currentBankType)
            end
        end
    end)
end

-- Note: We no longer use UnregisterAllEvents because it triggers BANKFRAME_CLOSED
-- Instead we just hide and move the frame off-screen

--[[
    Detect conflicting bank addons (CACHED)
    @return string|nil - Name of conflicting addon, or nil if none detected
]]
function TheQuartermaster:DetectBankAddonConflicts()
    -- Wrap in pcall to prevent errors from breaking the addon
    local success, conflicts = pcall(function()
        local found = {}
        
        -- TWW (11.0+) uses C_AddOns.IsAddOnLoaded(), older versions use IsAddOnLoaded()
        local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
        
        -- List of known conflicting addons (popular bank/bag addons)
        local conflictingAddons = {
            -- Popular bag addons
            "Bagnon", "Combuctor", "ArkInventory", "AdiBags", "Baganator",
            "LiteBag", "TBag", "BaudBag", "Inventorian",
            -- ElvUI modules
            "ElvUI_Bags", "ElvUI",
            -- Bank-specific
            "BankStack", "BankItems", "Sorted",
            -- Generic names (legacy)
            "BankUI", "InventoryManager", "BagAddon", "BankModifier",
            "CustomBank", "AdvancedInventory", "BagSystem"
        }
        
        for _, addonName in ipairs(conflictingAddons) do
            if IsLoaded(addonName) then
                -- ElvUI special check: Only add if bags module is enabled
                if addonName == "ElvUI" then
                    -- Check if ElvUI Bags module is ACTUALLY enabled
                    local elvuiConflict = false  -- Default: no conflict
                    
                    if ElvUI then
                        local E = ElvUI[1]
                        if E then
                            -- Bags is ENABLED if ANY of these is explicitly TRUE
                            local privateBagsEnabled = false
                            local dbBagsEnabled = false
                            
                            -- Check global setting (E.private.bags.enable)
                            if E.private and E.private.bags and E.private.bags.enable == true then
                                privateBagsEnabled = true
                            end
                            
                            -- Check profile setting (E.db.bags.enabled)
                            if E.db and E.db.bags and E.db.bags.enabled == true then
                                dbBagsEnabled = true
                            end
                            
                            -- Conflict if ANY setting is enabled
                            elvuiConflict = privateBagsEnabled or dbBagsEnabled
                        else
                            -- Can't access E, assume no conflict (safer default)
                            elvuiConflict = false
                        end
                    else
                        -- ElvUI not loaded yet, no conflict
                        elvuiConflict = false
                    end
                    
                    if elvuiConflict then
                        table.insert(found, addonName)
                    end
                else
                    -- Other addons: always conflict if loaded
                    table.insert(found, addonName)
                end
            end
        end
        
        return found
    end)
    
    if success then
        return conflicts
    else
        return {}
    end
end

--[[
    Helper: Check if any conflict addon is set to "useOther"
    Safe wrapper to prevent nil table errors
]]
function TheQuartermaster:IsUsingOtherBankAddon()
    if not self.db or not self.db.profile or not self.db.profile.bankConflictChoices then
        return false
    end
    
    for addonName, choice in pairs(self.db.profile.bankConflictChoices) do
        if choice == "useOther" then
            return true
        end
    end
    
    return false
end

--[[
    Clear conflict cache (call this after disabling an addon)
]]
function TheQuartermaster:ClearConflictCache()
    self._conflictCheckCache = nil
end

--[[
    Disable conflicting addon's bank module
    @param addonName string - Name of conflicting addon
    @return boolean success, string message
]]
function TheQuartermaster:DisableConflictingBankModule(addonName)
    if not addonName or addonName == "" then
        return false, "Unknown addon. Please disable manually."
    end
    
    -- ElvUI special handling - disable only bags module, not entire addon
    if addonName == "ElvUI" then
        -- Check if ElvUI is loaded
        if ElvUI then
            local E = ElvUI[1]
            if E then
                -- Method 1: Disable per-profile setting
                if E.db and E.db.bags then
                    E.db.bags.enabled = false
                end
                
                -- Method 2: Disable global setting (CRITICAL!)
                if E.private and E.private.bags then
                    E.private.bags.enable = false
                end
                
                -- Method 3: Try to disable module directly via ElvUI API
                if E.DisableModule then
                    pcall(function() E:DisableModule('Bags') end)
                end
                
                -- Method 4: Disable bags in ALL profiles (fallback)
                if E.data and E.data.profiles then
                    for profileName, profileData in pairs(E.data.profiles) do
                        if profileData.bags then
                            profileData.bags.enabled = false
                        end
                    end
                end
                
                -- Mark that bags module was disabled in our own DB
                if not self.db.profile.elvuiModuleStates then
                    self.db.profile.elvuiModuleStates = {}
                end
                self.db.profile.elvuiModuleStates.bagsDisabled = true
                
                self:Print("|cff00ff00ElvUI Bags module disabled successfully!|r")
                return true, "ElvUI Bags module disabled. Please /reload to apply changes."
            end
        end
        
        -- Fallback if ElvUI not accessible yet
        return true, "ElvUI bags will be disabled. Please /reload to apply changes."
    end
    
    -- Bagnon, Combuctor, AdiBags, etc. - disable entire addon
    local DisableAddon = C_AddOns and C_AddOns.DisableAddOn or DisableAddOn
    DisableAddon(addonName)
    return true, string.format("%s disabled. Please /reload to apply changes.", addonName)
end

--[[
    Enable conflicting addon's bank module (when user chooses to use it)
    @param addonName string - Name of conflicting addon
    @return boolean success, string message
]]
function TheQuartermaster:EnableConflictingBankModule(addonName)
    if not addonName then
        return false, "No addon name provided"
    end
    
    -- ElvUI special handling - enable bags module only
    if addonName == "ElvUI" then
        if ElvUI then
            local E = ElvUI[1]
            if E then
                -- Method 1: Enable per-profile setting
                if E.db and E.db.bags then
                    E.db.bags.enabled = true
                end
                
                -- Method 2: Enable global setting (CRITICAL!)
                if E.private and E.private.bags then
                    E.private.bags.enable = true
                end
                
                -- Method 3: Try to enable module directly via ElvUI API
                if E.EnableModule then
                    pcall(function() E:EnableModule('Bags') end)
                end
                
                -- Method 4: Enable bags in ALL profiles (fallback)
                if E.data and E.data.profiles then
                    for profileName, profileData in pairs(E.data.profiles) do
                        if profileData.bags then
                            profileData.bags.enabled = true
                        end
                    end
                end
                
                -- Clear disabled state in our own DB
                if self.db.profile.elvuiModuleStates then
                    self.db.profile.elvuiModuleStates.bagsDisabled = false
                end
                
                self:Print("|cff00ff00ElvUI Bags module enabled successfully!|r")
                return true, "ElvUI Bags module enabled. Please /reload to apply changes."
            end
        end
        
        return true, "ElvUI bags will be enabled. Please /reload to apply changes."
    end
    
    -- Other addons - enable entire addon
    local EnableAddon = C_AddOns and C_AddOns.EnableAddOn or EnableAddOn
    EnableAddon(addonName)
    return true, string.format("%s enabled. Please /reload to apply changes.", addonName)
end

--[[
    Show bank addon conflict warning popup with disable option
    @param addonName string - Name of conflicting addon
]]
function TheQuartermaster:QueueConflictPopup(addonName)
    if not self._conflictQueue then
        self._conflictQueue = {}
    end
    table.insert(self._conflictQueue, addonName)
end

function TheQuartermaster:ShowNextConflictPopup()
    if not self._conflictQueue then
        self._conflictQueue = {}
    end
    
    if self._isProcessingConflict or #self._conflictQueue == 0 then
        return
    end
    
    self._isProcessingConflict = true
    local addonName = table.remove(self._conflictQueue, 1)
    self:ShowBankAddonConflictWarning(addonName)
end

function TheQuartermaster:CheckBankConflictsOnLogin()
    -- Throttle: Don't check more than once every 1 second
    -- Prevents duplicate popups from multiple triggers (OnEnable, OnPlayerEnteringWorld, etc.)
    local now = time()
    if self._lastConflictCheck and (now - self._lastConflictCheck) < 1 then
        return
    end
    self._lastConflictCheck = now
    
    -- Don't interrupt an ongoing conflict resolution
    if self._isProcessingConflict then
        return
    end
    
    -- Initialize flags
    self._needsReload = false
    
    -- Safety check: Ensure db is initialized
    if not self.db or not self.db.profile or not self.db.profile.bankConflictChoices then
        return
    end
    
    -- Skip if bank module is disabled
    if not self.db.profile.bankModuleEnabled then
        return
    end
    
    -- Detect all conflicting addons
    local conflicts = self:DetectBankAddonConflicts()
    
    if not conflicts or #conflicts == 0 then
        return -- No conflicts
    end
    
    -- Filter out addons that user already made a choice for
    -- Note: Choices are already reset in OnEnable/OnBankOpened if user re-enabled addons
    local unresolvedConflicts = {}
    for _, addonName in ipairs(conflicts) do
        local choice = self.db.profile.bankConflictChoices[addonName]
        
        -- Show popup if:
        -- 1. No choice exists yet (first time, or choice was reset due to re-enable)
        -- 2. User previously chose "useWarband" but addon is still detected
        --    (This shouldn't happen if our disable logic works, but safe fallback)
        if not choice then
            -- No choice = need to ask user
            table.insert(unresolvedConflicts, addonName)
        elseif choice == "useWarband" then
            -- User chose Warband but addon still detected (shouldn't happen normally)
            -- This is a safety net in case disable failed
            table.insert(unresolvedConflicts, addonName)
        end
        -- Skip if choice == "useOther" (user wants to keep the other addon)
    end
    
    if #unresolvedConflicts == 0 then
        return -- All conflicts already resolved
    end
    
    self:Print("|cffffaa00Showing conflict popup for " .. #unresolvedConflicts .. " addon(s)|r")
    
    -- Queue all unresolved conflicts
    for _, addonName in ipairs(unresolvedConflicts) do
        self:QueueConflictPopup(addonName)
    end
    
    -- Start showing popups
    self:ShowNextConflictPopup()
end

function TheQuartermaster:ShowReloadPopup()
    -- Create reload confirmation popup
    StaticPopupDialogs["TheQuartermaster_RELOAD_UI"] = {
        text = L["CFF00FF00ADDON_SETTINGS_CHANGED_R_N_NA_UI_RELOAD_IS_REQUIRED"],
        button1 = "Reload",
        button2 = "Later",
        OnAccept = function()
            -- Reload must be user-confirmed; call the standard reload API from the popup click.
            if type(ReloadUI) == "function" then
                ReloadUI()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    
    StaticPopup_Show("TheQuartermaster_RELOAD_UI")
end


-- Show deferred reload prompts once combat ends
function TheQuartermaster:PLAYER_REGEN_ENABLED()
    if self._pendingReloadPopup then
        self._pendingReloadPopup = nil
        if self.ShowReloadPopup then
            self:ShowReloadPopup()
        else
            self:Print("|cffffaa00Please type |r|cff00ff00/reload|r|cffffaa00 to complete the pending change.|r")
        end
    end
end


function TheQuartermaster:ShowBankAddonConflictWarning(addonName)
    -- Create or update popup dialog
    StaticPopupDialogs["TheQuartermaster_BANK_CONFLICT"] = {
        text = "",
        button1 = "Use The Quartermaster",
        button2 = "Use " .. addonName,
        OnAccept = function(self)
            -- Button 1: User wants to use The Quartermaster - disable conflicting addon
            local addonName = self.data
            TheQuartermaster.db.profile.bankConflictChoices[addonName] = "useWarband"
            
            local success, message = TheQuartermaster:DisableConflictingBankModule(addonName)
            if not success then
                TheQuartermaster:Print(message)
            end
            
            -- Mark that we need reload (if addon was disabled)
            if success then
                -- Track that we disabled this addon
                TheQuartermaster.db.profile.toggledAddons[addonName] = "disabled"
                TheQuartermaster._needsReload = true
                TheQuartermaster:ClearConflictCache()
            end
            
            TheQuartermaster._isProcessingConflict = false
            
            -- Process next conflict OR reload if no more conflicts
            if #TheQuartermaster._conflictQueue > 0 then
                -- More conflicts to resolve (small delay for UX)
                C_Timer.After(0.3, function()
                    if TheQuartermaster then
                        TheQuartermaster:ShowNextConflictPopup()
                    end
                end)
            elseif TheQuartermaster._needsReload then
                -- All done, show reload popup
                TheQuartermaster:ShowReloadPopup()
            end
        end,
        OnCancel = function(self)
            -- Button 2: User wants to keep the other addon
            local addonName = self.data
            TheQuartermaster.db.profile.bankConflictChoices[addonName] = "useOther"
            
            -- NEW: Automatically disable bank module since user chose other addon
            TheQuartermaster.db.profile.bankModuleEnabled = false
            
            -- Track that user chose this addon (it's already enabled)
            TheQuartermaster.db.profile.toggledAddons[addonName] = "enabled"
            
            TheQuartermaster:Print(string.format(
                "|cff00ff00Using %s for bank UI.|r The Quartermaster will run in background mode (data tracking only).",
                addonName
            ))
            
            -- Enable the conflicting addon (make sure it's active)
            local success, message = TheQuartermaster:EnableConflictingBankModule(addonName)
            if success then
                TheQuartermaster._needsReload = true
            end
            
            TheQuartermaster._isProcessingConflict = false
            
            -- Process next conflict OR finish if no more conflicts
            if #TheQuartermaster._conflictQueue > 0 then
                -- More conflicts to resolve (small delay for UX)
                C_Timer.After(0.3, function()
                    if TheQuartermaster then
                        TheQuartermaster:ShowNextConflictPopup()
                    end
                end)
            elseif TheQuartermaster._needsReload then
                -- Some addons were enabled/disabled, show reload popup
                TheQuartermaster:ShowReloadPopup()
            else
                -- All done, no reload needed
                TheQuartermaster:Print("|cff00ff00All conflicts resolved! No reload needed.|r")
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false, -- Force user to choose
        preferredIndex = 3,
    }
    
    -- Set dynamic text
    local warningText
    
    -- ElvUI special message (only bags module will be disabled)
    if addonName == "ElvUI" then
        warningText = string.format(
            "|cffff9900Bank Addon Conflict|r\n\n" ..
            "You have |cff00ccff%s|r installed.\n\n" ..
            "Which addon do you want to use for bank UI?\n\n" ..
            "|cff00ff00Use The Quartermaster:|r Disable ElvUI |cffaaaaaa(Bags module only)|r\n" ..
            "|cff888888Use %s:|r TheQuartermaster works in background mode\n\n" ..
            "|cff00ff00Note:|r Only the ElvUI Bags module will be disabled,\n" ..
            "not the entire ElvUI addon.\n\n" ..
            "Characters, PvE, and Statistics tabs work regardless of choice.",
            addonName, addonName
        )
    else
        -- Generic message for other addons
        warningText = string.format(
            "|cffff9900Bank Addon Conflict|r\n\n" ..
            "You have |cff00ccff%s|r installed.\n\n" ..
            "Which addon do you want to use for bank UI?\n\n" ..
            "|cff00ff00Use The Quartermaster:|r Disable %s automatically\n" ..
            "|cff888888Use %s:|r TheQuartermaster works in background mode\n\n" ..
            "Characters, PvE, and Statistics tabs work regardless of choice.",
            addonName, addonName, addonName
        )
    end
    
    StaticPopupDialogs["TheQuartermaster_BANK_CONFLICT"].text = warningText
    local dialog = StaticPopup_Show("TheQuartermaster_BANK_CONFLICT")
    if dialog then
        dialog.data = addonName
    end
end

-- Setup BankFrame hook to make it invisible (but NOT hidden - keeps API working!)
function TheQuartermaster:SetupBankFrameHook()
    if not BankFrame then return end
    if self.bankFrameHooked then return end
    if self:IsUsingOtherBankAddon() then return end
    
    -- Hook OnShow to re-suppress if Blizzard tries to show the frame
    BankFrame:HookScript("OnShow", function()
        if TheQuartermaster and TheQuartermaster.bankFrameSuppressed then
            TheQuartermaster:SuppressDefaultBankFrame()
        end
    end)
    
    self.bankFrameHooked = true
end

-- Suppress Blizzard Bank UI (hide it completely)
function TheQuartermaster:SuppressDefaultBankFrame()
    if not BankFrame then return end
    if self:IsUsingOtherBankAddon() then return end
    
    self.bankFrameSuppressed = true
    
    -- Hide BankFrame (visual only - DON'T use :Hide(), it triggers BANKFRAME_CLOSED!)
    BankFrame:SetAlpha(0)
    BankFrame:EnableMouse(false)
    BankFrame:ClearAllPoints()
    BankFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10000, 10000)
    
    -- TWW FIX: Hide global BankPanel (this is what you actually see in TWW)
    if BankPanel then
        BankPanel:SetAlpha(0)
        BankPanel:EnableMouse(false)
        BankPanel:ClearAllPoints()
        BankPanel:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10000, 10000)
        
        -- Recursively hide all BankPanel children (visual only)
        local function HideAllChildren(frame)
            local children = { frame:GetChildren() }
            for _, child in ipairs(children) do
                if child then
                    pcall(function()
                        child:SetAlpha(0)
                        child:EnableMouse(false)
                        HideAllChildren(child)
                    end)
                end
            end
        end
        HideAllChildren(BankPanel)
    end
end

-- Suppress Guild Bank UI
function TheQuartermaster:SuppressGuildBankFrame()
    if not GuildBankFrame then return end
    if self:IsUsingOtherBankAddon() then return end
    
    self.guildBankFrameSuppressed = true
    
    -- Hide GuildBankFrame (visual only - DON'T use :Hide()!)
    GuildBankFrame:SetAlpha(0)
    GuildBankFrame:EnableMouse(false)
    GuildBankFrame:ClearAllPoints()
    GuildBankFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10000, 10000)
end

-- Restore Guild Bank UI
function TheQuartermaster:RestoreGuildBankFrame()
    if not GuildBankFrame then return end
    if self:IsUsingOtherBankAddon() then return end
    
    self.guildBankFrameSuppressed = false
    
    -- Restore GuildBankFrame
    GuildBankFrame:SetAlpha(1)
    GuildBankFrame:EnableMouse(true)
    GuildBankFrame:ClearAllPoints()
    GuildBankFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
    GuildBankFrame:Show()
    
    self:Print("Guild Bank UI restored")
end

-- Restore Blizzard Bank UI (show it again)
function TheQuartermaster:RestoreDefaultBankFrame()
    if not BankFrame then return end
    if self:IsUsingOtherBankAddon() then return end
    
    self.bankFrameSuppressed = false
    
    -- Restore BankFrame
    BankFrame:SetAlpha(1)
    BankFrame:EnableMouse(true)
    BankFrame:ClearAllPoints()
    BankFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
    BankFrame:Show()
    
    -- TWW FIX: Restore global BankPanel
    if BankPanel then
        BankPanel:SetAlpha(1)
        BankPanel:EnableMouse(true)
        BankPanel:Show()
        BankPanel:ClearAllPoints()
        BankPanel:SetPoint("TOPLEFT", BankFrame, "TOPLEFT", 0, 0)
        
        -- Recursively show all BankPanel children
        local function ShowAllChildren(frame)
            local children = { frame:GetChildren() }
            for _, child in ipairs(children) do
                if child then
                    pcall(function()
                        child:SetAlpha(1)
                        child:Show()
                        child:EnableMouse(true)
                        ShowAllChildren(child)
                    end)
                end
            end
        end
        ShowAllChildren(BankPanel)
    end
    
    self:Print("Blizzard Bank UI restored")
end

-- Show the default Blizzard bank frame (Classic Bank button)
function TheQuartermaster:ShowDefaultBankFrame()
    self:RestoreDefaultBankFrame()
    
    if OpenAllBags then
        OpenAllBags()
    end
end

function TheQuartermaster:OnBankClosed()
    self.bankIsOpen = false
    self.warbandBankIsOpen = false
    
    -- If user was using Classic Bank mode, hide bank again
    if self.classicBankMode then
        self.classicBankMode = false
        self:SuppressDefaultBankFrame()
    else
        -- Normal bank close (addon was already visible)
    -- Show warning if addon window is open
    if self:IsMainWindowShown() then
        -- Refresh title/status immediately
        if self.UpdateStatus then
             self:UpdateStatus()
        end
        -- View-only cache: avoid noisy chat spam when the bank frame closes.
        -- We still fall back to cached data silently.
    end
    
    -- Refresh UI if open (to update buttons/status)
    if self.RefreshUI then
        self:RefreshUI()
        end
    end
end

-- Guild Bank Opened Handler
function TheQuartermaster:OnGuildBankOpened()
    self.guildBankIsOpen = true
    self.currentBankType = "guild"
    
    -- Suppress Blizzard's Guild Bank frame if not using another addon
    if not self:IsUsingOtherBankAddon() then
        self:SuppressGuildBankFrame()
        
        -- Open main window to Guild Bank tab
        if self.ShowMainWindow then
            self:ShowMainWindow()
            -- Switch to Guild Bank tab (will be implemented in UI module)
            if self.SwitchBankTab then
                self:SwitchBankTab("guild")
            end
        end
    end
    
    -- Scan guild bank
    if self.db.profile.autoScan and self.ScanGuildBank then
        C_Timer.After(0.3, function()
            if TheQuartermaster and TheQuartermaster.ScanGuildBank then
                TheQuartermaster:ScanGuildBank()
            end
        end)
    end
    
    -- Refresh UI
    if self.RefreshUI then
        self:RefreshUI()
    end
end

-- Guild Bank Closed Handler
function TheQuartermaster:OnGuildBankClosed()
    self.guildBankIsOpen = false
    
    -- Show warning if addon window is open
    if self:IsMainWindowShown() then
        if self.UpdateStatus then
            self:UpdateStatus()
        end
        -- View-only cache: avoid noisy chat spam when the guild bank frame closes.
        -- We still fall back to cached data silently.
    end
    
    -- Refresh UI if open
    if self.RefreshUI then
        self:RefreshUI()
    end
end

-- Check if main window is visible
function TheQuartermaster:IsMainWindowShown()
    local UI = self.UI
    if UI and UI.mainFrame and UI.mainFrame:IsShown() then
        return true
    end
    -- Fallback check
    if TheQuartermasterMainFrame and TheQuartermasterMainFrame:IsShown() then
        return true
    end
    return false
end

-- Called when player or Warband Bank gold changes (PLAYER_MONEY, ACCOUNT_MONEY)
function TheQuartermaster:OnMoneyChanged()
    self.db.char.lastKnownGold = GetMoney()
    
    -- Update character gold in global tracking
    self:UpdateCharacterGold()
    
    -- INSTANT UI refresh if addon window is open
    if self.bankIsOpen and self.RefreshUI then
        -- Use very short delay to batch multiple money events
        if not self.moneyRefreshPending then
            self.moneyRefreshPending = true
            C_Timer.After(0.05, function()
                self.moneyRefreshPending = false
                if TheQuartermaster and TheQuartermaster.RefreshUI then
                    TheQuartermaster:RefreshUI()
                end
            end)
        end
    end
end

--[[
    Called when currency changes
]]
function TheQuartermaster:OnCurrencyChanged()
    -- Update currency data in background
    if self.UpdateCurrencyData then
        self:UpdateCurrencyData()
    end
    
    -- INSTANT UI refresh if currency tab is open
    local mainFrame = self.UI and self.UI.mainFrame
    if mainFrame and mainFrame.currentTab == "currency" and self.RefreshUI then
        -- Use short delay to batch multiple currency events
        if not self.currencyRefreshPending then
            self.currencyRefreshPending = true
            C_Timer.After(0.1, function()
                self.currencyRefreshPending = false
                if TheQuartermaster and TheQuartermaster.RefreshUI then
                    TheQuartermaster:RefreshUI()
                end
            end)
        end
    end
end

--[[
    Called when reputation changes
    Scan and update reputation data
]]
function TheQuartermaster:OnReputationChanged()
    -- Update guild rep (Guilds tab)
    if self.UpdateGuildData then
        self:UpdateGuildData()
    end

    -- Scan reputations in background
    if self.ScanReputations then
        self.currentTrigger = "UPDATE_FACTION"
        self:ScanReputations()
    end
    
    -- Send message for cache invalidation
    self:SendMessage("WARBAND_REPUTATIONS_UPDATED")
    
    -- INSTANT UI refresh if reputation tab is open
    local mainFrame = self.UI and self.UI.mainFrame
    if mainFrame and mainFrame.currentTab == "reputations" and self.RefreshUI then
        -- Use short delay to batch multiple reputation events
        if not self.reputationRefreshPending then
            self.reputationRefreshPending = true
            C_Timer.After(0.2, function()
                self.reputationRefreshPending = false
                if TheQuartermaster and TheQuartermaster.RefreshUI then
                    TheQuartermaster:RefreshUI()
                end
            end)
        end
    end
end


function TheQuartermaster:OnGuildChanged()
    if self.UpdateGuildData then
        self:UpdateGuildData()
    end

    -- Refresh instantly if Guilds tab is open
    local mainFrame = self.UI and self.UI.mainFrame
    if mainFrame and mainFrame.currentTab == "guild" and self.RefreshUI then
        if not self.guildRefreshPending then
            self.guildRefreshPending = true
            C_Timer.After(0.2, function()
                self.guildRefreshPending = false
                if TheQuartermaster and TheQuartermaster.RefreshUI then
                    TheQuartermaster:RefreshUI()
                end
            end)
        end
    end
end


--[[
    Called when M+ dungeon run completes
    Update PvE cache with new data
]]
function TheQuartermaster:CHALLENGE_MODE_COMPLETED(mapChallengeModeID, level, completionTime, onTime, keystoneUpgradeLevels)
    -- Re-collect PvE data for current character
    local pveData = self:CollectPvEData()
    
    -- Update cache
    local key = self:GetCharacterKey()
    if key and self.db and self.db.global and self.db.global.characters and self.db.global.characters[key] then
        self.db.global.characters[key].pve = pveData
        -- NOTE: "completionTime" is an event argument, so use the global time() here.
        self.db.global.characters[key].lastSeen = _G.time()
    end
    
    -- Refresh UI if PvE tab is visible
    if self.UI and self.UI.activeTab == "pve" then
        self:RefreshUI()
    end
end

--[[
    Return the saved-variable key for a character.
    This addon stores characters using the pattern: "Name-Realm".
]]
function TheQuartermaster:GetCharacterKey(unit)
    unit = unit or "player"

    local name = UnitName(unit)
    if not name or name == "" then
        return nil
    end

    -- Prefer normalized realm names when available (avoids spaces, connected realms formatting, etc.)
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
    if not realm or realm == "" then
        return nil
    end

    return name .. "-" .. realm
end

--[[
    Called when new weekly M+ record is set
    Update PvE cache with new data
]]
function TheQuartermaster:MYTHIC_PLUS_NEW_WEEKLY_RECORD()
    -- Same logic as CHALLENGE_MODE_COMPLETED
    self:CHALLENGE_MODE_COMPLETED()
end

--[[
    Called when an addon is loaded
    Check if it's a conflicting bank addon that user previously disabled
]]
function TheQuartermaster:OnAddonLoaded(event, addonName)
    if not self.db or not self.db.profile or not self.db.profile.bankConflictChoices then
        return
    end
    
    -- List of known conflicting addons
    local conflictingAddons = {
        "Bagnon", "Combuctor", "ArkInventory", "AdiBags", "Baganator",
        "LiteBag", "TBag", "BaudBag", "Inventorian",
        "ElvUI_Bags", "ElvUI",
        "BankStack", "BankItems", "Sorted",
        "BankUI", "InventoryManager", "BagAddon", "BankModifier",
        "CustomBank", "AdvancedInventory", "BagSystem"
    }
    
    -- Check if this is a conflicting addon
    local isConflicting = false
    for _, conflictAddon in ipairs(conflictingAddons) do
        if addonName == conflictAddon then
            isConflicting = true
            break
        end
    end
    
    if not isConflicting then
        return -- Not a conflicting addon
    end
    
    -- Check if user previously chose "useWarband" for this addon
    local previousChoice = self.db.profile.bankConflictChoices[addonName]
    
    if previousChoice == "useWarband" then
        -- User re-enabled an addon they previously disabled
        -- Reset choice and show popup after a delay
        
        -- Reset the choice so popup will show
        self.db.profile.bankConflictChoices[addonName] = nil
        
        -- Show conflict popup after brief delay (addon needs to fully initialize)
        C_Timer.After(2, function()
            if TheQuartermaster and TheQuartermaster.CheckBankConflictsOnLogin then
                -- CheckBankConflictsOnLogin has throttling, safe to call
                TheQuartermaster:CheckBankConflictsOnLogin()
            end
        end)
    end
end

--[[
    Called when player enters the world (login or reload)
]]
function TheQuartermaster:OnPlayerEnteringWorld(event, isInitialLogin, isReloadingUi)
    -- Scan player bags for Inventory view (view-only)
    if self.ScanInventory then
        C_Timer.After(2, function()
            if TheQuartermaster and TheQuartermaster.ScanInventory then
                TheQuartermaster:ScanInventory()
            end
        end)
    end
    -- Reset save flag on new login
    if isInitialLogin then
        self.characterSaved = false
    end

    -- Notifications: allow update/vault reminders after both login and /reload
    -- (Update notes still only show once per version via lastSeenVersion.)
    if (isInitialLogin or isReloadingUi) and self.CheckNotificationsOnLogin then
        self:CheckNotificationsOnLogin()
    end
    
    -- Scan reputations on login (after 3 seconds to ensure API is ready)
    C_Timer.After(3, function()
        if TheQuartermaster and TheQuartermaster.ScanReputations then
            TheQuartermaster.currentTrigger = "PLAYER_LOGIN"
            TheQuartermaster:ScanReputations()
        end
    end)
    
    -- Single save attempt after 2 seconds (enough for character data to load)
    C_Timer.After(2, function()
        if TheQuartermaster then
            TheQuartermaster:SaveCharacter()
        end
    end)

    -- Capture played time and current spec (for Characters tooltip)
    -- TIME_PLAYED_MSG is asynchronous, so we request it shortly after login/reload.
    C_Timer.After(2.5, function()
        if not TheQuartermaster then return end
        if RequestTimePlayed then
            RequestTimePlayed()
        end
        if TheQuartermaster.OnSpecializationChanged then
            TheQuartermaster:OnSpecializationChanged("PLAYER_SPECIALIZATION_CHANGED", "player")
        end
    end)
    
    -- CRITICAL: Secondary conflict check after longer delay
    -- This catches addons that load late (ElvUI modules, etc.)
    -- Runs BOTH on initial login AND reload to ensure nothing is missed
    if isInitialLogin or isReloadingUi then
        C_Timer.After(3, function()
            if TheQuartermaster and TheQuartermaster.CheckBankConflictsOnLogin then
                -- This is a safety net in case OnEnable check was too early
                TheQuartermaster:CheckBankConflictsOnLogin()
            end
        end)
        
        -- Extra check after 6 seconds for very late-loading addons
        C_Timer.After(6, function()
            if TheQuartermaster and TheQuartermaster.CheckBankConflictsOnLogin then
                -- Final safety check
                TheQuartermaster:CheckBankConflictsOnLogin()
            end
        end)
    end
end

--[[
    Called when player levels up
]]
function TheQuartermaster:OnPlayerLevelUp(event, level)
    -- Force update on level up
    self.characterSaved = false
    self:SaveCharacter()
end

-- XP / Rested XP updates (lightweight DB update + optional UI refresh)
function TheQuartermaster:OnPlayerXPChanged()
    if self.UpdateCurrentCharacterExperience then
        pcall(function()
            self:UpdateCurrentCharacterExperience()
        end)
    end

    -- Refresh UI if visible
    if TheQuartermasterMainFrame and TheQuartermasterMainFrame:IsShown() and self.RefreshUI then
        -- small delay to batch rapid XP ticks
        if not self.xpRefreshPending then
            self.xpRefreshPending = true
            C_Timer.After(0.15, function()
                self.xpRefreshPending = false
                if TheQuartermaster and TheQuartermaster.RefreshUI then
                    TheQuartermaster:RefreshUI()
                end
            end)
        end
    end
end


--[[
    Called when specialization changes (PLAYER_SPECIALIZATION_CHANGED)
    Updates specName for the current character (used by Characters tooltip)
]]
function TheQuartermaster:OnSpecializationChanged(event, unit)
    if unit and unit ~= "player" then
        return
    end

    local name = UnitName("player")
    local realm = GetRealmName()
    if not name or name == "" or not realm or realm == "" then
        return
    end

    local key = name .. "-" .. realm
    if not (self.db and self.db.global and self.db.global.characters and self.db.global.characters[key]) then
        return
    end

    local specName = nil
    if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        if specIndex then
            local _, sName = GetSpecializationInfo(specIndex)
            specName = sName
        end
    end

    if specName and specName ~= "" then
        self.db.global.characters[key].specName = specName
    end

    -- Keep the character showing as recently active
    self.db.global.characters[key].lastSeen = time()

    -- Refresh UI if open
    if self.InvalidateCharacterCache then
        self:InvalidateCharacterCache()
    end
    if self.RefreshUI then
        self:RefreshUI()
    end
end

--[[
    Called when TIME_PLAYED_MSG fires (RequestTimePlayed())
    Stores total played time (seconds) for the current character
]]
function TheQuartermaster:OnTimePlayedMsg(event, totalTime, levelTime)
    local name = UnitName("player")
    local realm = GetRealmName()
    if not name or name == "" or not realm or realm == "" then
        return
    end

    local key = name .. "-" .. realm
    if not (self.db and self.db.global and self.db.global.characters and self.db.global.characters[key]) then
        return
    end

    totalTime = tonumber(totalTime)
    if totalTime and totalTime > 0 then
        self.db.global.characters[key].playedTime = totalTime
        self.db.global.characters[key].lastSeen = time()

        if self.InvalidateCharacterCache then
            self:InvalidateCharacterCache()
        end
        if self.RefreshUI then
            self:RefreshUI()
        end
    end
end

--[[
    Called when combat starts (PLAYER_REGEN_DISABLED)
    Hides UI to prevent taint issues
]]
function TheQuartermaster:OnCombatStart()
    -- Hide main UI during combat (taint protection)
    if self.mainFrame and self.mainFrame:IsShown() then
        self.mainFrame:Hide()
        self._hiddenByCombat = true
        self:Print("|cffff6600UI hidden during combat.|r")
    end
end

--[[
    Called when combat ends (PLAYER_REGEN_ENABLED)
    Restores UI if it was hidden by combat
]]
function TheQuartermaster:OnCombatEnd()
    -- Restore UI after combat if it was hidden by combat
    if self._hiddenByCombat then
        if self.mainFrame then
            self.mainFrame:Show()
        end
        self._hiddenByCombat = false
    end

    -- If a reload was requested during combat (e.g. /tq resetrep), do it now
    if self._pendingReload then
        self._pendingReload = false
        C_Timer.After(0.1, function()
            if C_UI and C_UI.Reload then
                C_UI.Reload()
            else
                ReloadUI()
            end
        end)
        return
    end

end

--[[
    Called when PvE data changes (Great Vault, Lockouts, M+ completion)
]]
function TheQuartermaster:OnPvEDataChanged()
    -- Re-collect and update PvE data for current character
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    if self.db.global.characters and self.db.global.characters[key] then
        local pveData = self:CollectPvEData()
        self.db.global.characters[key].pve = pveData
        self.db.global.characters[key].lastSeen = time()
        
        -- Invalidate PvE cache for current character
        if self.InvalidatePvECache then
            self:InvalidatePvECache(key)
        end
        
        -- Refresh UI if PvE tab is open
        if self.RefreshPvEUI then
            self:RefreshPvEUI()
        end
    end
end

--[[
    Called when keystone might have changed (delayed bag update)
]]
function TheQuartermaster:OnKeystoneChanged()
    -- Throttle keystone checks to avoid spam
    if not self.keystoneCheckPending then
        self.keystoneCheckPending = true
        C_Timer.After(1, function()
            self.keystoneCheckPending = false
            if TheQuartermaster and TheQuartermaster.OnPvEDataChanged then
                TheQuartermaster:OnPvEDataChanged()
            end
        end)
    end
end

--[[
    Event handler for collection changes (mounts, pets, toys)
    Ultra-fast update with minimal throttle for instant UI feedback
]]
function TheQuartermaster:OnCollectionChanged(event)
    -- Minimal throttle only for TOYS_UPDATED (can fire frequently)
    -- NEW_* events are single-fire, no throttle needed
    local needsThrottle = (event == "TOYS_UPDATED")
    
    if needsThrottle and self.collectionCheckPending then
        return -- Skip if throttled
    end
    
    if needsThrottle then
        self.collectionCheckPending = true
        C_Timer.After(0.2, function()
            if TheQuartermaster then
                TheQuartermaster.collectionCheckPending = false
            end
        end)
    end
    
    -- Update character data
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    if self.db.global.characters and self.db.global.characters[key] then
        -- Update timestamp
        self.db.global.characters[key].lastSeen = time()
        
        -- Invalidate collection cache (data changed)
        if self.InvalidateCollectionCache then
            self:InvalidateCollectionCache()
        end
        
        -- INSTANT UI refresh if Statistics tab is active
        if self.UI and self.UI.mainFrame then
            local mainFrame = self.UI.mainFrame
            if mainFrame:IsShown() and mainFrame.currentTab == "stats" then
                if self.RefreshUI then
                    self:RefreshUI()
                end
            end
        end
    end
end

--[[
    Event handler for pet journal changes (cage/release)
    Smart tracking: Only update when pet count actually changes
]]
function TheQuartermaster:OnPetListChanged()
    -- Only process if UI is open on stats tab
    if not self.UI or not self.UI.mainFrame then return end
    
    local mainFrame = self.UI.mainFrame
    if not mainFrame:IsShown() or mainFrame.currentTab ~= "stats" then
        return -- Skip if UI not visible or wrong tab
    end
    
    -- Get current pet count
    local _, currentPetCount = C_PetJournal.GetNumPets()
    
    -- Initialize cache if needed
    if not self.lastPetCount then
        self.lastPetCount = currentPetCount
        return -- First call, just cache
    end
    
    -- Check if count actually changed
    if currentPetCount == self.lastPetCount then
        return -- No change, skip update
    end
    
    -- Count changed! Update cache
    self.lastPetCount = currentPetCount
    
    -- Throttle to batch rapid changes
    if self.petListCheckPending then return end
    
    self.petListCheckPending = true
    C_Timer.After(0.3, function()
        if not TheQuartermaster then return end
        TheQuartermaster.petListCheckPending = false
        
        -- Update timestamp
        local name = UnitName("player")
        local realm = GetRealmName()
        local key = name .. "-" .. realm
        
        if TheQuartermaster.db.global.characters and TheQuartermaster.db.global.characters[key] then
            TheQuartermaster.db.global.characters[key].lastSeen = time()
            
            -- Instant UI refresh
            if TheQuartermaster.RefreshUI then
                TheQuartermaster:RefreshUI()
            end
        end
    end)
end

-- SaveCurrentCharacterData() moved to Modules/DataService.lua


-- UpdateCharacterGold() moved to Modules/DataService.lua

-- CollectPvEData() moved to Modules/DataService.lua


-- GetAllCharacters() moved to Modules/DataService.lua

-- OnBagUpdate is used by both:
--  * RegisterBucketEvent("BAG_UPDATE", ...) which passes a table of bagIDs
--  * RegisterEvent("PLAYERBANKSLOTS_CHANGED" / "GUILDBANKBAGSLOTS_CHANGED") which passes the event name
--
-- AceBucket: bagIDs is a table with bagID keys.
-- Normal events: first arg is the event name, and no bagIDs table is provided.
function TheQuartermaster:OnBagUpdate(eventOrBagIDs, ...)

    local warbandUpdated = false
    local personalUpdated = false
    local inventoryUpdated = false
    local needsRescan = false

    if type(eventOrBagIDs) == "table" then
        -- BAG_UPDATE bucketed callback
        local bagIDs = eventOrBagIDs
        for bagID in pairs(bagIDs) do
            -- Check Warband bags
            if self:IsWarbandBag(bagID) then
                warbandUpdated = true
            end
            -- Check Personal bank bags (including main bank -1 and bags 6-12)
            if bagID == -1 or (bagID >= 6 and bagID <= 12) then
                personalUpdated = true
            end
            -- Check player inventory bags (0-5, includes reagent bag)
            if bagID >= 0 and bagID <= 5 then
                inventoryUpdated = true
            end
        end

        -- If inventory changed while bank is open, we need to re-scan banks too
        -- (item may have been moved from bank to inventory)
        needsRescan = inventoryUpdated or (self.bankIsOpen and (warbandUpdated or personalUpdated))

    elseif type(eventOrBagIDs) == "string" then
        -- Direct event callback (RegisterEvent)
        local event = eventOrBagIDs
        if event == "PLAYERBANKSLOTS_CHANGED" then
            personalUpdated = true
            needsRescan = true
        elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
            -- We treat guild bank similarly: refresh the cache if the UI is open.
            needsRescan = true
        else
            return
        end
    else
        return
    end
    
    -- Batch updates with a timer to avoid spam
    if needsRescan then
        if self.pendingScanTimer then
            self:CancelTimer(self.pendingScanTimer)
        end
        self.pendingScanTimer = self:ScheduleTimer(function()
            
            -- Keep Inventory cache current
            if inventoryUpdated and self.ScanInventory then
                self:ScanInventory()
                -- Ensure global character snapshot reflects latest inventory counts (tooltips use global cache)
                if self.SaveCurrentCharacterData then
                    self:SaveCurrentCharacterData()
                end
            end

            -- Re-scan both banks when any change occurs (items can move between them)
            if self.warbandBankIsOpen and self.ScanWarbandBank then
                self:ScanWarbandBank()
            end
            if self.bankIsOpen and self.ScanPersonalBank then
                self:ScanPersonalBank()
            end
            
            -- Invalidate item caches (data changed)
            if self.InvalidateItemCache then
                self:InvalidateItemCache()
            end
            
            -- Invalidate tooltip cache (items changed)
            if self.InvalidateTooltipCache then
                self:InvalidateTooltipCache()
            end
            
            -- Refresh UI
            if self.RefreshUI then
                self:RefreshUI()
            end
            
            
            self.pendingScanTimer = nil
        end, 0.5)
    end
end

--[[
    Utility Functions
]]

---Check if a bag ID is a Warband bank bag
---@param bagID number The bag ID to check
---@return boolean
-- Fast lookup table for Warband bag IDs (avoids ipairs loop on every BAG_UPDATE)
local WARBAND_BAG_SET = rawget(ns, "WARBAND_BAG_SET")
if not WARBAND_BAG_SET then
    WARBAND_BAG_SET = {}
    for _, id in ipairs(ns.WARBAND_BAGS or {}) do
        WARBAND_BAG_SET[id] = true
    end
    ns.WARBAND_BAG_SET = WARBAND_BAG_SET
end

function TheQuartermaster:IsWarbandBag(bagID)
    return WARBAND_BAG_SET[bagID] == true
end

---Check if Warband bank is currently open
---Uses event-based tracking combined with bag access verification
---@return boolean
function TheQuartermaster:IsWarbandBankOpen()
    -- Primary method: Use our tracked state from BANKFRAME events
    if self.warbandBankIsOpen then
        return true
    end
    
    -- Secondary method: If bank event flag is set, verify we can access Warband bags
    if self.bankIsOpen then
        local firstBagID = Enum.BagIndex.AccountBankTab_1
        if firstBagID then
            local numSlots = C_Container.GetContainerNumSlots(firstBagID)
            if numSlots and numSlots > 0 then
                -- We can access Warband bank, update flag
                self.warbandBankIsOpen = true
                return true
            end
        end
    end
    
    -- Fallback: Direct bag access check (in case events were missed)
    local firstBagID = Enum.BagIndex.AccountBankTab_1
    if firstBagID then
        local numSlots = C_Container.GetContainerNumSlots(firstBagID)
        -- In TWW, purchased Warband Bank tabs have 98 slots
        -- Only return true if we also see the bank is truly accessible
        if numSlots and numSlots > 0 then
            -- Try to verify by checking if BankFrame exists and is shown
            if BankFrame and BankFrame:IsShown() then
                self.warbandBankIsOpen = true
                self.bankIsOpen = true
                return true
            end
        end
    end
    
    return false
end

---Get the number of slots in a bag (with fallback)
---@param bagID number The bag ID
---@return number
function TheQuartermaster:GetBagSize(bagID)
    -- Use API wrapper for future-proofing
    return self:API_GetBagSize(bagID)
end

---Debug function (disabled for production)
---@param message string The message to print
function TheQuartermaster:Debug(message)
    if self.db and self.db.profile and self.db.profile.debugMode then
        self:Print("|cff888888[DEBUG]|r " .. tostring(message))
    end
end

---Get display name for an item (handles caged pets)
---Caged pets show "Pet Cage" in item name but have the real pet name in tooltip line 3
---@param itemID number The item ID
---@param itemName string The item name from cache
---@param classID number|nil The item class ID (17 = Battle Pet)
---@return string displayName The display name (pet name for caged pets, item name otherwise)
function TheQuartermaster:GetItemDisplayName(itemID, itemName, classID)
    -- If this is a caged pet (classID 17), try to get the pet name from tooltip
    if classID == 17 and itemID then
        local petName = self:GetPetNameFromTooltip(itemID)
        if petName then
            return petName
        end
    end
    
    -- Fallback: Use item name
    return itemName or "Unknown Item"
end

---Extract pet name from item tooltip (locale-independent)
---Used for caged pets where item name is "Pet Cage" but tooltip has the real pet name
---@param itemID number The item ID
---@return string|nil petName The pet's name extracted from tooltip
function TheQuartermaster:GetPetNameFromTooltip(itemID)
    if not itemID then
        return nil
    end
    
    -- METHOD 1: Try C_PetJournal API first (most reliable)
    if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
        local result = C_PetJournal.GetPetInfoByItemID(itemID)
        
        -- If result is a number, it's speciesID (old behavior)
        if type(result) == "number" and result > 0 then
            local speciesName = C_PetJournal.GetPetInfoBySpeciesID(result)
            if speciesName and speciesName ~= "" then
                return speciesName
            end
        end
        
        -- If result is a string, it's the pet name (TWW behavior)
        if type(result) == "string" and result ~= "" then
            return result
        end
    end
    
    -- METHOD 2: Tooltip parsing (fallback)
    if not C_TooltipInfo then
        return nil
    end
    
    local tooltipData = C_TooltipInfo.GetItemByID(itemID)
    if not tooltipData then
        return nil
    end
    
    -- METHOD 2A: CHECK battlePetName FIELD (TWW 11.0+ feature!)
    -- Surface args to expose all fields
    if TooltipUtil and TooltipUtil.SurfaceArgs then
        TooltipUtil.SurfaceArgs(tooltipData)
    end
    
    -- Check if battlePetName field exists (TWW API)
    if tooltipData.battlePetName and tooltipData.battlePetName ~= "" then
        return tooltipData.battlePetName
    end
    
    -- METHOD 2B: FALLBACK TO LINE PARSING
    if not tooltipData.lines then
        return nil
    end
    
    -- Caged pet tooltip structure (TWW):
    -- Line 1: Item name ("Pet Cage" / "BattlePet")
    -- Line 2: Category ("Battle Pet")
    -- Line 3: Pet's actual name OR empty OR quality/level
    -- Line 4+: Stats or "Use:" description
    
    -- Strategy: Find first line that:
    -- 1. Is NOT the item name
    -- 2. Is NOT "Battle Pet" or translations
    -- 3. Does NOT contain ":"
    -- 4. Is NOT quality/level info
    -- 5. Is a reasonable name length (3-35 chars)
    
    local knownBadPatterns = {
        "^Battle Pet",      -- Category (EN)
        "^BattlePet",       -- Item name
        "^Pet Cage",        -- Item name
        "^Kampfhaustier",   -- Category (DE)
        "^Mascotte",        -- Category (FR)
        "^Companion",       -- Old category
        "^Use:",            -- Description
        "^Requires:",       -- Requirement
        "Level %d",         -- Level info
        "^Poor",            -- Quality
        "^Common",          -- Quality
        "^Uncommon",        -- Quality
        "^Rare",            -- Quality
        "^Epic",            -- Quality
        "^Legendary",       -- Quality
        "^%d+$",            -- Just numbers
    }
    
    -- Parse tooltip lines for pet name
    for i = 1, math.min(#tooltipData.lines, 8) do
        local line = tooltipData.lines[i]
        if line and line.leftText then
            local text = line.leftText
            
            -- Clean color codes and formatting
            local cleanText = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|h", ""):gsub("|H", "")
            cleanText = cleanText:match("^%s*(.-)%s*$") or ""
            
            -- Check if this line is a valid pet name
            if #cleanText >= 3 and #cleanText <= 35 then
                local isBadLine = false
                
                -- Check against known bad patterns
                for _, pattern in ipairs(knownBadPatterns) do
                    if cleanText:match(pattern) then
                        isBadLine = true
                        break
                    end
                end
                
                -- Additional checks: contains ":" or starts with digit
                if not isBadLine then
                    if cleanText:match(":") or cleanText:match("^%d") then
                        isBadLine = true
                    end
                end
                
                if not isBadLine then
                    return cleanText
                end
            end
        end
    end

    return nil
end

--[[
    Placeholder functions for modules
    These will be implemented in their respective module files
]]

function TheQuartermaster:ScanWarbandBank()
    -- Implemented in Modules/Scanner.lua
end

function TheQuartermaster:ToggleMainWindow()
    -- Implemented in Modules/UI.lua
end

function TheQuartermaster:OpenDepositQueue()
    -- Implemented in Modules/Banker.lua
end

function TheQuartermaster:SearchItems(searchTerm)
    -- Implemented in Modules/UI.lua
end

function TheQuartermaster:RefreshUI()
    -- Implemented in Modules/UI.lua
end

function TheQuartermaster:RefreshPvEUI()
    -- Force refresh of PvE tab if currently visible (instant)
    if self.UI and self.UI.mainFrame then
        local mainFrame = self.UI.mainFrame
        if mainFrame:IsShown() and mainFrame.currentTab == "pve" then
            -- Instant refresh for responsive UI
            if self.RefreshUI then
                self:RefreshUI()
            end
        end
    end
end

function TheQuartermaster:OpenOptions()
    -- Delegate to Config.lua implementation when available.
    if self and self.optionsFrame and self.OpenOptions then
        -- This method will be replaced by Config.lua at load time; keep as safe fallback.
    end
    if Settings and Settings.OpenToCategory and self.optionsCategoryID and type(self.optionsCategoryID)=="number" then
        Settings.OpenToCategory(self.optionsCategoryID)
        return
    end
end

---Print bank debug information to help diagnose detection issues
function TheQuartermaster:PrintBankDebugInfo()
    self:Print("=== Bank Debug Info ===")
    
    -- Internal state flags
    self:Print("Internal Flags:")
    self:Print("  self.bankIsOpen: " .. tostring(self.bankIsOpen))
    self:Print("  self.warbandBankIsOpen: " .. tostring(self.warbandBankIsOpen))
    
    -- BankFrame check
    self:Print("BankFrame:")
    self:Print("  exists: " .. tostring(BankFrame ~= nil))
    if BankFrame then
        self:Print("  IsShown: " .. tostring(BankFrame:IsShown()))
    end
    
    -- Bag slot check (most reliable)
    self:Print("Warband Bank Bags:")
    for i = 1, 5 do
        local bagID = Enum.BagIndex["AccountBankTab_" .. i]
        if bagID then
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            local itemCount = 0
            if numSlots and numSlots > 0 then
                for slot = 1, numSlots do
                    local info = C_Container.GetContainerItemInfo(bagID, slot)
                    if info and info.itemID then
                        itemCount = itemCount + 1
                    end
                end
            end
            self:Print("  Tab " .. i .. ": BagID=" .. bagID .. ", Slots=" .. tostring(numSlots) .. ", Items=" .. itemCount)
        end
    end
    
    -- Final result
    self:Print("IsWarbandBankOpen(): " .. tostring(self:IsWarbandBankOpen()))
    self:Print("======================")
end

---Force scan without checking if bank is open (for debugging)
function TheQuartermaster:ForceScanWarbandBank()
    self:Print("Force scanning Warband Bank (bypassing open check)...")
    
    -- Temporarily mark bank as open for scan
    local wasOpen = self.bankIsOpen
    self.bankIsOpen = true
    
    -- Use the existing Scanner module
    local success = self:ScanWarbandBank()
    
    -- Restore original state
    self.bankIsOpen = wasOpen
    
    if success then
        self:Print("Force scan complete!")
    else
        self:Print("|cffff0000Force scan failed. Bank might not be accessible.|r")
    end
end

--[[
    Wipe all addon data and reload UI
    This is a destructive operation that cannot be undone
]]
function TheQuartermaster:WipeAllData()
    self:Print("|cffff9900Wiping all addon data...|r")
    
    -- Close UI first
    if self.HideMainWindow then
        self:HideMainWindow()
    end
    
    -- Clear all caches
    if self.ClearAllCaches then
        self:ClearAllCaches()
    end
    
    -- Reset the entire database
    if self.db then
        self.db:ResetDB(true)
    end
    
    self:Print("|cff00ff00All data wiped! Reloading UI...|r")
    
    -- Reload UI after a short delay
    C_Timer.After(1, function()
        if C_UI and C_UI.Reload then
            C_UI.Reload()
        else
            ReloadUI()
        end
    end)
end

function TheQuartermaster:InitializeConfig()
    -- Implemented in Config.lua
end

--[[
    Print current character's PvE data for debugging
]]
function TheQuartermaster:PrintPvEData()
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    self:Print("=== PvE Data for " .. name .. " ===")
    
    local pveData = self:CollectPvEData()
    
    -- Great Vault
    self:Print("|cffffd700Great Vault:|r")
    if pveData.greatVault and #pveData.greatVault > 0 then
        for i, activity in ipairs(pveData.greatVault) do
            local typeName = "Unknown"
            local typeNum = activity.type
            
            -- Try Enum first, fallback to numbers
            if Enum and Enum.WeeklyRewardChestThresholdType then
                if typeNum == Enum.WeeklyRewardChestThresholdType.Raid then typeName = "Raid"
                elseif typeNum == Enum.WeeklyRewardChestThresholdType.Activities then typeName = "M+"
                elseif typeNum == Enum.WeeklyRewardChestThresholdType.RankedPvP then typeName = "PvP"
                elseif typeNum == Enum.WeeklyRewardChestThresholdType.World then typeName = "World"
                end
            else
                -- Fallback to numeric values
                if typeNum == 1 then typeName = "Raid"
                elseif typeNum == 2 then typeName = "M+"
                elseif typeNum == 3 then typeName = "PvP"
                elseif typeNum == 4 then typeName = "World"
                end
            end
            
            self:Print(string.format("  %s (type=%d) [%d]: %d/%d (Level %d)", 
                typeName, typeNum, activity.index or 0, 
                activity.progress or 0, activity.threshold or 0,
                activity.level or 0))
        end
    else
        self:Print("  No vault data available")
    end
    
    -- Mythic+
    self:Print("|cffa335eeM+ Keystone:|r")
    if pveData.mythicPlus and pveData.mythicPlus.keystone then
        local ks = pveData.mythicPlus.keystone
        self:Print(string.format("  %s +%d", ks.name or "Unknown", ks.level or 0))
    else
        self:Print("  No keystone")
    end
    if pveData.mythicPlus then
        if pveData.mythicPlus.weeklyBest then
            self:Print(string.format("  Weekly Best: +%d", pveData.mythicPlus.weeklyBest))
        end
        if pveData.mythicPlus.runsThisWeek then
            self:Print(string.format("  Runs This Week: %d", pveData.mythicPlus.runsThisWeek))
        end
    end
    
    -- Lockouts
    self:Print("|cff0070ddRaid Lockouts:|r")
    if pveData.lockouts and #pveData.lockouts > 0 then
        for i, lockout in ipairs(pveData.lockouts) do
            self:Print(string.format("  %s (%s): %d/%d", 
                lockout.name or "Unknown",
                lockout.difficultyName or "Normal",
                lockout.progress or 0,
                lockout.total or 0))
        end
    else
        self:Print("  No active lockouts")
    end
    
    self:Print("===========================")
    
    -- Save the data
    if self.db.global.characters and self.db.global.characters[key] then
        self.db.global.characters[key].pve = pveData
        self.db.global.characters[key].lastSeen = time()
        self:Print("|cff00ff00Data saved! Use /tq pve to view in UI|r")
    end
end

--[[============================================================================
    FAVORITE CHARACTERS MANAGEMENT
============================================================================]]

---Check if a character is favorited
---@param characterKey string Character key ("Name-Realm")
---@return boolean
function TheQuartermaster:IsFavoriteCharacter(characterKey)
    if not self.db or not self.db.global or not self.db.global.favoriteCharacters then
        return false
    end
    
    for _, favKey in ipairs(self.db.global.favoriteCharacters) do
        if favKey == characterKey then
            return true
                    end
                end
    
    return false
    end
    
---Toggle favorite status for a character
---@param characterKey string Character key ("Name-Realm")
---@return boolean New favorite status
function TheQuartermaster:ToggleFavoriteCharacter(characterKey)
    if not self.db or not self.db.global then
        return false
    end
    
    -- Initialize if needed
    if not self.db.global.favoriteCharacters then
        self.db.global.favoriteCharacters = {}
    end
    
    local favorites = self.db.global.favoriteCharacters
    local isFavorite = self:IsFavoriteCharacter(characterKey)
    
    if isFavorite then
        -- Remove from favorites
        for i, favKey in ipairs(favorites) do
            if favKey == characterKey then
                table.remove(favorites, i)
                self:Print("|cffffff00Removed from favorites:|r " .. characterKey)
                                break
                            end
                        end
        return false
    else
        -- Add to favorites
        table.insert(favorites, characterKey)
        self:Print("|cffffd700Added to favorites:|r " .. characterKey)
        return true
        end
    end
    
---Get all favorite characters
---@return table Array of favorite character keys
function TheQuartermaster:GetFavoriteCharacters()
    if not self.db or not self.db.global or not self.db.global.favoriteCharacters then
        return {}
    end
    
    return self.db.global.favoriteCharacters
end

-- PerformItemSearch() moved to Modules/DataService.lua



