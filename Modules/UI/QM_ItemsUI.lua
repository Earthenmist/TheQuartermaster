--[[
    The Quartermaster - Items Tab
    Display and manage Warband and Personal bank items with interactive controls
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster


local QM_CopyItemLinkToChat
local QM_SearchForItem

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
        QM_OpenRowMenu_DROPDOWN = CreateFrame("Frame", "QM_RowContextMenuDrop", UIParent, "UIDropDownMenuTemplate")
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

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Feature Flags
local ENABLE_GUILD_BANK = ns.ENABLE_GUILD_BANK

-- Import shared UI components (always get fresh reference)
local function GetCOLORS()
    return ns.UI_COLORS
end
local GetQualityHex = ns.UI_GetQualityHex
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local GetTypeIcon = ns.UI_GetTypeIcon
local DrawEmptyState = ns.UI_DrawEmptyState
local AcquireItemRow = ns.UI_AcquireItemRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren

-- Context menu helper (right-click rows)
local function QM_ShowItemWatchlistMenu(itemID)
    itemID = tonumber(itemID)
    if not itemID then return end

    local pinned = TheQuartermaster:IsWatchlistedItem(itemID)
    local menu = {
            {
                text = pinned and "Unpin from Watchlist" or "Pin to Watchlist",
                func = function() TheQuartermaster:ToggleWatchlistItem(itemID) end,
            },
            {
                text = "Copy Item Link",
                func = function()
                    local link = select(2, GetItemInfo(itemID))
                    QM_CopyItemLinkToChat(link)
                end,
            },
            {
                text = "Search this item",
                func = function()
                    local name = (GetItemInfo(itemID))
                    QM_SearchForItem(name, itemID)
                end,
            },
        }

    QM_OpenRowMenu(menu, UIParent)
end

QM_CopyItemLinkToChat = function(itemLink)
    if not itemLink then return end
    -- Put link into chat edit box so user can Ctrl+C
    if ChatFrame_OpenChat then
        ChatFrame_OpenChat(itemLink)
    else
        local editBox = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
        if editBox then
            editBox:Insert(itemLink)
        end
    end
end


QM_SearchForItem = function(itemName, itemID)
    local f = TheQuartermaster.UI and TheQuartermaster.UI.mainFrame
    if not f then return end

    -- Switch to Search tab (tab system uses currentTab)
    f.currentTab = "search"

    local query = itemName
    if (not query or query == "") and itemID then
        query = (GetItemInfo(itemID))
    end
    query = query or ""

    if ns then
        ns.globalSearchText = query
        ns.globalSearchMode = ns.globalSearchMode or "all"
    end

    if f.searchBox and f.searchBox.SetText then
        f.searchBox:SetText(query)
        if f.searchBox.SetFocus then f.searchBox:SetFocus() end
    end

    TheQuartermaster:PopulateContent()
    f:Show()
end

    -- Switch to Search tab
    if f.ShowTab then
        f:ShowTab("search")
    end

    local query = itemName
    if (not query or query == "") and itemID then
        query = (GetItemInfo(itemID))
    end
    query = query or ""

    -- Set search box + global value
    if ns then
        ns.globalSearchText = query
    end
    if f.searchBox and f.searchBox.SetText then
        f.searchBox:SetText(query)
        if f.searchBox.SetFocus then f.searchBox:SetFocus() end
    end

    if TheQuartermaster.RefreshUI then
        TheQuartermaster:RefreshUI()
    elseif f.PopulateContent then
        f:PopulateContent()
    end
end



-- Money formatting helper (lazy-resolved to avoid load-order issues)
local function FormatMoney(amount)
    local addon = ns and ns.TheQuartermaster
    if addon and addon.db and addon.db.profile and addon.db.profile.discretionMode then
        return "|cff9aa0a6Hidden|r"
    end

    local fn = ns and ns.UI_FormatGold
    if type(fn) == "function" then
        return fn(amount)
    end
    if type(GetCoinTextureString) == "function" then
        return GetCoinTextureString(tonumber(amount) or 0)
    end
    return tostring(tonumber(amount) or 0)
end


-- ==============================
-- Item info resolution helpers
-- (fixes "Item ####" names until item data is cached client-side)
-- ==============================
local _tq_pendingInfoRefresh = false
local function _TQ_QueueInfoRefresh()
    if _tq_pendingInfoRefresh then return end
    _tq_pendingInfoRefresh = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.25, function()
            _tq_pendingInfoRefresh = false
            if TheQuartermaster and TheQuartermaster.RefreshUI then
                TheQuartermaster:RefreshUI()
            end
        end)
    else
        _tq_pendingInfoRefresh = false
    end
end

local function _TQ_ResolveItemInfo(item)
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
        _TQ_QueueInfoRefresh()
    end

    if (not item.iconFileID) and type(GetItemInfoInstant) == "function" then
        local _, _, _, _, iconFileID, cID, scID = GetItemInfoInstant(itemID)
        item.iconFileID = iconFileID or item.iconFileID
        item.classID = item.classID or cID
        item.subclassID = item.subclassID or scID
    end
end


-- Import shared UI layout constants
local UI_LAYOUT = ns.UI_LAYOUT
local ROW_HEIGHT = UI_LAYOUT.ROW_HEIGHT
local ROW_SPACING = UI_LAYOUT.ROW_SPACING
local HEADER_SPACING = UI_LAYOUT.HEADER_SPACING

-- Performance: Local function references
local format = string.format
local date = date

--============================================================================
-- PERSONAL BANK SLOT/TAB VIEW
--============================================================================

local function MatchesSearch(item, searchText)
    if not searchText or searchText == "" then return true end
    local s = tostring(searchText):lower()
    local name = tostring(item and item.name or ""):lower()
    local link = tostring(item and item.itemLink or ""):lower()
    return (name:find(s, 1, true) ~= nil) or (link:find(s, 1, true) ~= nil)
end


-- Best-effort enrichment for items that were scanned before item data fully loaded.
-- This prevents rows showing as "Item 12345" and being mis-grouped into Misc.
local QUALITY_FROM_COLOR = {
    ["9d9d9d"] = 0, -- poor
    ["ffffff"] = 1, -- common
    ["1eff00"] = 2, -- uncommon
    ["0070dd"] = 3, -- rare
    ["a335ee"] = 4, -- epic
    ["ff8000"] = 5, -- legendary
    ["e6cc80"] = 6, -- artifact
    ["00ccff"] = 7, -- heirloom
}

local function EnrichItemInPlace(item)
    if not item then return end

    local itemID = tonumber(item.itemID)
    local link = item.itemLink

    -- icon / class info (available instantly even if full item data isn't cached)
    if itemID and (not item.classID or not item.subclassID or not item.iconFileID) and type(GetItemInfoInstant) == "function" then
        local _, _, _, _, iconFileID, classID, subclassID = GetItemInfoInstant(itemID)
        item.iconFileID = item.iconFileID or iconFileID
        item.classID = item.classID or classID
        item.subclassID = item.subclassID or subclassID
    end

    -- type/subtype from class IDs (doesn't require cached GetItemInfo)
    if (not item.itemType or item.itemType == "") and item.classID and type(GetItemClassInfo) == "function" then
        item.itemType = GetItemClassInfo(item.classID) or item.itemType
    end
    if (not item.itemSubType or item.itemSubType == "") and item.classID and item.subclassID and type(GetItemSubClassInfo) == "function" then
        item.itemSubType = GetItemSubClassInfo(item.classID, item.subclassID) or item.itemSubType
    end

    -- quality (prefer stored value; otherwise derive from link color or C_Item helper)
    if item.quality == nil and link then
        local color = link:match("|c%x%x(%x%x%x%x%x%x)%x%x%x%x") or link:match("|c%x%x%x%x(%x%x%x%x%x%x)")
        if color then
            color = color:lower()
            item.quality = QUALITY_FROM_COLOR[color]
        end
    end
    if item.quality == nil and itemID and C_Item and C_Item.GetItemQualityByID then
        item.quality = C_Item.GetItemQualityByID(itemID)
    end
    if item.quality == nil then
        item.quality = 1 -- default to common (white) instead of poor-grey
    end

    -- name
    if (not item.name or item.name == "") and link then
        local n = link:match("%[(.-)%]")
        if n and n ~= "" then item.name = n end
    end
    if (not item.name or item.name == "") and itemID and type(GetItemInfo) == "function" then
        local n = GetItemInfo(itemID)
        if n and n ~= "" then item.name = n end
    end

    -- request async load if needed
    if itemID and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

local function DrawPersonalBankSlotView(self, parent, yOffset, width, itemsSearchText)
    local COLORS = GetCOLORS()

    local pb = self.db and self.db.char and self.db.char.personalBank or nil
    local bagSizes = pb and pb.bagSizes or {}
    local bagItems = pb and pb.items or {}

    -- Personal Bank Slot View shows the purchased bank bags only.
    -- (We intentionally do NOT include the base "Bank" container here; this avoids
    -- an empty "Bank" tab on some clients and matches the cached data layout.)
    local firstVisibleTab = 1
    local maxTab = #ns.PERSONAL_BANK_BAGS

    local tabIndex = (self.db and self.db.profile and self.db.profile.personalBankSlotTab) or firstVisibleTab
    if tabIndex < firstVisibleTab then tabIndex = firstVisibleTab end
    if tabIndex > maxTab then tabIndex = maxTab end
    if self.db and self.db.profile then
        self.db.profile.personalBankSlotTab = tabIndex
    end

    -- Sub-tabs for bank bags
    local bagTabBar = CreateFrame("Frame", nil, parent)
    bagTabBar:SetSize(width, 28)
    bagTabBar:SetPoint("TOPLEFT", 8, -yOffset)

    local btnW = 70
    local btnH = 22
    local spacing = 6
    local maxCols = math.max(1, math.floor((width + spacing) / (btnW + spacing)))

    local visibleCount = maxTab - firstVisibleTab + 1
    for displayIndex = 1, visibleCount do
        local i = firstVisibleTab + (displayIndex - 1)

        local row = math.floor((displayIndex - 1) / maxCols)
        local col = (displayIndex - 1) % maxCols

        local btn = CreateFrame("Button", nil, bagTabBar, "BackdropTemplate")
        btn:SetSize(btnW, btnH)
        btn:SetPoint("TOPLEFT", col * (btnW + spacing), -row * (btnH + spacing))
        btn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })

        local active = (i == tabIndex)
        local bg = active and COLORS.tabActive or COLORS.tabInactive
        btn:SetBackdropColor(bg[1], bg[2], bg[3], 1)
        if active then
            btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
        else
            btn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
        end

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER")
        label:SetText("Bag " .. i)
        label:SetTextColor(1, 1, 1, active and 0.95 or 0.8)

        btn:SetScript("OnClick", function()
            self.db.profile.personalBankSlotTab = i
            self:RefreshUI()
        end)
        btn:SetScript("OnEnter", function(b)
            b:SetBackdropColor(COLORS.tabHover[1], COLORS.tabHover[2], COLORS.tabHover[3], 1)
            b:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
        end)
        btn:SetScript("OnLeave", function(b)
            local a = (self.db.profile.personalBankSlotTab == i)
            local c = a and COLORS.tabActive or COLORS.tabInactive
            b:SetBackdropColor(c[1], c[2], c[3], 1)
            if a then
                b:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
            else
                b:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
            end
        end)
    end

    -- Compute tabbar height (rows)
    local tabRows = math.ceil(visibleCount / maxCols)
    local tabBarHeight = (tabRows * btnH) + ((tabRows - 1) * spacing)
    yOffset = yOffset + tabBarHeight + 12

    local numSlots = tonumber(bagSizes and bagSizes[tabIndex]) or 0
    if numSlots <= 0 then
        -- No cached slot size yet (usually means the bank hasn't been scanned on this character)
        local msg = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        msg:SetPoint("TOPLEFT", 18, -yOffset)
        msg:SetTextColor(0.7, 0.7, 0.7)
        msg:SetText(L["NO_SLOT_DATA_CACHED_YET_OPEN_YOUR_BANK_TO_SCAN_THIS_TAB"])
        return yOffset + 30
    end

    local grid = CreateFrame("Frame", nil, parent)
    grid:SetPoint("TOPLEFT", 8, -yOffset)
    grid:SetSize(width, 1)

    local slotSize = 32
    local pad = 4
    local cols = math.max(8, math.floor((width - 10) / (slotSize + pad)))

    local function StyleSlot(btn, highlight)
        if not btn._tqStyled then
            btn:SetBackdrop({
                bgFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeSize = 1,
            })
            btn:SetBackdropColor(0, 0, 0, 0.25)
            btn._tqStyled = true
        end
        if highlight then
            btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
        else
            btn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.7)
        end
    end

    local itemsForBag = bagItems and bagItems[tabIndex] or {}

    for slotID = 1, numSlots do
        local row = math.floor((slotID - 1) / cols)
        local col = (slotID - 1) % cols

        local btn = CreateFrame("Button", nil, grid, "BackdropTemplate")
        btn:SetSize(slotSize, slotSize)
        btn:SetPoint("TOPLEFT", 5 + col * (slotSize + pad), -row * (slotSize + pad))

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local countText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        countText:SetPoint("BOTTOMRIGHT", -1, 1)
        countText:SetJustifyH("RIGHT")

        local item = itemsForBag and itemsForBag[slotID] or nil
        local match = MatchesSearch(item, itemsSearchText)

        if item then
            icon:SetTexture(item.iconFileID or item.icon or item.texture or 134400)
            local count = tonumber(item.stackCount) or 1
            countText:SetText(count > 1 and tostring(count) or "")
        else
            icon:SetTexture(nil)
            countText:SetText("")
        end

        if itemsSearchText and itemsSearchText ~= "" then
            if item and match then
                icon:SetDesaturated(false)
                icon:SetAlpha(1)
                StyleSlot(btn, true)
            elseif item then
                icon:SetDesaturated(true)
                icon:SetAlpha(0.25)
                StyleSlot(btn, false)
            else
                StyleSlot(btn, false)
            end
        else
            StyleSlot(btn, false)
            if icon:GetTexture() then
                icon:SetDesaturated(false)
                icon:SetAlpha(1)
            end
        end

        btn:SetScript("OnEnter", function()
            if item and item.itemLink then
                GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(item.itemLink)
                GameTooltip:Show()
            end
        end)
        
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:SetScript("OnMouseUp", function(_, button)
    if not item then return end

    if button == "RightButton" and item.itemID then
        -- Use the same context menu as list rows
        local pinned = TheQuartermaster:IsWatchlistedItem(item.itemID)
        local menu = {
            {
                text = pinned and "Unpin from Watchlist" or "Pin to Watchlist",
                func = function() TheQuartermaster:ToggleWatchlistItem(item.itemID) end,
            },
            {
                text = "Copy Item Link",
                func = function()
                    QM_CopyItemLinkToChat(item.itemLink or select(2, GetItemInfo(item.itemID)))
                end,
            },
            {
                text = "Search this item",
                func = function()
                    QM_SearchForItem(item.name or GetItemInfo(item.itemID), item.itemID)
                end,
            },
        }
        QM_OpenRowMenu(menu, btn)
        return
    end

    if button == "LeftButton" and IsShiftKeyDown() and item.itemLink then
        ChatEdit_InsertLink(item.itemLink)
    end
end)

btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    local rows = math.ceil(numSlots / cols)
    local gridHeight = rows * (slotSize + pad) + 6
    grid:SetHeight(gridHeight)

    return yOffset + gridHeight
end

--============================================================================
-- WARBAND BANK SLOT/TAB VIEW (view-only)
--============================================================================

local function DrawWarbandBankSlotView(self, parent, yOffset, width, itemsSearchText)
    local COLORS = GetCOLORS()

    local wb = self.db and self.db.global and self.db.global.warbandBank or nil
    local tabSizes = wb and wb.tabSizes or {}
    local tabItems = wb and wb.items or {}

    local maxTab = #ns.WARBAND_BAGS
    local tabIndex = (self.db and self.db.profile and self.db.profile.warbandBankSlotTab) or 1
    if tabIndex < 1 then tabIndex = 1 end
    if tabIndex > maxTab then tabIndex = maxTab end
    if self.db and self.db.profile then
        self.db.profile.warbandBankSlotTab = tabIndex
    end

    -- Sub-tabs for warband bank tabs
    local tabBar = CreateFrame("Frame", nil, parent)
    tabBar:SetSize(width, 28)
    tabBar:SetPoint("TOPLEFT", 8, -yOffset)

    local btnW = 70
    local btnH = 22
    local spacing = 6
    local maxCols = math.max(1, math.floor((width + spacing) / (btnW + spacing)))

    for i = 1, maxTab do
        local row = math.floor((i - 1) / maxCols)
        local col = (i - 1) % maxCols

        local btn = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        btn:SetSize(btnW, btnH)
        btn:SetPoint("TOPLEFT", col * (btnW + spacing), -row * (btnH + spacing))
        btn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })

        local active = (i == tabIndex)
        local bg = active and COLORS.tabActive or COLORS.tabInactive
        btn:SetBackdropColor(bg[1], bg[2], bg[3], 1)
        if active then
            btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
        else
            btn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
        end

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER")
        label:SetText("Tab " .. i)
        label:SetTextColor(1, 1, 1, active and 0.95 or 0.8)

        btn:SetScript("OnClick", function()
            self.db.profile.warbandBankSlotTab = i
            self:RefreshUI()
        end)
        btn:SetScript("OnEnter", function(b)
            b:SetBackdropColor(COLORS.tabHover[1], COLORS.tabHover[2], COLORS.tabHover[3], 1)
            b:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
        end)
        btn:SetScript("OnLeave", function(b)
            local a = (self.db.profile.warbandBankSlotTab == i)
            local c = a and COLORS.tabActive or COLORS.tabInactive
            b:SetBackdropColor(c[1], c[2], c[3], 1)
            if a then
                b:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
            else
                b:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
            end
        end)
    end

    local tabRows = math.ceil(maxTab / maxCols)
    local tabBarHeight = (tabRows * btnH) + ((tabRows - 1) * spacing)
    yOffset = yOffset + tabBarHeight + 12

    local numSlots = tonumber(tabSizes and tabSizes[tabIndex]) or 0
    if numSlots <= 0 then
        local msg = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        msg:SetPoint("TOPLEFT", 18, -yOffset)
        msg:SetTextColor(0.7, 0.7, 0.7)
        msg:SetText(L["NO_SLOT_DATA_CACHED_YET_OPEN_YOUR_WARBAND_BANK_TO_SCAN_THIS"])
        return yOffset + 30
    end

    local grid = CreateFrame("Frame", nil, parent)
    grid:SetPoint("TOPLEFT", 8, -yOffset)
    grid:SetSize(width, 1)

    local slotSize = 32
    local pad = 4
    local cols = math.max(8, math.floor((width - 10) / (slotSize + pad)))

    local itemsForTab = tabItems and tabItems[tabIndex] or {}

    local function StyleSlot(btn, highlighted)
        if highlighted then
            btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
        else
            btn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.7)
        end
    end

    for slotID = 1, numSlots do
        local row = math.floor((slotID - 1) / cols)
        local col = (slotID - 1) % cols

        local btn = CreateFrame("Button", nil, grid, "BackdropTemplate")
        btn:SetSize(slotSize, slotSize)
        btn:SetPoint("TOPLEFT", 5 + col * (slotSize + pad), -row * (slotSize + pad))
        btn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0, 0, 0, 0.25)
        StyleSlot(btn, false)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local countText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        countText:SetPoint("BOTTOMRIGHT", -1, 1)
        countText:SetJustifyH("RIGHT")

        local item = itemsForTab and itemsForTab[slotID] or nil
        if item and item.iconFileID then
            icon:SetTexture(item.iconFileID)
            local count = tonumber(item.stackCount) or 1
            countText:SetText(count > 1 and tostring(count) or "")

            local match = MatchesSearch(item, itemsSearchText)
            if itemsSearchText and itemsSearchText ~= "" then
                if not match then
                    icon:SetDesaturated(true)
                    icon:SetAlpha(0.25)
                    btn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.35)
                else
                    icon:SetDesaturated(false)
                    icon:SetAlpha(1)
                    StyleSlot(btn, true)
                end
            else
                icon:SetDesaturated(false)
                icon:SetAlpha(1)
            end

            btn:SetScript("OnEnter", function()
                if item and item.itemLink then
                    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(item.itemLink)
                    GameTooltip:Show()
                end
            end)
            
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:SetScript("OnMouseUp", function(_, button)
    if not item then return end

    if button == "RightButton" and item.itemID then
        -- Use the same context menu as list rows
        local pinned = TheQuartermaster:IsWatchlistedItem(item.itemID)
        local menu = {
            {
                text = pinned and "Unpin from Watchlist" or "Pin to Watchlist",
                func = function() TheQuartermaster:ToggleWatchlistItem(item.itemID) end,
            },
            {
                text = "Copy Item Link",
                func = function()
                    QM_CopyItemLinkToChat(item.itemLink or select(2, GetItemInfo(item.itemID)))
                end,
            },
            {
                text = "Search this item",
                func = function()
                    QM_SearchForItem(item.name or GetItemInfo(item.itemID), item.itemID)
                end,
            },
        }
        QM_OpenRowMenu(menu, btn)
        return
    end

    if button == "LeftButton" and IsShiftKeyDown() and item.itemLink then
        ChatEdit_InsertLink(item.itemLink)
    end
end)

btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            icon:SetTexture(nil)
            countText:SetText("")
            btn:SetScript("OnEnter", nil)
            btn:SetScript("OnLeave", nil)
        end
    end

    local rows = math.ceil(numSlots / cols)
    local gridHeight = rows * (slotSize + pad) + 6
    grid:SetHeight(gridHeight)

    return yOffset + gridHeight
end

--============================================================================
-- GUILD BANK SLOT/TAB VIEW (view-only)
--============================================================================

local function DrawGuildBankSlotView(self, parent, yOffset, width, itemsSearchText)
    local COLORS = GetCOLORS()

    local guildName = GetGuildInfo("player")
    local gb = (guildName and self.db and self.db.global and self.db.global.guildBank and self.db.global.guildBank[guildName]) or nil
    local tabs = gb and gb.tabs or {}

    -- Determine how many tabs we know about (prefer live API when the bank is open)
    local maxTab = 0
    if GetNumGuildBankTabs then
        maxTab = tonumber(GetNumGuildBankTabs()) or 0
    end
    if maxTab <= 0 then
        for k in pairs(tabs) do
            if type(k) == "number" and k > maxTab then maxTab = k end
        end
    end

    if maxTab <= 0 then
        local msg = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        msg:SetPoint("TOPLEFT", 18, -yOffset)
        msg:SetTextColor(0.7, 0.7, 0.7)
        msg:SetText(L["NO_GUILD_BANK_DATA_CACHED_YET_OPEN_YOUR_GUILD_BANK"]) 
        return yOffset + 30
    end

    local tabIndex = (self.db and self.db.profile and self.db.profile.guildBankSlotTab) or 1
    if tabIndex < 1 then tabIndex = 1 end
    if tabIndex > maxTab then tabIndex = maxTab end
    if self.db and self.db.profile then
        self.db.profile.guildBankSlotTab = tabIndex
    end

    -- Sub-tabs for guild bank tabs
    local tabBar = CreateFrame("Frame", nil, parent)
    tabBar:SetSize(width, 28)
    tabBar:SetPoint("TOPLEFT", 8, -yOffset)

    local btnW = 90
    local btnH = 22
    local spacing = 6
    local maxCols = math.max(1, math.floor((width + spacing) / (btnW + spacing)))

    for i = 1, maxTab do
        local row = math.floor((i - 1) / maxCols)
        local col = (i - 1) % maxCols

        local btn = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        btn:SetSize(btnW, btnH)
        btn:SetPoint("TOPLEFT", col * (btnW + spacing), -row * (btnH + spacing))
        btn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })

        local active = (i == tabIndex)
        local bg = active and COLORS.tabActive or COLORS.tabInactive
        btn:SetBackdropColor(bg[1], bg[2], bg[3], 1)
        if active then
            btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
        else
            btn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
        end

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER")
        local tabName = (tabs[i] and tabs[i].name) or ("Tab " .. i)
        label:SetText(tabName)
        label:SetTextColor(1, 1, 1, active and 0.95 or 0.8)

        btn:SetScript("OnClick", function()
            self.db.profile.guildBankSlotTab = i
            self:RefreshUI()
        end)
        btn:SetScript("OnEnter", function(b)
            b:SetBackdropColor(COLORS.tabHover[1], COLORS.tabHover[2], COLORS.tabHover[3], 1)
            b:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
        end)
        btn:SetScript("OnLeave", function(b)
            local a = (self.db.profile.guildBankSlotTab == i)
            local c = a and COLORS.tabActive or COLORS.tabInactive
            b:SetBackdropColor(c[1], c[2], c[3], 1)
            if a then
                b:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
            else
                b:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
            end
        end)
    end

    local tabRows = math.ceil(maxTab / maxCols)
    local tabBarHeight = (tabRows * btnH) + ((tabRows - 1) * spacing)
    yOffset = yOffset + tabBarHeight + 12

    -- Guild bank has 98 slots per tab (14 x 7)
    local MAX_SLOTS = 98

    local itemsForTab = (tabs and tabs[tabIndex] and tabs[tabIndex].items) or nil
    if not itemsForTab then
        local msg = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        msg:SetPoint("TOPLEFT", 18, -yOffset)
        msg:SetTextColor(0.7, 0.7, 0.7)
        msg:SetText(L["NO_GUILD_BANK_DATA_CACHED_YET_OPEN_YOUR_GUILD_BANK"]) 
        return yOffset + 30
    end

    local grid = CreateFrame("Frame", nil, parent)
    grid:SetPoint("TOPLEFT", 8, -yOffset)
    grid:SetSize(width, 1)

    local slotSize = 32
    local pad = 4
    local cols = math.max(8, math.floor((width - 10) / (slotSize + pad)))

    local function StyleSlot(btn, highlighted)
        if highlighted then
            btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
        else
            btn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.7)
        end
    end

    for slotID = 1, MAX_SLOTS do
        local index = slotID
        local row = math.floor((index - 1) / cols)
        local col = (index - 1) % cols

        local btn = CreateFrame("Button", nil, grid, "BackdropTemplate")
        btn:SetSize(slotSize, slotSize)
        btn:SetPoint("TOPLEFT", col * (slotSize + pad), -row * (slotSize + pad))
        btn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.05, 0.05, 0.06, 1)
        StyleSlot(btn, false)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetAlpha(0.95)

        local itemData = itemsForTab[slotID]
        local tex = (itemData and (itemData.iconFileID or itemData.icon or itemData.texture))
        if tex then
            icon:SetTexture(tex)
        elseif itemData then
            icon:SetTexture(134400)
        else
            icon:SetTexture(nil)
        end

        -- stack count
        local countText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        countText:SetPoint("BOTTOMRIGHT", -2, 2)
        local count = itemData and itemData.stackCount
        if count and count > 1 then
            countText:SetText(count)
            countText:Show()
        else
            countText:SetText("")
            countText:Hide()
        end

		-- Search highlight (fade non-matches)
		icon:SetDesaturated(false)
		icon:SetAlpha(0.95)
		countText:SetAlpha(1)
		if itemsSearchText and itemsSearchText ~= "" and itemData then
			local name, link = GetItemInfo(itemData.itemID)
			local probe = {
				name = itemData.name or name,
				itemLink = itemData.itemLink or link,
			}
			-- If we can't resolve a name/link yet, don't aggressively fade it (avoids flicker while cache warms).
			local match = true
			if probe.name or probe.itemLink then
				match = MatchesSearch(probe, itemsSearchText)
			end
			if not match then
				icon:SetDesaturated(true)
				icon:SetAlpha(0.25)
				countText:SetAlpha(0.35)
			end
		end

        btn:SetScript("OnEnter", function(b)
            StyleSlot(b, true)
            if itemData and (itemData.itemLink or itemData.itemID) then
                GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
                if itemData.itemLink then
                    GameTooltip:SetHyperlink(itemData.itemLink)
                else
                    GameTooltip:SetItemByID(itemData.itemID)
                end
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function(b)
            StyleSlot(b, false)
            GameTooltip:Hide()
        end)
    end

    local rows = math.ceil(MAX_SLOTS / cols)
    local gridHeight = rows * (slotSize + pad) + 6
    grid:SetHeight(gridHeight)

    return yOffset + gridHeight
