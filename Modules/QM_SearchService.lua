--[[
    The Quartermaster - Search Service
    Provides Global Search + Watchlist aggregation helpers.
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

local function SafeLower(s)
    if not s then return "" end
    return tostring(s):lower()
end

-- Lightweight tooltip scan to detect the "<Expansion> Crafting Reagent" line.
-- We use this for Watchlist migration and classification when item class/subtype is unreliable.
local QM_SearchServiceScanTooltip
local function QM_EnsureSearchServiceTooltip()
    if QM_SearchServiceScanTooltip then return end
    QM_SearchServiceScanTooltip = CreateFrame("GameTooltip", "QM_SearchServiceScanTooltip", UIParent, "GameTooltipTemplate")
    QM_SearchServiceScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
end

local function QM_HasCraftingReagentLine(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end
    QM_EnsureSearchServiceTooltip()
    QM_SearchServiceScanTooltip:ClearLines()
    local ok = pcall(function()
        QM_SearchServiceScanTooltip:SetHyperlink("item:" .. itemID)
    end)
    if not ok then return false end

    local numLines = QM_SearchServiceScanTooltip:NumLines() or 0
    for i = 2, numLines do
        local left = _G["QM_SearchServiceScanTooltipTextLeft" .. i]
        local text = left and left:GetText()
        if text and text:find("Crafting Reagent", 1, true) then
            return true
        end
    end
    return false
end

local function GetProfileWatchlist(self)
    if not self.db or not self.db.profile then return nil end
    if not self.db.profile.watchlist then
        self.db.profile.watchlist = { items = {}, reagents = {}, currencies = {}, includeGuildBank = true }
    end
    self.db.profile.watchlist.items = self.db.profile.watchlist.items or {}
    self.db.profile.watchlist.reagents = self.db.profile.watchlist.reagents or {}
    self.db.profile.watchlist.currencies = self.db.profile.watchlist.currencies or {}
    if self.db.profile.watchlist.includeGuildBank == nil then
        self.db.profile.watchlist.includeGuildBank = true
    end

    -- Migration: if any pinned items look like reagents, move them into the reagent list.
    -- This removes reliance on per-frame reagent detection and fixes "pinned reagents show under Items".
    if self.db.profile.watchlist.items then
        local movedAny = false
        for itemID in pairs(self.db.profile.watchlist.items) do
            if type(itemID) == "number" then
                local isReagent = QM_HasCraftingReagentLine(itemID)
                if not isReagent and C_Item and C_Item.GetItemInfoInstant then
                    local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(itemID)
                    if not (equipLoc and equipLoc ~= "") then
                        local TRADE = Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods
                        local GEM   = Enum and Enum.ItemClass and Enum.ItemClass.Gem
                        if classID == TRADE or classID == GEM then
                            isReagent = true
                        end
                    end
                end

                if isReagent then
                    self.db.profile.watchlist.reagents[itemID] = self.db.profile.watchlist.reagents[itemID] or {}
                    self.db.profile.watchlist.items[itemID] = nil
                    movedAny = true
                end
            end
        end
        if movedAny then
            -- no-op; kept for readability
        end
    end
    return self.db.profile.watchlist
end

function TheQuartermaster:IsWatchlistedItem(itemID)
    local wl = GetProfileWatchlist(self)
    return wl and wl.items and wl.items[tonumber(itemID)] == true
end

function TheQuartermaster:IsWatchlistedReagent(itemID)
    local wl = GetProfileWatchlist(self)
    itemID = tonumber(itemID)
    return wl and wl.reagents and wl.reagents[itemID] ~= nil
end

function TheQuartermaster:IsWatchlistedCurrency(currencyID)
    local wl = GetProfileWatchlist(self)
    return wl and wl.currencies and wl.currencies[tonumber(currencyID)] == true
end

function TheQuartermaster:ToggleWatchlistItem(itemID)
    local wl = GetProfileWatchlist(self)
    itemID = tonumber(itemID)
    if not wl or not itemID then return end

    -- Ensure this item isn't also tracked as a reagent
    if wl.reagents and wl.reagents[itemID] then
        wl.reagents[itemID] = nil
    end
    wl.items[itemID] = not wl.items[itemID]
    if wl.items[itemID] == false then wl.items[itemID] = nil end
    if self.RefreshUI then self:RefreshUI() end
end

-- Reagent watchlist entries can store a desired target count.
-- opts.mode: "toggle" (default) or "ensure" to always keep pinned.
-- opts.targetDelta: number to add to current target (accumulative)
-- opts.targetSet: number to set target explicitly (absolute)
function TheQuartermaster:ToggleWatchlistReagent(itemID, opts)
    opts = opts or {}
    local wl = GetProfileWatchlist(self)
    itemID = tonumber(itemID)
    if not wl or not itemID then return end
    wl.reagents = wl.reagents or {}

    -- Remove from generic items list if present
    if wl.items and wl.items[itemID] then
        wl.items[itemID] = nil
    end

    local entry = wl.reagents[itemID]
    local shouldToggle = (opts.mode ~= "ensure")

    if shouldToggle then
        if entry then
            wl.reagents[itemID] = nil
            if self.RefreshUI then self:RefreshUI() end
            return
        else
            entry = {}
            wl.reagents[itemID] = entry
        end
    else
        if not entry then
            entry = {}
            wl.reagents[itemID] = entry
        end
    end

    if type(opts.targetSet) == "number" then
        entry.target = math.max(0, math.floor(opts.targetSet + 0.5))
    elseif type(opts.targetDelta) == "number" then
        local cur = tonumber(entry.target) or 0
        entry.target = math.max(0, math.floor(cur + opts.targetDelta + 0.5))
    end

    if self.RefreshUI then self:RefreshUI() end
end

function TheQuartermaster:GetWatchlistReagentTarget(itemID)
    local wl = GetProfileWatchlist(self)
    itemID = tonumber(itemID)
    if not wl or not wl.reagents or not itemID then return nil end
    local entry = wl.reagents[itemID]
    return entry and entry.target
end

function TheQuartermaster:SetWatchlistReagentTarget(itemID, target)
    itemID = tonumber(itemID)
    target = tonumber(target)
    if not itemID then return end
    if not target or target < 0 then target = 0 end
    self:ToggleWatchlistReagent(itemID, { mode = "ensure", targetSet = target })
end

function TheQuartermaster:ToggleWatchlistCurrency(currencyID)
    local wl = GetProfileWatchlist(self)
    currencyID = tonumber(currencyID)
    if not wl or not currencyID then return end
    wl.currencies[currencyID] = not wl.currencies[currencyID]
    if wl.currencies[currencyID] == false then wl.currencies[currencyID] = nil end
    if self.RefreshUI then self:RefreshUI() end
end

-- Counts item occurrences across cache (bags, personal bank, warband bank, optional guild bank)
function TheQuartermaster:CountItemTotals(itemID, includeGuildBank)
    itemID = tonumber(itemID)
    if not itemID then return 0, {} end

    local total = 0
    local breakdown = {} -- [label]=count

    local function Add(label, n)
        if not n or n <= 0 then return end
        total = total + n
        breakdown[label] = (breakdown[label] or 0) + n
    end

    -- Warband bank
    if self.db and self.db.global and self.db.global.warbandBank and self.db.global.warbandBank.items then
        for _, bagData in pairs(self.db.global.warbandBank.items) do
            for _, item in pairs(bagData) do
                if item and item.itemID == itemID then
                    Add("Warband Bank", item.stackCount or 1)
                end
            end
        end
    end

    -- Characters (bags + personal bank)
    if self.db and self.db.global and self.db.global.characters then
        for _, charData in pairs(self.db.global.characters) do
            local charLabel = (charData.name or "Unknown") .. " (" .. (charData.realm or "Unknown") .. ")"

            if charData.inventory and charData.inventory.items then
                local count = 0
                for _, bagData in pairs(charData.inventory.items) do
                    for _, item in pairs(bagData) do
                        if item and item.itemID == itemID then
                            count = count + (item.stackCount or 1)
                        end
                    end
                end
                Add(charLabel .. " - Bags", count)
            end

            if charData.personalBank then
                local count = 0
                for _, bagData in pairs(charData.personalBank) do
                    for _, item in pairs(bagData) do
                        if item and item.itemID == itemID then
                            count = count + (item.stackCount or 1)
                        end
                    end
                end
                Add(charLabel .. " - Bank", count)
            end
        end
    end

    -- Guild bank
    if includeGuildBank and self.db and self.db.global and self.db.global.guildBank then
        for guildName, guildData in pairs(self.db.global.guildBank) do
            if guildData and guildData.tabs then
                local guildCount = 0
                for _, tab in pairs(guildData.tabs) do
                    if tab and tab.items then
                        for _, item in pairs(tab.items) do
                            if item and item.itemID == itemID then
                                guildCount = guildCount + (item.count or item.stackCount or 1)
                            end
                        end
                    end
                end
                Add("Guild Bank - " .. guildName, guildCount)
            end
        end
    end

    return total, breakdown
end

function TheQuartermaster:CountCurrencyTotals(currencyID)
    currencyID = tonumber(currencyID)
    if not currencyID then return 0, {} end

    local total = 0
    local breakdown = {}
    local characters = self.GetAllCharacters and self:GetAllCharacters() or {}

    for _, char in ipairs(characters) do
        if char.currencies and char.currencies[currencyID] then
            local cur = char.currencies[currencyID]
            local qty = tonumber(cur.quantity or cur.count or 0) or 0
            total = total + qty
            local label = (char.name or "Unknown") .. " (" .. (char.realm or "Unknown") .. ")"
            breakdown[label] = qty
        end
    end

    return total, breakdown
end


-- Strict reagent check for filtering (prevents gear/non-mats from showing in Materials/Reagents modes)
local ITEM_CLASS_TRADEGOODS = Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods or 7
local ITEM_CLASS_GEM       = Enum and Enum.ItemClass and Enum.ItemClass.Gem or 3
local ITEM_CLASS_REAGENT   = Enum and Enum.ItemClass and Enum.ItemClass.Reagent or nil

-- Tooltip scanner (used to confirm Crafting Reagent label and derive expansion tag).
local QM_ReagentScanTooltip
local function QM_EnsureReagentTooltip()
    if QM_ReagentScanTooltip then return end
    QM_ReagentScanTooltip = CreateFrame("GameTooltip", "QM_ReagentScanTooltip", UIParent, "GameTooltipTemplate")
    QM_ReagentScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
end

local function QM_GetCraftingReagentLabel(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    QM_EnsureReagentTooltip()

    QM_ReagentScanTooltip:ClearLines()
    local ok = pcall(function()
        QM_ReagentScanTooltip:SetHyperlink("item:" .. itemID)
    end)
    if not ok then
        return nil
    end

    local numLines = QM_ReagentScanTooltip:NumLines() or 0
    for i = 2, numLines do
        local left = _G["QM_ReagentScanTooltipTextLeft" .. i]
        local text = left and left:GetText()
        if text and text:find("Crafting Reagent", 1, true) then
            return text
        end
    end
    return nil
end

local function QM_HasCraftingReagentLine(itemID)
    return QM_GetCraftingReagentLabel(itemID) ~= nil
end

local function QM_IsReagentItemID(item)
    if not item or not item.itemID then return false end

    -- Exclude equippables
    if item.equipLoc and item.equipLoc ~= "" then return false end

    local classID = item.classID
    if not classID and C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, equipLoc, _, cID = C_Item.GetItemInfoInstant(item.itemID)
        if equipLoc and equipLoc ~= "" then return false end
        classID = cID
    end

    -- If the tooltip explicitly says "Crafting Reagent", treat it as a reagent even if classID is odd.
    if QM_HasCraftingReagentLine(item.itemID) then
        return true
    end

    if not classID then return false end
    if classID == ITEM_CLASS_TRADEGOODS or classID == ITEM_CLASS_GEM or classID == ITEM_CLASS_REAGENT then
        return true
    end
    return false
end

function TheQuartermaster:PerformGlobalSearch(searchText, mode, includeGuildBank)
    local text = tostring(searchText or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return { items = {}, currencies = {} }
    end

    mode = mode or "all"
    if includeGuildBank == nil then
        local wl = GetProfileWatchlist(self)
        includeGuildBank = wl and wl.includeGuildBank or true
    end

    local out = { items = {}, currencies = {} }

    if mode == "all" or mode == "items" or mode == "reagents" then
        local itemResults = (self.PerformItemSearch and self:PerformItemSearch(text)) or {}
        if not includeGuildBank then
            local filtered = {}
            for _, r in ipairs(itemResults) do
                if r.location ~= "Guild Bank" then
                    table.insert(filtered, r)
                end
            end
            itemResults = filtered
        end
        if mode == "reagents" then
            local filtered = {}
            for _, r in ipairs(itemResults) do
                if r and r.item and QM_IsReagentItemID(r.item) then
                    table.insert(filtered, r)
                end
            end
            itemResults = filtered
        end
        out.items = itemResults
    end

    if mode == "all" or mode == "currency" then
        local currencyResults = (self.PerformCurrencySearch and self:PerformCurrencySearch(text)) or {}
        out.currencies = currencyResults
    end

    return out
end