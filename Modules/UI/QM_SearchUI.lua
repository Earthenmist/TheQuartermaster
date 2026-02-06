--[[
    The Quartermaster - Global Search UI
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
    row.pin:SetBackdropColor(0, 0, 0, 0.25)

    row.pin.text = row.pin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.pin.text:SetPoint("CENTER")
    row.pin.text:SetText("★")
    row.pin.text:SetTextColor(1, 1, 1)

    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
        GameTooltip:Hide()
    end)

    return row
end

function TheQuartermaster:DrawGlobalSearch(parent)

local yOffset = 8
local width = parent:GetWidth() - 20

-- Header card (icon + title/subtitle)
local header = CreateCard(parent, 72)
header:SetWidth(width)
header:SetPoint("TOPLEFT", 10, -yOffset)

local icon = header:CreateTexture(nil, "ARTWORK")
icon:SetSize(36, 36)
icon:SetPoint("LEFT", 16, 0)
icon:SetTexture("Interface\Icons\INV_Misc_Spyglass_02")

local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -2)
title:SetText("Global Search")
title:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])

local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
subtitle:SetText("Find items and currencies across your Warband, characters, and caches")
subtitle:SetTextColor(0.65, 0.65, 0.65)

yOffset = yOffset + 86

-- Controls card (extra padding)
local controls = CreateCard(parent, 64)
controls:SetWidth(width)
controls:SetPoint("TOPLEFT", 10, -yOffset)

local wl = self.db and self.db.profile and self.db.profile.watchlist
if not wl then wl = { includeGuildBank = true } end

local mode = ns.globalSearchMode or "all"
local includeGuild = (ns.globalSearchIncludeGuild ~= nil) and ns.globalSearchIncludeGuild or (wl.includeGuildBank ~= false)

-- Mode dropdown
if not controls.modeDrop then
    local drop = CreateFrame("Frame", nil, controls, "UIDropDownMenuTemplate")
    drop:SetPoint("TOPLEFT", 6, -18) -- padding
    UIDropDownMenu_SetWidth(drop, 120)
    UIDropDownMenu_SetText(drop, "All")

    local function SetMode(newMode, label)
        ns.globalSearchMode = newMode
        UIDropDownMenu_SetText(drop, label)
        self:PopulateContent()
    end

    UIDropDownMenu_Initialize(drop, function()
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.func = "All", function() SetMode("all", "All") end
        UIDropDownMenu_AddButton(info)
        info.text, info.func = "Items", function() SetMode("items", "Items") end
        UIDropDownMenu_AddButton(info)
        info.text, info.func = "Currency", function() SetMode("currency", "Currency") end
        UIDropDownMenu_AddButton(info)
    end)

    controls.modeDrop = drop
end

-- Include Guild Bank checkbox
if not controls.guildCheck then
    local cb = CreateFrame("CheckButton", nil, controls, "UICheckButtonTemplate")
    cb:SetPoint("LEFT", controls.modeDrop, "RIGHT", 30, 0)
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    cb.text:SetText("Include Guild Bank")
    cb:SetScript("OnClick", function(selfBtn)
        ns.globalSearchIncludeGuild = selfBtn:GetChecked()
        if TheQuartermaster.db and TheQuartermaster.db.profile and TheQuartermaster.db.profile.watchlist then
            TheQuartermaster.db.profile.watchlist.includeGuildBank = ns.globalSearchIncludeGuild
        end
        TheQuartermaster:PopulateContent()
    end)
    controls.guildCheck = cb
end

controls.guildCheck:SetChecked(includeGuild)

-- Fix dropdown label on refresh
if mode == "items" then UIDropDownMenu_SetText(controls.modeDrop, "Items")
elseif mode == "currency" then UIDropDownMenu_SetText(controls.modeDrop, "Currency")
else UIDropDownMenu_SetText(controls.modeDrop, "All") end

yOffset = yOffset + 74

local searchText = ns.globalSearchText or ""

    if searchText == "" then
        return DrawEmptyState(parent, "Type in the search box above to search across your Warband.", yOffset)
    end

    local results = self:PerformGlobalSearch(searchText, mode, includeGuild)

    -- Items results
    if mode == "all" or mode == "items" then
        local items = results.items or {}
        local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 10, -yOffset)
        title:SetText("Items")
        title:SetTextColor(1, 1, 1)
        yOffset = yOffset + 26

        if #items == 0 then
            yOffset = DrawEmptyState(parent, "No item matches found.", yOffset)
        else
            local rowH = 30
            for i=1, math.min(#items, 60) do
                local r = items[i]
                local item = r.item
                local row = CreateRow(parent, yOffset, width, rowH)
                row.icon:SetTexture(item and item.iconFileID or 134400)
                row.name:SetText(item and item.name or ("Item " .. tostring(item and item.itemID or "")))
                row.meta:SetText((r.location or "") .. (r.locationDetail and (" • " .. r.locationDetail) or ""))
                row.count:SetText(tostring(item and (item.stackCount or item.count or 1) or 1))

                local itemID = item and item.itemID
                local pinned = itemID and self:IsWatchlistedItem(itemID)
                row.pin.text:SetTextColor(pinned and COLORS.accent[1] or 1, pinned and COLORS.accent[2] or 1, pinned and COLORS.accent[3] or 1)

                row.pin:SetScript("OnClick", function()
                    if itemID then self:ToggleWatchlistItem(itemID) end
                end)

                row:SetScript("OnEnter", function(selfRow)
                    selfRow:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
                    if item and item.itemLink then
                        GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink(item.itemLink)
                        GameTooltip:Show()
                    end
                end)

                yOffset = yOffset + rowH + 6
            end
        end
        yOffset = yOffset + 10
    end

    -- Currency results
    if mode == "all" or mode == "currency" then
        local cur = results.currencies or {}
        local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 10, -yOffset)
        title:SetText("Currency")
        title:SetTextColor(1, 1, 1)
        yOffset = yOffset + 26

        if #cur == 0 then
            yOffset = DrawEmptyState(parent, "No currency matches found.", yOffset)
        else
            local rowH = 30
            for i=1, math.min(#cur, 60) do
                local r = cur[i]
                local currencyID = r.currencyID
                local c = r.currency or {}
                local row = CreateRow(parent, yOffset, width, rowH)

                row.icon:SetTexture(c.iconFileID or c.icon or 134400)
                row.name:SetText(c.name or ("Currency " .. tostring(currencyID)))
                row.meta:SetText((r.character or "Unknown") .. (r.realm and (" • " .. r.realm) or ""))
                row.count:SetText(tostring(c.quantity or c.count or 0))

                local pinned = currencyID and self:IsWatchlistedCurrency(currencyID)
                row.pin.text:SetTextColor(pinned and COLORS.accent[1] or 1, pinned and COLORS.accent[2] or 1, pinned and COLORS.accent[3] or 1)

                row.pin:SetScript("OnClick", function()
                    if currencyID then self:ToggleWatchlistCurrency(currencyID) end
                end)

                row:SetScript("OnEnter", function(selfRow)
                    selfRow:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
                    if currencyID and GameTooltip and GameTooltip.SetCurrencyByID then
                        GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
                        GameTooltip:SetCurrencyByID(currencyID)
                        GameTooltip:Show()
                    end
                end)

                yOffset = yOffset + rowH + 6
            end
        end
        yOffset = yOffset + 10
    end

        parent:SetHeight(yOffset + 20)
        return yOffset
end
