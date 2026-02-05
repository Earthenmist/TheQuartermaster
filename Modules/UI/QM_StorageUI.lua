--[[
    The Quartermaster - Storage Tab
    Hierarchical storage browser with search and category organization
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local FormatCharacterNameRealm = ns.UI_FormatCharacterNameRealm
local GetItemTypeName = ns.UI_GetItemTypeName
local GetItemClassID = ns.UI_GetItemClassID
local GetTypeIcon = ns.UI_GetTypeIcon
local GetQualityHex = ns.UI_GetQualityHex
local DrawEmptyState = ns.UI_DrawEmptyState
local function GetCOLORS()
    return ns.UI_COLORS
end

-- Import pooling functions
local AcquireStorageRow = ns.UI_AcquireStorageRow
local ReleaseStorageRow = ns.UI_ReleaseStorageRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren

-- Import shared UI layout constants
local UI_LAYOUT = ns.UI_LAYOUT
local ROW_HEIGHT = UI_LAYOUT.ROW_HEIGHT
local ROW_SPACING = UI_LAYOUT.ROW_SPACING
local HEADER_SPACING = UI_LAYOUT.HEADER_SPACING
local SECTION_SPACING = UI_LAYOUT.SECTION_SPACING

-- Performance: Local function references
local format = string.format

-- ==============================
-- Item info resolution helpers
-- ==============================
local _tq_storagePendingInfoRefresh = false
local function _TQ_StorageQueueInfoRefresh()
    if _tq_storagePendingInfoRefresh then return end
    _tq_storagePendingInfoRefresh = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.25, function()
            _tq_storagePendingInfoRefresh = false
            if TheQuartermaster and TheQuartermaster.RefreshUI then
                TheQuartermaster:RefreshUI()
            end
        end)
    else
        _tq_storagePendingInfoRefresh = false
    end
end

local function _TQ_StorageResolveItemInfo(item)
    if not item or not item.itemID then return end
    local itemID = tonumber(item.itemID)
    if not itemID then return end

    local name, link, quality, _, _, itemType, itemSubType, _, _, icon, _, classID, subclassID = GetItemInfo(itemID)
    if name and name ~= "" then
        item.name = name
        item.itemLink = item.itemLink or link
        if item.quality == nil then item.quality = quality end
        item.itemType = item.itemType or itemType
        item.itemSubType = item.itemSubType or itemSubType
        item.iconFileID = item.iconFileID or icon
        item.classID = item.classID or classID
        item.subclassID = item.subclassID or subclassID
        return true
    end

    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
        _TQ_StorageQueueInfoRefresh()
    end

    if (not item.iconFileID) and type(GetItemInfoInstant) == "function" then
        local _, _, _, _, iconFileID, cID, scID = GetItemInfoInstant(itemID)
        item.iconFileID = iconFileID or item.iconFileID
        item.classID = item.classID or cID
        item.subclassID = item.subclassID or scID
    end
end


-- ==============================
-- Item info resolution helpers
-- ==============================
local _tq_storagePendingInfoRefresh = false
local function _TQ_StorageQueueInfoRefresh()
    if _tq_storagePendingInfoRefresh then return end
    _tq_storagePendingInfoRefresh = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.25, function()
            _tq_storagePendingInfoRefresh = false
            if TheQuartermaster and TheQuartermaster.RefreshUI then
                TheQuartermaster:RefreshUI()
            end
        end)
    else
        _tq_storagePendingInfoRefresh = false
    end
end

local function _TQ_StorageResolveItemInfo(item)
    if not item or not item.itemID then return end

    local itemID = tonumber(item.itemID)
    if not itemID then return end

    local name, link, quality, _, _, itemType, itemSubType, _, _, icon, _, classID, subclassID = GetItemInfo(itemID)
    if name and name ~= "" then
        item.name = name
        item.itemLink = item.itemLink or link
        if item.quality == nil then item.quality = quality end
        item.itemType = item.itemType or itemType
        item.itemSubType = item.itemSubType or itemSubType
        item.iconFileID = item.iconFileID or icon
        item.classID = item.classID or classID
        item.subclassID = item.subclassID or subclassID
        return true
    end

    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
        _TQ_StorageQueueInfoRefresh()
    end

    if (not item.iconFileID) and type(GetItemInfoInstant) == "function" then
        local _, _, _, _, iconFileID, cID, scID = GetItemInfoInstant(itemID)
        item.iconFileID = iconFileID or item.iconFileID
        item.classID = item.classID or cID
        item.subclassID = item.subclassID or scID
    end
end

--============================================================================
-- DRAW STORAGE TAB (Hierarchical Storage Browser)
--============================================================================

