--[[
    The Quartermaster - Watchlist UI
    Pins important items/currencies and shows totals across your Warband.
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard
-- Compatibility helpers
local function QM_IsAddOnLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    end
    if IsAddOnLoaded then
        return IsAddOnLoaded(name)
    end
    return false
end

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
    local msg = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
    -- Keep long names from colliding with the control cluster / progress bar.
    row.name:SetWidth(260)

    row.total = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.total:SetPoint("RIGHT", -12, 0)
    row.total:SetJustifyH("RIGHT")
    row.total:SetTextColor(1, 1, 1)

    row.remove = CreateFrame("Button", nil, row, "BackdropTemplate")
    row.remove:SetSize(60, 20)
    row.remove:SetPoint("RIGHT", row.total, "LEFT", -10, 0)
    row.remove:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
    row.remove:SetBackdropColor(0, 0, 0, 0.25)

    row.remove.text = row.remove:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
	row._qmProgressText = row._qmProgress:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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

local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -2)
titleText:SetText("Watchlist")
titleText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])

local subText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
subText:SetText("Pinned items, reagents and currencies (totals across your Warband)")
-- Auctionator export button (only enabled when Auctionator is installed)
local auctionatorBtn = CreateFrame("Button", nil, titleCard, "BackdropTemplate")
auctionatorBtn:SetSize(160, 26)
auctionatorBtn:SetPoint("RIGHT", -16, 0)
auctionatorBtn:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1 })
auctionatorBtn:SetBackdropColor(0.10, 0.10, 0.12, 0.9)
auctionatorBtn:SetBackdropBorderColor(0.35, 0.1, 0.1, 0.8)

auctionatorBtn.text = auctionatorBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
auctionatorBtn.text:SetPoint("CENTER")
auctionatorBtn.text:SetText("Export (Auctionator)")

local hasAuctionator = QM_IsAddOnLoaded("Auctionator")
-- Keep the button mouse-enabled so the tooltip still works even if Auctionator is not loaded.
-- We visually grey it out and block clicks when inactive.
auctionatorBtn:SetEnabled(true)
auctionatorBtn._qmAuctionatorActive = hasAuctionator
auctionatorBtn:SetAlpha(hasAuctionator and 1 or 0.35)

auctionatorBtn:SetScript("OnEnter", function(selfBtn)
    local active = QM_IsAddOnLoaded("Auctionator")
    GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
    if not active then
        GameTooltip:AddLine("Auctionator not an active addon", 1, 0.2, 0.2)
    else
        GameTooltip:AddLine("Click to export a shopping list to import into Auctionator", 1, 1, 1, true)
    end
    GameTooltip:Show()
end)
auctionatorBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function BuildAuctionatorImportText()
    local wl = TheQuartermaster.db and TheQuartermaster.db.profile and TheQuartermaster.db.profile.watchlist or nil
    if not wl or not wl.reagents then
        return "Watchlist Items"
    end

    local entries = {}

    for itemID, entry in pairs(wl.reagents) do
        if entry then
            local target = TheQuartermaster:GetWatchlistReagentTarget(itemID) or 0
            if target and target > 0 then
                local total = TheQuartermaster:CountItemTotals(itemID, wl.includeGuildBank) or 0
                if total < target then
                    -- Prefer C_Item (more reliable than GetItemInfo for uncached items)
                    local name, bindType
                    if C_Item and C_Item.GetItemInfo then
                        local info = C_Item.GetItemInfo(itemID)
                        if info then
                            name = info.itemName
                            bindType = info.bindType
                        else
                            if C_Item.RequestLoadItemDataByID then
                                C_Item.RequestLoadItemDataByID(itemID)
                            end
                        end
                    end

                    if not name then
                        name, _, _, _, _, _, _, _, _, _, _, _, bindType = GetItemInfo(itemID)
                    end

                    -- Skip BoP / soulbound and Sparks (character-specific)
                    local lname = name and name:lower() or ""
                    if name and bindType ~= 1 and not lname:find("spark") then
                        -- Auctionator shopping list format uses caret (^) separators between entries.
                        -- IMPORTANT: Do not leave a trailing caret at the end.
                        table.insert(entries, string.format('"%s";;0;0;0;0;0;0;0;0;;#;;', name))
                    end
                end
            end
        end
    end

    if #entries == 0 then
        return "Watchlist Items"
    end

    return "Watchlist Items^" .. table.concat(entries, "^")
end

