--[[
    The Quartermaster - Equipment Tab
    Shows per-character equipped items (cached per character when that character is scanned).
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Import shared UI components (always get fresh reference)
local function GetCOLORS()
    return ns.UI_COLORS
end
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader

--============================================================================
-- SLOT CONFIG
--============================================================================

-- Compact set (includes all modern equipment slots that exist on Retail/Midnight)
-- Note: Shirt/Tabard are intentionally omitted (cosmetic and often empty).
local SLOT_ORDER = {
    { key = "HeadSlot",          label = "Head" },
    { key = "NeckSlot",          label = "Neck" },
    { key = "ShoulderSlot",      label = "Shoulder" },
    { key = "BackSlot",          label = "Back" },
    { key = "ChestSlot",         label = "Chest" },
    { key = "WristSlot",         label = "Wrist" },
    { key = "HandsSlot",         label = "Hands" },
    { key = "WaistSlot",         label = "Waist" },
    { key = "LegsSlot",          label = "Legs" },
    { key = "FeetSlot",          label = "Feet" },
    { key = "Finger0Slot",       label = "Ring" },
    { key = "Finger1Slot",       label = "Ring" },
    { key = "Trinket0Slot",      label = "Trinket" },
    { key = "Trinket1Slot",      label = "Trinket" },
    { key = "MainHandSlot",      label = "Main Hand" },
    { key = "SecondaryHandSlot", label = "Off Hand" },
}

local function GetSlotTexture(slotKey)
    if not GetInventorySlotInfo then return nil end
    local _, texture = GetInventorySlotInfo(slotKey)
    return texture
end

-- Extract the embedded link color to use as a fast, reliable quality indicator.
-- This works even when GetItemInfo() hasn't cached the item yet.
local function GetLinkRGB(itemLink)
    if type(itemLink) ~= "string" then return nil end
    local hex = itemLink:match("|c(%x%x%x%x%x%x%x%x)")
    if not hex then return nil end
    -- hex is AARRGGBB
    local rr = tonumber(hex:sub(3, 4), 16)
    local gg = tonumber(hex:sub(5, 6), 16)
    local bb = tonumber(hex:sub(7, 8), 16)
    if not rr or not gg or not bb then return nil end
    return rr / 255, gg / 255, bb / 255
end

local function GetItemQualityColor(item)
    if not item then return nil end

    -- 1) If the link is present, prefer the link color (most reliable).
    if item.itemLink then
        local r, g, b = GetLinkRGB(item.itemLink)
        if r then return r, g, b end

        -- fallback if link didn't match for some reason
        local quality = select(3, GetItemInfo(item.itemLink))
        if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
            local c = ITEM_QUALITY_COLORS[quality]
            return c.r, c.g, c.b
        end
    end

    -- 2) ItemID fallback (may still be uncached, but try)
    local itemID = item.itemID
    if not itemID and type(item.itemLink) == "string" then
        itemID = tonumber(item.itemLink:match("item:(%d+):"))
    end
    if itemID and C_Item and C_Item.GetItemQualityByID then
        local q = C_Item.GetItemQualityByID(itemID)
        if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
            local c = ITEM_QUALITY_COLORS[q]
            return c.r, c.g, c.b
        end
    end

    return nil
end

--============================================================================
-- TOOLTIP HELPERS
--============================================================================

