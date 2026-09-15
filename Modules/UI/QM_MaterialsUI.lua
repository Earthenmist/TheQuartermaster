--[[
    The Quartermaster - Materials (Reagents) View
    v1.0.14
    Notes:
      - Profession-focused category filter (no noisy subtypes).
      - Right-click row menu matches Items/Storage style.
      - Reagent detection is strict to avoid gear/non-mats.
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster
local L = ns.L

local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren

-- Context menu utility (works on modern + classic dropdown APIs)
local QM_OpenRowMenu_DROPDOWN
local function QM_OpenRowMenu(menu, anchor)
    if not menu or #menu == 0 then return end

    -- Modern menu API
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(anchor or UIParent, function(_, rootDescription)
            for _, entry in ipairs(menu) do
                rootDescription:CreateButton(entry.text, entry.func)
            end
        end)
        return
    end

    -- Legacy dropdown API fallback
    if not QM_OpenRowMenu_DROPDOWN then
        QM_OpenRowMenu_DROPDOWN = CreateFrame("Frame", "QM_MaterialsContextMenuDrop", UIParent, "UIDropDownMenuTemplate")
    end

    if UIDropDownMenu_Initialize and ToggleDropDownMenu and UIDropDownMenu_CreateInfo then
        UIDropDownMenu_Initialize(QM_OpenRowMenu_DROPDOWN, function(self, level)
            local info = UIDropDownMenu_CreateInfo()
            for _, entry in ipairs(menu) do
                info.text = entry.text
                info.func = entry.func
                info.notCheckable = true
                UIDropDownMenu_AddButton(info, level)
            end
        end, "MENU")
        ToggleDropDownMenu(1, nil, QM_OpenRowMenu_DROPDOWN, "cursor", 0, 0)
    end
end

local function QM_CopyItemLinkToChat(itemLink)
    if not itemLink then return end
    if ChatFrame_OpenChat then
        ChatFrame_OpenChat(itemLink)
    else
        local editBox = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
        if editBox then
            editBox:Insert(itemLink)
        end
    end
end

-- ============================================================================
-- Reagent detection & profession categories
-- ============================================================================

local ITEM_CLASS_TRADEGOODS = Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods or 7
local ITEM_CLASS_GEM       = Enum and Enum.ItemClass and Enum.ItemClass.Gem or 3
local ITEM_CLASS_REAGENT   = Enum and Enum.ItemClass and Enum.ItemClass.Reagent or nil

-- Tooltip scanner (used to confirm "Crafting Reagent" and derive expansion tags).
local QM_MaterialsScanTooltip
local function QM_EnsureMaterialsTooltip()
    if QM_MaterialsScanTooltip then return end
    QM_MaterialsScanTooltip = CreateFrame("GameTooltip", "QM_MaterialsScanTooltip", UIParent, "GameTooltipTemplate")
    QM_MaterialsScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
end

local function QM_GetCraftingReagentLabel(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    QM_EnsureMaterialsTooltip()

    QM_MaterialsScanTooltip:ClearLines()
    local ok = pcall(function()
        QM_MaterialsScanTooltip:SetHyperlink("item:" .. itemID)
    end)
    if not ok then return nil end

    local numLines = QM_MaterialsScanTooltip:NumLines() or 0
    for i = 2, numLines do
        local left = _G["QM_MaterialsScanTooltipTextLeft" .. i]
        local text = left and left:GetText()
        if text and text:find("Crafting Reagent", 1, true) then
            return text
        end
    end
    return nil
end

local function QM_GetExpansionTagFromLabel(label)
    if not label then return nil end
    local tag = label:gsub("%s+Crafting Reagent.*$", "")
    tag = tag:gsub("^%s+", ""):gsub("%s+$", "")
    if tag == "" or tag == label then return nil end
    return tag
end

local function QM_QueueMaterialsRefresh()
    if ns._materialsRefreshQueued then return end
    ns._materialsRefreshQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.20, function()
            ns._materialsRefreshQueued = nil
            if TheQuartermaster and TheQuartermaster.PopulateContent then
                TheQuartermaster:PopulateContent()
            end
        end)
    else
        ns._materialsRefreshQueued = nil
        if TheQuartermaster and TheQuartermaster.PopulateContent then
            TheQuartermaster:PopulateContent()
        end
    end
end

local function QM_EnsureMaterialsItemDataListener()
    if ns._materialsItemDataListener then return end

    local f = CreateFrame("Frame")
    ns._materialsItemDataListener = f

    local function HandleItemLoaded(itemID, success)
        itemID = tonumber(itemID)
        if not itemID then return end
        if ns.materialsPendingItemData and ns.materialsPendingItemData[itemID] then
            ns.materialsPendingItemData[itemID] = nil
            -- Clear cached tag (forces a re-scan on next filter pass)
            if ns.materialsExpansionTagCache then
                ns.materialsExpansionTagCache[itemID] = nil
            end
            QM_QueueMaterialsRefresh()
        end
    end

    f:SetScript("OnEvent", function(_, event, ...)
        if event == "ITEM_DATA_LOAD_RESULT" then
            local itemID, success = ...
            HandleItemLoaded(itemID, success)
        elseif event == "GET_ITEM_INFO_RECEIVED" then
            local itemID, success = ...
            HandleItemLoaded(itemID, success)
        end
    end)

    if f.RegisterEvent then
        if C_Item and C_Item.RequestLoadItemDataByID then
            f:RegisterEvent("ITEM_DATA_LOAD_RESULT")
        end
        -- Fallback for older clients / edge cases
        f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    end
end

local function QM_GetReagentExpansionTag(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end

    ns.materialsExpansionTagCache = ns.materialsExpansionTagCache or {}
    local cache = ns.materialsExpansionTagCache

    if cache[itemID] then
        return cache[itemID]
    end

    -- Ensure item data is cached before tooltip scans; otherwise request load and refresh later.
    if C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
        if C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
        ns.materialsPendingItemData = ns.materialsPendingItemData or {}
        ns.materialsPendingItemData[itemID] = true
        QM_EnsureMaterialsItemDataListener()
        return nil
    end

    -- Item metadata is locale-independent and also covers reagents without a tagged tooltip.
    local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    if getInfo then
        local result = {pcall(getInfo, itemID)}
        local expansion = result[16] -- fifteenth GetItemInfo return, after pcall status
        if result[1] and not (issecretvalue and issecretvalue(expansion)) then
            local tags = {[0] = "Classic", [1] = "Outland", [2] = "Northrend", [3] = "Cataclysm", [4] = "Pandaria", [5] = "Draenor", [6] = "Broken Isles", [7] = "Battle for Azeroth", [8] = "Shadowlands", [9] = "Dragon Isles", [10] = "Khaz Algar", [11] = "Midnight"}
            local tag = tags[expansion]
            if tag then cache[itemID] = tag; return tag end
        elseif not result[1] or (issecretvalue and issecretvalue(expansion)) then
            return nil
        end
    end

    local tag = QM_GetExpansionTagFromLabel(QM_GetCraftingReagentLabel(itemID))
    if tag and tag ~= "" then
        cache[itemID] = tag
        return tag
    end

    return nil
end

local function QM_HasCraftingReagentLine(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end

    ns.materialsReagentLineCache = ns.materialsReagentLineCache or {}
    local cache = ns.materialsReagentLineCache

    if cache[itemID] ~= nil then
        return cache[itemID]
    end

    -- If item data isn't ready yet, DO NOT exclude it from the list.
    -- Request data, mark pending, and allow it to display; we'll refine once info is cached.
    if C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
        if C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
        ns.materialsPendingItemData = ns.materialsPendingItemData or {}
        ns.materialsPendingItemData[itemID] = true
        QM_EnsureMaterialsItemDataListener()
        return true
    end

    -- Fast-path: class-based detection without tooltip scans.
    local classID
    if C_Item and C_Item.GetItemInfoInstant then
        classID = select(6, C_Item.GetItemInfoInstant(itemID))
    end
    if not classID then
        classID = select(12, GetItemInfo(itemID))
    end

    local TRADEGOODS = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or 7
    local GEM        = (Enum and Enum.ItemClass and Enum.ItemClass.Gem)        or 3
    local REAGENT    = (Enum and Enum.ItemClass and Enum.ItemClass.Reagent)    or nil

    if classID == TRADEGOODS or classID == GEM or (REAGENT and classID == REAGENT) then
        cache[itemID] = true
        return true
    end

    -- Slow path: tooltip tag scan (cached).
    cache[itemID] = (QM_GetCraftingReagentLabel(itemID) ~= nil)
    return cache[itemID]
end
-- Some reagents are ambiguous (multi-profession). As a best-effort, infer a primary
-- profession from tooltip wording (e.g. "alchemy"), with a sensible priority.
local PROF_KEYWORDS = {
    { key = "alchemy",        patterns = { "alchemy" } },
    { key = "enchanting",     patterns = { "enchant" } },
    { key = "engineering",    patterns = { "engineering", "engineer" } },
    { key = "inscription",    patterns = { "inscription", "scribe" } },
    { key = "jewelcrafting",  patterns = { "jewelcraft", "jewel" } },
    { key = "leatherworking", patterns = { "leatherworking", "skinning" } },
    { key = "tailoring",      patterns = { "tailoring" } },
    { key = "blacksmithing",  patterns = { "blacksmith" } },
    { key = "cooking",        patterns = { "cooking" } },
}

local function QM_GetPrimaryProfessionFromTooltip(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end

    ns.materialsPrimaryProfCache = ns.materialsPrimaryProfCache or {}
    local cache = ns.materialsPrimaryProfCache

    if cache[itemID] ~= nil then
        return cache[itemID] or nil
    end

    -- Don't do an expensive tooltip scan until item data is ready.
    if C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
        if C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
        ns.materialsPendingItemData = ns.materialsPendingItemData or {}
        ns.materialsPendingItemData[itemID] = true
        QM_EnsureMaterialsItemDataListener()
        return nil
    end

    -- Only scan tooltip for items that we believe are crafting reagents.
    if not QM_HasCraftingReagentLine(itemID) then
        cache[itemID] = false
        return nil
    end

    QM_EnsureMaterialsTooltip()
    QM_MaterialsScanTooltip:ClearLines()

    local ok = pcall(function()
        QM_MaterialsScanTooltip:SetHyperlink("item:" .. itemID)
    end)
    if not ok then
        cache[itemID] = false
        return nil
    end

    local numLines = QM_MaterialsScanTooltip:NumLines() or 0
    for i = 2, numLines do
        local left = _G["QM_MaterialsScanTooltipTextLeft" .. i]
        local text = left and left:GetText()
        if text and text ~= "" then
            local lower = text:lower()
            for _, def in ipairs(PROF_KEYWORDS) do
                for _, pat in ipairs(def.patterns) do
                    if lower:find(pat, 1, true) then
                        cache[itemID] = def.key
                        return def.key
                    end
                end
            end
        end
    end

    cache[itemID] = false
    return nil
end


-- Map itemSubType to a "best fit" profession category.
local SUBTYPE_TO_PROF = {
    ["Cloth"] = "tailoring",
    ["Leather"] = "leatherworking",
    ["Metal & Stone"] = "blacksmithing",
    ["Herb"] = "alchemy",
    ["Elemental"] = "alchemy",
    ["Cooking"] = "cooking",
    ["Enchanting"] = "enchanting",
    ["Inscription"] = "inscription",
    ["Jewelcrafting"] = "jewelcrafting",
    ["Parts"] = "engineering",
    ["Gems"] = "jewelcrafting",
}

-- Optional/Finishing reagents are used in multiple professions; show them for all filters.
local function IsUniversalReagentSubtype(subType)
    if not subType then return false end
    return subType == "Optional Reagents" or subType == "Finishing Reagents" or subType == "Reagent"
end

local function IsStrictReagent(item)
    if not item or not item.itemID then return false end

    -- If the scanner cached classID/equipLoc, use it to quickly exclude gear.
    if item.equipLoc and item.equipLoc ~= "" then return false end
    if item.classID and (item.classID ~= ITEM_CLASS_TRADEGOODS and item.classID ~= ITEM_CLASS_GEM and item.classID ~= ITEM_CLASS_REAGENT) then
        -- Still allow items explicitly labeled "Crafting Reagent" even if their class is odd.
        if not QM_HasCraftingReagentLine(item.itemID) then
            return false
        end
    end

    -- Fallback: use instant info if classID missing.
    if (not item.classID) and C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, equipLoc, icon, classID, subclassID = C_Item.GetItemInfoInstant(item.itemID)
        if equipLoc and equipLoc ~= "" then return false end
        if classID and (classID ~= ITEM_CLASS_TRADEGOODS and classID ~= ITEM_CLASS_GEM and classID ~= ITEM_CLASS_REAGENT) then
            if not QM_HasCraftingReagentLine(item.itemID) then
                return false
            end
        else
            -- If the game reports this item is a Trade Good / Gem / Reagent, treat it as a material
            -- even if the scanner hasn't populated subtype metadata yet (prevents undercounting).
            return true
        end
    end

    -- Tighten further: only include known mat subtypes, universal reagent subtypes, gems,
    -- or items explicitly labeled "Crafting Reagent".
    if item.classID == ITEM_CLASS_GEM then
        return true
    end
    local sub = item.itemSubType
    if sub and (SUBTYPE_TO_PROF[sub] or IsUniversalReagentSubtype(sub)) then
        return true
    end
    if QM_HasCraftingReagentLine(item.itemID) then
        return true
    end

    return false
end

-- Profession-focused categories (kept intentionally small & relevant)
local PROF_CATEGORIES = {
    { key = "all", label = "All" },
    { key = "alchemy", label = "Alchemy" },
    { key = "blacksmithing", label = "Blacksmithing" },
    { key = "cooking", label = "Cooking" },
    { key = "enchanting", label = "Enchanting" },
    { key = "engineering", label = "Engineering" },
    { key = "inscription", label = "Inscription" },
    { key = "jewelcrafting", label = "Jewelcrafting" },
    { key = "leatherworking", label = "Leatherworking" },
    { key = "tailoring", label = "Tailoring" },
}

-- Expansion tags are derived from the item tooltip line like "Khaz Algar Crafting Reagent".
-- This list is intentionally short and can be extended later without breaking saved selections.
local EXPANSION_FILTERS = {
    { key = "all", label = "All" },
    -- Tooltip tags use zone/region names (e.g. "Khaz Algar Crafting Reagent").
    -- Keep the *key* as the tag (so filtering works), but display expansion names.
    { key = "Midnight", label = "Midnight" },
    { key = "Khaz Algar", label = "The War Within" },
    { key = "Dragon Isles", label = "Dragonflight" },
    { key = "Shadowlands", label = "Shadowlands" },
    { key = "Broken Isles", label = "Legion" },
    { key = "Draenor", label = "Warlords of Draenor" },
    { key = "Pandaria", label = "Pandaria" },
    { key = "Cataclysm", label = "Cataclysm" },
    { key = "Northrend", label = "Wrath of the Lich King" },
    { key = "Outland", label = "The Burning Crusade" },
    { key = "Classic", label = "Classic" },
}

local function GetProfessionCategoryForItem(item)
    if not item then return "all" end

    -- If tooltip wording clearly implies a profession (e.g. "alchemy"), prefer that.
    -- This fixes cases like cauldron reagents where subType can be misleading.
    if item.itemID and QM_HasCraftingReagentLine(item.itemID) then
        local inferred = QM_GetPrimaryProfessionFromTooltip(item.itemID)
        if inferred then
            return inferred
        end
    end

    local sub = item.itemSubType
    if IsUniversalReagentSubtype(sub) then
        return "all"
    end
    if sub and SUBTYPE_TO_PROF[sub] then
        return SUBTYPE_TO_PROF[sub]
    end

    -- Gems may not always have subtypes populated; infer from class.
    if item.classID == ITEM_CLASS_GEM then
        return "jewelcrafting"
    end

    -- If it is explicitly a crafting reagent but doesn't map cleanly, keep it visible under All.
    if item.itemID and QM_HasCraftingReagentLine(item.itemID) then
        return "all"
    end

    return "all"
end

-- ============================================================================
-- Aggregation
-- ============================================================================

local function AddItemToTotals(totals, item, amount, source, perChar)
    if not item or not item.itemID or not amount or amount <= 0 then return end
    if not IsStrictReagent(item) then return end

    local id = tonumber(item.itemID)
    totals[id] = totals[id] or {
        itemID = id,
        name = item.name,
        itemLink = item.itemLink,
        iconFileID = item.iconFileID,
        itemSubType = item.itemSubType,
        classID = item.classID,
        total = 0,
        sources = {},
        characters = {},
    }

    local t = totals[id]
    t.total = (t.total or 0) + amount
    t.itemSubType = t.itemSubType or item.itemSubType
    t.iconFileID = t.iconFileID or item.iconFileID
    t.name = t.name or item.name
    t.itemLink = t.itemLink or item.itemLink
    t.classID = t.classID or item.classID
-- Ensure name/icon are filled even when cached data is incomplete (prevents blank rows).
if (not t.name or t.name == "") and GetItemInfo then
    local name, link, _, _, _, _, _, _, _, icon, _, classID = GetItemInfo(id)
    if name then
        t.name = name
        t.itemLink = t.itemLink or link
        t.iconFileID = t.iconFileID or icon
        t.classID = t.classID or classID
    else
        -- Request item data and refresh once it's available.
        if C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(id)
        end
        ns.materialsPendingItemData = ns.materialsPendingItemData or {}
        ns.materialsPendingItemData[id] = true
        QM_EnsureMaterialsItemDataListener()

        -- Non-empty placeholder avoids layout quirks.
        t.name = t.name or ("Item " .. id)
    end
end


    if source then
        t.sources[source] = (t.sources[source] or 0) + amount
    end
    if perChar then
        t.characters[perChar] = (t.characters[perChar] or 0) + amount
    end
end

local function IterateContainerItems(itemsTable, callback)
    if type(itemsTable) ~= "table" then return end
    for bagIndex, bagSlots in pairs(itemsTable) do
        if type(bagSlots) == "table" then
            for _, item in pairs(bagSlots) do
                if item and item.itemID then
                    callback(item)
                end
            end
        end
    end
end

local function CollectMaterials(self, opts)
    local db = self.db
    if not db then return {} end

    local totals = {}

    local includeReagentBag = opts.includeReagentBag
    local includeWarband = opts.includeWarband
    local includeAllChars = opts.includeAllChars
    local includeGuild = opts.includeGuild

    local playerKey = UnitName("player") .. "-" .. GetRealmName()


    -- Reagent Bag (current char) is bagID 5 in your inventory mapping (bagIndex varies).
    if includeReagentBag and db.char and db.char.inventory and db.char.inventory.items and db.char.inventory.bagIDs then
        for bagIndex, bagID in ipairs(db.char.inventory.bagIDs) do
            if bagID == 5 then
                local bagSlots = db.char.inventory.items[bagIndex] or {}
                for _, item in pairs(bagSlots) do
                    AddItemToTotals(totals, item, tonumber(item.stackCount or 1) or 1, "Reagent Bag", playerKey)
                end
            end
        end
    end

    -- Warband Bank
    if includeWarband and db.global and db.global.warbandBank and db.global.warbandBank.items then
        for tabIndex, tab in pairs(db.global.warbandBank.items) do
            if type(tab) == "table" then
                for _, item in pairs(tab) do
                    AddItemToTotals(totals, item, tonumber(item.stackCount or 1) or 1, "Warband Bank", "Warband")
                end
            end
        end
    end

    -- All Characters (bags + personal bank)
    -- NOTE: The Materials tab has an explicit "Reagent Bag" source for the *current character*.
    -- When both "Reagent Bag" and "All Characters" are enabled, we must avoid double-counting
    -- the current character's reagent bag as part of "Bags".
    if includeAllChars and db.global and db.global.characters then
        for charKey, charData in pairs(db.global.characters) do
            if type(charData) == "table" then
                if charData.inventory and charData.inventory.items then
                    -- If possible, use bagIDs so we can exclude bagID 5 (reagent bag) for the current character.
                    if charKey == playerKey and includeReagentBag and charData.inventory.bagIDs then
                        for bagIndex, bagID in ipairs(charData.inventory.bagIDs) do
                            if bagID ~= 5 then
                                local bagSlots = charData.inventory.items[bagIndex]
                                if type(bagSlots) == "table" then
                                    for _, item in pairs(bagSlots) do
                                        AddItemToTotals(totals, item, tonumber(item.stackCount or 1) or 1, "Bags", charKey)
                                    end
                                end
                            end
                        end
                    else
                        IterateContainerItems(charData.inventory.items, function(item)
                            AddItemToTotals(totals, item, tonumber(item.stackCount or 1) or 1, "Bags", charKey)
                        end)
                    end
                end
                if charData.personalBank then
                    IterateContainerItems(charData.personalBank, function(item)
                        AddItemToTotals(totals, item, tonumber(item.stackCount or 1) or 1, "Bank", charKey)
                    end)
                end
            end
        end
    end

    -- Guild Bank (cached)
    if includeGuild and db.global and db.global.guildBank then
        for guildName, guildData in pairs(db.global.guildBank) do
            if type(guildData) == "table" and guildData.tabs then
                for tabIndex, tabData in pairs(guildData.tabs) do
                    if tabData and tabData.items then
                        for _, item in pairs(tabData.items) do
                            AddItemToTotals(totals, item, tonumber(item.stackCount or 1) or 1, "Guild Bank", self:GetGuildBankLabel(guildData, guildName))
                        end
                    end
                end
            end
        end
    end

    -- Convert to array
    local out = {}
    for _, v in pairs(totals) do
        table.insert(out, v)
    end
    return out
end


-- ============================================================================
-- Tooltip totals (live scan fallback)
-- ============================================================================
-- The Materials tab has its own aggregated totals (based on tab filters).
-- However, the global tooltip enhancer may also add a "Total owned" line which
-- includes additional sources (warband/guild/banks). To avoid confusing mismatches
-- we compute a lightweight "live" breakdown for the hovered item ID and show it
-- consistently in the Materials tooltip.
local _materialsTooltipTotalsCache = {} -- [itemID] = { ts=time(), data = { total=, sources=table } }
local _MATERIALS_TOOLTIP_CACHE_TTL = 3

local function _QM_GetMaterialsTooltipTotals(itemID)
    if not itemID then return nil end
    local now = time()
    local cached = _materialsTooltipTotalsCache[itemID]
    if cached and cached.ts and (now - cached.ts) <= _MATERIALS_TOOLTIP_CACHE_TTL then
        return cached.data
    end

    local db = TheQuartermaster and TheQuartermaster.db
    if not db then return nil end

    local sources = {}
    local total = 0

    local function add(src, amount)
        if not amount or amount <= 0 then return end
        sources[src] = (sources[src] or 0) + amount
        total = total + amount
    end

    -- Character inventories + personal banks (all characters)
    if db.global and db.global.characters then
        local playerKey = UnitName("player") .. "-" .. GetRealmName()
        for charKey, charData in pairs(db.global.characters) do
            if type(charData) == "table" then
                -- Bags (split reagent bag for current character when bagIDs are available)
                if charData.inventory and charData.inventory.items then
                    if charData.inventory.bagIDs then
                        for bagIndex, bagID in ipairs(charData.inventory.bagIDs) do
                            local bagSlots = charData.inventory.items[bagIndex]
                            if type(bagSlots) == "table" then
                                for _, item in pairs(bagSlots) do
                                    if item and item.itemID == itemID then
                                        if charKey == playerKey and bagID == 5 then
                                            add("Reagent Bag", (item.stackCount or 1))
                                        else
                                            add("Bags", (item.stackCount or 1))
                                        end
                                    end
                                end
                            end
                        end
                    else
                        for _, bagData in pairs(charData.inventory.items) do
                            for _, item in pairs(bagData) do
                                if item and item.itemID == itemID then
                                    add("Bags", (item.stackCount or 1))
                                end
                            end
                        end
                    end
                end
                -- Personal Bank
                if charData.personalBank then
                    for _, bagData in pairs(charData.personalBank) do
                        for _, item in pairs(bagData) do
                            if item and item.itemID == itemID then
                                add("Bank", (item.stackCount or 1))
                            end
                        end
                    end
                end
            end
        end
    end

    -- Warband Bank
    if db.global and db.global.warbandBank and db.global.warbandBank.items then
        for _, bagData in pairs(db.global.warbandBank.items) do
            for _, item in pairs(bagData) do
                if item and item.itemID == itemID then
                    add("Warband Bank", (item.stackCount or 1))
                end
            end
        end
    end

    -- Guild Bank (cached)
    if db.global and db.global.guildBank then
        local guildCount = 0
        for _, guildData in pairs(db.global.guildBank) do
            if type(guildData) == "table" and guildData.tabs then
                for _, tabData in pairs(guildData.tabs) do
                    if tabData and tabData.items then
                        for _, item in pairs(tabData.items) do
                            if item and item.itemID == itemID then
                                guildCount = guildCount + (item.stackCount or item.count or item.quantity or 1)
                            end
                        end
                    end
                end
            end
        end
        add("Guild Bank", guildCount)
    end

    local data = { total = total, sources = sources }
    _materialsTooltipTotalsCache[itemID] = { ts = now, data = data }
    return data
end


-- ============================================================================
-- UI

local function ApplyItemQualityColor(fontString, itemID)
    if not fontString or not itemID then return end

    local quality
    if C_Item and C_Item.GetItemQualityByID then
        quality = C_Item.GetItemQualityByID(itemID)
        if quality == nil and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end

    if quality == nil then
        quality = select(3, GetItemInfo(itemID))
    end

    if quality ~= nil then
        local r, g, b = GetItemQualityColor(quality)
        fontString:SetTextColor(r or 1, g or 1, b or 1)
    else
        fontString:SetTextColor(1, 1, 1)
    end
end

-- ============================================================================

local function CreateRow(parent, y, width, height)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(width, height)
    row:SetPoint("TOPLEFT", 10, -y)
    row:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 2,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    row:SetBackdropColor(unpack(COLORS.bgCard))
    row:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 8, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetTextColor(1, 1, 1)

    row.meta = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
    row.meta:SetPoint("RIGHT", -60, 0)
    row.meta:SetJustifyH("RIGHT")
    row.meta:SetTextColor(0.8, 0.8, 0.8)

    row.count = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    row.count:SetPoint("RIGHT", -12, 0)
    row.count:SetJustifyH("RIGHT")
    row.count:SetTextColor(1, 1, 1)

    row.pin = CreateFrame("Button", nil, row, "BackdropTemplate")
    row.pin:SetSize(22, 22)
    row.pin:SetPoint("RIGHT", row.meta, "LEFT", -8, 0)
    row.pin:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
    row.pin:SetBackdropColor(0, 0, 0, 0.20)

    row.pin.icon = row.pin:CreateTexture(nil, "ARTWORK")
    row.pin.icon:SetAllPoints()
    row.pin.icon:SetTexture("Interface\\Common\\FavoritesIcon")
    row.pin.icon:SetAlpha(0.9)

    return row
end

local function DrawEmptyState(parent, text, yOffset)
    local msg = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    msg:SetPoint("TOPLEFT", 20, -yOffset)
    msg:SetTextColor(0.7, 0.7, 0.7)
    msg:SetText(text)
    return yOffset + 30
end

local function EnsureControls(self, parent)
    local c = parent.controls or {}
    parent.controls = c
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(64)
    c.sourceBar = bar
    ns.materialsSources = ns.materialsSources or {reagent=true, warband=true, all=true, guild=true}
    local function Skin(button)
        button:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        button:SetBackdropColor(unpack(COLORS.bgCard))
        button:SetBackdropBorderColor(unpack(COLORS.border))
        button:SetScript("OnEnter", function(b) b:SetBackdropBorderColor(unpack(COLORS.accent)) end)
        button:SetScript("OnLeave", function(b) b:SetBackdropBorderColor(unpack(COLORS.border)) end)
    end
    local function MakeCB(label, key, x)
        local cb = CreateFrame("CheckButton", nil, bar, "BackdropTemplate")
        cb:SetSize(18, 18); cb:SetPoint("TOPLEFT", x, -4); Skin(cb)
        local mark = cb:CreateTexture(nil, "ARTWORK")
        mark:SetPoint("TOPLEFT", 4, -4); mark:SetPoint("BOTTOMRIGHT", -4, 4)
        mark:SetColorTexture(unpack(COLORS.accent)); cb:SetCheckedTexture(mark)
        cb:SetChecked(ns.materialsSources[key])
        local text = cb:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
        text:SetPoint("LEFT", cb, "RIGHT", 8, 0); text:SetText(label)
        text:SetTextColor(unpack(COLORS.textNormal))
        cb:SetScript("OnClick", function(button)
            ns.materialsSources[key] = button:GetChecked() and true or false
            TheQuartermaster:PopulateContent()
        end)
        return cb
    end
    c.cbReagent = MakeCB(L.MAT_SOURCE_REAGENT, "reagent", 0)
    c.cbWarband = MakeCB(L.WARBAND_BANK, "warband", 150)
    c.cbAll = MakeCB(L.MAT_SOURCE_ALL, "all", 310)
    c.cbGuild = MakeCB(L.MAT_SOURCE_GUILD, "guild", 480)

    local function MakeDrop(prefix, choices, field, x)
        local button = CreateFrame("Button", nil, bar, "BackdropTemplate")
        button:SetSize(220, 26); button:SetPoint("TOPLEFT", x, -34); Skin(button)
        local label = button:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
        label:SetPoint("LEFT", 10, 0); label:SetPoint("RIGHT", -22, 0); label:SetJustifyH("LEFT")
        local arrow = button:CreateTexture(nil, "ARTWORK")
        arrow:SetSize(12, 12); arrow:SetPoint("RIGHT", -6, 0)
        arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
        arrow:SetVertexColor(unpack(COLORS.accent))
        local selected = ns[field] or "all"
        for _, choice in ipairs(choices) do if choice.key == selected then label:SetText(prefix .. ": " .. choice.label) end end
        local menu = CreateFrame("Frame", nil, button, "BackdropTemplate")
        menu:SetSize(220, #choices * 24 + 8); menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
        menu:SetFrameStrata("DIALOG"); Skin(menu); menu:Hide()
        for i, choice in ipairs(choices) do
            local option = CreateFrame("Button", nil, menu, "BackdropTemplate")
            option:SetSize(212, 24); option:SetPoint("TOPLEFT", 4, -4 - (i-1)*24); Skin(option)
            local text = option:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
            text:SetPoint("LEFT", 8, 0); text:SetText(choice.label)
            text:SetTextColor(unpack(choice.key == selected and COLORS.accent or COLORS.textNormal))
            option:SetScript("OnClick", function() menu:Hide(); ns[field] = choice.key; TheQuartermaster:PopulateContent() end)
        end
        button:SetScript("OnClick", function()
            local open = not menu:IsShown()
            if c.openMenu then c.openMenu:Hide() end
            c.openMenu = menu
            if open then menu:Show() end
        end)
        return button
    end
    c.categoryDrop = MakeDrop(L.MAT_FILTER_CATEGORY, PROF_CATEGORIES, "materialsCategory", 0)
    c.expansionDrop = MakeDrop(L.MAT_FILTER_EXPANSION, EXPANSION_FILTERS, "materialsExpansion", 232)
    return c
end

function TheQuartermaster:DrawMaterialsTab(parent)
    -- This tab lives inside the same scrollChild as all other tabs.
    -- Other views (Items/Storage) may aggressively release pooled children.
    -- PopulateContent() also hides all children on every refresh.
    --
    -- To avoid "blank" states and missing controls after tab switches, we rebuild
    -- the Materials UI on each draw. State (filters/search/toggles) lives in `ns.*`
    -- so rebuilds are stable and cheap.

    ReleaseAllPooledChildren(parent)
    parent.controls = {}
    parent._qmMaterialsBuilt = true

    local width = (parent:GetWidth() or 700) - 20

    -- Controls bar (checkboxes + dropdown)
    local controls = EnsureControls(self, parent)
    controls.sourceBar:ClearAllPoints()
    controls.sourceBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
    controls.sourceBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -10)

    -- Results title
    local title = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontHeading")
    title:SetPoint("TOPLEFT", controls.sourceBar, "BOTTOMLEFT", 0, -10)
    title:SetText("Results")
    title:SetTextColor(1, 1, 1)
    parent.controls.resultsTitle = title

    -- Results container
    local resultsParent = CreateFrame("Frame", nil, parent)
    resultsParent:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    resultsParent:SetWidth(width)
    resultsParent:SetHeight(1)
    parent.controls.resultsContainer = resultsParent

    local searchText = tostring(ns.materialsSearchText or ""):lower()
    local catKey = ns.materialsCategory or "all"
    local expKey = ns.materialsExpansion or "all"
    local sources = ns.materialsSources or { reagent=true, warband=true, all=true, guild=true }

    local data = CollectMaterials(self, {
        includeReagentBag = sources.reagent,
        includeWarband = sources.warband,
        includeAllChars = sources.all,
        includeGuild = sources.guild,
    })

    -- Apply filters (profession category + expansion + text search)
    local filtered = {}
    local hadPendingItemData = false
    for _, it in ipairs(data) do
        local prof = GetProfessionCategoryForItem(it)
        local okCat = (catKey == "all") or (prof == catKey) or (prof == "all" and IsUniversalReagentSubtype(it.itemSubType))
        if okCat then
            local okExp = true
            if expKey ~= "all" then
                local tag = QM_GetReagentExpansionTag(it.itemID)
                if not tag then
                    if ns.materialsPendingItemData and ns.materialsPendingItemData[tonumber(it.itemID)] then
                        hadPendingItemData = true
                    end
                    okExp = false
                else
                    okExp = (tag == expKey)
                end
            end
            if okExp then
                if searchText == "" or (it.name and it.name:lower():find(searchText, 1, true)) then
                    table.insert(filtered, it)
                end
            end
        end
    end

    table.sort(filtered, function(a,b)
        return (a.name or "") < (b.name or "")
    end)

    local yOffset = 0

    if #filtered == 0 then
        if hadPendingItemData then
            yOffset = DrawEmptyState(resultsParent, "Loading item data for expansion filtering... please try again in a moment.", 0)
        else
            yOffset = DrawEmptyState(resultsParent, "No crafting materials found for your current filters.", 0)
        end
        resultsParent:SetHeight(yOffset + 10)

        local total = 10 + 64 + 10 + 20 + 6 + yOffset + 30
        parent:SetHeight(total)
        return total
    end

    local rowH = 30
    for i=1, math.min(#filtered, 200) do
        local it = filtered[i]
        local itemID = it and it.itemID
        local row = CreateRow(resultsParent, yOffset, width, rowH)

        row.icon:SetTexture(it.iconFileID or 134400)
        row.name:SetText(it.name or ("Item " .. tostring(it.itemID)))
        ApplyItemQualityColor(row.name, itemID)
        -- show a clean profession label (not raw subtype noise)
        local profKey = GetProfessionCategoryForItem(it)
        local profLabel = "Reagent"
        for _, c in ipairs(PROF_CATEGORIES) do
            if c.key == profKey and c.key ~= "all" then profLabel = c.label end
        end
        row.meta:SetText(profLabel)

        -- Ensure the row count matches the tooltip + "Total owned" logic.
        -- (The tooltip totals are computed from the canonical per-character bag/bank caches.)
        local displayTotal = it.total or 0
        if itemID then
            local tt = _QM_GetMaterialsTooltipTotals(itemID)
            if tt and tt.total then
                displayTotal = tt.total
                it.total = tt.total
            end
        end

        row.count:SetText(tostring(displayTotal))
        -- Materials are reagents; keep pin state in the reagent watchlist bucket.
        local pinned = itemID and self:IsWatchlistedReagent(itemID)
        if pinned then
            row.pin.icon:SetVertexColor(1, 0.2, 0.2) -- red when pinned
        else
            row.pin.icon:SetVertexColor(1, 0.82, 0) -- yellow when not pinned
        end

        row.pin:SetScript("OnClick", function()
            if itemID then self:ToggleWatchlistReagent(itemID) end
            self:PopulateContent()
        end)

        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnMouseUp", function(_, button)
            if not itemID then return end

            if button == "RightButton" then
                local pinnedNow = self:IsWatchlistedReagent(itemID)
                local menu = {
                    {
                        text = pinnedNow and "Unpin from Watchlist" or "Pin to Watchlist",
                        func = function()
                            self:ToggleWatchlistReagent(itemID)
                            self:PopulateContent()
                        end,
                    },
                    {
                        text = "Copy Item Link",
                        func = function()
                            local link = it.itemLink or select(2, GetItemInfo(itemID))
                            QM_CopyItemLinkToChat(link)
                        end,
                    },
                    {
                        text = "Search this item",
                        func = function()
                            ns.globalSearchText = it.name or (GetItemInfo(itemID) or "")
                            -- open global search tab
                            if self.UI and self.UI.mainFrame then
                                self.UI.mainFrame.currentTab = "search"
                            end
                            self:PopulateContent()
                        end,
                    },
                }
                QM_OpenRowMenu(menu, row)
                return
            end

            if button == "LeftButton" and IsShiftKeyDown() then
                local link = it.itemLink or select(2, GetItemInfo(itemID))
                if link then ChatEdit_InsertLink(link) end
            end
        end)

        row:SetScript("OnEnter", function(selfRow)
            selfRow:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
            if itemID then
                GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(it.itemLink or select(2, GetItemInfo(itemID)) or ("item:"..itemID))
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cffffffffTotals|r", 1,1,1)

                local tData = _QM_GetMaterialsTooltipTotals(itemID)
                local totalVal = (tData and tData.total) or (it.total or 0)
                local sources = (tData and tData.sources) or it.sources or {}

                GameTooltip:AddLine("Total: " .. tostring(totalVal), 0.8,0.8,0.8)

                -- Show sources in a consistent order (only when > 0)
                local ordered = { "Bags", "Bank", "Reagent Bag", "Warband Bank", "Guild Bank" }
                for _, src in ipairs(ordered) do
                    local amt = sources[src]
                    if amt and amt > 0 then
                        GameTooltip:AddLine(src .. ": " .. tostring(amt), 0.8,0.8,0.8)
                    end
                end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(selfRow)
            selfRow:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
            GameTooltip:Hide()
        end)

        yOffset = yOffset + rowH + 6
    end

    resultsParent:SetHeight(yOffset + 10)

    -- Total content height: top padding + controls (64) + spacing + title + spacing + results
    local total = 10 + 64 + 10 + 20 + 6 + yOffset + 30
    parent:SetHeight(total)
    return total
end
