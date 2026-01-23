--[[
    The Quartermaster - Currency Tab
    Display all currencies across characters with Blizzard API headers
    
    EXACT StorageUI pattern:
    - Character → Expansion → Category → Currency rows
    - Season 3 is a CATEGORY under "The War Within" expansion
    - All spacing, fonts, colors match StorageUI
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local FormatGold = ns.UI_FormatGold
local FormatCharacterNameRealm = ns.UI_FormatCharacterNameRealm
local DrawEmptyState = ns.UI_DrawEmptyState
local function GetCOLORS()
    return ns.UI_COLORS
end

-- Performance: Local function references
local format = string.format
local floor = math.floor
local ipairs = ipairs
local pairs = pairs
local next = next

-- Import shared UI constants (EXACT StorageUI spacing)
local UI_LAYOUT = ns.UI_LAYOUT
local ROW_HEIGHT = UI_LAYOUT.ROW_HEIGHT
local ROW_SPACING = UI_LAYOUT.ROW_SPACING
local HEADER_SPACING = UI_LAYOUT.HEADER_SPACING
local SECTION_SPACING = UI_LAYOUT.SECTION_SPACING

--============================================================================
-- CURRENCY FORMATTING & HELPERS
--============================================================================

---Format number with thousand separators
---@param num number Number to format
---@return string Formatted number
local function FormatNumber(num)
    local formatted = tostring(num)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1.%2')
        if k == 0 then break end
    end
    return formatted
end

---Format currency quantity with cap indicator
---@param quantity number Current amount
---@param maxQuantity number Maximum amount (0 = no cap)
---@return string Formatted text with color
local function FormatCurrencyAmount(quantity, maxQuantity)
    if maxQuantity > 0 then
        local percentage = (quantity / maxQuantity) * 100
        local color
        
        if percentage >= 100 then
            color = "|cffff4444" -- Red (capped)
        elseif percentage >= 80 then
            color = "|cffffaa00" -- Orange (near cap)
        elseif percentage >= 50 then
            color = "|cffffff00" -- Yellow (half)
        else
            color = "|cffffffff" -- White (safe)
        end
        
        return format("%s%s|r / %s", color, FormatNumber(quantity), FormatNumber(maxQuantity))
    else
        return format("|cffffffff%s|r", FormatNumber(quantity))
    end
end

---Check if currency matches search text
---@param currency table Currency data
---@param searchText string Search text (lowercase)
---@return boolean matches
local function CurrencyMatchesSearch(currency, searchText)
    if not searchText or searchText == "" then
        return true
    end
    
    local name = (currency.name or ""):lower()
    local category = (currency.category or ""):lower()
    
    return name:find(searchText, 1, true) or category:find(searchText, 1, true)
end

--============================================================================
-- CURRENCY ROW RENDERING (EXACT StorageUI style)
--============================================================================

---Create a single currency row (PIXEL-PERFECT StorageUI style) - NO POOLING for stability
---@param parent Frame Parent frame
---@param currency table Currency data
---@param currencyID number Currency ID
---@param rowIndex number Row index for alternating colors
---@param indent number Left indent
---@param width number Parent width
---@param yOffset number Y position
---@return number newYOffset
local function CreateCurrencyRow(parent, currency, currencyID, rowIndex, indent, width, yOffset)
    -- Create new row (NO POOLING - currency rows are dynamic and cause render issues with pooling)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(width - indent, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 10 + indent, -yOffset)
    row:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
    })
    
    -- EXACT alternating row colors (StorageUI formula)
    row:SetBackdropColor(rowIndex % 2 == 0 and 0.07 or 0.05, rowIndex % 2 == 0 and 0.07 or 0.05, rowIndex % 2 == 0 and 0.09 or 0.06, 1)
    
    local hasQuantity = (currency.quantity or 0) > 0
    
    -- Icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", 15, 0)
    if currency.iconFileID then
        icon:SetTexture(currency.iconFileID)
    else
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    
    if not hasQuantity then
        icon:SetAlpha(0.4)
    end
    
    -- Name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", 43, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    nameText:SetWidth(width - indent - 200)
    nameText:SetText(currency.name or "Unknown Currency")
    if hasQuantity then
        nameText:SetTextColor(1, 1, 1)
    else
        nameText:SetTextColor(0.5, 0.5, 0.5)
    end
    
    -- Amount
    local amountText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    amountText:SetPoint("RIGHT", -10, 0)
    amountText:SetWidth(150)
    amountText:SetJustifyH("RIGHT")
    amountText:SetText(FormatCurrencyAmount(currency.quantity or 0, currency.maxQuantity or 0))
    if not hasQuantity then
        amountText:SetTextColor(0.5, 0.5, 0.5)
    end
    
    -- EXACT StorageUI hover effect
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.20, 1)
        
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if currencyID and C_CurrencyInfo then
            GameTooltip:SetCurrencyByID(currencyID)
        else
            GameTooltip:SetText(currency.name or "Currency", 1, 1, 1)
            if currency.maxQuantity and currency.maxQuantity > 0 then
                GameTooltip:AddLine(format("Maximum: %d", currency.maxQuantity), 0.7, 0.7, 0.7)
            end
        end
        GameTooltip:Show()
    end)
    
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(rowIndex % 2 == 0 and 0.07 or 0.05, rowIndex % 2 == 0 and 0.07 or 0.05, rowIndex % 2 == 0 and 0.09 or 0.06, 1)
        GameTooltip:Hide()
    end)
    
    return yOffset + ROW_SPACING
