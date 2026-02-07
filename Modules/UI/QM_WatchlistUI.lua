--[[
    The Quartermaster - Watchlist UI
    Pins important items/currencies and shows totals across your Warband.
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard

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
            row.name:SetText(name or ("Item " .. tostring(itemID)))
            local target = self:GetWatchlistReagentTarget(itemID)
            if target and target > 0 then
                row.total:SetText(string.format("%d/%d", total, target))
            else
                row.total:SetText(tostring(total))
            end

            -- Progress bar (only when a target is set)
            if not row.progress then
                row.progress = CreateFrame("StatusBar", nil, row)
                row.progress:SetSize(160, 8)
                row.progress:SetPoint("RIGHT", row.total, "LEFT", -8, 0)
                row.progress:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
                row.progress.bg = row.progress:CreateTexture(nil, "BACKGROUND")
                row.progress.bg:SetAllPoints(true)
                row.progress.bg:SetColorTexture(0, 0, 0, 0.35)
            end
            if target and target > 0 then
                row.progress:Show()
                row.progress:SetMinMaxValues(0, target)
                row.progress:SetValue(math.min(total, target))
            else
                row.progress:Hide()
            end

            if not row.targetBtn then
                row.targetBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                row.targetBtn:SetSize(52, 22)
                row.targetBtn:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
                row.targetBtn:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
                row.targetBtn:SetBackdropColor(0, 0, 0, 0.20)
                row.targetBtn.text = row.targetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.targetBtn.text:SetPoint("CENTER")
                row.targetBtn.text:SetText("Target")
                row.targetBtn:SetScript("OnEnter", function(btn)
                    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                    GameTooltip:AddLine("Set desired amount", 1, 1, 1)
                    GameTooltip:AddLine("Used for progress bars on Watchlist.", 0.7, 0.7, 0.7)
                    GameTooltip:Show()
                end)
                row.targetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end

            row.targetBtn:SetScript("OnClick", function()
                if self.OpenSetReagentTargetPopup then
                    self:OpenSetReagentTargetPopup(itemID)
                else
                    -- fallback
                    self:SetWatchlistReagentTarget(itemID, 0)
                end
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
            row.name:SetText(name or ("Item " .. tostring(itemID)))
            if target and target > 0 then
                row.total:SetText(string.format("%d/%d", total, target))
            else
                row.total:SetText(tostring(total))
            end

            -- Progress bar (only when target is set)
            if target and target > 0 then
                if not row._qmBar then
                    row._qmBar = CreateFrame("StatusBar", nil, row, "BackdropTemplate")
                    row._qmBar:SetPoint("LEFT", row.name, "LEFT", 0, -10)
                    row._qmBar:SetPoint("RIGHT", row.total, "LEFT", -10, -10)
                    row._qmBar:SetHeight(6)
                    row._qmBar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
                    row._qmBar:SetMinMaxValues(0, 1)
                    row._qmBar:SetValue(0)
                    row._qmBar:SetStatusBarColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)
                    row._qmBar:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
                    row._qmBar:SetBackdropColor(0, 0, 0, 0.35)
                end
                row._qmBar:Show()
                row._qmBar:SetMinMaxValues(0, target)
                row._qmBar:SetValue(math.min(total, target))
            elseif row._qmBar then
                row._qmBar:Hide()
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
                            selfPopup.editBox:SetText(tostring(cur))
                            selfPopup.editBox:HighlightText()
                        end,
                        OnAccept = function(selfPopup, data)
                            local val = tonumber(selfPopup.editBox:GetText() or "")
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

parent:SetHeight(yOffset + 20)
    return yOffset
end