end

-- Module-level state (shared with main QM_UI.lua via namespace)
-- These are accessed via ns.UI_GetItemsSubTab(), ns.UI_GetItemsSearchText(), etc.

--============================================================================
-- DRAW ITEM LIST (Main Items Tab)
--============================================================================

function TheQuartermaster:DrawItemList(parent)
    local yOffset = 8 -- Top padding for breathing room
    local width = parent:GetWidth() - 20 -- Match header padding (10 left + 10 right)
    
    -- PERFORMANCE: Release pooled frames back to pool before redrawing
    ReleaseAllPooledChildren(parent)
    
    -- CRITICAL: Sync WoW bank tab whenever we draw the item list
    -- This ensures right-click deposits go to the correct bank
    if self.bankIsOpen and (ns.UI_GetItemsSubTab() ~= "inventory") then
        self:SyncBankTab()
    end
    
    -- Get state from namespace (managed by main QM_UI.lua)
    local currentItemsSubTab = ns.UI_GetItemsSubTab()
    local itemsSearchText = ns.UI_GetItemsSearchText()
    local expandedGroups = ns.UI_GetExpandedGroups()

local function ResetExpandedGroups()
    -- Always start list-view category groups collapsed when entering Inventory / Personal Bank / Warband Bank.
    local t = expandedGroups
    if type(wipe) == "function" then
        wipe(t)
    else
        for k in pairs(t) do t[k] = nil end
    end