function TheQuartermaster:DrawStorageTab(parent)
    -- Release all pooled children before redrawing (performance optimization)
    ReleaseAllPooledChildren(parent)
    
    local yOffset = 8 -- Top padding for breathing room
    local width = parent:GetWidth() - 20
    local indent = 20
    
    -- Get search text from namespace
    local storageSearchText = ns.UI_GetStorageSearchText()
    
    -- ===== HEADER CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_36")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    -- Dynamic theme color for title
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Storage Browser|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText(L["BROWSE_ALL_ITEMS_ORGANIZED_BY_TYPE"])
    
    yOffset = yOffset + 78 -- Header height + spacing
    
    -- NOTE: Search box is now persistent in QM_UI.lua (searchArea)
    -- No need to create it here!
    
    -- Get expanded state
    local expanded = self.db.profile.storageExpanded or {}
    if not expanded.categories then expanded.categories = {} end
    if expanded.inventory == nil then expanded.inventory = false end
    
    -- Toggle function
    local function ToggleExpand(key, isExpanded)
        -- If isExpanded is boolean, use it directly (new callback style)
        -- If isExpanded is nil, toggle manually (old callback style for backwards compat)
        if type(isExpanded) == "boolean" then
            if key == "warband" or key == "personal" or key == "inventory" or key == "guildbanks" then
                expanded[key] = isExpanded
            else
                expanded.categories[key] = isExpanded
            end
        else
            -- Old style toggle (fallback)
            if key == "warband" or key == "personal" or key == "inventory" or key == "guildbanks" then
                expanded[key] = not expanded[key]
            else
                expanded.categories[key] = not expanded.categories[key]
            end
        end
        self:RefreshUI()
    end
    
    -- Shared item row renderer (Items tab style)
    -- ==============================
    local function DrawStorageItemRow(parent, item, rowWidth, xOffset, yOffset, rowIndex)
    local colors = GetCOLORS()

    local itemRow = CreateFrame("Button", nil, parent, "BackdropTemplate")
    itemRow:SetSize(rowWidth, ROW_HEIGHT)
    itemRow:SetPoint("TOPLEFT", xOffset, -yOffset)
    itemRow:SetBackdrop({
    bgFile = "Interface\\BUTTONS\\WHITE8X8",
    })

    -- Alternating row colors (Items style)
    local even = (rowIndex % 2 == 0)
    itemRow:SetBackdropColor(even and 0.07 or 0.05, even and 0.07 or 0.05, even and 0.09 or 0.06, 1)

    local itemID = item.itemID
    local itemName = item.name or (itemID and ("Item " .. tostring(itemID))) or "Unknown Item"
    local itemLink = item.itemLink
    local itemCount = item.count or item.quantity or item.stackCount or 1
    local iconFileID = item.iconFileID

    -- Ensure basic info if possible
    if itemID and (not item.name or not item.iconFileID) then
    local name, link, quality, _, _, itemType, itemSubType, _, _, icon, _, classID, subclassID = GetItemInfo(itemID)
    if name and name ~= "" then
    itemName = name
    item.name = name
    itemLink = itemLink or link
    item.itemLink = item.itemLink or link
    item.quality = item.quality or quality
    item.itemType = item.itemType or itemType
    item.itemSubType = item.itemSubType or itemSubType
    iconFileID = iconFileID or icon
    item.iconFileID = item.iconFileID or icon
    item.classID = item.classID or classID
    item.subclassID = item.subclassID or subclassID
    end
    end

    -- Quantity
    local qtyText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    qtyText:SetPoint("LEFT", 15, 0)
    qtyText:SetWidth(40)
    qtyText:SetJustifyH("LEFT")
    qtyText:SetTextColor(1, 0.82, 0)
    qtyText:SetText(itemCount > 1 and tostring(itemCount) or "")

    -- Icon
    local icon = itemRow:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 52, 0)
    icon:SetTexture(iconFileID or 134400)

    -- Name
    local nameText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWidth(rowWidth - 120)

    local displayName = itemName

    if type(displayName) == "string" then
        -- Trim leading whitespace just in case
        displayName = displayName:gsub("^%s+", "")

        -- Some cached sources include leading texture tags (e.g. "|T...|t") before the name.
        -- Strip any number of those so our hex cleanup works reliably.
        while displayName:match("^|T") do
            displayName = displayName:gsub("^|T.-|t", "")
            displayName = displayName:gsub("^%s+", "")
        end

        -- Some cached sources store raw hex like '1eff00Auto-Hammer' (or 8-char variants)
        if displayName:match("^%x%x%x%x%x%x%x%x") then
            displayName = displayName:gsub("^%x%x%x%x%x%x%x%x", "")
        end
        if displayName:match("^%x%x%x%x%x%x") then
            displayName = displayName:gsub("^%x%x%x%x%x%x", "")
        end

        -- If it already contains proper WoW color codes, use it directly
        if displayName:match("^|c%x%x%x%x%x%x%x%x") then
            nameText:SetText(displayName .. "|r")
        else
                        local quality = item.quality or 1
            local hex = GetQualityHex(quality)
            -- Normalize hex from UI_GetQualityHex: must be a WoW color code like |cffRRGGBB / |cAARRGGBB
            if type(hex) == "string" and not hex:match("^|c") then
                local raw = hex:gsub("^#", ""):gsub("^0x", "")
                if raw:match("^%x%x%x%x%x%x$") then
                    hex = "|cff" .. raw
                elseif raw:match("^%x%x%x%x%x%x%x%x$") then
                    hex = "|c" .. raw
                else
                    hex = "|cffffffff"
                end
            end
            nameText:SetText((hex or "|cffffffff") .. displayName .. "|r")
        end
    else
        local quality = item.quality or 1
        local hex = GetQualityHex(quality)
        if type(hex) == "string" and not hex:match("^|c") then
            local raw = hex:gsub("^#", ""):gsub("^0x", "")
            if raw:match("^%x%x%x%x%x%x$") then
                hex = "|cff" .. raw
            elseif raw:match("^%x%x%x%x%x%x%x%x$") then
                hex = "|c" .. raw
            else
                hex = "|cffffffff"
            end
        end
        nameText:SetText((hex or "|cffffffff") .. tostring(displayName or "") .. "|r")
    end

-- Tooltip
    itemRow:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if itemLink then
    GameTooltip:SetHyperlink(itemLink)
    elseif itemID then
    GameTooltip:SetItemByID(itemID)
    else
    GameTooltip:AddLine(itemName)
    end
    GameTooltip:Show()
    end)
    itemRow:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return itemRow
