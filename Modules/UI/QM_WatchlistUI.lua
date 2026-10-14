--[[
    The Quartermaster - Watchlist UI
    Pins important items/currencies and shows totals across your Warband.
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

local L = ns.L
local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard
local function QM_GetItemQualityColor(itemID)
    itemID = tonumber(itemID)
    if not itemID then return 1, 1, 1 end

    local quality
    if C_Item and C_Item.GetItemQualityByID then
        quality = C_Item.GetItemQualityByID(itemID)
    end
    if not quality then
        local _, _, q = GetItemInfo(itemID)
        quality = q
    end

    if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        local c = ITEM_QUALITY_COLORS[quality]
        return c.r or 1, c.g or 1, c.b or 1
    end
    return 1, 1, 1
end


-- Treat Trade Goods / Gems / Reagent class items as "Reagents" for Watchlist grouping
local ITEM_CLASS_TRADEGOODS = Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods or 7
local ITEM_CLASS_GEM       = Enum and Enum.ItemClass and Enum.ItemClass.Gem or 3
local ITEM_CLASS_REAGENT   = Enum and Enum.ItemClass and Enum.ItemClass.Reagent or nil

-- Tooltip scanner so we can detect items that are labeled "Crafting Reagent" even if their
-- item class doesn't fall under Trade Goods/Gem on a given build.
local QM_WatchlistScanTooltip
local function QM_EnsureWatchlistTooltip()
    if QM_WatchlistScanTooltip then return end
    QM_WatchlistScanTooltip = CreateFrame("GameTooltip", "QM_WatchlistScanTooltip", UIParent, "GameTooltipTemplate")
    QM_WatchlistScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
end

local function QM_HasCraftingReagentLine(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end
    QM_EnsureWatchlistTooltip()

    QM_WatchlistScanTooltip:ClearLines()
    local ok = pcall(function()
        QM_WatchlistScanTooltip:SetHyperlink("item:" .. itemID)
    end)
    if not ok then return false end

    local numLines = QM_WatchlistScanTooltip:NumLines() or 0
    for i = 2, numLines do
        local left = _G["QM_WatchlistScanTooltipTextLeft" .. i]
        local text = left and left:GetText()
        if text and text:find("Crafting Reagent", 1, true) then
            return true
        end
    end
    return false
end

local function IsReagentItemID(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end

    -- Strong signal: many crafting reagents include a tooltip line like
    -- "Dragon Isles Crafting Reagent" / "Khaz Algar Crafting Reagent".
    -- If we see it, treat as a reagent regardless of classID quirks.
    if QM_HasCraftingReagentLine(itemID) then
        return true
    end

    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if type(getInstant) ~= "function" then
        -- Fall back to tooltip detection only (slow but safe).
        return QM_HasCraftingReagentLine(itemID)
    end

    local _, _, _, equipLoc, _, classID = getInstant(itemID)
    if equipLoc and equipLoc ~= "" then return false end
    if classID == ITEM_CLASS_TRADEGOODS or classID == ITEM_CLASS_GEM or (ITEM_CLASS_REAGENT and classID == ITEM_CLASS_REAGENT) then
        return true
    end

    -- Fallback: if item info is available, use the item subType as a secondary signal.
    -- This helps in cases where classID is quirky but the item is clearly a crafting mat.
    if C_Item and C_Item.GetItemInfo then
        local name, link, quality, itemLevel, reqLevel, className, subClassName, maxStack, equipSlot = C_Item.GetItemInfo(itemID)
        if equipSlot and equipSlot ~= "" then return false end
        if subClassName then
            local known = {
                ["Cloth"] = true,
                ["Leather"] = true,
                ["Metal & Stone"] = true,
                ["Herb"] = true,
                ["Elemental"] = true,
                ["Cooking"] = true,
                ["Enchanting"] = true,
                ["Inscription"] = true,
                ["Jewelcrafting"] = true,
                ["Parts"] = true,
                ["Gems"] = true,
                ["Optional Reagents"] = true,
                ["Finishing Reagents"] = true,
                ["Reagent"] = true,
            }
            if known[subClassName] then
                return true
            end
        end
    end
    return false
end

local function DrawEmptyState(parent, text, yOffset)
    local msg = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    msg:SetPoint("TOPLEFT", 20, -yOffset)
    msg:SetTextColor(0.7, 0.7, 0.7)
    msg:SetText(text)
    return yOffset + 30
end

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
    -- Keep long names from colliding with the control cluster / progress bar.
    row.name:SetWidth(260)

    row.total = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    row.total:SetPoint("RIGHT", -12, 0)
    row.total:SetJustifyH("RIGHT")
    row.total:SetTextColor(1, 1, 1)

    row.remove = CreateFrame("Button", nil, row, "BackdropTemplate")
    row.remove:SetSize(60, 20)
    row.remove:SetPoint("RIGHT", row.total, "LEFT", -10, 0)
    row.remove:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
    row.remove:SetBackdropColor(0, 0, 0, 0.25)

    row.remove.text = row.remove:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
    row.remove.text:SetPoint("CENTER")
    row.remove.text:SetText("Unpin")

    -- Optional progress bar used for reagent targets.
    row._qmProgress = CreateFrame("StatusBar", nil, row, "BackdropTemplate")
	-- Ensure the bar sits above the row's backdrop textures.
	row._qmProgress:SetFrameLevel(row:GetFrameLevel() + 1)
    row._qmProgress:SetHeight(10)
    row._qmProgress:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
	-- Keep the fill texture below overlay text.
	local tex = row._qmProgress:GetStatusBarTexture()
	if tex then tex:SetDrawLayer("ARTWORK", 0) end
    row._qmProgress:SetMinMaxValues(0, 1)
    row._qmProgress:SetValue(0)
    row._qmProgress:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1 })
    row._qmProgress:SetBackdropColor(0, 0, 0, 0.35)
    row._qmProgress:SetBackdropBorderColor(0.35, 0.1, 0.1, 0.6)
    row._qmProgress:SetStatusBarColor(0.75, 0.12, 0.12, 0.9)
    row._qmProgress:Hide()

	-- Put the % text on the row (not the StatusBar) so it never gets hidden by the fill texture.
	row._qmProgressText = row._qmProgress:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
	row._qmProgressText:SetPoint("CENTER", row._qmProgress, "CENTER", 0, 0)
	row._qmProgressText:SetDrawLayer("OVERLAY", 20)
	row._qmProgressText:SetTextColor(1, 1, 1, 1)
	row._qmProgressText:SetShadowOffset(1, -1)
	row._qmProgressText:SetShadowColor(0, 0, 0, 1)
    row._qmProgressText:SetText("")
    row.remove.text:SetTextColor(1, 1, 1)

    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
        GameTooltip:Hide()
    end)

    return row
end

function TheQuartermaster:DrawWatchlist(parent)
    local yOffset = 8
    local width = parent:GetWidth() - 20

    local scopes = self:GetRecipeWatchlistScopes()
    local scope = self.recipeWatchlistScope or "general"
    local wl = self:GetRecipeWatchlistView(scope)
    local function ScopeButton(label, x, y, buttonWidth, callback)
        local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
        b:SetSize(buttonWidth, 26); b:SetPoint("TOPLEFT", x, -y)
        b:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        b:SetBackdropColor(unpack(COLORS.bgCard)); b:SetBackdropBorderColor(unpack(COLORS.border))
        b.text = b:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
        b.text:SetPoint("CENTER"); b.text:SetText(label)
        b:SetScript("OnClick", callback)
        return b
    end

    local function DrawLocations(itemID, y)
        local total, breakdown = self:CountItemTotals(itemID, wl.includeGuildBank)
        local function Line(label, count)
            local text = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
            text:SetPoint("TOPLEFT", 36, -y); text:SetWidth(width - 140); text:SetJustifyH("LEFT")
            text:SetText(label)
            if count then
                local value = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
                value:SetPoint("TOPRIGHT", -30, -y); value:SetText(tostring(count))
            end
            y = y + math.max(24, text:GetStringHeight() + 6)
        end
        Line(string.format(L.RW_LOCATIONS_TOTAL, total))
        Line(L.RW_LOCATIONS_HINT)
        local labels = {}
        for label, count in pairs(breakdown or {}) do if count > 0 then labels[#labels + 1] = label end end
        table.sort(labels)
        if #labels == 0 then
            Line(L.RW_LOCATIONS_EMPTY)
        else
            local pages = math.max(1, math.ceil(#labels / 10))
            local page = math.max(1, math.min(pages, self.watchlistLocationPage or 1))
            self.watchlistLocationPage = page
            for i = (page - 1) * 10 + 1, math.min(#labels, page * 10) do Line(labels[i], breakdown[labels[i]]) end
            if pages > 1 then
                ScopeButton(L.RB_PREVIOUS, 36, y, 100, function()
                    self.watchlistLocationPage = math.max(1, page - 1); self:RefreshUI()
                end)
                ScopeButton(string.format(L.RB_PAGE, page, pages), 146, y, 130, function() end)
                ScopeButton(L.RB_NEXT, 286, y, 100, function()
                    self.watchlistLocationPage = math.min(pages, page + 1); self:RefreshUI()
                end)
                y = y + 34
            end
        end
        return y + 10
    end

    -- If any item names are not yet cached on first load, request item data and redraw once.
    local needsRefresh = false
    local function RequestItemData(itemID)
        if C_Item and C_Item.RequestLoadItemDataByID and itemID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
        needsRefresh = true
    end

    
-- ===== HEADER CARD =====
local titleCard = CreateCard(parent, 72)
titleCard:SetPoint("TOPLEFT", 10, -yOffset)
titleCard:SetPoint("TOPRIGHT", -10, -yOffset)

local icon = titleCard:CreateTexture(nil, "ARTWORK")
icon:SetSize(36, 36)
icon:SetPoint("LEFT", 16, 0)
icon:SetTexture("Interface\\Icons\\INV_Misc_EngGizmos_30") -- clipboard/list style

local titleText = titleCard:CreateFontString(nil, "OVERLAY", "QuartermasterFontHeading")
titleText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -2)
titleText:SetText("Watchlist")
titleText:SetTextColor(unpack(COLORS.textNormal))

local subText = titleCard:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
subText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
subText:SetText("Pinned items, reagents and currencies (totals across your Warband)")
-- Auctionator export button (only enabled when Auctionator is installed)
local auctionatorBtn = CreateFrame("Button", nil, titleCard, "BackdropTemplate")
auctionatorBtn:SetSize(160, 26)
auctionatorBtn:SetPoint("RIGHT", -16, 0)
auctionatorBtn:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1 })
auctionatorBtn:SetBackdropColor(unpack(COLORS.bgCard))
auctionatorBtn:SetBackdropBorderColor(unpack(COLORS.border))

auctionatorBtn.text = auctionatorBtn:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
auctionatorBtn.text:SetPoint("CENTER")
auctionatorBtn.text:SetText(L.AU_SEND)
auctionatorBtn.text:SetTextColor(unpack(COLORS.textNormal))

local hasAuctionator = TheQuartermaster:HasAuctionatorShoppingAPI()
-- Keep the button mouse-enabled so the tooltip still works even if Auctionator is not loaded.
-- We visually grey it out and block clicks when inactive.
auctionatorBtn:SetEnabled(true)
auctionatorBtn._qmAuctionatorActive = hasAuctionator
auctionatorBtn:SetAlpha(hasAuctionator and 1 or 0.35)

auctionatorBtn:SetScript("OnEnter", function(selfBtn)
    local active = TheQuartermaster:HasAuctionatorShoppingAPI()
    if active then
        selfBtn:SetBackdropColor(unpack(COLORS.bgLight))
        selfBtn:SetBackdropBorderColor(unpack(COLORS.accent))
    end
    GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
    if not active then
        GameTooltip:AddLine(L.AU_UNAVAILABLE, 1, 0.2, 0.2)
    else
        GameTooltip:AddLine(L.AU_HELP, 1, 1, 1, true)
    end
    GameTooltip:Show()
end)
auctionatorBtn:SetScript("OnLeave", function(selfBtn)
    selfBtn:SetBackdropColor(unpack(COLORS.bgCard))
    selfBtn:SetBackdropBorderColor(unpack(COLORS.border))
    GameTooltip:Hide()
end)

auctionatorBtn:SetScript("OnClick", function()
    local _, message = TheQuartermaster:SendWatchlistToAuctionator(scope)
    TheQuartermaster:Print(message)
end)
subText:SetTextColor(0.7, 0.7, 0.7)
yOffset = yOffset + 84

    local selected = 1
    for i, option in ipairs(scopes) do if option.id == scope then selected = i end end
    local function Select(index)
        self.watchlistLocationItem = nil
        self.recipeWatchlistScope = scopes[index].id
        self.watchlistReagentPage = 1
        self:RefreshUI()
    end
    ScopeButton(scopes[selected].name .. "  v", 10, yOffset, width, function()
        if not self.watchlistPickerOpen then self.watchlistPickerPage = math.ceil(selected / 8) end
        self.watchlistPickerOpen = not self.watchlistPickerOpen
        self:RefreshUI()
    end)
    yOffset = yOffset + 36
    if self.watchlistPickerOpen then
        local pages = math.max(1, math.ceil(#scopes / 8))
        local page = math.max(1, math.min(pages, self.watchlistPickerPage or 1))
        for i = (page - 1) * 8 + 1, math.min(#scopes, page * 8) do
            ScopeButton(scopes[i].name, 20, yOffset, width - 20, function()
                self.watchlistPickerOpen = false
                self.watchlistCraftError = nil
                Select(i)
            end)
            yOffset = yOffset + 30
        end
        if pages > 1 then
            ScopeButton(L.RB_PREVIOUS, 20, yOffset, 100, function()
                self.watchlistPickerPage = math.max(1, page - 1); self:RefreshUI()
            end)
            ScopeButton(string.format(L.RB_PAGE, page, pages), 130, yOffset, 130, function() end)
            ScopeButton(L.RB_NEXT, 270, yOffset, 100, function()
                self.watchlistPickerPage = math.min(pages, page + 1); self:RefreshUI()
            end)
            yOffset = yOffset + 34
        end
    end
    ScopeButton(wl.includeGuildBank and L.RW_GUILD_ON or L.RW_GUILD_OFF, 10, yOffset, 250, function()
        self.db.profile.watchlistIncludeGuildBank = not wl.includeGuildBank
        self:RefreshUI()
    end)
    ScopeButton(self.db.profile.watchlistMissingOnly and L.RW_MISSING_ONLY or L.RW_SHOW_ALL, 270, yOffset, 210, function()
        self.db.profile.watchlistMissingOnly = not self.db.profile.watchlistMissingOnly
        self.watchlistReagentPage = 1
        self:RefreshUI()
    end)
    yOffset = yOffset + 36
    if self.watchlistCraftEditor then self.watchlistCraftEditor:Hide() end
    if type(scope) == "number" then
        local count = self:GetRecipeWatchlistCrafts(scope)
        local edit = self.watchlistCraftEditor
        if not edit then
            edit = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
            self.watchlistCraftEditor = edit
            edit:SetAutoFocus(false); edit:SetNumeric(true); edit:SetMaxLetters(5)
            edit:SetFontObject("QuartermasterFontBody"); edit:SetTextInsets(8, 8, 0, 0)
            edit:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
            edit:SetBackdropColor(unpack(COLORS.bgCard)); edit:SetBackdropBorderColor(unpack(COLORS.border))
            edit:SetTextColor(unpack(COLORS.textNormal))
            edit:SetScript("OnHide", function(b) b:ClearFocus() end)
        end
        local label = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
        label:SetPoint("TOPLEFT", 10, -yOffset - 6); label:SetText(L.RQ_CRAFTS)
        edit:ClearAllPoints(); edit:SetPoint("TOPLEFT", 145, -yOffset)
        edit:SetSize(90, 28); edit:SetText(tostring(count)); edit:Show()
        local function Apply()
            self.watchlistCraftError = not self:SetRecipeWatchlistCrafts(scope, edit:GetText()) and scope or nil
            edit:ClearFocus(); self:RefreshUI()
        end
        edit:SetScript("OnEnterPressed", Apply)
        edit:SetScript("OnEscapePressed", function(b) b:SetText(tostring(count)); b:ClearFocus() end)
        ScopeButton(L.RQ_APPLY, 245, yOffset, 100, Apply)
        yOffset = yOffset + 38
        if self.watchlistCraftError == scope then
            local errorText = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
            errorText:SetPoint("TOPLEFT", 10, -yOffset); errorText:SetWidth(width)
            errorText:SetText(L.RW_QUANTITY_ERROR)
            yOffset = yOffset + math.max(32, errorText:GetStringHeight() + 12)
        end
    end
    local scopeHint = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
    scopeHint:SetPoint("TOPLEFT", 10, -yOffset); scopeHint:SetWidth(width)
    scopeHint:SetText(scope == "all" and L.RW_COMBINED_HINT or L.RW_HINT)
    yOffset = yOffset + math.max(42, scopeHint:GetStringHeight() + 12)

    local pinnedItems, pinnedReagents, filteredTotals = {}, {}, {}
    for itemID in pairs(wl.items) do
        pinnedItems[#pinnedItems + 1] = itemID
    end
    for itemID, entry in pairs(wl.reagents) do
        local include = true
        if self.db.profile.watchlistMissingOnly then
            local target = type(entry) == "table" and entry.target
            include = type(target) == "number" and target > 0
            if include then
                filteredTotals[itemID] = self:CountItemTotals(itemID, wl.includeGuildBank)
                include = filteredTotals[itemID] < target
            end
        end
        if include then pinnedReagents[#pinnedReagents + 1] = itemID end
    end
    table.sort(pinnedItems)
    table.sort(pinnedReagents)

    if scope == "general" then
    -- Items
    local itemsTitle = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontHeading")
    itemsTitle:SetPoint("TOPLEFT", 10, -yOffset)
    itemsTitle:SetText("Items")
    itemsTitle:SetTextColor(unpack(COLORS.textNormal))
    yOffset = yOffset + 26

    if #pinnedItems == 0 then
        yOffset = DrawEmptyState(parent, "No pinned items yet. Use Global Search to pin items quickly.", yOffset)
    else
        local rowH = 30
        for i = 1, math.min(#pinnedItems, 60) do
            local itemID = pinnedItems[i]

            local total, breakdown = self:CountItemTotals(itemID, wl.includeGuildBank)
            local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
            local row = CreateRow(parent, yOffset, width, rowH)
            row.icon:SetTexture(icon or 134400)
            if not name then
                RequestItemData(itemID)
            end
            row.name:SetText(name or ("Item " .. tostring(itemID)))
            do local r,g,b = QM_GetItemQualityColor(itemID); row.name:SetTextColor(r,g,b) end
            -- Items do not use target amounts/progress bars.
            row.total:SetText(tostring(total))

            -- Rows are reused; ensure reagent-only widgets are hidden/reset.
            if row._qmBar then row._qmBar:Hide() end
            if row._qmTargetBtn then row._qmTargetBtn:Hide() end
            row.total:ClearAllPoints()
            row.total:SetPoint("RIGHT", -16, 0)

            row.remove:SetScript("OnClick", function()
                self:ToggleWatchlistItem(itemID)
            end)

            row:SetScript("OnEnter", function(selfRow)
                selfRow:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
                GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
                if GameTooltip.SetItemByID then
                    GameTooltip:SetItemByID(itemID)
                end
                GameTooltip:Show()
            end)

            yOffset = yOffset + rowH + 6
        end
    end

    yOffset = yOffset + 12

    end

    -- Reagents
    local reagTitle = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontHeading")
    reagTitle:SetPoint("TOPLEFT", 10, -yOffset)
    reagTitle:SetText(L.RW_REAGENTS .. " — " .. L.RW_LOCATIONS_CLICK)
    reagTitle:SetTextColor(unpack(COLORS.textNormal))
    yOffset = yOffset + 26

    if #pinnedReagents == 0 then
        yOffset = DrawEmptyState(parent, self.db.profile.watchlistMissingOnly and next(wl.reagents) and L.RW_NO_MISSING or L.RW_EMPTY, yOffset)
    else
        local rowH = 30
        local pages = math.max(1, math.ceil(#pinnedReagents / 30))
        local page = math.min(pages, math.max(1, self.watchlistReagentPage or 1))
        self.watchlistReagentPage = page
        ScopeButton(L.RB_PREVIOUS, 10, yOffset, 90, function()
            self.watchlistReagentPage = math.max(1, page - 1); self:RefreshUI()
        end)
        ScopeButton(string.format(L.RB_PAGE, page, pages), 110, yOffset, 130, function() end)
        ScopeButton(L.RB_NEXT, 250, yOffset, 90, function()
            self.watchlistReagentPage = math.min(pages, page + 1); self:RefreshUI()
        end)
        yOffset = yOffset + 34
        for _, col in ipairs({{L.RW_HAVE, -350}, {L.RW_NEED, -260}, {L.RW_MISSING, -170}}) do
            local heading = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
            heading:SetPoint("TOPRIGHT", col[2], -yOffset); heading:SetWidth(85); heading:SetJustifyH("RIGHT")
            heading:SetText(col[1])
        end
        yOffset = yOffset + 24
        for i = (page - 1) * 30 + 1, math.min(#pinnedReagents, page * 30) do
            local itemID = pinnedReagents[i]

            local total = filteredTotals[itemID]
            if total == nil then total = self:CountItemTotals(itemID, wl.includeGuildBank) end
            local target = type(wl.reagents[itemID]) == "table" and wl.reagents[itemID].target or nil
            local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
            local row = CreateRow(parent, yOffset, width, rowH)
            row.icon:SetTexture(icon or 134400)
            row:SetScript("OnClick", function()
                self.watchlistLocationItem = self.watchlistLocationItem ~= itemID and itemID or nil
                self.watchlistLocationPage = 1
                self:RefreshUI()
            end)
            if not name then
                RequestItemData(itemID)
            end
            row.name:SetText(ns.UI_IngredientVariantLabel(itemID))
            row.name:SetWordWrap(false)
            do local r,g,b = QM_GetItemQualityColor(itemID); row.name:SetTextColor(r,g,b) end
            row.total:Hide()
            row.name:SetWidth(math.max(100, width - 480))
            local function Column(value, offset)
                local text = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
                text:SetPoint("RIGHT", offset, 0); text:SetWidth(85); text:SetJustifyH("RIGHT")
                text:SetText(tostring(value))
                return text
            end
            row.have = Column(total, -340)
            row.need = Column(target or "—", -250)
            row.missing = Column(target and math.max(0, target - total) or "—", -160)
            row.remove:ClearAllPoints(); row.remove:SetPoint("RIGHT", -8, 0)

            -- Target button
            if not row._qmTargetBtn then
                row._qmTargetBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                row._qmTargetBtn:SetSize(56, 20)
                row._qmTargetBtn:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
                row._qmTargetBtn:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
                row._qmTargetBtn:SetBackdropColor(0, 0, 0, 0.20)
                row._qmTargetBtn.text = row._qmTargetBtn:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
                row._qmTargetBtn.text:SetPoint("CENTER")
                row._qmTargetBtn.text:SetText("Target")
            end
            row._qmTargetBtn:SetShown(scope == "general")
            row.remove:SetShown(scope ~= "all")

            row._qmTargetBtn:SetScript("OnClick", function()
                if not StaticPopupDialogs["QM_SET_REAGENT_TARGET"] then
                    StaticPopupDialogs["QM_SET_REAGENT_TARGET"] = {
                        text = "Set desired amount",
                        button1 = OKAY,
                        button2 = CANCEL,
                        hasEditBox = true,
                        maxLetters = 8,
                        whileDead = true,
                        hideOnEscape = true,
                        OnShow = function(selfPopup, data)
                            local cur = TheQuartermaster:GetWatchlistReagentTarget(data.itemID) or 0
                            local eb = selfPopup.editBox or selfPopup.EditBox
                            if eb then
                                eb:SetText(tostring(cur))
                                eb:HighlightText()
                            end
                        end,
                        OnAccept = function(selfPopup, data)
                            local eb = selfPopup.editBox or selfPopup.EditBox
                            local val = tonumber((eb and eb:GetText()) or "")
                            if not val then val = 0 end
                            TheQuartermaster:SetWatchlistReagentTarget(data.itemID, math.max(0, math.floor(val + 0.5)))
                        end,
                        EditBoxOnEnterPressed = function(selfPopup)
                            local parentPopup = selfPopup:GetParent()
                            if parentPopup and parentPopup.button1 and parentPopup.button1:IsEnabled() then
                                parentPopup.button1:Click()
                            end
                        end,
                    }
                end
                StaticPopup_Show("QM_SET_REAGENT_TARGET", nil, nil, { itemID = itemID })
            end)

            row.remove:SetScript("OnClick", function()
                if scope == "general" then self:ToggleWatchlistReagent(itemID)
                elseif type(scope) == "number" then self:ToggleRecipeIngredient(scope, itemID) end
            end)

            row:SetScript("OnEnter", function(selfRow)
                selfRow:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
                GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
                if GameTooltip.SetItemByID then
                    GameTooltip:SetItemByID(itemID)
                end
                GameTooltip:Show()
            end)

            yOffset = yOffset + rowH + 6
            if self.watchlistLocationItem == itemID then yOffset = DrawLocations(itemID, yOffset) end
        end
    end

    yOffset = yOffset + 12

    if scope == "general" then
    -- Currency
    local curTitle = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontHeading")
    curTitle:SetPoint("TOPLEFT", 10, -yOffset)
    curTitle:SetText("Currency")
    curTitle:SetTextColor(unpack(COLORS.textNormal))
    yOffset = yOffset + 26

    local anyCur = false
    for currencyID in pairs(wl.currencies) do
        anyCur = true
        break
    end
    if not anyCur then
        yOffset = DrawEmptyState(parent, "No pinned currencies yet. Use Global Search to pin currencies quickly.", yOffset)
    else
        local rowH = 30
        local shown = 0
        for currencyID in pairs(wl.currencies) do
            shown = shown + 1
            if shown > 60 then break end

            local total, breakdown = self:CountCurrencyTotals(currencyID)
            local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(currencyID)
            local name = info and info.name or ("Currency " .. tostring(currencyID))
            local icon = info and info.iconFileID
            local row = CreateRow(parent, yOffset, width, rowH)
            row.icon:SetTexture(icon or 134400)
            row.name:SetText(name)
            row.total:SetText(tostring(total))

            -- Rows are reused; ensure reagent-only widgets are hidden/reset.
            if row._qmBar then row._qmBar:Hide() end
            if row._qmTargetBtn then row._qmTargetBtn:Hide() end
            row.total:ClearAllPoints()
            row.total:SetPoint("RIGHT", -16, 0)

            row.remove:SetScript("OnClick", function()
                self:ToggleWatchlistCurrency(currencyID)
            end)

            row:SetScript("OnEnter", function(selfRow)
                selfRow:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
                GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
                if GameTooltip.SetCurrencyByID then
                    GameTooltip:SetCurrencyByID(currencyID)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Totals", 1,1,1)
                for label, count in pairs(breakdown) do
                    GameTooltip:AddDoubleLine(label, tostring(count), 0.8,0.8,0.8, 1,1,1)
                end
                GameTooltip:Show()
            end)

            yOffset = yOffset + rowH + 6
        end
    end



    end

-- ===== HOW TO PIN NOTICE =====
-- Keep the notice near the bottom of the visible viewport when the list is short,
-- but allow it to flow naturally after content when the list is long.
local viewportH = (parent:GetParent() and parent:GetParent():GetHeight()) or 520
local desiredTop = viewportH - 85 -- approx height + padding
if yOffset < desiredTop then
    yOffset = desiredTop
else
    yOffset = yOffset + 15
end

local noticeFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
noticeFrame:SetSize(width - 20, 60)
noticeFrame:SetPoint("TOPLEFT", 10, -yOffset)
noticeFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
noticeFrame:SetBackdropColor(unpack(COLORS.bgCard))
noticeFrame:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)

local noticeIcon = noticeFrame:CreateTexture(nil, "ARTWORK")
noticeIcon:SetSize(24, 24)
noticeIcon:SetPoint("LEFT", 10, 0)
noticeIcon:SetTexture("Interface\\Common\\FavoritesIcon")

local noticeText = noticeFrame:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
noticeText:SetPoint("LEFT", noticeIcon, "RIGHT", 10, 5)
noticeText:SetPoint("RIGHT", -10, 5)
noticeText:SetJustifyH("LEFT")
noticeText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
noticeText:SetText("How to pin to Watchlist")

local noticeSubText = noticeFrame:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
noticeSubText:SetPoint("TOPLEFT", noticeIcon, "TOPRIGHT", 10, -15)
noticeSubText:SetPoint("RIGHT", -10, 0)
noticeSubText:SetJustifyH("LEFT")
noticeSubText:SetTextColor(0.8, 0.8, 0.8)
noticeSubText:SetText("Tip: In Global Search, right-click a result row to Pin/Unpin. You can also click the star icon.")

yOffset = yOffset + 75


    -- If any rows were drawn using fallback text (e.g. "Item 12345"), schedule a single redraw once item data is available.
    if needsRefresh and not TheQuartermaster._watchlistRefreshPending then
        TheQuartermaster._watchlistRefreshPending = true
        C_Timer.After(0.25, function()
            TheQuartermaster._watchlistRefreshPending = nil
            local mf = TheQuartermaster.UI and TheQuartermaster.UI.mainFrame
            if mf and mf:IsShown() and mf.currentTab == "watchlist" then
                TheQuartermaster:PopulateContent()
            end
        end)
    end
parent:SetHeight(yOffset + 20)
    return yOffset
end