local function EnsureAuctionatorCopyPopup()
    if TheQuartermaster._qmAuctionatorCopyFrame then
        return TheQuartermaster._qmAuctionatorCopyFrame
    end

    local f = CreateFrame("Frame", "QM_AuctionatorCopyFrame", UIParent, "BackdropTemplate")
    f:SetSize(640, 260)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
    do local b = COLORS.border; f:SetBackdropBorderColor(b[1], b[2], b[3], 0.9) end
    f:Hide()

    local titleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(34)
    titleBar:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
    do local a = COLORS.accentDark; titleBar:SetBackdropColor(a[1], a[2], a[3], 0.92) end

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", 14, 0)
    title:SetText("Auctionator Import Text")
    title:SetTextColor(1, 1, 1)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 14, -10)
    hint:SetText("Ctrl+C to copy — closes automatically after copying")
    hint:SetTextColor(0.85, 0.85, 0.85)

    -- Scrollable edit box (for long Auctionator lists)
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -102)
    scroll:SetPoint("BOTTOMRIGHT", -34, 16)
    scroll:SetFrameLevel(f:GetFrameLevel() + 2)

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(true)
    eb:SetFontObject("ChatFontNormal")
    eb:SetWidth(scroll:GetWidth() - 16)
    eb:SetTextInsets(10, 10, 10, 10)
    eb:EnableMouse(true)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnKeyDown", function(_, key)
        if IsControlKeyDown() and (key == "C" or key == "c") then
            C_Timer.After(0.05, function()
                if f:IsShown() then f:Hide() end
            end)
        end
    end)
    eb:SetScript("OnTextChanged", function(self)
        scroll:UpdateScrollChildRect()
    end)

    -- Backdrop around the scroll frame (matches QM theme)
    scroll.bg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    scroll.bg:SetPoint("TOPLEFT", scroll, -2, 2)
    scroll.bg:SetPoint("BOTTOMRIGHT", scroll, 22, -2)
    scroll.bg:SetFrameLevel(f:GetFrameLevel() + 1)
    scroll.bg:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1 })
    scroll.bg:SetBackdropColor(0, 0, 0, 0.55)
    do local b = COLORS.border; scroll.bg:SetBackdropBorderColor(b[1], b[2], b[3], 0.85) end

    scroll:SetScrollChild(eb)

    f:SetScript("OnShow", function()
        eb:SetWidth(math.max(1, scroll:GetWidth() - 24))
        scroll:UpdateScrollChildRect()
    end)

    f.editBox = eb

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    TheQuartermaster._qmAuctionatorCopyFrame = f
    return f
end

local function ShowAuctionatorCopyPopup()
    local textToCopy = BuildAuctionatorImportText()
    local f = EnsureAuctionatorCopyPopup()

    -- Try to keep it above the main QM frame if it exists
    if TheQuartermaster.UI and TheQuartermaster.UI.mainFrame and TheQuartermaster.UI.mainFrame:IsShown() then
        f:ClearAllPoints()
        f:SetPoint("CENTER", TheQuartermaster.UI.mainFrame, "CENTER", 0, 0)
    else
        f:ClearAllPoints()
        f:SetPoint("CENTER")
    end

    f:Show()
    f.editBox:SetText(textToCopy)
    f.editBox:HighlightText()
    f.editBox:SetFocus()
end