end


    
    -- ===== HEADER CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\achievement_guildperk_mobilebanking")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    -- Dynamic theme color for title
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local headerTitle = "Bank Items"
    local headerSub = "Browse your Warband and Personal bank (view only)"
    if currentItemsSubTab == "inventory" then
        headerTitle = "Inventory"
        headerSub = "Browse your bags (view only)"
    elseif currentItemsSubTab == "personal" then
        headerTitle = "Personal Bank"
        headerSub = "Browse your Personal bank (view only)"
    elseif currentItemsSubTab == "warband" then
        headerTitle = "Warband Bank"
        headerSub = "Browse your Warband bank (view only)"
    elseif currentItemsSubTab == "guild" then
        headerTitle = "Guild Bank"
        headerSub = "Browse your guild bank (view only)"
    end
    titleText:SetText("|cff" .. hexColor .. headerTitle .. "|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText(headerSub)
    
    yOffset = yOffset + 78 -- Header height + spacing
    
    -- NOTE: Search box is now persistent in QM_UI.lua (searchArea)
    -- No need to create it here!
    
    -- ===== SUB-TAB BUTTONS =====
    local tabFrame = CreateFrame("Frame", nil, parent)
    tabFrame:SetSize(width, 32)
    tabFrame:SetPoint("TOPLEFT", 8, -yOffset)
    
    -- Get theme colors
    local COLORS = GetCOLORS()
    local tabActiveColor = COLORS.tabActive
    local tabInactiveColor = COLORS.tabInactive
    local accentColor = COLORS.accent
    
    -- INVENTORY BUTTON (First/Left)
    local inventoryBtn = CreateFrame("Button", nil, tabFrame, "BackdropTemplate")
    inventoryBtn:SetSize(110, 28)
    inventoryBtn:SetPoint("LEFT", 0, 0)
    inventoryBtn:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    local isInventoryActive = currentItemsSubTab == "inventory"
    inventoryBtn:SetBackdropColor(
        isInventoryActive and tabActiveColor[1] or tabInactiveColor[1],
        isInventoryActive and tabActiveColor[2] or tabInactiveColor[2],
        isInventoryActive and tabActiveColor[3] or tabInactiveColor[3],
        1
    )
    if isInventoryActive then
        inventoryBtn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
    else
        inventoryBtn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
    end
    local invText = inventoryBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    invText:SetPoint("CENTER")
    invText:SetText(L["INVENTORY"])
    invText:SetTextColor(1, 1, 1)
    inventoryBtn:SetScript("OnClick", function()
        if (TheQuartermaster.db and TheQuartermaster.db.profile and TheQuartermaster.db.profile.inventoryViewMode) == "list" then
            ResetExpandedGroups()
        end
        ns.UI_SetItemsSubTab("inventory")
        TheQuartermaster:RefreshUI()
    end)
    inventoryBtn:SetScript("OnEnter", function(self)
        local hoverR = accentColor[1] * 0.6 + 0.15
        local hoverG = accentColor[2] * 0.6 + 0.15
        local hoverB = accentColor[3] * 0.6 + 0.15
        self:SetBackdropColor(hoverR, hoverG, hoverB, 1)
        self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.8)
    end)
    inventoryBtn:SetScript("OnLeave", function(self)
        local active = ns.UI_GetItemsSubTab() == "inventory"
        local c = active and tabActiveColor or tabInactiveColor
        self:SetBackdropColor(c[1], c[2], c[3], 1)
        if active then
            self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
        else
            self:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
        end
    end)

    -- PERSONAL BANK BUTTON (Second)
    local personalBtn = CreateFrame("Button", nil, tabFrame, "BackdropTemplate")
    personalBtn:SetSize(130, 28)
    personalBtn:SetPoint("LEFT", inventoryBtn, "RIGHT", 8, 0)
    
    -- Add backdrop for border
    personalBtn:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    
    local isPersonalActive = currentItemsSubTab == "personal"
    personalBtn:SetBackdropColor(
        isPersonalActive and tabActiveColor[1] or tabInactiveColor[1],
        isPersonalActive and tabActiveColor[2] or tabInactiveColor[2],
        isPersonalActive and tabActiveColor[3] or tabInactiveColor[3],
        1
    )
    -- Set border color
    if isPersonalActive then
        personalBtn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
    else
        personalBtn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
    end
    
    -- Remove old texture background (now using backdrop)
    local personalBg = personalBtn  -- Keep reference name for compatibility
    
    local personalText = personalBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    personalText:SetPoint("CENTER")
    personalText:SetText(L["PERSONAL_BANK"])
    personalText:SetTextColor(1, 1, 1)  -- Fixed white color
    
    personalBtn:SetScript("OnClick", function()
        ns.UI_SetItemsSubTab("personal")  -- This now automatically calls SyncBankTab
        TheQuartermaster:RefreshUI()
    end)
    personalBtn:SetScript("OnEnter", function(self)
        local hoverR = accentColor[1] * 0.6 + 0.15
        local hoverG = accentColor[2] * 0.6 + 0.15
        local hoverB = accentColor[3] * 0.6 + 0.15
        self:SetBackdropColor(hoverR, hoverG, hoverB, 1)
        self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.8)
    end)
    personalBtn:SetScript("OnLeave", function(self)
        local active = ns.UI_GetItemsSubTab() == "personal"
        local c = active and tabActiveColor or tabInactiveColor
        self:SetBackdropColor(c[1], c[2], c[3], 1)
        if active then
            self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
        else
            self:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
        end
    end)
    
    -- WARBAND BANK BUTTON (Second/Right)
    local warbandBtn = CreateFrame("Button", nil, tabFrame, "BackdropTemplate")
    warbandBtn:SetSize(130, 28)
    warbandBtn:SetPoint("LEFT", personalBtn, "RIGHT", 8, 0)
    
    -- Add backdrop for border
    warbandBtn:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    
    local isWarbandActive = currentItemsSubTab == "warband"
    warbandBtn:SetBackdropColor(
        isWarbandActive and tabActiveColor[1] or tabInactiveColor[1],
        isWarbandActive and tabActiveColor[2] or tabInactiveColor[2],
        isWarbandActive and tabActiveColor[3] or tabInactiveColor[3],
        1
    )
    -- Set border color
    if isWarbandActive then
        warbandBtn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
    else
        warbandBtn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
    end
    
    -- Remove old texture background (now using backdrop)
    local warbandBg = warbandBtn  -- Keep reference name for compatibility
    
    local warbandText = warbandBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    warbandText:SetPoint("CENTER")
    warbandText:SetText(L["WARBAND_BANK"])
    warbandText:SetTextColor(1, 1, 1)  -- Fixed white color
    
    warbandBtn:SetScript("OnClick", function()
        ns.UI_SetItemsSubTab("warband")  -- This now automatically calls SyncBankTab
        TheQuartermaster:RefreshUI()
    end)
    warbandBtn:SetScript("OnEnter", function(self)
        local hoverR = accentColor[1] * 0.6 + 0.15
        local hoverG = accentColor[2] * 0.6 + 0.15
        local hoverB = accentColor[3] * 0.6 + 0.15
        self:SetBackdropColor(hoverR, hoverG, hoverB, 1)
        self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.8)
    end)
    warbandBtn:SetScript("OnLeave", function(self) 
        local active = ns.UI_GetItemsSubTab() == "warband"
        local c = active and tabActiveColor or tabInactiveColor
        self:SetBackdropColor(c[1], c[2], c[3], 1)
        if active then
            self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
        else
            self:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
        end
    end)
    
    -- GUILD BANK BUTTON (Third/Right) - DISABLED BY DEFAULT
    if ENABLE_GUILD_BANK then
        local guildBtn = CreateFrame("Button", nil, tabFrame, "BackdropTemplate")
        guildBtn:SetSize(130, 28)
        guildBtn:SetPoint("LEFT", warbandBtn, "RIGHT", 8, 0)
        
        -- Add backdrop for border
        guildBtn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        
        local isGuildActive = currentItemsSubTab == "guild"
        guildBtn:SetBackdropColor(
            isGuildActive and tabActiveColor[1] or tabInactiveColor[1],
            isGuildActive and tabActiveColor[2] or tabInactiveColor[2],
            isGuildActive and tabActiveColor[3] or tabInactiveColor[3],
            1
        )
        -- Set border color
        if isGuildActive then
            guildBtn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
        else
            guildBtn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
        end
        
        -- Remove old texture background (now using backdrop)
        local guildBg = guildBtn  -- Keep reference name for compatibility
        
        local guildText = guildBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        guildText:SetPoint("CENTER")
        guildText:SetText(L["GUILD_BANK"])
        guildText:SetTextColor(1, 1, 1)  -- Fixed white color
        
        -- Check if player is in a guild
        local isInGuild = IsInGuild()
        if not isInGuild then
            guildBtn:Disable()
            guildBtn:SetAlpha(0.5)
            guildText:SetTextColor(0.4, 0.4, 0.4)  -- Dim gray when disabled
        end
        
        guildBtn:SetScript("OnClick", function()
            if not isInGuild then
                TheQuartermaster:Print("|cffff6600You must be in a guild to access Guild Bank.|r")
                return
            end
            ns.UI_SetItemsSubTab("guild")  -- This now automatically calls SyncBankTab
            TheQuartermaster:RefreshUI()
        end)
        guildBtn:SetScript("OnEnter", function(self) 
            if isInGuild then
                local hoverR = accentColor[1] * 0.6 + 0.15
                local hoverG = accentColor[2] * 0.6 + 0.15
                local hoverB = accentColor[3] * 0.6 + 0.15
                self:SetBackdropColor(hoverR, hoverG, hoverB, 1)
                self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.8)
            end
        end)
        guildBtn:SetScript("OnLeave", function(self) 
            local active = ns.UI_GetItemsSubTab() == "guild"
            local c = active and tabActiveColor or tabInactiveColor
            self:SetBackdropColor(c[1], c[2], c[3], 1)
            if active then
                self:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
            else
                self:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
            end
        end)
    end -- ENABLE_GUILD_BANK
    
    -- ============================================================
    -- Header controls: use a custom BackdropTemplate button.
    --
    -- Why not UIPanelButtonTemplate?
    -- That template can re-apply textures/fonts on show/refresh. We saw
    -- the List View / Slot View toggle intermittently revert to default
    -- styling until /reload. These toggles are rebuilt as plain buttons
    -- with our own themed backdrop + fontstring so they stay stable.
    -- ============================================================
    local function CreateStableToggleButton(parent, label)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(96, 24)
        btn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
        btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)

        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.text:SetPoint("CENTER", 0, 0)
        btn.text:SetTextColor(1, 1, 1, 0.95)
        btn.text:SetText(label or "")

        function btn:SetLabel(t)
            if btn.text then btn.text:SetText(t or "") end
        end

        return btn
    end

    -- ===== WARBAND BANK HEADER CONTROLS (View-only) =====
    -- Warband Bank is view-only in Items. We show cached gold and allow switching between
    -- the grouped list view and a slot+tab view.
    if currentItemsSubTab == "warband" then
        -- Small themed action buttons for Warband header controls
        local function StripDefaultButtonTextures(btn)
            local nt = btn:GetNormalTexture(); if nt then nt:SetAlpha(0) end
            local pt = btn:GetPushedTexture(); if pt then pt:SetAlpha(0) end
            local ht = btn:GetHighlightTexture(); if ht then ht:SetAlpha(0) end
            local dt = btn:GetDisabledTexture(); if dt then dt:SetAlpha(0) end
        end

        local function ApplyThemedActionButton(btn)
            if not btn or not btn.SetBackdrop then return end
            StripDefaultButtonTextures(btn)
            btn:SetBackdrop({
                bgFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeSize = 1,
            })

            -- Base state
            btn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
            btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)

            -- Ensure consistent text sizing/centering across sessions
            btn:SetNormalFontObject("GameFontHighlightSmall")
            btn:SetHighlightFontObject("GameFontHighlightSmall")
            btn:SetDisabledFontObject("GameFontDisableSmall")
            if btn.GetFontString and btn:GetFontString() then
                btn:GetFontString():SetTextColor(1, 1, 1, 0.95)
                btn:GetFontString():SetJustifyH("CENTER")
            end
        end
        -- Gold display for Warband Bank (cached)
        local goldDisplay = tabFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        goldDisplay:SetPoint("RIGHT", tabFrame, "RIGHT", -110, 0)
        local warbandGold = TheQuartermaster:GetWarbandBankMoney() or 0
        goldDisplay:SetText(FormatMoney(warbandGold))
        -- Make the gold/Hidden label match the theme and remain readable
        if TheQuartermaster.db and TheQuartermaster.db.profile and TheQuartermaster.db.profile.discretionMode then
            goldDisplay:SetTextColor(unpack(COLORS.textDim))
        else
            goldDisplay:SetTextColor(unpack(COLORS.textNormal))
        end

        -- View mode toggle (list <-> slots)
        local mode = (self.db and self.db.profile and self.db.profile.warbandBankViewMode) or "list"

        -- Custom themed button (no UIPanelButtonTemplate) to prevent template textures/fonts
        -- from randomly re-applying and "breaking" the look.
        local toggleBtn = CreateFrame("Button", nil, tabFrame, "BackdropTemplate")
        toggleBtn:SetSize(96, 24)
        toggleBtn:SetPoint("RIGHT", tabFrame, "RIGHT", -5, 0)

        toggleBtn.text = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        toggleBtn.text:SetPoint("CENTER")
        toggleBtn.text:SetTextColor(1, 1, 1, 0.95)
        toggleBtn.text:SetText(mode == "slots" and "List View" or "Slot View")

        toggleBtn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })
        toggleBtn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
        toggleBtn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)

        toggleBtn:SetScript("OnClick", function()
            local cur = (self.db.profile.warbandBankViewMode or "list")
            self.db.profile.warbandBankViewMode = (cur == "slots") and "list" or "slots"
            self:RefreshUI()
        end)

        toggleBtn:SetScript("OnEnter", function(btn)
            if btn.SetBackdropColor then
                btn:SetBackdropColor(COLORS.tabHover[1], COLORS.tabHover[2], COLORS.tabHover[3], 1)
                btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
            end
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:AddLine("Warband Bank View", 1, 0.82, 0)
            GameTooltip:AddLine("Toggle between the grouped list view and a slot + tab view.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)

        toggleBtn:SetScript("OnLeave", function(btn)
            if btn.SetBackdropColor then
                btn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
                btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)
            end
            GameTooltip:Hide()
        end)

        -- Keep label in sync after refresh
        toggleBtn:HookScript("OnShow", function(btn)
            local m = (self.db.profile.warbandBankViewMode or "list")
            if btn.text then
                btn.text:SetText(m == "slots" and "List View" or "Slot View")
            end
        end)
    end
    
    -- ===== INVENTORY VIEW MODE TOGGLE =====
    -- Inventory can be shown as either a grouped list (default) or a slot+bag layout.
    if currentItemsSubTab == "inventory" then
		local mode = (self.db and self.db.profile and self.db.profile.inventoryViewMode) or "list"

		local toggleBtn = CreateFrame("Button", nil, tabFrame, "BackdropTemplate")
		toggleBtn:SetSize(96, 24)
		toggleBtn:SetPoint("RIGHT", tabFrame, "RIGHT", -5, 0)
		toggleBtn:SetBackdrop({
			bgFile = "Interface\\BUTTONS\\WHITE8X8",
			edgeFile = "Interface\\BUTTONS\\WHITE8X8",
			edgeSize = 1,
		})
		toggleBtn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
		toggleBtn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)

		toggleBtn.text = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		toggleBtn.text:SetPoint("CENTER")
		toggleBtn.text:SetTextColor(1, 1, 1, 0.95)
		toggleBtn.text:SetText(mode == "slots" and "List View" or "Slot View")

		toggleBtn:SetScript("OnClick", function()
			local cur = (self.db.profile.inventoryViewMode or "list")
			self.db.profile.inventoryViewMode = (cur == "slots") and "list" or "slots"
			self:RefreshUI()
		end)

		toggleBtn:SetScript("OnEnter", function(btn)
			btn:SetBackdropColor(COLORS.tabHover[1], COLORS.tabHover[2], COLORS.tabHover[3], 1)
			btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
			GameTooltip:SetOwner(btn, "ANCHOR_TOP")
			GameTooltip:AddLine("Inventory View", 1, 0.82, 0)
			GameTooltip:AddLine("Toggle between the grouped list view and a slot + bag view.", 0.8, 0.8, 0.8, true)
			GameTooltip:Show()
		end)

		toggleBtn:SetScript("OnLeave", function(btn)
			btn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
			btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)
			GameTooltip:Hide()
		end)

		toggleBtn:HookScript("OnShow", function(btn)
			local m = (self.db.profile.inventoryViewMode or "list")
			if btn.text then
				btn.text:SetText(m == "slots" and "List View" or "Slot View")
			end
		end)
    end
