--[[
    The Quartermaster - Experience Tab
    Foundation for the Experience tab (currently mirrors Characters)
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

-- Import shared UI components (always get fresh reference)
local function GetCOLORS()
    return ns.UI_COLORS
end
local CreateCard = ns.UI_CreateCard
local FormatGold = ns.UI_FormatGold
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader

--============================================================================
-- TOOLTIP HELPERS
--============================================================================

-- FontStrings can't receive mouse events, so we add a tiny overlay frame for hover.
local function AttachColumnTooltip(parentRow, xOffset, width, title, description)
    local hit = CreateFrame("Frame", nil, parentRow)
    hit:SetPoint("LEFT", xOffset, 0)
    hit:SetSize(width, 24)
    hit:SetFrameLevel((parentRow:GetFrameLevel() or 1) + 5)
    hit:EnableMouse(true)

    hit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(description, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return hit
end

--============================================================================
-- DRAW CHARACTER LIST
--============================================================================

function TheQuartermaster:DrawExperienceList(parent)
    local yOffset = 8 -- Top padding for breathing room
    local width = parent:GetWidth() - 20
    
    -- Get all characters (cached for performance)
    local characters = self.GetCachedCharacters and self:GetCachedCharacters() or self:GetAllCharacters()
    
    -- Get current player key
    local currentPlayerName = UnitName("player")
    local currentPlayerRealm = GetRealmName()
    local currentPlayerKey = currentPlayerName .. "-" .. currentPlayerRealm
    
    -- ===== TITLE CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    -- Use the current player's portrait (race/gender) for the Characters tab header icon.
    -- Falls back to a static icon if portrait APIs aren't available.
    if SetPortraitTexture then
        pcall(SetPortraitTexture, titleIcon, "player")
    else
        titleIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    end
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    -- Dynamic theme color for title
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Experience|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText(#characters .. " characters tracked")
    
    yOffset = yOffset + 75 -- Reduced spacing
    
    
    -- ===== SUMMARY BOXES =====
    local totalPlayedSeconds = 0
    local maxLevelCount = 0
    local fullyRestedCount = 0

    local maxLevel = 80
    if type(GetMaxPlayerLevel) == "function" then
        local ml = GetMaxPlayerLevel()
        if type(ml) == "number" and ml > 0 then
            maxLevel = ml
        end
    end

    for _, char in ipairs(characters) do
        if char.playedTime and char.playedTime > 0 then
            totalPlayedSeconds = totalPlayedSeconds + char.playedTime
        end

        if (char.level or 0) >= maxLevel then
            maxLevelCount = maxLevelCount + 1
        else
            -- Fully rested = rested pool at cap (150% of a level)
            local restXP = tonumber(char.restXP) or 0
            local maxXP = tonumber(char.maxXP) or 0
            local cap = math.floor(maxXP * 1.5 + 0.5)
            if maxXP > 0 and restXP >= cap then
                fullyRestedCount = fullyRestedCount + 1
            end
        end
    end

    local function FormatPlayedTime(seconds)
        if not seconds or seconds <= 0 then
            return "--"
        end
        local days = math.floor(seconds / 86400)
        local hours = math.floor((seconds % 86400) / 3600)
        local mins = math.floor((seconds % 3600) / 60)
        local secs = math.floor(seconds % 60)
        return string.format("%dd %02dh %02dm %02ds", days, hours, mins, secs)
    end

    -- Calculate card width for 3 cards in a row
    local leftMargin = 10
    local rightMargin = 10
    local cardSpacing = 10
    local totalSpacing = cardSpacing * 2  -- 2 gaps between 3 cards
    local threeCardWidth = (width - leftMargin - rightMargin - totalSpacing) / 3

    -- Accent hex for theme-colored numbers
    local COLORS = GetCOLORS()
    local ar, ag, ab = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local accentHex = string.format("%02x%02x%02x", ar * 255, ag * 255, ab * 255)

    -- Total Played Time Card (Left)
    local playedCard = CreateCard(parent, 90)
    playedCard:SetWidth(threeCardWidth)
    playedCard:SetPoint("TOPLEFT", leftMargin, -yOffset)

    local pIcon = playedCard:CreateTexture(nil, "ARTWORK")
    pIcon:SetSize(36, 36)
    pIcon:SetPoint("LEFT", 15, 0)
    pIcon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")

    local pLabel = playedCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pLabel:SetPoint("TOPLEFT", pIcon, "TOPRIGHT", 12, -2)
    pLabel:SetText("TOTAL PLAYED")
    pLabel:SetTextColor(0.6, 0.6, 0.6)

    local pValue = playedCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    do
        local font, size, flags = pValue:GetFont()
        if font and size then
            pValue:SetFont(font, math.max(10, math.floor(size * 0.67 + 0.5)), flags)
        end
    end
    pValue:SetPoint("BOTTOMLEFT", pIcon, "BOTTOMRIGHT", 12, 0)
    pValue:SetText("|cffffffff" .. FormatPlayedTime(totalPlayedSeconds) .. "|r")

    -- Max Level Characters Card (Middle)
    local maxLvlCard = CreateCard(parent, 90)
    maxLvlCard:SetWidth(threeCardWidth)
    maxLvlCard:SetPoint("LEFT", playedCard, "RIGHT", cardSpacing, 0)

    local mIcon = maxLvlCard:CreateTexture(nil, "ARTWORK")
    mIcon:SetSize(36, 36)
    mIcon:SetPoint("LEFT", 15, 0)
    mIcon:SetTexture("Interface\\Icons\\achievement_level_90") -- generic achievement icon (exists broadly)

    local mLabel = maxLvlCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mLabel:SetPoint("TOPLEFT", mIcon, "TOPRIGHT", 12, -2)
    mLabel:SetText("MAX LEVEL")
    mLabel:SetTextColor(0.6, 0.6, 0.6)

    local mValue = maxLvlCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    do
        local font, size, flags = mValue:GetFont()
        if font and size then
            mValue:SetFont(font, math.max(10, math.floor(size * 0.67 + 0.5)), flags)
        end
    end
    mValue:SetPoint("BOTTOMLEFT", mIcon, "BOTTOMRIGHT", 12, 0)
    mValue:SetText("|cff" .. accentHex .. tostring(maxLevelCount) .. "|r")

    -- Fully Rested Characters Card (Right)
    local restedCard = CreateCard(parent, 90)
    restedCard:SetWidth(threeCardWidth)
    restedCard:SetPoint("LEFT", maxLvlCard, "RIGHT", cardSpacing, 0)
    restedCard:SetPoint("RIGHT", -rightMargin, 0)

    local rIcon = restedCard:CreateTexture(nil, "ARTWORK")
    rIcon:SetSize(36, 36)
    rIcon:SetPoint("LEFT", 15, 0)
    rIcon:SetTexture("Interface\\Icons\\Spell_Nature_Sleep") -- Zzz / rested

    local rLabel = restedCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rLabel:SetPoint("TOPLEFT", rIcon, "TOPRIGHT", 12, -2)
    rLabel:SetText("FULLY RESTED")
    rLabel:SetTextColor(0.6, 0.6, 0.6)

    local rValue = restedCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    do
        local font, size, flags = rValue:GetFont()
        if font and size then
            rValue:SetFont(font, math.max(10, math.floor(size * 0.67 + 0.5)), flags)
        end
    end
    rValue:SetPoint("BOTTOMLEFT", rIcon, "BOTTOMRIGHT", 12, 0)
    rValue:SetText("|cffffffff" .. tostring(fullyRestedCount) .. "|r")

    yOffset = yOffset + 100
-- ===== SORT CHARACTERS: FAVORITES → REGULAR =====
    local favorites = {}
    local regular = {}
    
    for _, char in ipairs(characters) do
        local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
        
        -- Add to appropriate list (current character is not separated)
        if self:IsFavoriteCharacter(charKey) then
            table.insert(favorites, char)
        else
            table.insert(regular, char)
        end
    end
    
    -- Load custom order from profile
    if not self.db.profile.characterOrder then
        self.db.profile.characterOrder = {
            favorites = {},
            regular = {}
        }
    end
    
    -- Sort function (with custom order support)
    local function sortCharacters(list, orderKey)
        local customOrder = self.db.profile.characterOrder[orderKey] or {}
        
        -- If custom order exists and has items, use it
        if #customOrder > 0 then
            local ordered = {}
            local charMap = {}
            
            -- Create a map for quick lookup
            for _, char in ipairs(list) do
                local key = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
                charMap[key] = char
            end
            
            -- Add characters in custom order
            for _, charKey in ipairs(customOrder) do
                if charMap[charKey] then
                    table.insert(ordered, charMap[charKey])
                    charMap[charKey] = nil  -- Remove to track remaining
                end
            end
            
            -- Add any new characters not in custom order (at the end, sorted)
            local remaining = {}
            for _, char in pairs(charMap) do
                table.insert(remaining, char)
            end
            table.sort(remaining, function(a, b)
                if (a.level or 0) ~= (b.level or 0) then
                    return (a.level or 0) > (b.level or 0)
                else
                    return (a.name or ""):lower() < (b.name or ""):lower()
                end
            end)
            for _, char in ipairs(remaining) do
                table.insert(ordered, char)
            end
            
            return ordered
        else
            -- Default sort: level desc → name asc (ignore table header sorting for now)
            table.sort(list, function(a, b)
                if (a.level or 0) ~= (b.level or 0) then
                    return (a.level or 0) > (b.level or 0)
                else
                    return (a.name or ""):lower() < (b.name or ""):lower()
                end
            end)
            return list
        end
    end
    
    -- Sort both groups with custom order
    favorites = sortCharacters(favorites, "favorites")
    regular = sortCharacters(regular, "regular")
    
    -- Update current character's lastSeen to now (so it shows as online)
    if self.db.global.characters and self.db.global.characters[currentPlayerKey] then
        self.db.global.characters[currentPlayerKey].lastSeen = time()
    end
    
    -- ===== EMPTY STATE =====
    if #characters == 0 then
        local emptyIcon = parent:CreateTexture(nil, "ARTWORK")
        emptyIcon:SetSize(48, 48)
        emptyIcon:SetPoint("TOP", 0, -yOffset - 30)
        emptyIcon:SetTexture("Interface\\Icons\\Ability_Spy")
        emptyIcon:SetDesaturated(true)
        emptyIcon:SetAlpha(0.4)
        
        local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        emptyText:SetPoint("TOP", 0, -yOffset - 90)
        emptyText:SetText("|cff666666No characters tracked yet|r")
        
        local emptyDesc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyDesc:SetPoint("TOP", 0, -yOffset - 115)
        emptyDesc:SetTextColor(0.5, 0.5, 0.5)
        emptyDesc:SetText("Characters are automatically registered on login")
        
        return yOffset + 200
    end
    
    -- Initialize collapse state (persistent)
    if not self.db.profile.ui then
        self.db.profile.ui = {}
    end
    if self.db.profile.ui.favoritesExpanded == nil then
        self.db.profile.ui.favoritesExpanded = true
    end
    if self.db.profile.ui.charactersExpanded == nil then
        self.db.profile.ui.charactersExpanded = true
    end
    
    
    -- Column header (Experience)
    do
        local header = CreateFrame("Frame", nil, parent)
        header:SetSize(width, 22)
        header:SetPoint("TOPLEFT", 10, -yOffset)

        local bg = header:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.07, 0.07, 0.09, 0.9)

        -- Align with row layout (same icon padding as rows)
        local baseX = 96  -- after: favorite + online + class + faction
        local nameX  = baseX
        local levelX = nameX + 240 + 16
        local restX  = levelX + 25 + 14
        local maxX   = restX + 70 + 14
        local fullX  = maxX + 70 + 14
        local playedX = fullX + 95 + 16
        local statusX = playedX + 70 + 16

        local function AddLabel(text, x, w, justify)
            local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("LEFT", x, 0)
            fs:SetWidth(w)
            fs:SetJustifyH(justify or "LEFT")
            fs:SetText("|cffaaaaaa" .. text .. "|r")
            return fs
        end

        AddLabel("Character", nameX, 240, "LEFT")
        AddLabel("Lvl", levelX, 25, "CENTER")
        AddLabel("Rested XP", restX, 70, "CENTER")
        AddLabel("Max XP", maxX, 70, "CENTER")
        AddLabel("Rested In", fullX, 95, "CENTER")
        AddLabel("Played", playedX, 70, "LEFT")
        AddLabel("Status", statusX, 90, "LEFT")

        yOffset = yOffset + 26
    end

-- ===== FAVORITES SECTION (Always show header) =====
    local favHeader, _, favIcon = CreateCollapsibleHeader(
        parent,
        string.format("Favorites |cff888888(%d)|r", #favorites),
        "favorites",
        self.db.profile.ui.favoritesExpanded,
        function(isExpanded)
            self.db.profile.ui.favoritesExpanded = isExpanded
            self:RefreshUI()
        end,
        "Interface\\Icons\\trade_archaeology_tyrandesfavoritedoll"
    )
    favHeader:SetPoint("TOPLEFT", 10, -yOffset)
    favHeader:SetPoint("TOPRIGHT", -10, -yOffset)
    
    -- Color the favorites header icon gold
    if favIcon then
        favIcon:SetVertexColor(1, 0.84, 0)
    end
    
    yOffset = yOffset + 38  -- Standard header spacing
    
    if self.db.profile.ui.favoritesExpanded then
        yOffset = yOffset + 3  -- Small spacing after header
        if #favorites > 0 then
            for i, char in ipairs(favorites) do
                yOffset = self:DrawExperienceRow(parent, char, i, width, yOffset, true, true, favorites, "favorites", i, #favorites, currentPlayerKey)
            end
        else
            -- Empty state
            local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            emptyText:SetPoint("TOPLEFT", 30, -yOffset)
            emptyText:SetTextColor(0.5, 0.5, 0.5)
            emptyText:SetText("No favorite characters yet. Click the star icon to favorite a character.")
            yOffset = yOffset + 35
        end
    end
    
    -- ===== REGULAR CHARACTERS SECTION (Always show header) =====
    local charHeader, _, charHeaderIcon = CreateCollapsibleHeader(
        parent,
        string.format("Characters |cff888888(%d)|r", #regular),
        "characters",
        self.db.profile.ui.charactersExpanded,
        function(isExpanded)
            self.db.profile.ui.charactersExpanded = isExpanded
            self:RefreshUI()
        end,
        "Interface\\Icons\\INV_Misc_Book_09"
    )
    charHeader:SetPoint("TOPLEFT", 10, -yOffset)
    charHeader:SetPoint("TOPRIGHT", -10, -yOffset)

    -- Replace the section header icon with the current player's portrait (race/gender)
    if charHeaderIcon and SetPortraitTexture then
        pcall(SetPortraitTexture, charHeaderIcon, "player")
    end
    yOffset = yOffset + 38  -- Standard header spacing
    
    if self.db.profile.ui.charactersExpanded then
        yOffset = yOffset + 3  -- Small spacing after header
        if #regular > 0 then
            for i, char in ipairs(regular) do
                yOffset = self:DrawExperienceRow(parent, char, i, width, yOffset, false, true, regular, "regular", i, #regular, currentPlayerKey)
            end
        else
            -- Empty state
            local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            emptyText:SetPoint("TOPLEFT", 30, -yOffset)
            emptyText:SetTextColor(0.5, 0.5, 0.5)
            emptyText:SetText("All characters are favorited!")
            yOffset = yOffset + 35
        end
    end
    
    return yOffset
end

--============================================================================
-- DRAW SINGLE CHARACTER ROW
--============================================================================

function TheQuartermaster:DrawExperienceRow(parent, char, index, width, yOffset, isFavorite, showReorder, charList, listKey, positionInList, totalInList, currentPlayerKey)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 38)  -- Taller row height
    row:SetPoint("TOPLEFT", 10, -yOffset)
    row:EnableMouse(true)
    
    -- Check if this is the current character
    local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
    local isCurrent = (charKey == currentPlayerKey)
    
    -- Row background (alternating colors)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local bgColor = index % 2 == 0 and {0.08, 0.08, 0.10, 1} or {0.05, 0.05, 0.06, 1}
    bg:SetColorTexture(unpack(bgColor))
    row.bgColor = bgColor
    
    -- Class color
    local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}
    
    local leftOffset = 10  -- Start from left edge with minimal padding
        
    -- Favorite button (star icon)
    local favButton = CreateFrame("Button", nil, row)
    favButton:SetSize(22, 22)
    favButton:SetPoint("LEFT", leftOffset, 0)
    leftOffset = leftOffset + 26  -- Spacing after favorite
    
    -- Reserve space for online indicator (even if not shown, for alignment)
    local onlineSpace = 20  -- Spacing for online icon
    
    local favIcon = favButton:CreateTexture(nil, "ARTWORK")
    favIcon:SetAllPoints()
    if isFavorite then
        -- Filled gold star (same as in header)
        favIcon:SetTexture("Interface\\COMMON\\FavoritesIcon")
        favIcon:SetVertexColor(1, 0.84, 0)  -- Gold color
    else
        -- Empty gray star
        favIcon:SetTexture("Interface\\COMMON\\FavoritesIcon")
        favIcon:SetDesaturated(true)
        favIcon:SetVertexColor(0.5, 0.5, 0.5)
    end
    favButton.icon = favIcon
    favButton.charKey = charKey
    
    favButton:SetScript("OnClick", function(self)
        local newStatus = TheQuartermaster:ToggleFavoriteCharacter(self.charKey)
        -- Update icon (always use same star texture, just change color)
        if newStatus then
            self.icon:SetDesaturated(false)
            self.icon:SetVertexColor(1, 0.84, 0)  -- Gold
        else
            self.icon:SetDesaturated(true)
            self.icon:SetVertexColor(0.5, 0.5, 0.5)  -- Gray
        end
        -- Refresh to re-sort
        TheQuartermaster:RefreshUI()
    end)
    
    favButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if isFavorite then
            GameTooltip:SetText("|cffffd700Favorite Character|r\nClick to remove from favorites")
        else
            GameTooltip:SetText("Click to add to favorites\n|cff888888Favorites are always shown at the top|r")
        end
        GameTooltip:Show()
    end)
    
    favButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Online indicator (only for current character, but space is always reserved)
    if isCurrent then
        local onlineIndicator = row:CreateTexture(nil, "ARTWORK")
        onlineIndicator:SetSize(16, 16)
        onlineIndicator:SetPoint("LEFT", leftOffset, 0)
        onlineIndicator:SetTexture("Interface\\FriendsFrame\\StatusIcon-Online")
    end
    leftOffset = leftOffset + onlineSpace  -- Always add space (aligned)
    
    -- Class icon
    local classIcon = row:CreateTexture(nil, "ARTWORK")
    classIcon:SetSize(18, 18)
    classIcon:SetPoint("LEFT", leftOffset, 0)
    leftOffset = leftOffset + 20  -- Spacing after class icon
    local coords = CLASS_ICON_TCOORDS[char.classFile]
    if coords then
        classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        classIcon:SetTexCoord(unpack(coords))
    else
        classIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- Faction flag between class icon and name
    local factionIcon = row:CreateTexture(nil, "ARTWORK")
    factionIcon:SetSize(16, 16)
    factionIcon:SetPoint("LEFT", leftOffset, 0)
    factionIcon:Hide()

    local faction = char.faction
    if type(faction) == "string" then
        local f = faction:lower()
        if f:find("alliance") then
            factionIcon:SetTexture("Interface\\FriendsFrame\\PlusManz-Alliance")
            factionIcon:Show()
        elseif f:find("horde") then
            factionIcon:SetTexture("Interface\\FriendsFrame\\PlusManz-Horde")
            factionIcon:Show()
        end
    end

    leftOffset = leftOffset + 20  -- Spacing after faction icon
    -- Evenly distributed columns from left to right (Experience view)
    -- Tuned for: XP columns + played + status while keeping name readable.
    local nameOffset = leftOffset
    local nameWidth  = 240

    local levelOffset = nameOffset + nameWidth + 16
    local levelWidth  = 25

    local restOffset  = levelOffset + levelWidth + 14
    local restWidth   = 70

    local maxOffset   = restOffset + restWidth + 14
    local maxWidth    = 70

    local fullOffset  = maxOffset + maxWidth + 14
    local fullWidth   = 95

    local playedOffset = fullOffset + fullWidth + 16
    local playedWidth  = 70

    local statusOffset = playedOffset + playedWidth + 16
    local statusWidth  = 90

-- Character name with realm (combined) (in class color)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", nameOffset, 0)
    local nameReserve = (showReorder and 52 or 0)
    nameText:SetWidth(nameWidth - nameReserve)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    -- Name in class color, realm in gray
    nameText:SetText(string.format("|cff%02x%02x%02x%s|r|cff808080-%s|r", 
        classColor.r * 255, classColor.g * 255, classColor.b * 255, 
        char.name or "Unknown",
        char.realm or "Unknown"))
    
    -- Reorder buttons (after name, on the right side)
    if showReorder and charList then
        local reorderButtons = CreateFrame("Frame", nil, row)
        reorderButtons:SetSize(48, 24)
        reorderButtons:SetPoint("LEFT", nameOffset + nameWidth - 48, 0)  -- Right side of name area
        reorderButtons:Hide()
        reorderButtons:SetFrameLevel(row:GetFrameLevel() + 10)
        
        -- Store reference immediately for closures
        row.reorderButtons = reorderButtons
        
        -- Up arrow (LEFT side) - Move character UP in list
        local upBtn = CreateFrame("Button", nil, reorderButtons)
        upBtn:SetSize(22, 22)
        upBtn:SetPoint("LEFT", 0, 0)
        
        -- Disable if first in list
        if positionInList and positionInList == 1 then
            upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled")
            upBtn:SetAlpha(0.5)
            upBtn:Disable()
            upBtn:EnableMouse(false)
        else
            upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
            upBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
            upBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
            
            upBtn:SetScript("OnClick", function()
                TheQuartermaster:ReorderCharacter(char, charList, listKey, -1)
            end)
            
            upBtn:SetScript("OnEnter", function(self)
                row.reorderButtons:Show()
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Move Up")
                GameTooltip:Show()
            end)
            
            upBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end
        
        -- Down arrow (RIGHT side) - Move character DOWN in list
        local downBtn = CreateFrame("Button", nil, reorderButtons)
        downBtn:SetSize(22, 22)
        downBtn:SetPoint("RIGHT", 0, 0)
        
        -- Disable if last in list
        if positionInList and totalInList and positionInList == totalInList then
            downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled")
            downBtn:SetAlpha(0.5)
            downBtn:Disable()
            downBtn:EnableMouse(false)
        else
            downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
            downBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
            downBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
            
            downBtn:SetScript("OnClick", function()
                TheQuartermaster:ReorderCharacter(char, charList, listKey, 1)
            end)
            
            downBtn:SetScript("OnEnter", function(self)
                row.reorderButtons:Show()
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Move Down")
                GameTooltip:Show()
            end)
            
            downBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end
    end
    
    -- Level (just the number, centered in its column)
    local levelText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    levelText:SetPoint("LEFT", levelOffset, 0)
    levelText:SetWidth(levelWidth)
    levelText:SetJustifyH("CENTER")
    levelText:SetText(string.format("|cff%02x%02x%02x%d|r", 
        classColor.r * 255, classColor.g * 255, classColor.b * 255, 
        char.level or 1))
    

    -- Rest/XP values
    local maxPlayerLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 80
    local isMaxLevel = (type(char.level) == "number" and char.level >= maxPlayerLevel)

    local restXP = char.restXP or char.restXp or char.restedXP or char.restedXp
    local maxXP = char.maxXP or char.maxXp or char.xpMax or char.xpmax

    -- Rest XP (as % up to 150%)
    local restText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    restText:SetPoint("LEFT", restOffset, 0)
    restText:SetWidth(restWidth)
    restText:SetJustifyH("CENTER")

    if isMaxLevel then
        restText:SetText("|cffaaaaaaMax Level|r")
    elseif type(restXP) == "number" and type(maxXP) == "number" and maxXP > 0 and restXP >= 0 then
        local pct = (restXP / maxXP) * 100
        if pct > 150 then pct = 150 end
        restText:SetText(string.format("|cffcccccc%.0f%%|r", pct))
    else
        restText:SetText("|cff666666--|r")
    end

    -- Tooltip (Rest XP)
    AttachColumnTooltip(row, restOffset, restWidth,
        "Rested XP",
        "Shown as a % or \"Max Level\"")

    -- Max XP (maximum rested XP pool)
    local maxText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    maxText:SetPoint("LEFT", maxOffset, 0)
    maxText:SetWidth(maxWidth)
    maxText:SetJustifyH("CENTER")

    if isMaxLevel then
        maxText:SetText("|cffaaaaaaMax Level|r")
    elseif type(maxXP) == "number" and maxXP > 0 then
        local capXP = math.floor(maxXP * 1.5)
        maxText:SetText("|cffcccccc" .. BreakUpLargeNumbers(capXP) .. "|r")
    else
        maxText:SetText("|cff666666--|r")
    end

    -- Tooltip (Max XP)
    AttachColumnTooltip(row, maxOffset, maxWidth,
        "Max XP",
        "Maximum rested Experience that can be accumilated")

    -- Fully rested in
    local fullText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fullText:SetPoint("LEFT", fullOffset, 0)
    fullText:SetWidth(fullWidth)
    fullText:SetJustifyH("CENTER")

    if isMaxLevel then
        fullText:SetText("|cffaaaaaaMax Level|r")
    else
        local capXP = (type(maxXP) == "number" and maxXP > 0) and (maxXP * 1.5) or nil
        if capXP and type(restXP) == "number" and restXP >= capXP - 1 then
            fullText:SetText("|cff88ff88Fully Rested|r")
        else
            local fullyRestedSeconds = char.fullyRestedIn or char.fullyRestedSeconds or char.fullyRested or nil
            if type(fullyRestedSeconds) == "number" and fullyRestedSeconds > 0 then
                local d = math.floor(fullyRestedSeconds / 86400)
                local h = math.floor((fullyRestedSeconds % 86400) / 3600)
                local m = math.floor((fullyRestedSeconds % 3600) / 60)
                local s = math.floor(fullyRestedSeconds % 60)
                fullText:SetText(string.format("|cff888888%02dd %02dh|r", d, h))
            else
                fullText:SetText("|cff666666--|r")
            end
        end
    end

    -- Tooltip (Fully Rested In)
    AttachColumnTooltip(row, fullOffset, fullWidth,
        "Fully Rested In",
        "Time remaining, \"Fully Rested\", or \"Max Level\"")

-- Played time
    local playedText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    playedText:SetPoint("LEFT", playedOffset, 0)
    playedText:SetWidth(playedWidth)
    playedText:SetJustifyH("CENTER")

    local playedSeconds = tonumber(char.playedTime or char.totalPlayed or char.playedSeconds or char.played or char.timePlayed)
    local playedStr = "--"
    if playedSeconds and playedSeconds > 0 then
        local days = math.floor(playedSeconds / 86400)
        local hours = math.floor((playedSeconds % 86400) / 3600)
        if days > 0 then
            playedStr = string.format("%dd %dh", days, hours)
        else
            playedStr = string.format("%dh", hours)
        end
    end
    playedText:SetText("|cff888888" .. playedStr .. "|r")


    -- Online status positioned after played time

    local lastSeenText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lastSeenText:SetPoint("LEFT", statusOffset, 0)  -- Positioned after profession area
    lastSeenText:SetWidth(statusWidth)
    lastSeenText:SetJustifyH("LEFT")
    
    local lastSeenStr = ""
    if isCurrent then
        lastSeenStr = "|cff00ff00Online|r"
    elseif char.lastSeen then
        local timeDiff = time() - char.lastSeen
        if timeDiff < 60 then
            lastSeenStr = "|cff00ff00Online|r"
        elseif timeDiff < 3600 then
            lastSeenStr = math.floor(timeDiff / 60) .. "m ago"
        elseif timeDiff < 86400 then
            lastSeenStr = math.floor(timeDiff / 3600) .. "h ago"
        else
            lastSeenStr = math.floor(timeDiff / 86400) .. "d ago"
        end
    else
        lastSeenStr = "Unknown"
    end
    lastSeenText:SetText(lastSeenStr)
    lastSeenText:SetTextColor(0.7, 0.7, 0.7)
    
    -- Delete button (right side, after last seen) - Only show if NOT current character
    if not isCurrent then
        local deleteBtn = CreateFrame("Button", nil, row)
        deleteBtn:SetSize(22, 22)
        deleteBtn:SetPoint("RIGHT", -10, 0)
        
        local deleteIcon = deleteBtn:CreateTexture(nil, "ARTWORK")
        deleteIcon:SetAllPoints()
        deleteIcon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        deleteIcon:SetDesaturated(true)
        deleteIcon:SetVertexColor(0.8, 0.2, 0.2)
        deleteBtn.icon = deleteIcon
        deleteBtn.charKey = charKey
        deleteBtn.charName = char.name or "Unknown"
        
        deleteBtn:SetScript("OnClick", function(self)
            -- Show confirmation dialog
            StaticPopupDialogs["TheQuartermaster_DELETE_CHARACTER"] = {
                text = string.format(
                    "|cffff9900Delete Character?|r\n\n" ..
                    "Are you sure you want to delete |cff00ccff%s|r?\n\n" ..
                    "This will remove:\n" ..
                    "• Gold data\n" ..
                    "• Personal bank cache\n" ..
                    "• Profession info\n" ..
                    "• PvE progress\n" ..
                    "• All statistics\n\n" ..
                    "|cffff0000This action cannot be undone!|r",
                    self.charName
                ),
                button1 = "Delete",
                button2 = "Cancel",
                OnAccept = function()
                    local success = TheQuartermaster:DeleteCharacter(self.charKey)
                    if success and TheQuartermaster.RefreshUI then
                        TheQuartermaster:RefreshUI()
                    end
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            
            StaticPopup_Show("TheQuartermaster_DELETE_CHARACTER")
        end)
        
        deleteBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("|cffff5555Delete Character|r\nClick to remove this character's data")
            GameTooltip:Show()
        end)
        
        deleteBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
        
    -- Hover effect + Tooltip
    row:SetScript("OnEnter", function(self)
        bg:SetColorTexture(0.18, 0.18, 0.25, 1)
        
        -- Show reorder buttons on hover (no animation)
        if showReorder and self.reorderButtons then
            self.reorderButtons:SetAlpha(1)
            self.reorderButtons:Show()
        end
        
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(char.name or "Unknown", classColor.r, classColor.g, classColor.b)
        GameTooltip:AddLine(char.realm or "", 0.5, 0.5, 0.5)
        
        if isCurrent then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ff00Currently Online|r", 0.3, 1, 0.3)
        end
        
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Class:", char.class or "Unknown", 1, 1, 1, classColor.r, classColor.g, classColor.b)
        GameTooltip:AddDoubleLine("Level:", tostring(char.level or 1), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Gold:", FormatGold(char.gold or 0), 1, 1, 1, 1, 0.82, 0)
        if char.faction then
            GameTooltip:AddDoubleLine("Faction:", char.faction, 1, 1, 1, 0.7, 0.7, 0.7)
        end
        if char.race then
            GameTooltip:AddDoubleLine("Race:", char.race, 1, 1, 1, 0.7, 0.7, 0.7)
        end
        -- Spec (best-effort: may not be available for older cached characters)
        local specName = char.specName or char.spec or char.specialization or "Unknown"
        GameTooltip:AddDoubleLine("Spec:", tostring(specName), 1, 1, 1, 0.7, 0.7, 0.7)

        -- Played time (best-effort: expects seconds if available)
        local playedSeconds = tonumber(char.playedTime or char.totalPlayed or char.playedSeconds)
        local playedText
        if playedSeconds and playedSeconds > 0 then
            local days = math.floor(playedSeconds / 86400)
            local hours = math.floor((playedSeconds % 86400) / 3600)
            local mins = math.floor((playedSeconds % 3600) / 60)
            if days > 0 then
                playedText = string.format("%dd %dh", days, hours)
            else
                playedText = string.format("%dh %dm", hours, mins)
            end
        else
            playedText = "Unknown"
        end
        GameTooltip:AddDoubleLine("Played time:", playedText, 1, 1, 1, 0.7, 0.7, 0.7)

        
        
        GameTooltip:Show()
    end)
    
    row:SetScript("OnLeave", function(self)
        bg:SetColorTexture(unpack(self.bgColor))
        GameTooltip:Hide()
        
        -- Hide reorder buttons (no animation, direct hide)
        if showReorder and self.reorderButtons then
            self.reorderButtons:Hide()
        end
    end)
    
    return yOffset + 40  -- Row height (38) + spacing (2)
end

--============================================================================
-- REORDER CHARACTER IN LIST
--============================================================================

