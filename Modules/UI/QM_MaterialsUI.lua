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

local function QM_GetReagentExpansionTag(itemID)
    return QM_GetExpansionTagFromLabel(QM_GetCraftingReagentLabel(itemID))
end

local function QM_HasCraftingReagentLine(itemID)
    return QM_GetCraftingReagentLabel(itemID) ~= nil
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
        if text and text ~= "" then
            local lower = text:lower()
            for _, def in ipairs(PROF_KEYWORDS) do
                for _, pat in ipairs(def.patterns) do
                    if lower:find(pat, 1, true) then
                        return def.key
                    end
                end
            end
        end
    end
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
    { key = "Khaz Algar", label = "The War Within" },
    { key = "Dragon Isles", label = "Dragonflight" },
    { key = "Shadowlands", label = "Shadowlands" },
    { key = "Broken Isles", label = "Legion" },
    { key = "Draenor", label = "Warlords of Draenor" },
    { key = "Pandaria", label = "Pandaria" },
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
                if charData.personalBank and charData.personalBank.items then
                    IterateContainerItems(charData.personalBank.items, function(item)
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
                            AddItemToTotals(totals, item, tonumber(item.stackCount or 1) or 1, "Guild Bank", guildName)
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
-- UI
-- ============================================================================

local function CreateRow(parent, y, width, height)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(width, height)
    row:SetPoint("TOPLEFT", 10, -y)
    row:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    row:SetBackdropColor(0.10, 0.10, 0.12, 1)
    row:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 8, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetTextColor(1, 1, 1)

    row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.meta:SetPoint("RIGHT", -60, 0)
    row.meta:SetJustifyH("RIGHT")
    row.meta:SetTextColor(0.8, 0.8, 0.8)

    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
    local msg = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    msg:SetPoint("TOPLEFT", 20, -yOffset)
    msg:SetTextColor(0.7, 0.7, 0.7)
    msg:SetText(text)
    return yOffset + 30
end

local function EnsureControls(self, parent)
    parent.controls = parent.controls or {}
    local c = parent.controls

    if not c.sourceBar then
        local bar = CreateFrame("Frame", nil, parent)
        bar:SetPoint("TOPLEFT", 10, -120)
        bar:SetPoint("TOPRIGHT", -10, -120)
        bar:SetHeight(52)
        c.sourceBar = bar

        local function MakeCB(label, x)
            local cb = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
            cb:SetPoint("TOPLEFT", x, -6)
            cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cb.text:SetPoint("LEFT", cb, "RIGHT", 6, 0)
            cb.text:SetText(label)
            return cb
        end

        c.cbReagent = MakeCB("Reagent Bag", 0)
        c.cbWarband = MakeCB("Warband Bank", 140)
        c.cbAll = MakeCB("All Characters", 300)
        c.cbGuild = MakeCB("Guild Bank (cached)", 470)

        -- Defaults
        if ns.materialsSources == nil then
            ns.materialsSources = { reagent=true, warband=true, all=true, guild=true }
        end

        c.cbReagent:SetChecked(ns.materialsSources.reagent)
        c.cbWarband:SetChecked(ns.materialsSources.warband)
        c.cbAll:SetChecked(ns.materialsSources.all)
        c.cbGuild:SetChecked(ns.materialsSources.guild)

        local function OnSourceChanged()
            ns.materialsSources.reagent = c.cbReagent:GetChecked()
            ns.materialsSources.warband = c.cbWarband:GetChecked()
            ns.materialsSources.all = c.cbAll:GetChecked()
            ns.materialsSources.guild = c.cbGuild:GetChecked()
            TheQuartermaster:PopulateContent()
        end
        c.cbReagent:SetScript("OnClick", OnSourceChanged)
        c.cbWarband:SetScript("OnClick", OnSourceChanged)
        c.cbAll:SetScript("OnClick", OnSourceChanged)
        c.cbGuild:SetScript("OnClick", OnSourceChanged)

        -- Category dropdown (profession focused)
        local drop = CreateFrame("Frame", "QM_MaterialsCategoryDropDown", bar, "UIDropDownMenuTemplate")
        -- Small padding so the dropdown doesn't feel glued to the checkboxes.
        drop:SetPoint("TOPLEFT", 0, -34)
        UIDropDownMenu_SetWidth(drop, 180)
        c.categoryDrop = drop

        -- Expansion dropdown (derived from tooltip tags like "Khaz Algar Crafting Reagent")
        local expDrop = CreateFrame("Frame", "QM_MaterialsExpansionDropDown", bar, "UIDropDownMenuTemplate")
        expDrop:SetPoint("LEFT", drop, "RIGHT", -10, 0)
        UIDropDownMenu_SetWidth(expDrop, 180)
        c.expansionDrop = expDrop

        local function SetCat(key, label)
            ns.materialsCategory = key
            UIDropDownMenu_SetText(drop, "Category: " .. (label or "All"))
            TheQuartermaster:PopulateContent()
        end

        UIDropDownMenu_Initialize(drop, function(frame, level)
            local info = UIDropDownMenu_CreateInfo()
            for _, cat in ipairs(PROF_CATEGORIES) do
                info.text = cat.label
                info.func = function() SetCat(cat.key, cat.label) end
                info.notCheckable = true
                UIDropDownMenu_AddButton(info)
            end
        end)

        local function SetExpansion(key, label)
            ns.materialsExpansion = key
            UIDropDownMenu_SetText(expDrop, "Expansion: " .. (label or "All"))
            TheQuartermaster:PopulateContent()
        end

        UIDropDownMenu_Initialize(expDrop, function(frame, level)
            local info = UIDropDownMenu_CreateInfo()
            for _, ex in ipairs(EXPANSION_FILTERS) do
                info.text = ex.label
                info.func = function() SetExpansion(ex.key, ex.label) end
                info.notCheckable = true
                UIDropDownMenu_AddButton(info)
            end
        end)

        if not ns.materialsCategory then ns.materialsCategory = "all" end
        local label = "All"
        for _, cat in ipairs(PROF_CATEGORIES) do
            if cat.key == ns.materialsCategory then label = cat.label end
        end
        UIDropDownMenu_SetText(drop, "Category: " .. label)

        if not ns.materialsExpansion then ns.materialsExpansion = "all" end
        local exLabel = "All"
        for _, ex in ipairs(EXPANSION_FILTERS) do
            if ex.key == ns.materialsExpansion then exLabel = ex.label end
        end
        UIDropDownMenu_SetText(expDrop, "Expansion: " .. exLabel)
    end

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

    -- Header card
    local card = CreateCard(parent, 70)
    card:SetPoint("TOPLEFT", 10, -20)
    card:SetPoint("TOPRIGHT", -10, -20)

    local titleIcon = card:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\inv_misc_herb_19")

    local titleText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hex = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hex .. "Materials" .. "|r")

    local subtitleText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText("Crafting reagents across your Warband, banks, and caches")

    parent.controls.headerCard = card

    -- Controls bar (checkboxes + dropdown)
    local controls = EnsureControls(self, parent)
    controls.sourceBar:ClearAllPoints()
    controls.sourceBar:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -10)
    controls.sourceBar:SetPoint("TOPRIGHT", card, "BOTTOMRIGHT", 0, -10)

    -- Results title
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", controls.sourceBar, "BOTTOMLEFT", 0, -10)
    title:SetText("Results")
    title:SetTextColor(1, 1, 1)
    parent.controls.resultsTitle = title

    -- Results container
    local resultsParent = CreateFrame("Frame", nil, parent)
    resultsParent:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    resultsParent:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, 0)
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
    for _, it in ipairs(data) do
        local prof = GetProfessionCategoryForItem(it)
        local okCat = (catKey == "all") or (prof == catKey) or (prof == "all" and IsUniversalReagentSubtype(it.itemSubType))
        if okCat then
            local okExp = true
            if expKey ~= "all" then
                local tag = QM_GetReagentExpansionTag(it.itemID)
                okExp = (tag == expKey)
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
        yOffset = DrawEmptyState(resultsParent, "No crafting materials found for your current filters.", 0)
        resultsParent:SetHeight(yOffset + 10)

        local total = 20 + 88 + 10 + 52 + 10 + 20 + 6 + yOffset + 30
        parent:SetHeight(total)
        return total
    end

    local rowH = 30
    for i=1, math.min(#filtered, 200) do
        local it = filtered[i]
        local row = CreateRow(resultsParent, yOffset, width, rowH)

        row.icon:SetTexture(it.iconFileID or 134400)
        row.name:SetText(it.name or ("Item " .. tostring(it.itemID)))
        -- show a clean profession label (not raw subtype noise)
        local profKey = GetProfessionCategoryForItem(it)
        local profLabel = "Reagent"
        for _, c in ipairs(PROF_CATEGORIES) do
            if c.key == profKey and c.key ~= "all" then profLabel = c.label end
        end
        row.meta:SetText(profLabel)
        row.count:SetText(tostring(it.total or 0))

        local itemID = it.itemID
        local pinned = itemID and self:IsWatchlistedItem(itemID)
        row.pin.icon:SetVertexColor(pinned and COLORS.accent[1] or 1, pinned and COLORS.accent[2] or 1, pinned and COLORS.accent[3] or 1)

        row.pin:SetScript("OnClick", function()
            if itemID then self:ToggleWatchlistReagent(itemID) end
            self:PopulateContent()
        end)

        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnMouseUp", function(_, button)
            if not itemID then return end

            if button == "RightButton" then
                local pinnedNow = self:IsWatchlistedItem(itemID)
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
                GameTooltip:AddLine("Total: " .. tostring(it.total or 0), 0.8,0.8,0.8)
                if it.sources then
                    for src, amt in pairs(it.sources) do
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

    -- Total content height: header (20+88) + spacing + controls (52) + spacing + title + spacing + results
    local total = 20 + 88 + 10 + 52 + 10 + 20 + 6 + yOffset + 30
    parent:SetHeight(total)
    return total
end