-- Personal Bank has no gold controls (WoW doesn't support gold storage in personal bank)

    -- ===== PERSONAL BANK VIEW MODE TOGGLE =====
    -- Personal Bank can be shown as either a grouped list (default) or a slot+tab layout.
    if currentItemsSubTab == "personal" then
		local mode = (self.db and self.db.profile and self.db.profile.personalBankViewMode) or "list"
		local toggleBtn = CreateFrame("Button", nil, tabFrame, "BackdropTemplate")
		toggleBtn:SetSize(96, 24)
		toggleBtn:SetPoint("RIGHT", tabFrame, "RIGHT", -5, 0)
		toggleBtn:SetBackdrop({
			bgFile = "Interface\\BUTTONS\\WHITE8X8",
			edgeFile = "Interface\\BUTTONS\\WHITE8X8",
			edgeSize = 1,
		})
		toggleBtn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
		toggleBtn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)

		toggleBtn.text = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		toggleBtn.text:SetPoint("CENTER")
		toggleBtn.text:SetTextColor(1, 1, 1, 0.95)
		toggleBtn.text:SetText(mode == "slots" and "List View" or "Slot View")

		toggleBtn:SetScript("OnClick", function()
			local cur = (self.db.profile.personalBankViewMode or "list")
			self.db.profile.personalBankViewMode = (cur == "slots") and "list" or "slots"
			self:RefreshUI()
		end)

		toggleBtn:SetScript("OnEnter", function(btn)
			btn:SetBackdropColor(COLORS.tabHover[1], COLORS.tabHover[2], COLORS.tabHover[3], 1)
			btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
			GameTooltip:SetOwner(btn, "ANCHOR_TOP")
			GameTooltip:AddLine("Personal Bank View", 1, 0.82, 0)
			GameTooltip:AddLine("Toggle between the grouped list view and a slot + tab view (like the default bank).", 0.8, 0.8, 0.8, true)
			GameTooltip:Show()
		end)

		toggleBtn:SetScript("OnLeave", function(btn)
			btn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
			btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)
			GameTooltip:Hide()
		end)

		toggleBtn:HookScript("OnShow", function(btn)
			local m = (self.db.profile.personalBankViewMode or "list")
			if btn.text then
				btn.text:SetText(m == "slots" and "List View" or "Slot View")
			end
		end)
    end

    -- ===== GUILD BANK VIEW MODE TOGGLE =====
    -- Guild Bank can be shown as either a grouped list or a slot+tab layout.
    if currentItemsSubTab == "guild" then
        -- Gold display for Guild Bank (cached; display-only)
        local guildGoldDisplay = tabFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        guildGoldDisplay:SetPoint("RIGHT", tabFrame, "RIGHT", -110, 0)
        local guildGold = (TheQuartermaster and TheQuartermaster.GetCachedGuildBankMoney and TheQuartermaster:GetCachedGuildBankMoney()) or 0
        guildGoldDisplay:SetText(FormatMoney(guildGold))
        if TheQuartermaster.db and TheQuartermaster.db.profile and TheQuartermaster.db.profile.discretionMode then
            guildGoldDisplay:SetTextColor(unpack(COLORS.textDim))
        else
            guildGoldDisplay:SetTextColor(unpack(COLORS.textNormal))
        end

        local mode = (self.db and self.db.profile and self.db.profile.guildBankViewMode) or "slots"
        local toggleBtn = CreateFrame("Button", nil, tabFrame, "BackdropTemplate")
        toggleBtn:SetSize(96, 24)
        toggleBtn:SetPoint("RIGHT", tabFrame, "RIGHT", -5, 0)
        toggleBtn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })
        toggleBtn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
        toggleBtn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)

        toggleBtn.text = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        toggleBtn.text:SetPoint("CENTER")
        toggleBtn.text:SetTextColor(1, 1, 1, 0.95)
        toggleBtn.text:SetText(mode == "slots" and "List View" or "Slot View")

        toggleBtn:SetScript("OnClick", function()
            local cur = (self.db.profile.guildBankViewMode or "slots")
            self.db.profile.guildBankViewMode = (cur == "slots") and "list" or "slots"
            self:RefreshUI()
        end)

        toggleBtn:SetScript("OnEnter", function(btn)
            btn:SetBackdropColor(COLORS.tabHover[1], COLORS.tabHover[2], COLORS.tabHover[3], 1)
            btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:AddLine("Guild Bank View", 1, 0.82, 0)
            GameTooltip:AddLine("Toggle between the grouped list view and a slot + tab view.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)

        toggleBtn:SetScript("OnLeave", function(btn)
            btn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
            btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)
            GameTooltip:Hide()
        end)

        toggleBtn:HookScript("OnShow", function(btn)
            local m = (self.db.profile.guildBankViewMode or "slots")
            if btn.text then
                btn.text:SetText(m == "slots" and "List View" or "Slot View")
            end
        end)
    end
    yOffset = yOffset + 40
    
    -- Get items based on selected sub-tab
    local items = {}
    if currentItemsSubTab == "warband" then
        items = self:GetWarbandBankItems() or {}
    elseif currentItemsSubTab == "guild" then
        items = self:GetGuildBankItems() or {}
    elseif currentItemsSubTab == "inventory" then
        items = self:GetInventoryItems() or {}
    else
        items = self:GetPersonalBankItems() or {}
    end

    
    -- ===== INVENTORY SLOT VIEW =====
    if currentItemsSubTab == "inventory" and (self.db.profile.inventoryViewMode == "slots") then
        local function DrawInventorySlots(startY)
            local inv = (self.db and self.db.char and self.db.char.inventory) or {}
            local bagSizes = inv.bagSizes or {}
            local bagIDs = inv.bagIDs or {}
            local bagItems = inv.items or {}

            local bagCount = #ns.INVENTORY_BAGS
            local selected = tonumber(self.db.profile.inventorySlotTab) or 1
            if selected < 1 then selected = 1 end
            if selected > bagCount then selected = bagCount end
            self.db.profile.inventorySlotTab = selected

            -- Bag tab bar
            local bagTabBar = CreateFrame("Frame", nil, parent)
            bagTabBar:SetSize(width, 26)
            bagTabBar:SetPoint("TOPLEFT", 8, -startY)

            local tabW, tabH = 70, 22
            local tabGap = 6
            local x = 0

            local function MakeBagLabel(i)
                local bagID = bagIDs[i]
                if bagID == nil then return "Bag" end
                return (ns.INVENTORY_BAG_LABELS and ns.INVENTORY_BAG_LABELS[bagID])
                    or (bagID == 0 and "Backpack" or (bagID == 5 and "Reagent" or ("Bag " .. tostring(bagID))))
            end

            for i = 1, bagCount do
                local bagID = bagIDs[i]
                -- Hide reagent bag tab if not present
                if bagID ~= 5 or (bagSizes[i] and bagSizes[i] > 0) then
                    local btn = CreateFrame("Button", nil, bagTabBar, "BackdropTemplate")
                    btn:SetSize(tabW, tabH)
                    btn:SetPoint("LEFT", x, 0)
                    x = x + tabW + tabGap

                    btn:SetBackdrop({
                        bgFile = "Interface\\BUTTONS\\WHITE8X8",
                        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                        edgeSize = 1,
                    })

                    local isActive = (i == selected)
                    local bg = isActive and COLORS.tabActive or COLORS.tabInactive
                    btn:SetBackdropColor(bg[1], bg[2], bg[3], 1)
                    btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], isActive and 1 or 0.45)

                    local t = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    t:SetPoint("CENTER")
                    t:SetText(MakeBagLabel(i))
                    t:SetTextColor(1, 1, 1, 0.95)

                    btn:SetScript("OnClick", function()
                        self.db.profile.inventorySlotTab = i
                        self:RefreshUI()
                    end)
                    btn:SetScript("OnEnter", function(b)
                        b:SetBackdropColor(COLORS.tabHover[1], COLORS.tabHover[2], COLORS.tabHover[3], 1)
                        b:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
                    end)
                    btn:SetScript("OnLeave", function(b)
                        local active = (self.db.profile.inventorySlotTab == i)
                        local c = active and COLORS.tabActive or COLORS.tabInactive
                        b:SetBackdropColor(c[1], c[2], c[3], 1)
                        b:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], active and 1 or 0.45)
                    end)
                end
            end

            local gridY = startY + 30
            local grid = CreateFrame("Frame", nil, parent)
            grid:SetPoint("TOPLEFT", 8, -gridY)
            grid:SetSize(width, 10)

            local numSlots = tonumber(bagSizes[selected]) or 0
            if numSlots <= 0 then
                local msg = grid:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                msg:SetPoint("TOPLEFT", 6, -6)
                msg:SetTextColor(0.7, 0.7, 0.7)
                msg:SetText(L["NO_SLOT_DATA_CACHED_YET"])
                grid:SetHeight(30)
                return gridY + 34
            end

            local slotSize = 32
            local pad = 4
            local cols = math.floor((width - 10) / (slotSize + pad))
            if cols < 8 then cols = 8 end

            for slot = 1, numSlots do
                local row = math.floor((slot - 1) / cols)
                local col = (slot - 1) % cols

                local btn = CreateFrame("Button", nil, grid, "BackdropTemplate")
                btn:SetSize(slotSize, slotSize)
                btn:SetPoint("TOPLEFT", col * (slotSize + pad), -row * (slotSize + pad))

                btn:SetBackdrop({
                    bgFile = "Interface\\BUTTONS\\WHITE8X8",
                    edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                    edgeSize = 1,
                })
                btn:SetBackdropColor(0, 0, 0, 0.25)
                btn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.7)

                local icon = btn:CreateTexture(nil, "ARTWORK")
                icon:SetAllPoints()
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                local item = (bagItems[selected] or {})[slot]
                if item and item.iconFileID then
                    icon:SetTexture(item.iconFileID)

                    btn:SetScript("OnEnter", function()
                        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                        if item.itemLink then
                            GameTooltip:SetHyperlink(item.itemLink)
                        end
                        GameTooltip:Show()
                    end)
                    
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:SetScript("OnMouseUp", function(_, button)
    if not item then return end

    if button == "RightButton" and item.itemID then
        -- Use the same context menu as list rows
        local pinned = TheQuartermaster:IsWatchlistedItem(item.itemID)
        local menu = {
            {
                text = pinned and "Unpin from Watchlist" or "Pin to Watchlist",
                func = function() TheQuartermaster:ToggleWatchlistItem(item.itemID) end,
            },
            {
                text = "Copy Item Link",
                func = function()
                    QM_CopyItemLinkToChat(item.itemLink or select(2, GetItemInfo(item.itemID)))
                end,
            },
            {
                text = "Search this item",
                func = function()
                    QM_SearchForItem(item.name or GetItemInfo(item.itemID), item.itemID)
                end,
            },
        }
        QM_OpenRowMenu(menu, btn)
        return
    end

    if button == "LeftButton" and IsShiftKeyDown() and item.itemLink then
        ChatEdit_InsertLink(item.itemLink)
    end
end)

btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

					-- Search highlight (fade non-matches)
					-- Use the shared matcher so we consistently check name *and* itemLink.
					if itemsSearchText and itemsSearchText ~= "" then
						if not MatchesSearch(item, itemsSearchText) then
							icon:SetDesaturated(true)
							icon:SetAlpha(0.35)
						end
					end
                end
            end

            local rows = math.ceil(numSlots / cols)
            grid:SetHeight(rows * (slotSize + pad) + 10)
            return gridY + rows * (slotSize + pad) + 18
        end

        -- Delay drawing until after the stats bar so it appears in slot view too
        parent.__tq_inventorySlotDrawer = DrawInventorySlots
    else
        parent.__tq_inventorySlotDrawer = nil
    end


-- ===== PERSONAL BANK SLOT VIEW =====
    if currentItemsSubTab == "personal" and (self.db.profile.personalBankViewMode == "slots") then
        local function DrawPersonalBankSlots(startY)
            local pb = (self.db and self.db.char and self.db.char.personalBank) or {}
            local bagSizes = pb.bagSizes or {}
            local bagIDs = pb.bagIDs or {}
            local bagItems = pb.items or {}

            local bagCount = #ns.PERSONAL_BANK_BAGS
            local selected = tonumber(self.db.profile.personalBankSlotTab) or 1
            if selected < 1 then selected = 1 end
            if selected > bagCount then selected = bagCount end
            self.db.profile.personalBankSlotTab = selected

            -- Bag tab bar
            local bagTabBar = CreateFrame("Frame", nil, parent)
            bagTabBar:SetSize(width, 26)
            bagTabBar:SetPoint("TOPLEFT", 8, -startY)

            local tabW, tabH = 70, 22
            local tabGap = 6
            local x = 0

            local function MakeBagLabel(i)
                if i == 1 then return "Bank" end
                return "Bag " .. (i - 1)
            end

            for i = 1, bagCount do
                local btn = CreateFrame("Button", nil, bagTabBar, "BackdropTemplate")
                btn:SetSize(tabW, tabH)
                btn:SetPoint("LEFT", x, 0)
                x = x + tabW + tabGap

                btn:SetBackdrop({
                    bgFile = "Interface\\BUTTONS\\WHITE8X8",
                    edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                    edgeSize = 1,
                })

                local isActive = (i == selected)
                local bg = isActive and COLORS.tabActive or COLORS.tabInactive
                btn:SetBackdropColor(bg[1], bg[2], bg[3], 1)
                btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], isActive and 1 or 0.45)

                local t = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                t:SetPoint("CENTER")
                t:SetText(MakeBagLabel(i))
                t:SetTextColor(1, 1, 1, 0.95)

                btn:SetScript("OnClick", function()
                    self.db.profile.personalBankSlotTab = i
                    self:RefreshUI()
                end)
                btn:SetScript("OnEnter", function(b)
                    b:SetBackdropColor(COLORS.tabHover[1], COLORS.tabHover[2], COLORS.tabHover[3], 1)
                    b:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
                end)
                btn:SetScript("OnLeave", function(b)
                    local active = (self.db.profile.personalBankSlotTab == i)
                    local c = active and COLORS.tabActive or COLORS.tabInactive
                    b:SetBackdropColor(c[1], c[2], c[3], 1)
                    b:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], active and 1 or 0.45)
                end)
            end

            local gridY = startY + 30
            local grid = CreateFrame("Frame", nil, parent)
            grid:SetPoint("TOPLEFT", 8, -gridY)
            grid:SetSize(width, 10)

            local numSlots = tonumber(bagSizes[selected]) or 0
            if numSlots <= 0 then
                -- No cached slot info yet
                local msg = grid:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                msg:SetPoint("TOPLEFT", 6, -6)
                msg:SetTextColor(0.7, 0.7, 0.7)
                msg:SetText(L["NO_SLOT_DATA_CACHED_YET_OPEN_YOUR_BANK_ONCE_TO_SCAN_SLOTS"])
                grid:SetHeight(30)
                return gridY + 34
            end

            local slotSize = 32
            local pad = 4
            local cols = math.floor((width - 12) / (slotSize + pad))
            if cols < 8 then cols = 8 end
            if cols > 14 then cols = 14 end
            local rows = math.ceil(numSlots / cols)

            local itemsForBag = bagItems[selected] or {}
            local search = (itemsSearchText or "")

            for slot = 1, numSlots do
                local col = (slot - 1) % cols
                local row = math.floor((slot - 1) / cols)
                local bx = 6 + col * (slotSize + pad)
                local by = -6 - row * (slotSize + pad)

                local btn = CreateFrame("Button", nil, grid, "BackdropTemplate")
                btn:SetSize(slotSize, slotSize)
                btn:SetPoint("TOPLEFT", bx, by)
                btn:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    edgeSize = 1,
                })
                btn:SetBackdropColor(0.06, 0.06, 0.08, 1)
                btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.35)

                local icon = btn:CreateTexture(nil, "ARTWORK")
                icon:SetAllPoints()
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                local countText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
                countText:SetPoint("BOTTOMRIGHT", -2, 2)

                local data = itemsForBag[slot]
                if data and data.itemLink then
                    icon:SetTexture(data.iconFileID or data.texture or data.icon)
                    countText:SetText((data.stackCount and data.stackCount > 1) and data.stackCount or "")

                    btn:SetScript("OnEnter", function()
                        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink(data.itemLink)
                        GameTooltip:Show()
                    end)
                    
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:SetScript("OnMouseUp", function(_, button)
    if not item then return end

    if button == "RightButton" and item.itemID then
        -- Use the same context menu as list rows
        local pinned = TheQuartermaster:IsWatchlistedItem(item.itemID)
        local menu = {
            {
                text = pinned and "Unpin from Watchlist" or "Pin to Watchlist",
                func = function() TheQuartermaster:ToggleWatchlistItem(item.itemID) end,
            },
            {
                text = "Copy Item Link",
                func = function()
                    QM_CopyItemLinkToChat(item.itemLink or select(2, GetItemInfo(item.itemID)))
                end,
            },
            {
                text = "Search this item",
                func = function()
                    QM_SearchForItem(item.name or GetItemInfo(item.itemID), item.itemID)
                end,
            },
        }
        QM_OpenRowMenu(menu, btn)
        return
    end

    if button == "LeftButton" and IsShiftKeyDown() and item.itemLink then
        ChatEdit_InsertLink(item.itemLink)
    end
end)

btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                    if search ~= "" then
                        local n = ((data.name or "") .. " " .. (data.itemLink or "")):lower()
                        if not n:find(search, 1, true) then
                            icon:SetDesaturated(true)
                            icon:SetAlpha(0.25)
                            btn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.35)
                        else
                            icon:SetDesaturated(false)
                            icon:SetAlpha(1)
                            btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
                        end
                    end
                else
                    icon:SetTexture(nil)
                    countText:SetText("")
                end
            end

            local totalH = (rows * (slotSize + pad)) + 12
            grid:SetHeight(totalH)
            return gridY + totalH
        end

        -- We draw the slot view starting where the stats bar would normally go
        -- (stats bar is still helpful, so keep it above and start below it)
        -- yOffset at this point is the same as list view would use.
        -- We still show statsBar and then replace the list content.
        -- Continue after stats bar is created below.
        -- (We delay the return until after the stats bar section.)
        parent.__tq_slotView = { draw = DrawPersonalBankSlots, startY = yOffset }
    else
        parent.__tq_slotView = nil
    end
    
    -- Apply search filter (Items tab specific)
    if itemsSearchText and itemsSearchText ~= "" then
        local filtered = {}
        for _, item in ipairs(items) do
        EnrichItemInPlace(item)
            local itemName = (item.name or ""):lower()
            local itemLink = (item.itemLink or ""):lower()
            if itemName:find(itemsSearchText, 1, true) or itemLink:find(itemsSearchText, 1, true) then
                table.insert(filtered, item)
            end
        end
        items = filtered
    end
    
    -- Sort items alphabetically by name
    table.sort(items, function(a, b)
        local nameA = (a.name or ""):lower()
        local nameB = (b.name or ""):lower()
        return nameA < nameB
    end)
    
    -- ===== STATS BAR =====
    local statsBar = CreateFrame("Frame", nil, parent)
    statsBar:SetSize(width, 24)
    statsBar:SetPoint("TOPLEFT", 8, -yOffset)
    
    local statsBg = statsBar:CreateTexture(nil, "BACKGROUND")
    statsBg:SetAllPoints()
    statsBg:SetColorTexture(0.08, 0.08, 0.10, 1)
    
    local statsText = statsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsText:SetPoint("LEFT", 10, 0)
    -- Theme-coloured "X items" prefix (match current theme/class colour)
    local COLORS = GetCOLORS()
    local tr, tg, tb = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local itemsHex = string.format("%02x%02x%02x", tr * 255, tg * 255, tb * 255)

    local bankStats = self:GetBankStatistics()
    
    if currentItemsSubTab == "inventory" then
        local inv = (self.db and self.db.char and self.db.char.inventory) or {}
        local used = tonumber(inv.usedSlots) or 0
        local total = tonumber(inv.totalSlots) or 0
        local last = tonumber(inv.lastScan) or 0
        statsText:SetText(string.format("|cff%s%d items|r  •  %d/%d slots  •  Last: %s",
            itemsHex, #items, used, total,
            last > 0 and date("%H:%M", last) or "Never"))
    elseif currentItemsSubTab == "warband" then
        local wb = bankStats.warband
        statsText:SetText(string.format("|cff%s%d items|r  •  %d/%d slots  •  Last: %s",
            itemsHex, #items, wb.usedSlots, wb.totalSlots,
            wb.lastScan > 0 and date("%H:%M", wb.lastScan) or "Never"))
    elseif currentItemsSubTab == "guild" then
        local gb = bankStats.guild or { usedSlots = 0, totalSlots = 0, lastScan = 0 }
        statsText:SetText(string.format("|cff%s%d items|r  •  %d/%d slots  •  Last: %s",
            itemsHex, #items, gb.usedSlots, gb.totalSlots,
            gb.lastScan > 0 and date("%H:%M", gb.lastScan) or "Never"))
    else
        local pb = bankStats.personal
        statsText:SetText(string.format("|cff%s%d items|r  •  %d/%d slots  •  Last: %s",
            itemsHex, #items, pb.usedSlots, pb.totalSlots,
            pb.lastScan > 0 and date("%H:%M", pb.lastScan) or "Never"))
    end
    statsText:SetTextColor(0.6, 0.6, 0.6)
    
    yOffset = yOffset + 28

    -- INVENTORY: Slot + tab view (shows empty slots too)
    if currentItemsSubTab == "inventory" then
        local viewMode = (self.db and self.db.profile and self.db.profile.inventoryViewMode) or "list"
        if viewMode == "slots" and parent.__tq_inventorySlotDrawer then
            return parent.__tq_inventorySlotDrawer(yOffset)
        end
    end

    -- PERSONAL BANK: Slot + tab view (shows empty slots too)
    if currentItemsSubTab == "personal" then
        local viewMode = (self.db and self.db.profile and self.db.profile.personalBankViewMode) or "list"
        if viewMode == "slots" then
            return DrawPersonalBankSlotView(self, parent, yOffset, width, itemsSearchText)
        end
    end

    -- WARBAND BANK: Slot + tab view (shows empty slots too)
    if currentItemsSubTab == "warband" then
        local viewMode = (self.db and self.db.profile and self.db.profile.warbandBankViewMode) or "list"
        if viewMode == "slots" then
            return DrawWarbandBankSlotView(self, parent, yOffset, width, itemsSearchText)
        end
    end

    -- GUILD BANK: Slot + tab view (shows empty slots too)
    if currentItemsSubTab == "guild" then
        local viewMode = (self.db and self.db.profile and self.db.profile.guildBankViewMode) or "slots"
        if viewMode == "slots" then
            return DrawGuildBankSlotView(self, parent, yOffset, width, itemsSearchText)
        end
    end
    
    -- ===== EMPTY STATE =====
    if #items == 0 then
        local hint
        if currentItemsSubTab == "warband" then
            hint = "Open your Warband Bank to scan items"
        elseif currentItemsSubTab == "guild" then
            hint = "Open your Guild Bank to scan items"
        elseif currentItemsSubTab == "personal" then
            hint = "Open your Personal Bank to scan items"
        elseif currentItemsSubTab == "inventory" then
            hint = "Open your bags to scan items"
        end
        return DrawEmptyState(self, parent, yOffset, itemsSearchText ~= "", itemsSearchText, hint)
    end
    
    -- ===== GROUP ITEMS BY TYPE =====
    local groups = {}
    local groupOrder = {}
    
    for _, item in ipairs(items) do
        local typeName = item.itemType
        if not typeName or typeName == "" then
            typeName = "Miscellaneous"
        end
        if not groups[typeName] then
            -- Use persisted expanded state.
            -- For Items List View we default categories to *expanded* so behaviour matches Storage.
            local groupKey = currentItemsSubTab .. "_" .. typeName
            if expandedGroups[groupKey] == nil then
                expandedGroups[groupKey] = true
            end
            groups[typeName] = { name = typeName, items = {}, groupKey = groupKey }
            table.insert(groupOrder, typeName)
        end
        table.insert(groups[typeName].items, item)
    end
    
    -- Sort group names alphabetically
    table.sort(groupOrder)
    
    -- ===== DRAW GROUPS =====
    -- NOTE: Use actual widget heights for layout.
    -- Fixed y increments can drift (scaling, font metrics, dynamic text),
    -- which can manifest as overlapping/"bleeding" sections or large blank gaps
    -- until something forces a full rebuild.
    local rowIdx = 0
    for _, typeName in ipairs(groupOrder) do
        local group = groups[typeName]
        local isExpanded = expandedGroups[group.groupKey]
        
        -- Get icon from first item in group
        local typeIcon = nil
        if group.items[1] and group.items[1].classID then
            typeIcon = GetTypeIcon(group.items[1].classID)
        end
        
        -- Toggle function for this group
        local gKey = group.groupKey
        local function ToggleGroup(key, isExpanded)
            -- Use isExpanded if provided (new style), otherwise toggle (old style)
            if type(isExpanded) == "boolean" then
                expandedGroups[key] = isExpanded
            else
                expandedGroups[key] = not expandedGroups[key]
            end
            TheQuartermaster:RefreshUI()
        end
        
        -- Create collapsible header with purple border and icon
        local groupHeader, expandBtn = CreateCollapsibleHeader(
            parent,
            format("%s (%d)", typeName, #group.items),
            gKey,
            isExpanded,
            function(isExpanded) ToggleGroup(gKey, isExpanded) end,
            typeIcon
        )
        groupHeader:ClearAllPoints()
        groupHeader:SetPoint("TOPLEFT", 10, -yOffset)

        do
            local h = groupHeader:GetHeight()
            if not h or h <= 0 then
                h = HEADER_SPACING
            end
            yOffset = yOffset + h + 6
        end
        
        -- Draw items in this group (if expanded)
        if isExpanded then
            for _, item in ipairs(group.items) do
                rowIdx = rowIdx + 1
                local i = rowIdx
                
                -- PERFORMANCE: Acquire from pool instead of creating new
                local row = AcquireItemRow(parent, width, ROW_HEIGHT)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 8, -yOffset)
                row.idx = i
                
                -- Update background color (alternating rows)
                row.bg:SetColorTexture(i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.09 or 0.06, 1)
                
                -- Update quantity
                row.qtyText:SetText(format("|cffffff00%d|r", item.stackCount or 1))
                _TQ_ResolveItemInfo(item)

                -- Update icon
                row.icon:SetTexture(item.iconFileID or item.icon or item.texture or 134400)
                
                -- Update name (with pet cage handling)
                local nameWidth = width - 200
                row.nameText:SetWidth(nameWidth)
                -- NOTE: some caches may store an empty string for name/itemName while item data is still loading.
                -- In Lua, "" is truthy, so we must treat empty as missing or rows appear blank.
                local baseName = (item.name and item.name ~= "" and item.name)
                    or (item.itemName and item.itemName ~= "" and item.itemName)
                    or format("Item %s", tostring(item.itemID or "?"))
                -- Use GetItemDisplayName to handle caged pets (shows pet name instead of "Pet Cage")
                local displayName = TheQuartermaster:GetItemDisplayName(item.itemID, baseName, item.classID)
                if not displayName or displayName == "" then
                    displayName = baseName
                end
                row.nameText:SetText(format("|cff%s%s|r", GetQualityHex(item.quality), displayName))
                
                -- Update location
                local locText
                if currentItemsSubTab == "warband" then
                    locText = item.tabIndex and format("Tab %d", item.tabIndex) or ""
                elseif currentItemsSubTab == "guild" then
                    if item.tabName and item.tabName ~= "" then
                        locText = item.tabName
                    elseif item.tabIndex then
                        locText = format("Tab %d", item.tabIndex)
                    else
                        locText = ""
                    end
                else
                    locText = item.bagIndex and format("Bag %d", item.bagIndex) or ""
                end
                row.locationText:SetText(locText)
                row.locationText:SetTextColor(0.5, 0.5, 0.5)
                
                -- Update hover/tooltip handlers
                row:SetScript("OnEnter", function(self)
                    self.bg:SetColorTexture(0.15, 0.15, 0.20, 1)
                    if item.itemLink then
                        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                        GameTooltip:SetHyperlink(item.itemLink)
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cff888888Shift+Left-Click|r Link in chat", 0.7, 0.7, 0.7)
                        GameTooltip:Show()
                    elseif item.itemID then
                        -- Fallback: Use itemID if itemLink is not available
                        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                        GameTooltip:SetItemByID(item.itemID)
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cff888888Shift+Left-Click|r Link in chat", 0.7, 0.7, 0.7)
                        GameTooltip:Show()
                    end
                end)
                row:SetScript("OnLeave", function(self)
                    self.bg:SetColorTexture(self.idx % 2 == 0 and 0.07 or 0.05, self.idx % 2 == 0 and 0.07 or 0.05, self.idx % 2 == 0 and 0.09 or 0.06, 1)
                    GameTooltip:Hide()
                end)
                
                -- Helper to get bag/slot IDs
                local function GetItemBagSlot()
                    local bagID, slotID
                    
                    if currentItemsSubTab == "warband" and item.tabIndex then
                        local warbandBags = {
                            Enum.BagIndex.AccountBankTab_1,
                            Enum.BagIndex.AccountBankTab_2,
                            Enum.BagIndex.AccountBankTab_3,
                            Enum.BagIndex.AccountBankTab_4,
                            Enum.BagIndex.AccountBankTab_5,
                        }
                        bagID = warbandBags[item.tabIndex]
                        slotID = item.slotID
                    elseif currentItemsSubTab == "personal" and item.bagIndex then
                        -- Use stored bagID from item data if available
                        if item.actualBagID then
                            bagID = item.actualBagID
                        else
                            -- Use enum-based lookup
                            local personalBags = { 
                                Enum.BagIndex.Bank or -1, 
                                Enum.BagIndex.BankBag_1 or 6, 
                                Enum.BagIndex.BankBag_2 or 7, 
                                Enum.BagIndex.BankBag_3 or 8, 
                                Enum.BagIndex.BankBag_4 or 9, 
                                Enum.BagIndex.BankBag_5 or 10, 
                                Enum.BagIndex.BankBag_6 or 11, 
                                Enum.BagIndex.BankBag_7 or 12 
                            }
                            bagID = personalBags[item.bagIndex]
                        end
                        slotID = item.slotID
                    end
                    return bagID, slotID
                end
                
                -- Click handlers for item interaction
                -- View-only: no item movement. Keep Shift+Left-Click to link in chat.
                row:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and item.itemID then
        QM_ShowItemWatchlistMenu(item.itemID)
        return
    end

    if button == "LeftButton" and IsShiftKeyDown() and item.itemLink then
        ChatEdit_InsertLink(item.itemLink)
    end
end)
                
                do
                    local rh = row:GetHeight()
                    if not rh or rh <= 0 then
                        rh = ROW_HEIGHT
                    end
                    yOffset = yOffset + rh + 2
                end
            end  -- for item in group.items
        end  -- if group.expanded
    end  -- for typeName in groupOrder
    
    return yOffset + 20
end