end
    
    local function ItemMatchesSearch(item)
        if not storageSearchText or storageSearchText == "" then
            return true
        end

-- ==============================


        local itemName = (item.name or ""):lower()
        local itemLink = (item.itemLink or ""):lower()
        return itemName:find(storageSearchText, 1, true) or itemLink:find(storageSearchText, 1, true)
    end
    
    -- PRE-SCAN: If search is active, find which categories have matches
    local categoriesWithMatches = {}
    local hasAnyMatches = false
    if storageSearchText and storageSearchText ~= "" then
        -- Scan Warband Bank
        local warbandBankData = self.db.global.warbandBank and self.db.global.warbandBank.items or {}
        for bagID, bagData in pairs(warbandBankData) do
            for slotID, item in pairs(bagData) do
                if item and item.itemID and ItemMatchesSearch(item) then
                    local classID = item.classID or GetItemClassID(item.itemID)
                    local typeName = GetItemTypeName(classID)
                    local categoryKey = "warband_" .. typeName
                    categoriesWithMatches[categoryKey] = true
                    categoriesWithMatches["warband"] = true
                    hasAnyMatches = true
                end
            end
        end

        -- Scan Personal Banks
        for charKey, charData in pairs(self.db.global.characters or {}) do
            if charData.personalBank then
                for bagID, bagData in pairs(charData.personalBank) do
                    for slotID, item in pairs(bagData) do
                        if item and item.itemID and ItemMatchesSearch(item) then
                            local classID = item.classID or GetItemClassID(item.itemID)
                            local typeName = GetItemTypeName(classID)
                            local charCategoryKey = "personal_" .. charKey
                            local typeKey = charCategoryKey .. "_" .. typeName
                            categoriesWithMatches[typeKey] = true
                            categoriesWithMatches[charCategoryKey] = true
                            categoriesWithMatches["personal"] = true
                            hasAnyMatches = true
                        end
                    end
                end
            end
        end

        -- Scan Cached Guild Banks (stored in global DB by guild name)
        local allGuildBanks = self.db.global.guildBank or {}
        for guildName, guildData in pairs(allGuildBanks) do
            if guildData and guildData.tabs then
                for tabIndex, tabData in pairs(guildData.tabs) do
                    if tabData and tabData.items then
                        for slotID, item in pairs(tabData.items) do
                            if item and item.itemID and ItemMatchesSearch(item) then
                                local classID = item.classID or GetItemClassID(item.itemID)
                                local typeName = GetItemTypeName(classID)
                                local guildKey = "guildbanks_" .. tostring(guildName)
                                local typeKey = guildKey .. "_" .. typeName
                                categoriesWithMatches[typeKey] = true
                                categoriesWithMatches[guildKey] = true
                                categoriesWithMatches["guildbanks"] = true
                                hasAnyMatches = true
                            end
                        end
                    end
                end
            end
        end

        -- Scan Inventories (per-character bags)
        for charKey, charData in pairs(self.db.global.characters or {}) do
            if charData.inventory and charData.inventory.items then
                for _, bagData in pairs(charData.inventory.items) do
                    for _, item in pairs(bagData) do
                        if item and item.itemID and ItemMatchesSearch(item) then
                            local classID = item.classID or GetItemClassID(item.itemID)
                            local typeName = GetItemTypeName(classID)
                            local charCategoryKey = "inventory_" .. charKey
                            local typeKey = charCategoryKey .. "_" .. typeName
                            categoriesWithMatches[typeKey] = true
                            categoriesWithMatches[charCategoryKey] = true
                            categoriesWithMatches["inventory"] = true
                            hasAnyMatches = true
                        end
                    end
                end
            end
        end
    end

    -- If search is active but no matches, show empty state
    if storageSearchText and storageSearchText ~= "" and not hasAnyMatches then
        return DrawEmptyState(self, parent, yOffset, true, storageSearchText)
    end
    


-- ===== INVENTORY SECTION =====
-- Auto-expand if search has matches in this section
local inventoryExpanded = expanded.inventory
if storageSearchText and storageSearchText ~= "" and categoriesWithMatches["inventory"] then
    inventoryExpanded = true
end

-- Skip section entirely if search active and no matches
if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches["inventory"] then
    -- Skip this section
else
    local invHeader = nil
    invHeader = CreateCollapsibleHeader(
        parent,
        "Inventories",
        "inventory",
        inventoryExpanded,
        function(isExpanded) ToggleExpand("inventory", isExpanded) end,
        "Interface\\Icons\\INV_Misc_Bag_08"
    )
    invHeader:SetPoint("TOPLEFT", 10, -yOffset)
    yOffset = yOffset + HEADER_SPACING
end