local function AttachItemTooltip(btn, itemLink)
    if not btn then return end
    btn:SetScript("OnEnter", function(self)
        if not itemLink then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetHyperlink(itemLink)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

--============================================================================
-- LIST DRAW
--============================================================================

function TheQuartermaster:DrawEquipmentList(parent)
    local yOffset = 8
    local width = parent:GetWidth() - 20

    -- Get all characters (cached for performance)
    local characters = self.GetCachedCharacters and self:GetCachedCharacters() or self:GetAllCharacters()

    -- Quality border refresh (avoid full UI refresh loops)
    local qualityWidgets = {}
    TheQuartermaster._equipmentQualityWidgets = qualityWidgets
    TheQuartermaster._equipmentQualityAttempts = 0
    TheQuartermaster._equipmentQualityToken = (TheQuartermaster._equipmentQualityToken or 0) + 1
    local qualityToken = TheQuartermaster._equipmentQualityToken

    -- ===== SORT CHARACTERS: FAVORITES → REGULAR (matches Experience screen behaviour) =====
    local favorites, regular = {}, {}
    for _, char in ipairs(characters) do
        local charKey = char._key
        if not charKey then
            charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
        end
        if self:IsFavoriteCharacter(charKey) then
            table.insert(favorites, char)
        else
            table.insert(regular, char)
        end
    end

    -- Load custom order from profile (shared with other character list screens)
    if not self.db.profile.characterOrder then
        self.db.profile.characterOrder = { favorites = {}, regular = {} }
    end

    local function sortCharacters(list, orderKey)
        local customOrder = self.db.profile.characterOrder[orderKey] or {}
        if #customOrder > 0 then
            local ordered, charMap = {}, {}
            for _, char in ipairs(list) do
                local key = char._key or ((char.name or "Unknown") .. "-" .. (char.realm or "Unknown"))
                charMap[key] = char
            end
            for _, charKey in ipairs(customOrder) do
                if charMap[charKey] then
                    table.insert(ordered, charMap[charKey])
                    charMap[charKey] = nil
                end
            end
            local remaining = {}
            for _, c in pairs(charMap) do
                table.insert(remaining, c)
            end
            table.sort(remaining, function(a, b)
                if (a.level or 0) ~= (b.level or 0) then
                    return (a.level or 0) > (b.level or 0)
                end
                return (a.name or ""):lower() < (b.name or ""):lower()
            end)
            for _, c in ipairs(remaining) do
                table.insert(ordered, c)
            end
            return ordered
        end

        table.sort(list, function(a, b)
            if (a.level or 0) ~= (b.level or 0) then
                return (a.level or 0) > (b.level or 0)
            end
            return (a.name or ""):lower() < (b.name or ""):lower()
        end)
        return list
    end

    favorites = sortCharacters(favorites, "favorites")
    regular = sortCharacters(regular, "regular")

    -- ===== TITLE CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)

    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\INV_Chest_Cloth_17")

    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Equipment|r")

    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText(L["EQUIPMENT_DESC"])

    yOffset = yOffset + 75

    -- ===== COLUMN HEADER =====
    local header = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    header:SetHeight(36)
    header:SetPoint("TOPLEFT", 10, -yOffset)
    header:SetPoint("TOPRIGHT", -10, -yOffset)
    header:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
    header:SetBackdropColor(0.08, 0.08, 0.10, 1)

    -- Slightly bigger icons/cells (requested)
    local favW  = 26
    local nameW = 170
    local cellW = 44
    -- Header: keep left padding for the favorite column, but don't show a star icon
local nameLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("LEFT", 12 + favW, 0)
    nameLabel:SetText("Character")
    nameLabel:SetTextColor(0.9, 0.9, 0.9)

    -- Slot icons (as buttons so we can show a slot tooltip)
    local x = 12 + favW + nameW
    local HEADER_ICON_SIZE = 30
    for _, slot in ipairs(SLOT_ORDER) do
        local hb = CreateFrame("Button", nil, header, "BackdropTemplate")
        hb:SetSize(cellW - 6, 32)
        hb:SetPoint("LEFT", header, "LEFT", x + 3, 0)
        hb:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        hb:SetBackdropColor(0.10, 0.10, 0.12, 0.45)
        hb:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.35)

        local tex = hb:CreateTexture(nil, "ARTWORK")
        tex:SetSize(HEADER_ICON_SIZE, HEADER_ICON_SIZE)
        tex:SetPoint("CENTER", 0, 0)
        tex:SetTexture(GetSlotTexture(slot.key) or "Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetDesaturated(false)
        tex:SetAlpha(0.92)

        hb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(slot.label or slot.key, 1, 1, 1)
            GameTooltip:Show()
        end)
        hb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        x = x + cellW
    end

    yOffset = yOffset + 38

    -- ===== COLLAPSIBLE GROUPS (Favorites / Characters) =====
    if not self.db.profile.ui then
        self.db.profile.ui = {}
    end
    if self.db.profile.ui.favoritesExpanded == nil then
        self.db.profile.ui.favoritesExpanded = true
    end
    if self.db.profile.ui.charactersExpanded == nil then
        self.db.profile.ui.charactersExpanded = true
    end

    local rowH = 40

    local function DrawEquipmentRow(char, index, isFavorite)
        local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        row:SetHeight(rowH)
        row:SetPoint("TOPLEFT", 10, -yOffset)
        row:SetPoint("TOPRIGHT", -10, -yOffset)
        row:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
        if (index % 2) == 0 then
            row:SetBackdropColor(0.06, 0.06, 0.07, 1)
        else
            row:SetBackdropColor(0.045, 0.045, 0.055, 1)
        end

        local charKey = char._key or ((char.name or "Unknown") .. "-" .. (char.realm or "Unknown"))

        -- Favorite toggle button (matches Experience/Characters screens)
        local favButton = CreateFrame("Button", nil, row)
        favButton:SetSize(22, 22)
        favButton:SetPoint("LEFT", 12, 0)

        local favIcon = favButton:CreateTexture(nil, "ARTWORK")
        favIcon:SetAllPoints()
        favIcon:SetTexture("Interface\\COMMON\\FavoritesIcon")
        if isFavorite then
            favIcon:SetDesaturated(false)
            favIcon:SetVertexColor(1, 0.84, 0)
        else
            favIcon:SetDesaturated(true)
            favIcon:SetVertexColor(0.5, 0.5, 0.5)
        end
        favButton.icon = favIcon
        favButton.charKey = charKey

        favButton:SetScript("OnClick", function(self)
            local newStatus = TheQuartermaster:ToggleFavoriteCharacter(self.charKey)
            if newStatus then
                self.icon:SetDesaturated(false)
                self.icon:SetVertexColor(1, 0.84, 0)
            else
                self.icon:SetDesaturated(true)
                self.icon:SetVertexColor(0.5, 0.5, 0.5)
            end
            TheQuartermaster:RefreshUI()
        end)

        favButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if isFavorite then
                GameTooltip:SetText(L["CFFFFD700FAVORITE_CHARACTER_R_NCLICK_TO_REMOVE_FROM_FAVORITE"])
            else
                GameTooltip:SetText(L["CLICK_TO_ADD_TO_FAVORITES_N_CFF888888FAVORITES_ARE_ALWAYS_SH"])
            end
            GameTooltip:Show()
        end)
        favButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Character label (class-colored when possible)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", 12 + favW, 0)
        label:SetWidth(nameW)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetMaxLines(1)
        local baseName = (char.name or "?")
        local realm = (char.realm and char.realm ~= "") and char.realm or nil

        -- Build a single-line name where the realm portion is grey (matches other screens)
        local nameDisplay
        local classColor = (char.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.classFile]) or nil
        if classColor then
            nameDisplay = string.format("|cff%02x%02x%02x%s|r",
                classColor.r * 255, classColor.g * 255, classColor.b * 255,
                baseName
            )
        else
            nameDisplay = baseName
        end

        if realm then
            nameDisplay = nameDisplay .. string.format("|cff666666-%s|r", realm)
        end

        label:SetText(nameDisplay)
        -- Per-slot icons/buttons
        local equipment = char.equipment or {}
        local cx = 12 + favW + nameW
        for _, slot in ipairs(SLOT_ORDER) do
            local cell = CreateFrame("Button", nil, row, "BackdropTemplate")
            cell:SetSize(cellW - 2, rowH - 6)
            cell:SetPoint("LEFT", row, "LEFT", cx + 1, 0)
            cell:SetBackdrop({
                bgFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false,
                edgeSize = 10,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            cell:SetBackdropColor(0.10, 0.10, 0.12, 0.35)
            cell:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.25)

            local item = equipment and equipment[slot.key] or nil

            local ICON_SIZE = 30
            local icon = cell:CreateTexture(nil, "ARTWORK")
            icon:SetSize(ICON_SIZE, ICON_SIZE)
            icon:SetPoint("CENTER", 0, 0)

            -- Quality border sits ON the icon (not the whole cell), and can be thicker.
            local qBorder = CreateFrame("Frame", nil, cell, "BackdropTemplate")
            qBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
            qBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
            qBorder:SetBackdrop({
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false,
                edgeSize = 14,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            qBorder:Hide()

            -- Track this slot for deferred quality updates (no heavy RefreshUI)
            cell._qmItem = item
            cell._qmQBorder = qBorder
            table.insert(qualityWidgets, cell)

            if item and (item.iconFileID or item.itemLink or item.itemID) then
                icon:SetTexture(item.iconFileID or "Interface\\Icons\\INV_Misc_QuestionMark")
                icon:SetDesaturated(false)
                icon:SetAlpha(1)

                -- Quality indicator: color the ICON border (works even when item info is uncached)
                local qr, qg, qb = GetItemQualityColor(item)
                if qr then
                    qBorder:SetBackdropBorderColor(qr, qg, qb, 1)
                    qBorder:Show()
                else
                    qBorder:Hide()
                    -- If the item link is missing, request load so a refresh can pick up quality by ID.
                    if item.itemID and C_Item and C_Item.RequestLoadItemDataByID then
                        C_Item.RequestLoadItemDataByID(item.itemID)
                    end
                end

                AttachItemTooltip(cell, item.itemLink)
            else
                icon:SetTexture(GetSlotTexture(slot.key) or "Interface\\Icons\\INV_Misc_QuestionMark")
                icon:SetDesaturated(true)
                icon:SetAlpha(0.35)

                cell:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.15)
                qBorder:Hide()

                cell:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(slot.label or slot.key, 1, 1, 1)
                    GameTooltip:AddLine("No data for this character yet. Log into the character once so The Quartermaster can cache equipment.", 0.8, 0.8, 0.8, true)
                    GameTooltip:Show()
                end)
                cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end

            cx = cx + cellW
        end

        yOffset = yOffset + rowH + 2
    end

    -- Favorites section
    local favHeader, _, favIcon = CreateCollapsibleHeader(
        parent,
        string.format("Favorites |cff888888(%d)|r", #favorites),
        "equipment_favorites",
        self.db.profile.ui.favoritesExpanded,
        function(isExpanded)
            self.db.profile.ui.favoritesExpanded = isExpanded
            self:RefreshUI()
        end,
        "Interface\\Icons\\trade_archaeology_tyrandesfavoritedoll"
    )
    favHeader:SetPoint("TOPLEFT", 10, -yOffset)
    favHeader:SetPoint("TOPRIGHT", -10, -yOffset)
    if favIcon then
        favIcon:SetVertexColor(1, 0.84, 0)
    end
    yOffset = yOffset + 38

    if self.db.profile.ui.favoritesExpanded then
        yOffset = yOffset + 3
        if #favorites > 0 then
            for i, char in ipairs(favorites) do
                DrawEquipmentRow(char, i, true)
            end
        else
            local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            emptyText:SetPoint("TOPLEFT", 30, -yOffset)
            emptyText:SetTextColor(0.5, 0.5, 0.5)
            emptyText:SetText(L["NO_FAVORITE_CHARACTERS_YET_CLICK_THE_STAR_ICON_TO_FAVORITE_A"])
            yOffset = yOffset + 35
        end
    end

    -- Regular characters section
    local charHeader, _, charHeaderIcon = CreateCollapsibleHeader(
        parent,
        string.format("Characters |cff888888(%d)|r", #regular),
        "equipment_characters",
        self.db.profile.ui.charactersExpanded,
        function(isExpanded)
            self.db.profile.ui.charactersExpanded = isExpanded
            self:RefreshUI()
        end,
        "Interface\\Icons\\INV_Misc_Book_09"
    )
    charHeader:SetPoint("TOPLEFT", 10, -yOffset)
    charHeader:SetPoint("TOPRIGHT", -10, -yOffset)
    if charHeaderIcon and SetPortraitTexture then
        pcall(SetPortraitTexture, charHeaderIcon, "player")
    end
    yOffset = yOffset + 38

    if self.db.profile.ui.charactersExpanded then
        yOffset = yOffset + 3
        if #regular > 0 then
            for i, char in ipairs(regular) do
                DrawEquipmentRow(char, i, false)
            end
        else
            local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            emptyText:SetPoint("TOPLEFT", 30, -yOffset)
            emptyText:SetTextColor(0.5, 0.5, 0.5)
            emptyText:SetText(L["ALL_CHARACTERS_ARE_FAVORITED"])
            yOffset = yOffset + 35
        end
    end


    -- Some items on alts may not have item quality available immediately.
    -- Instead of calling RefreshUI (which is expensive), do a few lightweight passes that only update borders.
    local function RunQualityPass()
        if not parent or not parent.IsShown or not parent:IsShown() then return end
        if qualityToken ~= (TheQuartermaster._equipmentQualityToken or 0) then return end

        TheQuartermaster._equipmentQualityAttempts = (TheQuartermaster._equipmentQualityAttempts or 0) + 1
        local attempts = TheQuartermaster._equipmentQualityAttempts

        local remaining = 0
        for _, cell in ipairs(TheQuartermaster._equipmentQualityWidgets or {}) do
            local item = cell._qmItem
            local qBorder = cell._qmQBorder
            if item and qBorder then
                local qr, qg, qb = GetItemQualityColor(item)
                if qr then
                    qBorder:SetBackdropBorderColor(qr, qg, qb, 1)
                    qBorder:Show()
                else
                    remaining = remaining + 1
                    if item.itemID and C_Item and C_Item.RequestLoadItemDataByID then
                        C_Item.RequestLoadItemDataByID(item.itemID)
                    end
                end
            end
        end

        if remaining > 0 and attempts < 3 and C_Timer and C_Timer.After then
            C_Timer.After(0.25, RunQualityPass)
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, RunQualityPass)
    end


    return yOffset + 10
end
