--[[
    The Quartermaster - Materials / Reagents UI

    Aggregates reagent-like items across:
      - Reagent Bag (current character)
      - Warband Bank
      - All Characters (bags + personal banks)
      - Guild Bank (cached, optional)

    Design goals:
      - Clean totals + actionable breakdown
      - Fast filtering (text + category)
      - First-class Watchlist integration (pin star)
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard

local function SafeLower(s)
    if not s then return "" end
    return tostring(s):lower()
end

local function DrawEmptyState(parent, text, yOffset)
    local msg = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    msg:SetPoint("TOPLEFT", 20, -yOffset)
    msg:SetTextColor(0.7, 0.7, 0.7)
    msg:SetText(text)
    return yOffset + 30
end

-- Conservative "reagent-like" filter based on cached fields.
-- We treat Trade Goods (classID 7) as primary, but also allow explicit Reagent itemType.
local function IsReagentLike(item)
    if not item then return false end

    -- If we scanned from the reagent bag, it's safe to treat it as a reagent.
    if item.__fromReagentBag then return true end

    local classID = tonumber(item.classID)
    if classID == 7 then return true end -- Trade Goods

    local t = SafeLower(item.itemType)
    if t:find("trade") then return true end
    if t:find("reagent") then return true end

    -- Some older mats report as "Miscellaneous" but still have trade-good subtypes.
    local st = SafeLower(item.itemSubType)
    if st:find("cloth") or st:find("herb") or st:find("leather") or st:find("metal") or st:find("stone") then return true end
    if st:find("enchant") or st:find("elemental") or st:find("parts") then return true end

    return false
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
    row.meta:SetPoint("RIGHT", -72, 0)
    row.meta:SetJustifyH("RIGHT")
    row.meta:SetTextColor(0.75, 0.75, 0.75)

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

    row.pin:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        local text = btn.isPinned and "Unpin from Watchlist" or "Pin to Watchlist"
        GameTooltip:AddLine(text, 1, 1, 1)
        GameTooltip:AddLine("Click to toggle.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    row.pin:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
        GameTooltip:Hide()
    end)

    return row
end

local function FormatCount(n)
    n = tonumber(n) or 0
    if n >= 1000000 then
        return string.format("%.1fm", n / 1000000)
    elseif n >= 10000 then
        return string.format("%.1fk", n / 1000)
    end
    return tostring(n)
end

-- Build aggregation of reagent-like items.
local function BuildMaterialsIndex(self, opts)
    local items = {} -- [itemID] = { itemID, name, icon, itemType, itemSubType, total, breakdown = { [label]=count }, sampleLink }

    local function Add(item, count, label)
        if not item or not item.itemID then return end
        if not count or count <= 0 then return end

        if not IsReagentLike(item) then return end

        local itemID = tonumber(item.itemID)
        if not itemID then return end

        local entry = items[itemID]
        if not entry then
            entry = {
                itemID = itemID,
                name = item.name,
                icon = item.iconFileID,
                itemType = item.itemType,
                itemSubType = item.itemSubType,
                total = 0,
                breakdown = {},
                sampleLink = item.itemLink,
            }
            items[itemID] = entry
        end

        entry.total = (entry.total or 0) + count
        entry.breakdown[label] = (entry.breakdown[label] or 0) + count

        -- Backfill metadata if this entry was created from sparse cache.
        if not entry.name or entry.name == "" then entry.name = item.name end
        if not entry.icon or entry.icon == 0 then entry.icon = item.iconFileID end
        if (not entry.itemType or entry.itemType == "") and item.itemType then entry.itemType = item.itemType end
        if (not entry.itemSubType or entry.itemSubType == "") and item.itemSubType then entry.itemSubType = item.itemSubType end
        if not entry.sampleLink and item.itemLink then entry.sampleLink = item.itemLink end
    end

    -- 1) Reagent bag (current character)
    if opts.includeReagentBag and self.db and self.db.char and self.db.char.inventory and self.db.char.inventory.items then
        local inv = self.db.char.inventory
        local bagIDs = inv.bagIDs or {}
        for bagIndex, bagData in pairs(inv.items) do
            local bagID = bagIDs[bagIndex]
            if bagID == 5 then
                for _, item in pairs(bagData) do
                    if item and item.itemID then
                        item.__fromReagentBag = true
                        Add(item, item.stackCount or 1, "Reagent Bag")
                        item.__fromReagentBag = nil
                    end
                end
            end
        end
    end

    -- 2) Warband bank
    if opts.includeWarbandBank and self.db and self.db.global and self.db.global.warbandBank and self.db.global.warbandBank.items then
        for _, tabData in pairs(self.db.global.warbandBank.items) do
            for _, item in pairs(tabData) do
                if item and item.itemID then
                    Add(item, item.stackCount or item.count or 1, "Warband Bank")
                end
            end
        end
    end

    -- 3) All characters (bags + personal banks)
    if opts.includeAllCharacters and self.db and self.db.global and self.db.global.characters then
        for _, charData in pairs(self.db.global.characters) do
            local charLabel = (charData.name or "Unknown") .. "-" .. (charData.realm or "Unknown")

            -- Bags
            if charData.inventory and charData.inventory.items then
                for _, bagData in pairs(charData.inventory.items) do
                    for _, item in pairs(bagData) do
                        if item and item.itemID then
                            Add(item, item.stackCount or 1, charLabel .. " • Bags")
                        end
                    end
                end
            end

            -- Personal bank
            if charData.personalBank then
                for _, bagData in pairs(charData.personalBank) do
                    for _, item in pairs(bagData) do
                        if item and item.itemID then
                            Add(item, item.stackCount or 1, charLabel .. " • Bank")
                        end
                    end
                end
            end
        end
    end

    -- 4) Guild bank (cached)
    if opts.includeGuildBank and self.db and self.db.global and self.db.global.guildBank then
        for guildName, guildData in pairs(self.db.global.guildBank) do
            if guildData and guildData.tabs then
                for tabIndex, tab in pairs(guildData.tabs) do
                    if tab and tab.items then
                        for _, item in pairs(tab.items) do
                            if item and item.itemID then
                                Add(item, item.count or item.stackCount or 1, "Guild Bank • " .. guildName .. " • Tab " .. tostring(tabIndex))
                            end
                        end
                    end
                end
            end
        end
    end

    local list = {}
    for _, entry in pairs(items) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        local an = SafeLower(a.name)
        local bn = SafeLower(b.name)
        if an == bn then
            return (a.total or 0) > (b.total or 0)
        end
        return an < bn
    end)

    return list