if inventoryExpanded and not (storageSearchText and storageSearchText ~= "" and not categoriesWithMatches["inventory"]) then
    for charKey, charData in pairs(self.db.global.characters or {}) do
        if charData.inventory and charData.inventory.items then
            local charCategoryKey = "inventory_" .. charKey

            -- Skip character if search active and no matches
            if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches[charCategoryKey] then
                -- Skip
            else
                local charName, charRealm = charKey:match("^(.-)%-(.+)$")
                if not charName then
                    charName = charKey
                    charRealm = "Unknown"
                end

                local isCharExpanded = expanded.categories[charCategoryKey]
                if storageSearchText and storageSearchText ~= "" and categoriesWithMatches[charCategoryKey] then
                    isCharExpanded = true
                end

                local charIcon = "Interface\\Icons\\Achievement_Character_Human_Male"
                if charData.classFile then
                    charIcon = "Interface\\Icons\\ClassIcon_" .. charData.classFile
                end

                local displayName = (FormatCharacterNameRealm and FormatCharacterNameRealm(charName, charRealm, charData.classFile))
                    or string.format("%s-%s", charName or "Unknown", charRealm or "Unknown")

                local charHeader = CreateCollapsibleHeader(
                    parent,
                    displayName,
                    charCategoryKey,
                    isCharExpanded,
                    function(isExpanded) ToggleExpand(charCategoryKey, isExpanded) end,
                    charIcon
                )
                charHeader:SetPoint("TOPLEFT", 10 + indent, -yOffset)
                charHeader:SetWidth(width - indent)
                yOffset = yOffset + HEADER_SPACING

                if isCharExpanded then
                    -- Group inventory items by type
                    local invItemsByType = {}
                    for _, bagData in pairs(charData.inventory.items) do
                        for _, item in pairs(bagData) do
                            if item and item.itemID then
                                local classID = item.classID or GetItemClassID(item.itemID)
                                local typeName = GetItemTypeName(classID)
                                if not invItemsByType[typeName] then
                                    invItemsByType[typeName] = {}
                                end
                                if not item.classID then
                                    item.classID = classID
                                end
                                table.insert(invItemsByType[typeName], item)
                            end
                        end
                    end

                    local sortedTypes = {}
                    for typeName in pairs(invItemsByType) do
                        table.insert(sortedTypes, typeName)
                    end
                    table.sort(sortedTypes)

                    for _, typeName in ipairs(sortedTypes) do
                        local typeKey = charCategoryKey .. "_" .. typeName

                        if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches[typeKey] then
                            -- skip
                        else
                            local isTypeExpanded = expanded.categories[typeKey]
                            if storageSearchText and storageSearchText ~= "" and categoriesWithMatches[typeKey] then
                                isTypeExpanded = true
                            end

                            local matchCount = 0
                            for _, item in ipairs(invItemsByType[typeName]) do
                                if ItemMatchesSearch(item) then
                                    matchCount = matchCount + 1
                                end
                            end

                            local typeIcon = nil
                            if invItemsByType[typeName][1] and invItemsByType[typeName][1].classID then
                                typeIcon = GetTypeIcon(invItemsByType[typeName][1].classID)
                            end

                            local displayCount = (storageSearchText and storageSearchText ~= "") and matchCount or #invItemsByType[typeName]
                            local typeHeader = CreateCollapsibleHeader(
                                parent,
                                typeName .. " (" .. displayCount .. ")",
                                typeKey,
                                isTypeExpanded,
                                function(isExpanded) ToggleExpand(typeKey, isExpanded) end,
                                typeIcon
                            )
                            typeHeader:SetPoint("TOPLEFT", 10 + indent * 2, -yOffset)
                            typeHeader:SetWidth(width - indent * 2)
                            yOffset = yOffset + HEADER_SPACING

                            if isTypeExpanded then
                                local rowIdx = 0
                                for _, item in ipairs(invItemsByType[typeName]) do
                                    if ItemMatchesSearch(item) then
                                        rowIdx = rowIdx + 1
                                        local i = rowIdx

                                        
local itemRow = CreateFrame("Button", nil, parent, "BackdropTemplate")
                                        itemRow:SetSize(width - indent * 2, ROW_HEIGHT)
                                        itemRow:SetPoint("TOPLEFT", 10 + indent * 2, -yOffset)
                                        itemRow:SetBackdrop({ bgFile = "Interface\BUTTONS\WHITE8X8" })
                                        itemRow:SetBackdropColor(i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.09 or 0.06, 1)

                                        local qtyText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                                        qtyText:SetPoint("LEFT", 15, 0)
                                        qtyText:SetWidth(45)
                                        qtyText:SetJustifyH("RIGHT")
                                        qtyText:SetText(format("|cffffff00%d|r", item.stackCount or 1))

                                        local icon = itemRow:CreateTexture(nil, "ARTWORK")
                                        icon:SetSize(22, 22)
                                        icon:SetPoint("LEFT", 70, 0)
                                        icon:SetTexture(item.iconFileID or 134400)

                                        local nameText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                                        nameText:SetPoint("LEFT", 98, 0)
                                        nameText:SetJustifyH("LEFT")
                                        nameText:SetWordWrap(false)
                                        nameText:SetWidth(width - indent * 2 - 200)

                                        _TQ_StorageResolveItemInfo(item)


                                        local baseName = item.name or format("Item %s", tostring(item.itemID or "?"))
                                        local displayName = TheQuartermaster:GetItemDisplayName(item.itemID, baseName, item.classID)
                                        nameText:SetText(format("|cff%s%s|r", GetQualityHex(item.quality or 1), displayName))

                                        local locationText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                                        locationText:SetPoint("RIGHT", -10, 0)
                                        locationText:SetWidth(90)
                                        locationText:SetJustifyH("RIGHT")
                                        locationText:SetText(item.location or "")
                                        locationText:SetTextColor(0.5, 0.5, 0.5)

                                        itemRow:SetScript("OnEnter", function(self)
                                            self:SetBackdropColor(0.15, 0.15, 0.20, 1)
                                            if item.itemLink then
                                                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                                                GameTooltip:SetHyperlink(item.itemLink)
                                                GameTooltip:Show()
                                            elseif item.itemID then
                                                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                                                GameTooltip:SetItemByID(item.itemID)
                                                GameTooltip:Show()
                                            end
                                        end)
                                        itemRow:SetScript("OnLeave", function(self)
                                            self:SetBackdropColor(i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.09 or 0.06, 1)
                                            GameTooltip:Hide()
                                        end)

                                        yOffset = yOffset + ROW_SPACING
                                    end
                                end

                                yOffset = yOffset + SECTION_SPACING
                            end
                        end
                    end
                end
            end
        end
    end