end

--============================================================================
-- MAIN DRAW FUNCTION
--============================================================================

function TheQuartermaster:DrawCurrencyTab(parent)
    -- Clear all old frames (currency rows are NOT pooled)
    for _, child in pairs({parent:GetChildren()}) do
        if child:GetObjectType() ~= "Frame" then  -- Skip non-frame children like FontStrings
            pcall(function()
                child:Hide()
                child:ClearAllPoints()
            end)
        end
    end
    
    local yOffset = 8
    local width = parent:GetWidth() - 20
    local indent = 20
    
    -- Get search text
    local currencySearchText = (ns.currencySearchText or ""):lower()
    
    -- Get all characters
    local characters = self:GetAllCharacters()
    if not characters or #characters == 0 then
        DrawEmptyState(parent, "No character data available", yOffset)
        return yOffset + 50
    end
    
    -- View mode and zero toggle
    -- currencyViewMode:
    --   "warband"   = All Warband (default) - hides alt list, shows this character + warband/account-wide currencies
    --   "character" = Character Only - shows alt list (current behaviour)
    local viewMode = self.db.profile.currencyViewMode
    if not viewMode or (viewMode ~= "warband" and viewMode ~= "character") then
        viewMode = "warband"
        self.db.profile.currencyViewMode = viewMode
    end
    local showZero = self.db.profile.currencyShowZero
    if showZero == nil then showZero = true end
    
    -- Expanded state
    local expanded = self.db.profile.currencyExpanded or {}
    
    -- Get current online character
    local currentPlayerName = UnitName("player")
    local currentRealm = GetRealmName()
    local currentCharKey = currentPlayerName .. "-" .. currentRealm
    
    -- Helper functions for expand/collapse
    local function IsExpanded(key, default)
        if expanded[key] == nil then
            return default or false
        end
        return expanded[key]
    end
    
    local function ToggleExpand(key, isExpanded)
        if not self.db.profile.currencyExpanded then
            self.db.profile.currencyExpanded = {}
        end
        self.db.profile.currencyExpanded[key] = isExpanded
        self:RefreshUI()
    end
    
    -- ===== TITLE CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    -- Dynamic theme color for title
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Currency Tracker|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText("Track all currencies across your characters")

    -- Small themed action buttons (match the rest of The Quartermaster UI)
    local function StripDefaultButtonTextures(btn)
        local nt = btn:GetNormalTexture(); if nt then nt:SetAlpha(0) end
        local pt = btn:GetPushedTexture(); if pt then pt:SetAlpha(0) end
        local ht = btn:GetHighlightTexture(); if ht then ht:SetAlpha(0) end
        local dt = btn:GetDisabledTexture(); if dt then dt:SetAlpha(0) end
    end

    local function ApplyThemedActionButton(btn)
        if not btn or not btn.SetBackdrop then return end
        local COLORS = GetCOLORS()
        StripDefaultButtonTextures(btn)
        btn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })

        btn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
        btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)

        -- Consistent font sizing/centering across reloads/sessions
        btn:SetNormalFontObject("GameFontHighlightSmall")
        btn:SetHighlightFontObject("GameFontHighlightSmall")
        btn:SetDisabledFontObject("GameFontDisableSmall")
        if btn.GetFontString and btn:GetFontString() then
            btn:GetFontString():SetTextColor(1, 1, 1, 0.95)
            btn:GetFontString():SetJustifyH("CENTER")
        end
    end
    
    -- Filter Mode + Zero Qty buttons (custom themed, same approach as Items tab)
    -- We intentionally avoid UIPanelButtonTemplate here because it can randomly reapply textures/fonts and
    -- "break" the button appearance on first open / after UI reloads.
    local function CreateHeaderActionButton(parent, width, label, tooltipTitle, tooltipLine)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(width, 24)

        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.text:SetPoint("CENTER")
        btn.text:SetTextColor(1, 1, 1, 0.95)
        btn.text:SetText(label or "")

        btn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })

        local COLORS = GetCOLORS()
        btn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
        btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)

        btn:SetScript("OnEnter", function(b)
            local c = GetCOLORS()
            b:SetBackdropColor(c.tabHover[1], c.tabHover[2], c.tabHover[3], 1)
            b:SetBackdropBorderColor(c.accent[1], c.accent[2], c.accent[3], 0.9)

            if tooltipTitle then
                GameTooltip:SetOwner(b, "ANCHOR_TOP")
                GameTooltip:AddLine(tooltipTitle, 1, 0.82, 0)
                if tooltipLine then
                    GameTooltip:AddLine(tooltipLine, 1, 1, 1, true)
                end
                GameTooltip:Show()
            end
        end)

        btn:SetScript("OnLeave", function(b)
            local c = GetCOLORS()
            b:SetBackdropColor(c.tabInactive[1], c.tabInactive[2], c.tabInactive[3], 1)
            b:SetBackdropBorderColor(c.accent[1], c.accent[2], c.accent[3], 0.65)
            GameTooltip:Hide()
        end)

        return btn
    end

    local btnHolder = CreateFrame("Frame", nil, titleCard)
    btnHolder:SetPoint("RIGHT", titleCard, "RIGHT", -10, 0)
    btnHolder:SetSize(300, 24)

    -- Show/Hide 0 Qty toggle
    local zeroBtn = CreateHeaderActionButton(
        btnHolder,
        100,
        showZero and "Hide 0 Qty" or "Show 0 Qty",
        "Zero Quantities",
        "Toggle showing currencies with 0 quantity."
    )
    zeroBtn:SetPoint("RIGHT", btnHolder, "RIGHT", 0, 0)
    zeroBtn:SetScript("OnClick", function(self)
        showZero = not showZero
        TheQuartermaster.db.profile.currencyShowZero = showZero
        self.text:SetText(showZero and "Hide 0 Qty" or "Show 0 Qty")
        TheQuartermaster:RefreshUI()
    end)


    -- All Warband / Character Only toggle
    local toggleBtn = CreateHeaderActionButton(
        btnHolder,
        140,
        viewMode == "warband" and "All Warband" or "Character Only",
        "Currency View",
        "All Warband: shows this character + warband/account-wide currencies (hides alt list).\nCharacter Only: shows each character and their currencies."
    )
    toggleBtn:SetPoint("RIGHT", zeroBtn, "LEFT", -8, 0)
    toggleBtn:SetScript("OnClick", function(self)
        if viewMode == "warband" then
            viewMode = "character"
        else
            viewMode = "warband"
        end
        TheQuartermaster.db.profile.currencyViewMode = viewMode
        self.text:SetText(viewMode == "warband" and "All Warband" or "Character Only")
        TheQuartermaster:RefreshUI()
    end)