end

local function GetDistinctSubTypes(list)
    local set = {}
    local out = {}
    for _, e in ipairs(list or {}) do
        local st = e.itemSubType
        if st and st ~= "" and not set[st] then
            set[st] = true
            table.insert(out, st)
        end
    end
    table.sort(out)
    return out
end

function TheQuartermaster:DrawMaterialsTab(parent)
    local yOffset = 8
    local width = parent:GetWidth() - 20

    -- Defaults
    if ns.materialsIncludeReagentBag == nil then ns.materialsIncludeReagentBag = true end
    if ns.materialsIncludeWarband == nil then ns.materialsIncludeWarband = true end
    if ns.materialsIncludeAllChars == nil then ns.materialsIncludeAllChars = true end
    if ns.materialsIncludeGuild == nil then
        local wl = self.db and self.db.profile and self.db.profile.watchlist
        ns.materialsIncludeGuild = (wl and wl.includeGuildBank ~= false) or true
    end
    ns.materialsSubTypeFilter = ns.materialsSubTypeFilter or "All"

    -- Header
    local header = CreateCard(parent, 72)
    header:SetWidth(width)
    header:SetPoint("TOPLEFT", 10, -yOffset)

    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("LEFT", 16, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Organ_06")

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -2)
    title:SetText("Materials")
    title:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])

    local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetText("Crafting reagents across your Warband, banks, and caches")
    subtitle:SetTextColor(0.65, 0.65, 0.65)

    yOffset = yOffset + 86

    -- Controls
    local controls = CreateCard(parent, 78)
    controls:SetWidth(width)
    controls:SetPoint("TOPLEFT", 10, -yOffset)

    if not controls.built then
        controls.built = true

        local function MakeCheck(label, x, y, initial, onChange)
            local cb = CreateFrame("CheckButton", nil, controls, "UICheckButtonTemplate")
            cb:SetPoint("TOPLEFT", x, -y)
            cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cb.text:SetPoint("LEFT", cb, "RIGHT", 6, 0)
            cb.text:SetText(label)
            cb:SetChecked(initial)
            cb:SetScript("OnClick", function(selfBtn)
                onChange(selfBtn:GetChecked())
                TheQuartermaster:PopulateContent()
            end)
            return cb
        end

        controls.cbReagentBag = MakeCheck("Reagent Bag", 10, 18, ns.materialsIncludeReagentBag, function(v) ns.materialsIncludeReagentBag = v end)
        controls.cbWarband = MakeCheck("Warband Bank", 140, 18, ns.materialsIncludeWarband, function(v) ns.materialsIncludeWarband = v end)
        controls.cbAllChars = MakeCheck("All Characters", 280, 18, ns.materialsIncludeAllChars, function(v) ns.materialsIncludeAllChars = v end)
        controls.cbGuild = MakeCheck("Guild Bank (cached)", 430, 18, ns.materialsIncludeGuild, function(v)
            ns.materialsIncludeGuild = v
            if TheQuartermaster.db and TheQuartermaster.db.profile and TheQuartermaster.db.profile.watchlist then
                TheQuartermaster.db.profile.watchlist.includeGuildBank = v
            end
        end)

        -- Category dropdown
        local drop = CreateFrame("Frame", nil, controls, "UIDropDownMenuTemplate")
        drop:SetPoint("TOPLEFT", 6, -46)
        UIDropDownMenu_SetWidth(drop, 210)
        UIDropDownMenu_SetText(drop, "Category: All")
        controls.categoryDrop = drop

        local function SetSubType(value)
            ns.materialsSubTypeFilter = value or "All"
            if ns.materialsSubTypeFilter == "All" then
                UIDropDownMenu_SetText(drop, "Category: All")
            else
                UIDropDownMenu_SetText(drop, "Category: " .. ns.materialsSubTypeFilter)
            end
            TheQuartermaster:PopulateContent()
        end

        controls.SetSubType = SetSubType
    end

    -- Update checkbox states on refresh
    controls.cbReagentBag:SetChecked(ns.materialsIncludeReagentBag)
    controls.cbWarband:SetChecked(ns.materialsIncludeWarband)
    controls.cbAllChars:SetChecked(ns.materialsIncludeAllChars)
    controls.cbGuild:SetChecked(ns.materialsIncludeGuild)

    yOffset = yOffset + 88

    local searchText = SafeLower(ns.materialsSearchText or "")

    local opts = {
        includeReagentBag = ns.materialsIncludeReagentBag,
        includeWarbandBank = ns.materialsIncludeWarband,
        includeAllCharacters = ns.materialsIncludeAllChars,
        includeGuildBank = ns.materialsIncludeGuild,
    }

    local list = BuildMaterialsIndex(self, opts)

    -- Build subtype list and init dropdown each draw
    local subTypes = GetDistinctSubTypes(list)
    UIDropDownMenu_Initialize(controls.categoryDrop, function()
        local info = UIDropDownMenu_CreateInfo()
        info.text = "All"
        info.func = function() controls.SetSubType("All") end
        UIDropDownMenu_AddButton(info)

        for _, st in ipairs(subTypes) do
            info = UIDropDownMenu_CreateInfo()
            info.text = st
            info.func = function() controls.SetSubType(st) end
            UIDropDownMenu_AddButton(info)
        end
    end)

    if ns.materialsSubTypeFilter == "All" then
        UIDropDownMenu_SetText(controls.categoryDrop, "Category: All")
    else
        UIDropDownMenu_SetText(controls.categoryDrop, "Category: " .. tostring(ns.materialsSubTypeFilter))
    end

    -- Apply filters
    local filtered = {}
    for _, e in ipairs(list) do
        local name = SafeLower(e.name)
        if (searchText == "" or name:find(searchText, 1, true)) then
            if ns.materialsSubTypeFilter == "All" or (e.itemSubType and e.itemSubType == ns.materialsSubTypeFilter) then
                table.insert(filtered, e)
            end
        end
    end

    if #filtered == 0 then
        if (ns.materialsSearchText or "") == "" then
            return DrawEmptyState(parent, "No materials found in the selected sources.", yOffset)
        end
        return DrawEmptyState(parent, "No materials match your search.", yOffset)
    end

    -- Results
    local title2 = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title2:SetPoint("TOPLEFT", 10, -yOffset)
    title2:SetText("Results")
    title2:SetTextColor(1, 1, 1)
    yOffset = yOffset + 26

    local rowH = 30
    for i = 1, math.min(#filtered, 120) do
        local e = filtered[i]
        local row = CreateRow(parent, yOffset, width, rowH)

        row.icon:SetTexture(e.icon or 134400)
        row.name:SetText(e.name or ("Item " .. tostring(e.itemID)))
        row.meta:SetText(e.itemSubType or e.itemType or "")
        row.count:SetText(FormatCount(e.total or 0))

        -- Watchlist pin
        local pinned = self:IsWatchlistedItem(e.itemID)
        row.pin.isPinned = pinned
        row.pin.icon:SetVertexColor(pinned and COLORS.accent[1] or 1, pinned and COLORS.accent[2] or 1, pinned and COLORS.accent[3] or 1)
        row.pin:SetScript("OnClick", function()
            self:ToggleWatchlistItem(e.itemID)
        end)

        row:SetScript("OnEnter", function(selfRow)
            selfRow:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
            GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
            if e.sampleLink then
                GameTooltip:SetHyperlink(e.sampleLink)
            elseif GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(e.itemID)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Totals", 1, 1, 1)

            -- Sort breakdown to show biggest contributors first
            local pairsList = {}
            for label, count in pairs(e.breakdown or {}) do
                table.insert(pairsList, { label = label, count = count })
            end
            table.sort(pairsList, function(a, b) return (a.count or 0) > (b.count or 0) end)

            local maxLines = 12
            for idx = 1, math.min(#pairsList, maxLines) do
                local p = pairsList[idx]
                GameTooltip:AddDoubleLine(p.label, tostring(p.count), 0.8, 0.8, 0.8, 1, 1, 1)
            end
            if #pairsList > maxLines then
                GameTooltip:AddLine("...")
            end

            GameTooltip:Show()
        end)

        yOffset = yOffset + rowH + 6
    end

    parent:SetHeight(yOffset + 20)
    return yOffset
end