end

    yOffset = yOffset + 10

    -- ===== WARBAND BANK SECTION =====
    -- Auto-expand if search has matches in this section
    local warbandExpanded = expanded.warband
    if storageSearchText and storageSearchText ~= "" and categoriesWithMatches["warband"] then
        warbandExpanded = true
    end
    
    -- Skip section entirely if search active and no matches
    if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches["warband"] then
        -- Skip this section
    else
        local warbandHeader, warbandBtn = CreateCollapsibleHeader(
            parent,
            "Warband Bank",
            "warband",
            warbandExpanded,
            function(isExpanded) ToggleExpand("warband", isExpanded) end,
            "Interface\\Icons\\INV_Misc_Bag_36"
        )
        warbandHeader:SetPoint("TOPLEFT", 10, -yOffset)
        yOffset = yOffset + HEADER_SPACING
    end
    
    if warbandExpanded and not (storageSearchText and storageSearchText ~= "" and not categoriesWithMatches["warband"]) then
        -- Group warband items by type
        local warbandItems = {}
        local warbandBankData = self.db.global.warbandBank and self.db.global.warbandBank.items or {}
        
        for bagID, bagData in pairs(warbandBankData) do
            for slotID, item in pairs(bagData) do
                if item.itemID then
                    -- Use stored classID or get it from API
                    local classID = item.classID or GetItemClassID(item.itemID)
                    local typeName = GetItemTypeName(classID)
                    
                    if not warbandItems[typeName] then
                        warbandItems[typeName] = {}
                    end
                    -- Store classID in item for icon lookup
                    if not item.classID then
                        item.classID = classID
                    end
                    table.insert(warbandItems[typeName], item)
                end
            end
        end
        
        -- Sort types alphabetically
        local sortedTypes = {}
        for typeName in pairs(warbandItems) do
            table.insert(sortedTypes, typeName)
        end
        table.sort(sortedTypes)
        
        -- Draw each type category
        for _, typeName in ipairs(sortedTypes) do
            local categoryKey = "warband_" .. typeName
            
            -- Skip category if search active and no matches
            if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches[categoryKey] then
                -- Skip this category
            else
                -- Auto-expand if search has matches in this category
                local isTypeExpanded = expanded.categories[categoryKey]
                if storageSearchText and storageSearchText ~= "" and categoriesWithMatches[categoryKey] then
                    isTypeExpanded = true
                end
                
                -- Count items that match search (for display)
                local matchCount = 0
                for _, item in ipairs(warbandItems[typeName]) do
                    if ItemMatchesSearch(item) then
                        matchCount = matchCount + 1
                    end
                end
                
                -- Get icon from first item in category
                local typeIcon = nil
                if warbandItems[typeName][1] and warbandItems[typeName][1].classID then
                    typeIcon = GetTypeIcon(warbandItems[typeName][1].classID)
                end
                
                -- Type header (indented) - show match count if searching
                local displayCount = (storageSearchText and storageSearchText ~= "") and matchCount or #warbandItems[typeName]
                local typeHeader, typeBtn = CreateCollapsibleHeader(
                    parent,
                    typeName .. " (" .. displayCount .. ")",
                    categoryKey,
                    isTypeExpanded,
                    function(isExpanded) ToggleExpand(categoryKey, isExpanded) end,
                    typeIcon
                )
                typeHeader:SetPoint("TOPLEFT", 10 + indent, -yOffset)
                typeHeader:SetWidth(width - indent)
                yOffset = yOffset + HEADER_SPACING
                
                if isTypeExpanded then
                    -- Display items in this category (with search filter)
                    local rowIdx = 0
                    for _, item in ipairs(warbandItems[typeName]) do
                        -- Apply search filter
                        local shouldShow = ItemMatchesSearch(item)
                        
                        if shouldShow then
                            rowIdx = rowIdx + 1
                            local i = rowIdx
                            
                            -- Items tab style row
                            local itemRow = CreateFrame("Button", nil, parent, "BackdropTemplate")
                            itemRow:SetSize(width - indent, ROW_HEIGHT)
                            itemRow:SetPoint("TOPLEFT", 10 + indent, -yOffset)
                            itemRow:SetBackdrop({
                                bgFile = "Interface\\BUTTONS\\WHITE8X8",
                            })
                            -- Alternating row colors (Items style)
                            itemRow:SetBackdropColor(i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.09 or 0.06, 1)
                            
                            -- Quantity (left side, Items style)
                            local qtyText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                            qtyText:SetPoint("LEFT", 15, 0)
                            qtyText:SetWidth(45)
                            qtyText:SetJustifyH("RIGHT")
                            qtyText:SetText(format("|cffffff00%d|r", item.stackCount or 1))
                            
                            -- Icon
                            local icon = itemRow:CreateTexture(nil, "ARTWORK")
                            icon:SetSize(22, 22)
                            icon:SetPoint("LEFT", 70, 0)
                            icon:SetTexture(item.iconFileID or 134400)
                            
                            -- Name (with pet cage handling and quality color, Items style)
                            local nameText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                            nameText:SetPoint("LEFT", 98, 0)
                            nameText:SetJustifyH("LEFT")
                            nameText:SetWordWrap(false)
                            nameText:SetWidth(width - indent - 200)
                            _TQ_StorageResolveItemInfo(item)

                            local baseName = item.name or format("Item %s", tostring(item.itemID or "?"))
                            local displayName = TheQuartermaster:GetItemDisplayName(item.itemID, baseName, item.classID)
                            nameText:SetText(format("|cff%s%s|r", GetQualityHex(item.quality), displayName))
                            
                            -- Location (right side, Items style)
                            local locationText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            locationText:SetPoint("RIGHT", -10, 0)
                            locationText:SetWidth(60)
                            locationText:SetJustifyH("RIGHT")
                            local locText = item.tabIndex and format("Tab %d", item.tabIndex) or ""
                            locationText:SetText(locText)
                            locationText:SetTextColor(0.5, 0.5, 0.5)
                            
                            -- Tooltip support (Items style)
                            itemRow:SetScript("OnEnter", function(self)
                                self:SetBackdropColor(0.15, 0.15, 0.20, 1)
                                if item.itemLink then
                                    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                                    GameTooltip:SetHyperlink(item.itemLink)
                                    GameTooltip:Show()
                                elseif item.itemID then
                                    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                                    GameTooltip:SetItemByID(item.itemID)
                                    GameTooltip:Show()
                                end
                            end)
                            itemRow:SetScript("OnLeave", function(self)
                                self:SetBackdropColor(i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.09 or 0.06, 1)
                                GameTooltip:Hide()
                            end)
                            
                            yOffset = yOffset + ROW_SPACING
                        end
                    end
                end
            end
        end
        
        if #sortedTypes == 0 then
            local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            emptyText:SetPoint("TOPLEFT", 10 + indent, -yOffset)
            emptyText:SetTextColor(0.5, 0.5, 0.5)
            emptyText:SetText(L["NO_ITEMS_IN_WARBAND_BANK"])
            yOffset = yOffset + SECTION_SPACING
        end
    end
    
    yOffset = yOffset + 10
    
    -- ===== PERSONAL BANKS SECTION =====
    -- Auto-expand if search has matches in this section
    local personalExpanded = expanded.personal
    if storageSearchText and storageSearchText ~= "" and categoriesWithMatches["personal"] then
        personalExpanded = true
    end
    
    -- Skip section entirely if search active and no matches
    if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches["personal"] then
        -- Skip this section
    else
        local personalHeader, personalBtn = CreateCollapsibleHeader(
            parent,
            "Personal Banks",
            "personal",
            personalExpanded,
            function(isExpanded) ToggleExpand("personal", isExpanded) end,
            "Interface\\Icons\\Achievement_Character_Human_Male"
        )
        personalHeader:SetPoint("TOPLEFT", 10, -yOffset)
        yOffset = yOffset + HEADER_SPACING
    end
    
    if personalExpanded and not (storageSearchText and storageSearchText ~= "" and not categoriesWithMatches["personal"]) then

        