yOffset = yOffset + 78
    
    -- ===== RENDER CHARACTERS =====
    local hasAnyData = false
    local charactersWithCurrencies = {}
    
    -- Collect characters with currencies
    for _, char in ipairs(characters) do
        if char.currencies and next(char.currencies) then
            local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
            local isOnline = (charKey == currentCharKey)
            
            -- Filter currencies
            local matchingCurrencies = {}
            for currencyID, currency in pairs(char.currencies) do
                local passesZeroFilter = showZero or ((currency.quantity or 0) > 0)
                
                if not currency.isHidden 
                   and passesZeroFilter
                   and CurrencyMatchesSearch(currency, currencySearchText) then
                    table.insert(matchingCurrencies, {
                        id = currencyID,
                        data = currency,
                    })
                end
            end
            
            if #matchingCurrencies > 0 then
                hasAnyData = true
                table.insert(charactersWithCurrencies, {
                    char = char,
                    key = charKey,
                    currencies = matchingCurrencies,
                    isOnline = isOnline,
                    sortPriority = isOnline and 0 or 1,
                })
            end
        end
    end
    
    -- Sort (online first)
    table.sort(charactersWithCurrencies, function(a, b)
        if a.sortPriority ~= b.sortPriority then
            return a.sortPriority < b.sortPriority
        end
        return (a.char.name or "") < (b.char.name or "")
    end)
    

    -- All Warband view: hide alt list by rendering ONLY the current (online) character.
    -- We still keep the single character header for context, but no other alts are listed.
    if viewMode == "warband" and #charactersWithCurrencies > 0 then
        local selected = nil
        for _, cd in ipairs(charactersWithCurrencies) do
            if cd.isOnline then
                selected = cd
                break
            end
        end
        if not selected then
            selected = charactersWithCurrencies[1]
        end

        -- Merge account-wide (warband) currencies from all characters into the selected list.
        local accountWide = {}
        for _, cd in ipairs(charactersWithCurrencies) do
            for _, curr in ipairs(cd.currencies) do
                if curr.data and curr.data.isAccountWide then
                    local existing = accountWide[curr.id]
                    if not existing or (curr.data.quantity or 0) > (existing.data.quantity or 0) then
                        accountWide[curr.id] = curr
                    end
                end
            end
        end

        local merged = {}
        local seen = {}
        for _, curr in ipairs(selected.currencies) do
            merged[#merged+1] = curr
            seen[curr.id] = true
        end
        for cid, curr in pairs(accountWide) do
            if not seen[cid] then
                merged[#merged+1] = curr
            end
        end
        selected.currencies = merged

        charactersWithCurrencies = { selected }
    end

    if not hasAnyData then
        DrawEmptyState(parent, 
            currencySearchText ~= "" and "No currencies match your search" or "No currencies found",
            yOffset)
        return yOffset + 100
    end
    
    
    -- ============================================================================
    -- Blizzard-like ordering (requested)
    -- ============================================================================
    local LEGACY_ORDER = {
        "The War Within",
        "Dragonflight",
        "Shadowlands",
        "Battle for Azeroth",
        "Legion",
        "Warlords of Draenor",
        "Mists of Pandaria",
        "Wrath of the Lich King",
        "Burning Crusade",
        "The Burning Crusade",
        "Account-Wide",
        "Other",
    }

    local function NormalizeHeaderName(name)
        name = name or ""
        name = name:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        return name:lower()
    end

    -- Blizzard header names can differ between versions (e.g. "The War Within" vs "War Within").
    -- Resolve a bucket by trying common aliases so we don't drop currencies when names vary.
    local function GetBucketByHeaderName(buckets, headerName)
        local key = NormalizeHeaderName(headerName)
        local bucket = buckets[key]
        if bucket then return bucket, key end

        -- Try stripping leading "the "
        if key:sub(1, 4) == "the " then
            local alt = key:sub(5)
            bucket = buckets[alt]
            if bucket then return bucket, alt end
        end

        -- Try adding leading "the "
        local withThe = "the " .. key
        bucket = buckets[withThe]
        if bucket then return bucket, withThe end

        return nil, key
    end

    local function BuildHeaderBuckets(currList)
        local buckets = {}
        for _, curr in ipairs(currList) do
            local header = (curr.data and curr.data.headerName) or "Other"
            local key = NormalizeHeaderName(header)
            buckets[key] = buckets[key] or { name = header, items = {} }
            table.insert(buckets[key].items, curr)
        end
        -- stable sort each bucket by name
        for _, b in pairs(buckets) do
            table.sort(b.items, function(a, b2)
                return (a.data.name or "") < (b2.data.name or "")
            end)
        end
        return buckets
    end

    local function RenderCurrenciesUnderHeader(headerTitle, headerKey, headerIcon, items, baseIndent, defaultExpanded, nestedFn, allowEmpty, countOverride)
        if (not items or #items == 0) and not allowEmpty then
            return
        end

        local hKey = headerKey
        local hExpanded = IsExpanded(hKey, defaultExpanded ~= false)

        if currencySearchText ~= "" then
            hExpanded = true
        end

        local hdr, _ = CreateCollapsibleHeader(
            parent,
            headerTitle .. " (" .. (countOverride or #items) .. ")",
            hKey,
            hExpanded,
            function(isExpanded) ToggleExpand(hKey, isExpanded) end,
            headerIcon
        )
        hdr:SetPoint("TOPLEFT", 10 + baseIndent, -yOffset)
        hdr:SetWidth(width - baseIndent)
        hdr:SetBackdropColor(0.10, 0.10, 0.12, 0.9)
        local COLORS = GetCOLORS()
        local borderColor = COLORS.accent
        hdr:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)

        yOffset = yOffset + HEADER_SPACING

        if hExpanded then
            local rowIdx = 0
            for _, curr in ipairs(items) do
                rowIdx = rowIdx + 1
                yOffset = CreateCurrencyRow(parent, curr.data, curr.id, rowIdx, baseIndent, width, yOffset)
            end
        end

        if nestedFn then
            nestedFn(hExpanded)
        end
    end

    local function RenderBlizzardOrder(charKeyForState, currList, baseIndent)
        local buckets = BuildHeaderBuckets(currList)

        -- Midnight (when it exists) + Season subheaders
        local midnight = buckets["midnight"]
        if midnight and #midnight.items > 0 then
            RenderCurrenciesUnderHeader(
                midnight.name,
                charKeyForState .. "-hdr-midnight",
                "Interface\\Icons\\INV_Misc_QuestionMark",
                midnight.items,
                baseIndent,
                true,
                function()
                    -- Season subheaders (Season 1, Season 2, ...)
                    for i = 1, 6 do
                        local sKey = "season " .. i
                        local sBucket = buckets[sKey]
                        if sBucket and #sBucket.items > 0 then
                            RenderCurrenciesUnderHeader(
                                sBucket.name,
                                charKeyForState .. "-hdr-midnight-" .. sKey:gsub("%s",""),
                                "Interface\\Icons\\INV_Misc_QuestionMark",
                                sBucket.items,
                                baseIndent + 20,
                                true
                            )
                        end
                    end
                end
            )
        end

        -- Dungeon & Raid
        local dr = buckets["dungeon and raid"] or buckets["dungeons and raids"] or buckets["dungeon & raid"]
        if dr and #dr.items > 0 then
            RenderCurrenciesUnderHeader(
                dr.name,
                charKeyForState .. "-hdr-dungeonraid",
                "Interface\\Icons\\achievement_boss_archaedas",
                dr.items,
                baseIndent,
                true
            )
        end

        -- Miscellaneous with Timerunning subheader
        local misc = buckets["miscellaneous"]
        if misc and #misc.items > 0 then
            RenderCurrenciesUnderHeader(
                misc.name,
                charKeyForState .. "-hdr-misc",
                "Interface\\Icons\\INV_Misc_Gear_01",
                misc.items,
                baseIndent,
                true,
                function()
                    local tr = buckets["timerunning"] or buckets["time running"]
                    if tr and #tr.items > 0 then
                        RenderCurrenciesUnderHeader(
                            tr.name,
                            charKeyForState .. "-hdr-timerunning",
                            "Interface\\Icons\\INV_Misc_QuestionMark",
                            tr.items,
                            baseIndent + 20,
                            true
                        )
                    end
                end
            )
        elseif (buckets["timerunning"] or buckets["time running"]) then
            local tr = buckets["timerunning"] or buckets["time running"]
            if tr and #tr.items > 0 then
                RenderCurrenciesUnderHeader(
                    "Miscellaneous",
                    charKeyForState .. "-hdr-misc",
                    "Interface\\Icons\\INV_Misc_Gear_01",
                    tr.items,
                    baseIndent,
                    true,
                    function()
                        RenderCurrenciesUnderHeader(
                            tr.name,
                            charKeyForState .. "-hdr-timerunning",
                            "Interface\\Icons\\INV_Misc_QuestionMark",
                            tr.items,
                            baseIndent + 20,
                            true
                        )
                    end
                )
            end
        end

        -- Player vs. Player
        local pvp = buckets["player vs. player"] or buckets["pvp"]
        if pvp and #pvp.items > 0 then
            RenderCurrenciesUnderHeader(
                pvp.name,
                charKeyForState .. "-hdr-pvp",
                "Interface\\Icons\\Achievement_BG_returnXflags_def_WSG",
                pvp.items,
                baseIndent,
                true
            )
        end

        -- Legacy (with expansion subheadings)
        local legacyItemsCount = 0
        for _, expName in ipairs(LEGACY_ORDER) do
            local b = select(1, GetBucketByHeaderName(buckets, expName))
            if b and #b.items > 0 then
                legacyItemsCount = legacyItemsCount + #b.items
            end
        end


        -- Season buckets sometimes appear as top-level headers (e.g. "Season 3") but should be nested under
        -- Legacy → The War Within (to mirror Blizzard's currency layout).
        local warWithinBucket, warWithinKey = GetBucketByHeaderName(buckets, "The War Within")
        local seasonCount = 0
        for i = 1, 6 do
            local sKey = "season " .. i
            local sBucket = buckets[sKey]
            if sBucket and #sBucket.items > 0 then
                seasonCount = seasonCount + #sBucket.items
            end
        end
        if seasonCount > 0 then
            legacyItemsCount = legacyItemsCount + seasonCount
        end

        if legacyItemsCount > 0 then
            local legacyKey = charKeyForState .. "-hdr-legacy"
            local legacyExpanded = IsExpanded(legacyKey, true)
            if currencySearchText ~= "" then legacyExpanded = true end

            local legacyHdr, _ = CreateCollapsibleHeader(
                parent,
                "Legacy (" .. legacyItemsCount .. ")",
                legacyKey,
                legacyExpanded,
                function(isExpanded) ToggleExpand(legacyKey, isExpanded) end,
                "Interface\\Icons\\INV_Misc_QuestionMark"
            )
            legacyHdr:SetPoint("TOPLEFT", 10 + baseIndent, -yOffset)
            legacyHdr:SetWidth(width - baseIndent)
            legacyHdr:SetBackdropColor(0.10, 0.10, 0.12, 0.9)
            local COLORS = GetCOLORS()
            local borderColor = COLORS.accent
            legacyHdr:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)

            yOffset = yOffset + HEADER_SPACING

            if legacyExpanded then
                for _, expName in ipairs(LEGACY_ORDER) do
                    local b, key = GetBucketByHeaderName(buckets, expName)

                    if key == warWithinKey then
                        -- War Within: nest Season headers beneath it
                        local wwItems = (b and b.items) or {}
                        local wwSeasonCount = 0
                        for i = 1, 6 do
                            local sKey = "season " .. i
                            local sBucket = buckets[sKey]
                            if sBucket and #sBucket.items > 0 then
                                wwSeasonCount = wwSeasonCount + #sBucket.items
                            end
                        end

                        if (#wwItems > 0) or (wwSeasonCount > 0) then
                            RenderCurrenciesUnderHeader(
                                (b and b.name) or expName,
                                charKeyForState .. "-legacy-" .. key:gsub("%s",""),
                                nil,
                                wwItems,
                                baseIndent + 20,
                                true,
                                function()
                                    for i = 1, 6 do
                                        local sKey = "season " .. i
                                        local sBucket = buckets[sKey]
                                        if sBucket and #sBucket.items > 0 then
                                            RenderCurrenciesUnderHeader(
                                                sBucket.name,
                                                charKeyForState .. "-legacy-" .. key:gsub("%s","") .. "-" .. sKey:gsub("%s",""),
                                                "Interface\Icons\INV_Misc_QuestionMark",
                                                sBucket.items,
                                                baseIndent + 40,
                                                true
                                            )
                                        end
                                    end
                                end,
                                true,
                                (#wwItems + wwSeasonCount)
                            )
                        end
                    else
                        if b and #b.items > 0 then
                            RenderCurrenciesUnderHeader(
                                b.name,
                                charKeyForState .. "-legacy-" .. key:gsub("%s",""),
                                nil,
                                b.items,
                                baseIndent + 20,
                                true
                            )
                        end
                    end
                end
            end
        end
    end

-- Draw each character
    for _, charData in ipairs(charactersWithCurrencies) do
        local char = charData.char
        local charKey = charData.key
        local currencies = charData.currencies
        
        -- Character header
        local classColor = RAID_CLASS_COLORS[char.classFile or char.class] or {r=1, g=1, b=1}
        local onlineBadge = charData.isOnline and " |cff00ff00(Online)|r" or ""
        local charName = (FormatCharacterNameRealm and FormatCharacterNameRealm(char.name, char.realm, char.classFile or char.class))
            or format("%s-%s", char.name or "Unknown", char.realm or "Unknown")
        
        local charKey_expand = "currency-char-" .. charKey
        local charExpanded = IsExpanded(charKey_expand, charData.isOnline)  -- Auto-expand online character
        
        if currencySearchText ~= "" then
            charExpanded = true
        end
        
        -- Get class icon texture path
        local classIconPath = nil
        local coords = CLASS_ICON_TCOORDS[char.classFile or char.class]
        if coords then
            classIconPath = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
        end
        
        local charHeader, charBtn, classIcon = CreateCollapsibleHeader(
            parent,
            format("%s%s - |cff888888%d currencies|r", charName, onlineBadge, #currencies),
            charKey_expand,
            charExpanded,
            function(isExpanded) ToggleExpand(charKey_expand, isExpanded) end,
            classIconPath  -- Pass class icon path
        )
        
        -- If we have class icon coordinates, apply them
        if classIcon and coords then
            classIcon:SetTexCoord(unpack(coords))
        end
        
        charHeader:SetPoint("TOPLEFT", 10, -yOffset)
        charHeader:SetWidth(width)
        charHeader:SetBackdropColor(0.10, 0.10, 0.12, 0.9)
        local COLORS = GetCOLORS()
        local borderColor = COLORS.accent
        charHeader:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)
        
        yOffset = yOffset + HEADER_SPACING
        
        if charExpanded then
            local charIndent = 20
            
                        -- Render currencies in Blizzard header order (shared between both views)
            RenderBlizzardOrder(charKey, currencies, charIndent)
        end
        
        yOffset = yOffset + 5
    end
    
    -- ===== API LIMITATION NOTICE =====
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
    noticeFrame:SetBackdropBorderColor(0.5, 0.4, 0.2, 0.8)
    
    local noticeIcon = noticeFrame:CreateTexture(nil, "ARTWORK")
    noticeIcon:SetSize(24, 24)
    noticeIcon:SetPoint("LEFT", 10, 0)
    noticeIcon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    
    local noticeText = noticeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noticeText:SetPoint("LEFT", noticeIcon, "RIGHT", 10, 5)
    noticeText:SetPoint("RIGHT", -10, 5)
    noticeText:SetJustifyH("LEFT")
    noticeText:SetText("|cffffcc00Currency Transfer Limitation|r")
    
    local noticeSubText = noticeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noticeSubText:SetPoint("TOPLEFT", noticeIcon, "TOPRIGHT", 10, -15)
    noticeSubText:SetPoint("RIGHT", -10, 0)
    noticeSubText:SetJustifyH("LEFT")
    noticeSubText:SetTextColor(0.8, 0.8, 0.8)
    noticeSubText:SetText("Blizzard API does not support automated currency transfers. Please use the in-game currency frame to manually transfer Warband currencies.")
    
    yOffset = yOffset + 75
    
    return yOffset
end