auctionatorBtn:SetScript("OnClick", function()
    local active = QM_IsAddOnLoaded("Auctionator")
    if not active then
        -- Do nothing (tooltip already explains why)
        return
    end
    ShowAuctionatorCopyPopup()
end)
subText:SetTextColor(0.7, 0.7, 0.7)
yOffset = yOffset + 84

    local wl = (self.db and self.db.profile and self.db.profile.watchlist) or { items = {}, reagents = {}, currencies = {}, includeGuildBank = true }
    wl.items = wl.items or {}
    wl.reagents = wl.reagents or {}
    wl.currencies = wl.currencies or {}

    local pinnedItems, pinnedReagents = {}, {}
    for itemID in pairs(wl.items) do
        pinnedItems[#pinnedItems + 1] = itemID
    end
    for itemID in pairs(wl.reagents) do
        pinnedReagents[#pinnedReagents + 1] = itemID
    end
    table.sort(pinnedItems)
    table.sort(pinnedReagents)

    -- Items
    local itemsTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    itemsTitle:SetPoint("TOPLEFT", 10, -yOffset)
    itemsTitle:SetText("Items")
    itemsTitle:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
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

    -- Reagents
    local reagTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    reagTitle:SetPoint("TOPLEFT", 10, -yOffset)
    reagTitle:SetText("Reagents")
    reagTitle:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    yOffset = yOffset + 26

    if #pinnedReagents == 0 then
        yOffset = DrawEmptyState(parent, "No pinned reagents yet. Pin reagents from Materials or Global Search.", yOffset)
    else
        local rowH = 30
        for i = 1, math.min(#pinnedReagents, 60) do
            local itemID = pinnedReagents[i]

            local total, breakdown = self:CountItemTotals(itemID, wl.includeGuildBank)
            local target = self:GetWatchlistReagentTarget(itemID)
            local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
            local row = CreateRow(parent, yOffset, width, rowH)
            row.icon:SetTexture(icon or 134400)
            if not name then
                RequestItemData(itemID)
            end
            row.name:SetText(name or ("Item " .. tostring(itemID)))
            do local r,g,b = QM_GetItemQualityColor(itemID); row.name:SetTextColor(r,g,b) end
            if target and target > 0 then
                row.total:SetText(string.format("%d/%d", total, target))
            else
                row.total:SetText(tostring(total))
            end

            -- Progress bar (only when target is set)
            if target and target > 0 then
                if not row._qmBar then
                    row._qmBar = CreateFrame("StatusBar", nil, row, "BackdropTemplate")
					-- Keep the bar above the row backdrop, but ensure the % text is above the fill.
					row._qmBar:SetFrameLevel(row:GetFrameLevel() + 1)
                    -- Layout is refined below once the Target button exists.
                    row._qmBar:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
                    row._qmBar:SetPoint("RIGHT", row.total, "LEFT", -10, 0)
                    row._qmBar:SetHeight(12)
                    row._qmBar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
					local tex = row._qmBar:GetStatusBarTexture()
					if tex and tex.SetDrawLayer then
						-- Keep fill behind the percentage text.
						tex:SetDrawLayer("BACKGROUND", 0)
					end
                    row._qmBar:SetMinMaxValues(0, 1)
                    row._qmBar:SetValue(0)
                    row._qmBar:SetStatusBarColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.90)
                    row._qmBar:SetBackdrop({
                        bgFile = "Interface\\BUTTONS\\WHITE8X8",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        edgeSize = 12,
                        insets = { left = 2, right = 2, top = 2, bottom = 2 },
                    })
                    row._qmBar:SetBackdropColor(0, 0, 0, 0.55)
                    row._qmBar:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.85)

					row._qmBarText = row._qmBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					if row._qmBarText and row._qmBarText.SetDrawLayer then
						row._qmBarText:SetDrawLayer("OVERLAY", 7)
					end
                    row._qmBarText:SetPoint("CENTER", row._qmBar, "CENTER", 0, 0)
					row._qmBarText:SetText("")
					row._qmBarText:SetTextColor(1, 1, 1)
					if row._qmBarText.SetShadowOffset then
						row._qmBarText:SetShadowOffset(1, -1)
						row._qmBarText:SetShadowColor(0, 0, 0, 0.8)
					end
                end
                row._qmBar:Show()
                -- Prefer to span the bar between the name and the Target button so it reads as a "progress column".
                if row._qmTargetBtn then
                    row._qmBar:ClearAllPoints()
                    row._qmBar:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
                    row._qmBar:SetPoint("RIGHT", row._qmTargetBtn, "LEFT", -10, 0)
                end
                row._qmBar:SetMinMaxValues(0, target)
                row._qmBar:SetValue(math.min(total, target))
                if row._qmBarText then
                    row._qmBarText:SetText(string.format("%d%%", math.floor((math.min(total, target) / math.max(1, target)) * 100 + 0.5)))
                end
            elseif row._qmBar then
                row._qmBar:Hide()
                if row._qmBarText then row._qmBarText:SetText("") end
            end

            -- Target button
            if not row._qmTargetBtn then
                row._qmTargetBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                row._qmTargetBtn:SetSize(56, 20)
                row._qmTargetBtn:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
                row._qmTargetBtn:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
                row._qmTargetBtn:SetBackdropColor(0, 0, 0, 0.20)
                row._qmTargetBtn.text = row._qmTargetBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row._qmTargetBtn.text:SetPoint("CENTER")
                row._qmTargetBtn.text:SetText("Target")
            end
            row._qmTargetBtn:Show()

            -- Ensure progress bar doesn't run under the Target/Unpin controls
            if row._qmBar then
                row._qmBar:ClearAllPoints()
                row._qmBar:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
                row._qmBar:SetPoint("RIGHT", row._qmTargetBtn, "LEFT", -10, 0)
            end
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
                self:ToggleWatchlistReagent(itemID)
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

    -- Currency
    local curTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    curTitle:SetPoint("TOPLEFT", 10, -yOffset)
    curTitle:SetText("Currency")
    curTitle:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
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
noticeFrame:SetBackdropColor(0.1, 0.1, 0.15, 0.9)
noticeFrame:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)

local noticeIcon = noticeFrame:CreateTexture(nil, "ARTWORK")
noticeIcon:SetSize(24, 24)
noticeIcon:SetPoint("LEFT", 10, 0)
noticeIcon:SetTexture("Interface\\Common\\FavoritesIcon")

local noticeText = noticeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
noticeText:SetPoint("LEFT", noticeIcon, "RIGHT", 10, 5)
noticeText:SetPoint("RIGHT", -10, 5)
noticeText:SetJustifyH("LEFT")
noticeText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
noticeText:SetText("How to pin to Watchlist")

local noticeSubText = noticeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
