--[[
    The Quartermaster - Watchlist UI
    Pins important items/currencies and shows totals across your Warband.
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard

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
subText:SetText("Pinned items and currencies (totals across your Warband)")
subText:SetTextColor(0.7, 0.7, 0.7)
yOffset = yOffset + 84

    local wl = (self.db and self.db.profile and self.db.profile.watchlist) or { items = {}, currencies = {}, includeGuildBank = true }
    wl.items = wl.items or {}
    wl.currencies = wl.currencies or {}

    -- Items
    local itemsTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    itemsTitle:SetPoint("TOPLEFT", 10, -yOffset)
    itemsTitle:SetText("Items")
    itemsTitle:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    yOffset = yOffset + 26

    local anyItems = false
    for itemID in pairs(wl.items) do
        anyItems = true
        break
    end
    if not anyItems then
        yOffset = DrawEmptyState(parent, "No pinned items yet. Use Global Search to pin items quickly.", yOffset)
    else
        local rowH = 30
        local shown = 0
        for itemID in pairs(wl.items) do
            shown = shown + 1
            if shown > 60 then break end

            local total, breakdown = self:CountItemTotals(itemID, wl.includeGuildBank)
            local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
            local row = CreateRow(parent, yOffset, width, rowH)
            row.icon:SetTexture(icon or 134400)
            row.name:SetText(name or ("Item " .. tostring(itemID)))
            row.total:SetText(tostring(total))

            row.remove:SetScript("OnClick", function()
                self:ToggleWatchlistItem(itemID)
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
yOffset = yOffset + 15

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
noticeSubText:SetText("Open Global Search, then click the star icon next to a result to pin/unpin items or currencies.")

yOffset = yOffset + 75

    parent:SetHeight(yOffset + 20)
    return yOffset
end
