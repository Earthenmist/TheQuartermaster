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

local function AttachItemTooltip(btn, item)
    local itemLink = item.itemLink or (item.itemID and ("item:" .. item.itemID))
    if not btn then return end
    btn:SetScript("OnEnter", function(self)
        if not itemLink then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetHyperlink(itemLink)
        GameTooltip:AddLine(item.lastScan and string.format(L.EQ_SCANNED, date("%Y-%m-%d %H:%M", item.lastScan)) or L.EQ_SCAN_UNKNOWN, 0.6, 0.6, 0.6, true)
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

    local function sortCharacters(list)
        return ns.SortCharacterRows(self.db, list)
    end

    favorites = sortCharacters(favorites, "favorites")
    regular = sortCharacters(regular, "regular")

    local COLORS = GetCOLORS()

    -- ===== COLUMN HEADER =====
    local header = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    header:SetHeight(36)
    header:SetPoint("TOPLEFT", 10, -yOffset)
    header:SetPoint("TOPRIGHT", -10, -yOffset)
    header:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
    header:SetBackdropColor(unpack(COLORS.bgCard))

    -- Share available space between the name and all equipment slots.
    local favW  = 26
    local nameW = math.max(160, math.min(230, width * 0.22))
    local cellW = math.max(12, (width - 12 - favW - nameW - 12) / #SLOT_ORDER)
    local iconSize = math.max(8, math.min(30, cellW - 6))
    -- Header: keep left padding for the favorite column, but don't show a star icon
    local nameLabel = header:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    nameLabel:SetPoint("LEFT", 12 + favW, 0)
    nameLabel:SetText("Character")
    nameLabel:SetTextColor(0.9, 0.9, 0.9)

    -- Slot icons (as buttons so we can show a slot tooltip)
    local x = 12 + favW + nameW
    local HEADER_ICON_SIZE = iconSize
    for _, slot in ipairs(SLOT_ORDER) do
        local hb = CreateFrame("Button", nil, header, "BackdropTemplate")
        hb:SetSize(cellW - 6, 32)
        hb:SetPoint("LEFT", header, "LEFT", x + 3, 0)
        hb:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false,
            edgeSize = 1,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        hb:SetBackdropColor(unpack(COLORS.bgCard))
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

    local rowH = 48

    local function DrawEquipmentRow(char, index, isFavorite)
        local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        row:SetHeight(rowH)
        row:SetPoint("TOPLEFT", 10, -yOffset)
        row:SetPoint("TOPRIGHT", -10, -yOffset)
        row:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
        if (index % 2) == 0 then
            row:SetBackdropColor(unpack(COLORS.bg))
        else
            row:SetBackdropColor(unpack(COLORS.bgCard))
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
        local label = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
        label:SetPoint("TOPLEFT", 12 + favW, -7)
        label:SetWidth(nameW - 10)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetMaxLines(1)
        local baseName = (char.name or "?")
        local realm = (char.realm and char.realm ~= "") and char.realm or nil

        -- Keep the full name readable above the secondary realm line.
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

        label:SetText(nameDisplay)
        local detail = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
        detail:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
        detail:SetWidth(nameW - 10); detail:SetWordWrap(false); detail:SetJustifyH("LEFT")
        local ilvl = tonumber(char.ilvlEquipped or char.ilvl)
        detail:SetText((realm or "") .. (ilvl and string.format("  |  iLvl %.1f", ilvl) or ""))
        detail:SetTextColor(unpack(COLORS.textDim))
        local nameHit = CreateFrame("Frame", nil, row)
        nameHit:SetPoint("LEFT", 12 + favW, 0); nameHit:SetSize(nameW - 8, rowH)
        nameHit:EnableMouse(true)
        nameHit:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(baseName .. (realm and ("-" .. realm) or ""))
            GameTooltip:AddLine(L.EQUIPMENT_DESC, 0.6, 0.6, 0.6, true)
            if ilvl then GameTooltip:AddLine(string.format(L.EQ_AVERAGE_ILVL, ilvl), 1, 1, 1) end
            GameTooltip:Show()
        end)
        nameHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Per-slot icons/buttons
        local equipment = char.equipment or {}
        local cx = 12 + favW + nameW
        for _, slot in ipairs(SLOT_ORDER) do
            local cell = CreateFrame("Button", nil, row, "BackdropTemplate")
            cell:SetSize(cellW - 2, rowH - 6)
            cell:SetPoint("LEFT", row, "LEFT", cx + 1, 0)
            cell:SetBackdrop({
                bgFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false,
                edgeSize = 1,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            cell:SetBackdropColor(unpack(COLORS.bgCard))
            cell:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.25)

            local item = equipment and equipment[slot.key] or nil

            local ICON_SIZE = iconSize
            local icon = cell:CreateTexture(nil, "ARTWORK")
            icon:SetSize(ICON_SIZE, ICON_SIZE)
            icon:SetPoint("CENTER", 0, 0)

            -- A flat quality border sits around the icon.
            local qBorder = CreateFrame("Frame", nil, cell, "BackdropTemplate")
            qBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
            qBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
            qBorder:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false,
                edgeSize = 1,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            qBorder:Hide()

            -- Item level label (optional)
            -- NOTE: The quality border is a separate Frame and can sit above FontStrings even when using OVERLAY.
            -- To guarantee readability, put the ilvl text on its own overlay Frame with a higher FrameLevel.
            local ilvlOverlay = CreateFrame("Frame", nil, cell)
            ilvlOverlay:SetAllPoints(cell)
            ilvlOverlay:SetFrameLevel(qBorder:GetFrameLevel() + 2)

            local ilvlText = ilvlOverlay:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
            ilvlText:SetPoint("BOTTOMRIGHT", -1, 6) -- lifted to clear icon border
            ilvlText:SetJustifyH("RIGHT")
            ilvlText:SetTextColor(1, 0.82, 0, 1)

            -- Make it readable on top of everything in the cell
            ilvlText:SetDrawLayer("OVERLAY", 10)
            local font, size = ilvlText:GetFont()
            if font then
                ilvlText:SetFont(font, (size or 10), "OUTLINE")
            end
            ilvlText:SetShadowOffset(1, -1)
            ilvlText:SetShadowColor(0, 0, 0, 1)


            -- Track this slot for deferred quality updates (no heavy RefreshUI)
            cell._qmItem = ns.EquipmentSlotState(item) == "item" and item or nil
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


                -- Item level (optional)
                do
                    local showIlvl = self.db and self.db.profile and self.db.profile.showItemLevel
                    local ilvl = nil
                    if showIlvl and item then
                        -- Prefer detailed ilvl from hyperlink (accounts for upgrades/bonusIDs)
                        if item.itemLink and C_Item and C_Item.GetDetailedItemLevelInfo then
                            ilvl = C_Item.GetDetailedItemLevelInfo(item.itemLink)
                        end
                        if (not ilvl) and item.itemLevel then
                            ilvl = item.itemLevel
                        end
                    end

                    if ilvl then
                        ilvlText:SetText(string.format("|cffffd100%d|r", ilvl))
                    else
                        ilvlText:SetText("")
                    end
                end
                AttachItemTooltip(cell, item)
            else
                icon:SetTexture(GetSlotTexture(slot.key) or "Interface\\Icons\\INV_Misc_QuestionMark")
                icon:SetDesaturated(true)
                local empty = ns.EquipmentSlotState(item) == "empty"
                icon:SetAlpha(empty and 0.18 or 0.08)

                ilvlText:ClearAllPoints()
                ilvlText:SetPoint("CENTER", cell, "CENTER", 0, 0)
                ilvlText:SetText(empty and "-" or "?")
                ilvlText:SetTextColor(unpack(empty and COLORS.textDim or COLORS.warning))

                cell:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.15)
                qBorder:Hide()

                cell:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(slot.label or slot.key, 1, 1, 1)
                    GameTooltip:AddLine(empty and L.EQ_EMPTY or L.EQ_UNSCANNED, 0.8, 0.8, 0.8, true)
                    if empty then GameTooltip:AddLine(string.format(L.EQ_SCANNED, date("%Y-%m-%d %H:%M", item.lastScan)), 0.6, 0.6, 0.6) end
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
            local emptyText = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
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
            local emptyText = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
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