for charKey, charData in pairs(self.db.global.characters or {}) do
            if charData.personalBank then
                local charName, charRealm = charKey:match("^(.-)%-(.+)$")
                if not charName then
                    charName = charKey
                    charRealm = "Unknown"
                end
                local charCategoryKey = "personal_" .. charKey
                
                -- Skip character if search active and no matches
                if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches[charCategoryKey] then
                    -- Skip this character
                else
                    -- Auto-expand if search has matches for this character
                    local isCharExpanded = expanded.categories[charCategoryKey]
                    if storageSearchText and storageSearchText ~= "" and categoriesWithMatches[charCategoryKey] then
                        isCharExpanded = true
                    end
                    
                    -- Get character class icon
                    local charIcon = "Interface\\Icons\\Achievement_Character_Human_Male"  -- Default
                    if charData.classFile then
                        charIcon = "Interface\\Icons\\ClassIcon_" .. charData.classFile
                    end
                    
                    -- Character header (indented)
                    local displayName = (FormatCharacterNameRealm and FormatCharacterNameRealm(charName, charRealm, charData.classFile))
                        or string.format("%s-%s", charName or "Unknown", charRealm or "Unknown")

                    local charHeader, charBtn = CreateCollapsibleHeader(
                        parent,
                        displayName,
                        charCategoryKey,
                        isCharExpanded,
                        function(isExpanded) ToggleExpand(charCategoryKey, isExpanded) end,
                        charIcon
                    )
                    charHeader:SetPoint("TOPLEFT", 10 + indent, -yOffset)
                    charHeader:SetWidth(width - indent)
                    yOffset = yOffset + HEADER_SPACING
                    
                    if isCharExpanded then
                    -- Group character's items by type
                    local charItems = {}
                    for bagID, bagData in pairs(charData.personalBank) do
                        for slotID, item in pairs(bagData) do
                            if item.itemID then
                                -- Use stored classID or get it from API
                                local classID = item.classID or GetItemClassID(item.itemID)
                                local typeName = GetItemTypeName(classID)
                                
                                if not charItems[typeName] then
                                    charItems[typeName] = {}
                                end
                                -- Store classID in item for icon lookup
                                if not item.classID then
                                    item.classID = classID
                                end
                                table.insert(charItems[typeName], item)
                            end
                        end
                    end
                    
                    -- Sort types
                    local charSortedTypes = {}
                    for typeName in pairs(charItems) do
                        table.insert(charSortedTypes, typeName)
                    end
                    table.sort(charSortedTypes)
                    
                    -- Draw each type category for this character
                    for _, typeName in ipairs(charSortedTypes) do
                        local typeKey = "personal_" .. charKey .. "_" .. typeName
                        
                        -- Skip category if search active and no matches
                        if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches[typeKey] then
                            -- Skip this category
                        else
                            -- Auto-expand if search has matches in this category
                            local isTypeExpanded = expanded.categories[typeKey]
                            if storageSearchText and storageSearchText ~= "" and categoriesWithMatches[typeKey] then
                                isTypeExpanded = true
                            end
                            
                            -- Count items that match search (for display)
                            local matchCount = 0
                            for _, item in ipairs(charItems[typeName]) do
                                if ItemMatchesSearch(item) then
                                    matchCount = matchCount + 1
                                end
                            end
                            
                            -- Get icon from first item in category
                            local typeIcon2 = nil
                            if charItems[typeName][1] and charItems[typeName][1].classID then
                                typeIcon2 = GetTypeIcon(charItems[typeName][1].classID)
                            end
                            
                            -- Type header (double indented) - show match count if searching
                            local displayCount = (storageSearchText and storageSearchText ~= "") and matchCount or #charItems[typeName]
                            local typeHeader2, typeBtn2 = CreateCollapsibleHeader(
                                parent,
                                typeName .. " (" .. displayCount .. ")",
                                typeKey,
                                isTypeExpanded,
                                function(isExpanded) ToggleExpand(typeKey, isExpanded) end,
                                typeIcon2
                            )
                            typeHeader2:SetPoint("TOPLEFT", 10 + indent * 2, -yOffset)
                            typeHeader2:SetWidth(width - indent * 2)
                            yOffset = yOffset + HEADER_SPACING
                            
                            if isTypeExpanded then
                                -- Display items (with search filter)
                                local rowIdx = 0
                                for _, item in ipairs(charItems[typeName]) do
                                    -- Apply search filter
                                    local shouldShow = ItemMatchesSearch(item)
                                    
                                    if shouldShow then
                                        rowIdx = rowIdx + 1
                                        local i = rowIdx
                                        
                                        -- Items tab style row
                                        local itemRow = CreateFrame("Button", nil, parent, "BackdropTemplate")
                                        itemRow:SetSize(width - indent * 2, ROW_HEIGHT)
                                        itemRow:SetPoint("TOPLEFT", 10 + indent * 2, -yOffset)
                                        itemRow:SetBackdrop({
                                            bgFile = "Interface\\BUTTONS\\WHITE8X8",
                                        })
                                        -- Alternating row colors (Items style)
                                        itemRow:SetBackdropColor(i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.09 or 0.06, 1)
                                        
                                        -- Quantity (left side, Items style)
                                        local qtyText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                                        qtyText:SetPoint("LEFT", 15, 0)
                                        qtyText:SetWidth(45)
                                        qtyText:SetJustifyH("RIGHT")
                                        qtyText:SetText(format("|cffffff00%d|r", item.stackCount or 1))
                                        
                                        -- Icon
                                        local icon = itemRow:CreateTexture(nil, "ARTWORK")
                                        icon:SetSize(22, 22)
                                        icon:SetPoint("LEFT", 70, 0)
                                        icon:SetTexture(item.iconFileID or 134400)
                                        
                                        -- Name (with pet cage handling and quality color, Items style)
                                        local nameText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                                        nameText:SetPoint("LEFT", 98, 0)
                                        nameText:SetJustifyH("LEFT")
                                        nameText:SetWordWrap(false)
                                        nameText:SetWidth(width - indent * 2 - 200)
                                        _TQ_StorageResolveItemInfo(item)

                                        local baseName = item.name or format("Item %s", tostring(item.itemID or "?"))
                                        local displayName = TheQuartermaster:GetItemDisplayName(item.itemID, baseName, item.classID)
                                        nameText:SetText(format("|cff%s%s|r", GetQualityHex(item.quality), displayName))
                                        
                                        -- Location (right side, Items style)
                                        local locationText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                                        locationText:SetPoint("RIGHT", -10, 0)
                                        locationText:SetWidth(60)
                                        locationText:SetJustifyH("RIGHT")
                                        local locText = item.bagIndex and format("Bag %d", item.bagIndex) or ""
                                        locationText:SetText(locText)
                                        locationText:SetTextColor(0.5, 0.5, 0.5)
                                        
                                        -- Tooltip support (Items style)
                                        itemRow:SetScript("OnEnter", function(self)
                                            self:SetBackdropColor(0.15, 0.15, 0.20, 1)
                                            if item.itemLink then
                                                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                                                GameTooltip:SetHyperlink(item.itemLink)
                                                GameTooltip:Show()
                                            elseif item.itemID then
                                                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                                                GameTooltip:SetItemByID(item.itemID)
                                                GameTooltip:Show()
                                            end
                                        end)
                                        itemRow:SetScript("OnLeave", function(self)
                                            self:SetBackdropColor(i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.09 or 0.06, 1)
                                            GameTooltip:Hide()
                                        end)
                                        
                                        yOffset = yOffset + ROW_SPACING
                                    end
                                end
                            end
                        end
                    end
                    
                    if #charSortedTypes == 0 then
                        local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        emptyText:SetPoint("TOPLEFT", 10 + indent * 2, -yOffset)
                        emptyText:SetTextColor(0.5, 0.5, 0.5)
                        emptyText:SetText(L["NO_ITEMS_IN_PERSONAL_BANK"])
                        yOffset = yOffset + SECTION_SPACING
                    end
                    end
                end
            end
        end
    end
    
    

    yOffset = yOffset + 10

    -- ===== GUILD BANKS SECTION =====
    -- Auto-expand if search has matches in this section
    local guildBanksExpanded = expanded.guildbanks
    if storageSearchText and storageSearchText ~= "" and categoriesWithMatches["guildbanks"] then
        guildBanksExpanded = true
    end

    -- Skip section entirely if search active and no matches
    if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches["guildbanks"] then
        -- Skip this section
    else
        local guildBanksHeader, guildBanksBtn = CreateCollapsibleHeader(
            parent,
            "Guild Banks",
            "guildbanks",
            guildBanksExpanded,
            function(isExpanded) ToggleExpand("guildbanks", isExpanded) end,
            "Interface\\Icons\\INV_Misc_Note_02"
        )
        guildBanksHeader:SetPoint("TOPLEFT", 10, -yOffset)
        yOffset = yOffset + HEADER_SPACING
    end

    if guildBanksExpanded and not (storageSearchText and storageSearchText ~= "" and not categoriesWithMatches["guildbanks"]) then

        local allGuildBanks = self.db.global.guildBank or {}
        local guildNames = {}
        for gName, gData in pairs(allGuildBanks) do
            if gData and gData.tabs then
                table.insert(guildNames, gName)
            end
        end
        table.sort(guildNames)

        if #guildNames == 0 then
            local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            emptyText:SetPoint("TOPLEFT", 10 + indent, -yOffset)
            emptyText:SetTextColor(0.5, 0.5, 0.5)
            emptyText:SetText(L["NO_GUILD_BANKS_CACHED"] or "No cached guild banks.")
            yOffset = yOffset + SECTION_SPACING
        else
            for _, guildName in ipairs(guildNames) do
                local guildKey = "guildbanks_" .. tostring(guildName)

                -- Skip guild if search active and no matches
                if not (storageSearchText and storageSearchText ~= "" and not categoriesWithMatches[guildKey]) then
                    local isGuildExpanded = expanded.categories[guildKey]
                    if storageSearchText and storageSearchText ~= "" and categoriesWithMatches[guildKey] then
                        isGuildExpanded = true
                    end

                    local guildHeader = CreateCollapsibleHeader(
                        parent,
                        tostring(guildName),
                        guildKey,
                        isGuildExpanded,
                        function(isExpanded) ToggleExpand(guildKey, isExpanded) end,
                        "Interface\\Icons\\INV_Misc_Book_09"
                    )
                    guildHeader:SetPoint("TOPLEFT", 10 + indent, -yOffset)
                    guildHeader:SetWidth(width - indent)
                    yOffset = yOffset + HEADER_SPACING

                    if isGuildExpanded then
                        local guildData = allGuildBanks[guildName]
                        local guildItems = {}

                        if guildData and guildData.tabs then
                            for tabIndex, tabData in pairs(guildData.tabs) do
                                if tabData and tabData.items then
                                    for slotID, item in pairs(tabData.items) do
                                        if item and item.itemID then
                                            table.insert(guildItems, item)
                                        end
                                    end
                                end
                            end
                        end

                        -- Group by type
                        local itemsByType = {}
                        for _, item in ipairs(guildItems) do
                            if not storageSearchText or storageSearchText == "" or ItemMatchesSearch(item) then
                                local classID = item.classID or GetItemClassID(item.itemID)
                                local typeName = GetItemTypeName(classID)
                                itemsByType[typeName] = itemsByType[typeName] or {}
                                table.insert(itemsByType[typeName], item)
                            end
                        end

                        local typeNames = {}
                        for typeName in pairs(itemsByType) do
                            table.insert(typeNames, typeName)
                        end
                        table.sort(typeNames)

                        if #typeNames == 0 then
                            local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                            emptyText:SetPoint("TOPLEFT", 10 + indent * 2, -yOffset)
                            emptyText:SetTextColor(0.5, 0.5, 0.5)
                            emptyText:SetText(L["NO_ITEMS_IN_GUILD_BANK"] or "No items found.")
                            yOffset = yOffset + SECTION_SPACING
                        else
                            for _, typeName in ipairs(typeNames) do
                                local typeKey = guildKey .. "_" .. typeName

                                -- Skip type if search active and no matches
                                if not (storageSearchText and storageSearchText ~= "" and not categoriesWithMatches[typeKey]) then
                                    local isTypeExpanded = expanded.categories[typeKey]
                                    if storageSearchText and storageSearchText ~= "" and categoriesWithMatches[typeKey] then
                                        isTypeExpanded = true
                                    end

                                    local typeHeader = CreateCollapsibleHeader(
                                        parent,
                                        typeName,
                                        typeKey,
                                        isTypeExpanded,
                                        function(isExpanded) ToggleExpand(typeKey, isExpanded) end,
                                        GetTypeIcon(typeName)
                                    )
                                    typeHeader:SetPoint("TOPLEFT", 10 + indent * 2, -yOffset)
                                    typeHeader:SetWidth(width - indent * 2)
                                    yOffset = yOffset + HEADER_SPACING

                                    if isTypeExpanded then
                                        local typeItems = itemsByType[typeName] or {}
                                        local rowIdx = 0
                                        -- Avoid relying on C_Item.GetItemNameByID here (can be nil/tainted depending on load state)
                                        table.sort(typeItems, function(a, b)
                                            local aName = a.name or (a.itemID and ("Item " .. tostring(a.itemID))) or ""
                                            local bName = b.name or (b.itemID and ("Item " .. tostring(b.itemID))) or ""
                                            return aName < bName
                                        end)

                                        for _, item in ipairs(typeItems) do
                                            rowIdx = (rowIdx or 0) + 1
                                            DrawStorageItemRow(parent, item, width - indent * 3, 10 + indent * 3, yOffset, rowIdx)
                                            yOffset = yOffset + ROW_HEIGHT
                                        end

                                        yOffset = yOffset + SECTION_SPACING
                                    end
                                end
                            end
                        end

                        yOffset = yOffset + SECTION_SPACING
                    end
                end
            end
        end

    end


return yOffset + 20
end