--[[
    The Quartermaster - Characters Tab
    Display all tracked characters with gold, level, and last seen info
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
-- DRAW CHARACTER LIST
--============================================================================

function TheQuartermaster:DrawCharacterList(parent)
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
        titleIcon:SetTexture("Interface\\Icons\\Achievement_Character_Human_Female")
    end
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    -- Dynamic theme color for title
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Your Characters|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText(#characters .. " characters tracked")
    
    yOffset = yOffset + 75 -- Reduced spacing
    
    -- ===== TOTAL GOLD DISPLAY =====
    local totalGold = 0
    local totalPlayedSeconds = 0
    for _, char in ipairs(characters) do
        totalGold = totalGold + (char.gold or 0)
        if char.playedTime and char.playedTime > 0 then
            totalPlayedSeconds = totalPlayedSeconds + char.playedTime
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

        -- Display as dd hh mm ss (requested: hh mm dd ss)
        return string.format("%dd %02dh %02dm %02ds", days, hours, mins, secs)
    end
    
    -- Add Warband Bank gold to total
    local warbandBankGold = self:GetWarbandBankMoney() or 0
    local totalWithWarband = totalGold + warbandBankGold
    
    -- Calculate card width for 3 cards in a row (same as Statistics)
    local leftMargin = 10
    local rightMargin = 10
    local cardSpacing = 10
    local totalSpacing = cardSpacing * 2  -- 2 gaps between 3 cards
    local threeCardWidth = (width - leftMargin - rightMargin - totalSpacing) / 3
    
    -- Total Played Time Card (Left)
    local charGoldCard = CreateCard(parent, 90)
    charGoldCard:SetWidth(threeCardWidth)
    charGoldCard:SetPoint("TOPLEFT", leftMargin, -yOffset)
    local COLORS = GetCOLORS()
    local ar, ag, ab = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local accentHex = string.format("%02x%02x%02x", ar * 255, ag * 255, ab * 255)
    
    local cg1Icon = charGoldCard:CreateTexture(nil, "ARTWORK")
    cg1Icon:SetSize(36, 36)
    cg1Icon:SetPoint("LEFT", 15, 0)
    cg1Icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    
    local cg1Label = charGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cg1Label:SetPoint("TOPLEFT", cg1Icon, "TOPRIGHT", 12, -2)
    cg1Label:SetText("TOTAL PLAYED")
    cg1Label:SetTextColor(0.6, 0.6, 0.6)
    
    local cg1Value = charGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    do
        local font, size, flags = cg1Value:GetFont()
        if font and size then
            cg1Value:SetFont(font, math.max(10, math.floor(size * 0.67 + 0.5)), flags)
        end
    end
    cg1Value:SetPoint("BOTTOMLEFT", cg1Icon, "BOTTOMRIGHT", 12, 0)
    cg1Value:SetText("|cffffffff" .. FormatPlayedTime(totalPlayedSeconds) .. "|r")
    
    -- Warband Gold Card (Middle)
    local wbGoldCard = CreateCard(parent, 90)
    wbGoldCard:SetWidth(threeCardWidth)
    wbGoldCard:SetPoint("LEFT", charGoldCard, "RIGHT", cardSpacing, 0)
    wbGoldCard:SetBackdropColor(0.12, 0.10, 0.05, 1)
    wbGoldCard:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    
    local wb1Icon = wbGoldCard:CreateTexture(nil, "ARTWORK")
    wb1Icon:SetSize(36, 36)
    wb1Icon:SetPoint("LEFT", 15, 0)
    wb1Icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    
    local wb1Label = wbGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wb1Label:SetPoint("TOPLEFT", wb1Icon, "TOPRIGHT", 12, -2)
    wb1Label:SetText("WARBAND GOLD")
    wb1Label:SetTextColor(0.6, 0.6, 0.6)
    
    local wb1Value = wbGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    do
        local font, size, flags = wb1Value:GetFont()
        if font and size then
            wb1Value:SetFont(font, math.max(10, math.floor(size * 0.67 + 0.5)), flags)
        end
    end
    wb1Value:SetPoint("BOTTOMLEFT", wb1Icon, "BOTTOMRIGHT", 12, 0)
    wb1Value:SetText("|cffffd700" .. FormatGold(warbandBankGold) .. "|r")
    
    -- Total Gold Card (Right)
    local totalGoldCard = CreateCard(parent, 90)
    totalGoldCard:SetWidth(threeCardWidth)
    totalGoldCard:SetPoint("LEFT", wbGoldCard, "RIGHT", cardSpacing, 0)
    totalGoldCard:SetPoint("RIGHT", -rightMargin, 0)
    totalGoldCard:SetBackdropColor(0.12, 0.10, 0.05, 1)
    totalGoldCard:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    
    local tg1Icon = totalGoldCard:CreateTexture(nil, "ARTWORK")
    tg1Icon:SetSize(36, 36)
    tg1Icon:SetPoint("LEFT", 15, 0)
    tg1Icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    
    local tg1Label = totalGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tg1Label:SetPoint("TOPLEFT", tg1Icon, "TOPRIGHT", 12, -2)
    tg1Label:SetText("TOTAL GOLD")
    tg1Label:SetTextColor(0.6, 0.6, 0.6)
    
    local tg1Value = totalGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    do
        local font, size, flags = tg1Value:GetFont()
        if font and size then
            tg1Value:SetFont(font, math.max(10, math.floor(size * 0.67 + 0.5)), flags)
        end
    end
    tg1Value:SetPoint("BOTTOMLEFT", tg1Icon, "BOTTOMRIGHT", 12, 0)
    tg1Value:SetText("|cffffd700" .. FormatGold(totalWithWarband) .. "|r")
    
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
        "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"  -- Heart/people icon
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
                yOffset = self:DrawCharacterRow(parent, char, i, width, yOffset, true, true, favorites, "favorites", i, #favorites, currentPlayerKey)
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
        "Interface\\Icons\\Achievement_Character_Human_Female"
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
                yOffset = self:DrawCharacterRow(parent, char, i, width, yOffset, false, true, regular, "regular", i, #regular, currentPlayerKey)
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

function TheQuartermaster:DrawCharacterRow(parent, char, index, width, yOffset, isFavorite, showReorder, charList, listKey, positionInList, totalInList, currentPlayerKey)
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
    -- Evenly distributed columns from left to right
    -- NOTE: widths are tuned so: name does not clip, money stays on one line, and new columns fit.
    local nameOffset = leftOffset
    local nameWidth = 230  -- Wider so long names + realm don't truncate as easily

    local levelOffset = nameOffset + nameWidth + 20
    local levelWidth = 25

    -- Item level (equipped)
    local ilvlOffset = levelOffset + levelWidth + 10
    local ilvlWidth = 52

    -- Keystone level
    local keyOffset = ilvlOffset + ilvlWidth + 10
    local keyWidth = 46

    local goldOffset = keyOffset + keyWidth + 15
    -- Wider gold column so the formatted "Xg Ys Zc" display stays on one line
    local goldAmountWidth = 140

    -- Professions
    local profOffset = goldOffset + goldAmountWidth + 15
    local profWidth = 160

    -- Played time (total)
    local playedOffset = profOffset + profWidth + 15
    local playedWidth = 62

    -- Last Seen positioned after played time
    local lastSeenOffset = playedOffset + playedWidth + 15
    local lastSeenWidth = 90
    
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
    

    -- Item level (equipped)
    local ilvlText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ilvlText:SetPoint("LEFT", ilvlOffset, 0)
    ilvlText:SetWidth(ilvlWidth)
    ilvlText:SetJustifyH("CENTER")
    local ilvl = char.ilvlEquipped or char.ilvlAvg
    if ilvl then
        ilvlText:SetText(string.format("|cffcccccc%.1f|r", ilvl))
    else
        ilvlText:SetText("|cff666666--|r")
    end

    -- Keystone: show an icon when the character has a key, otherwise show dashes.
    -- The icon provides a tooltip (keystone link) on hover.
    local keyText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    keyText:SetPoint("LEFT", keyOffset, 0)
    keyText:SetWidth(keyWidth)
    keyText:SetJustifyH("CENTER")

    local keyIcon = row:CreateTexture(nil, "OVERLAY")
    keyIcon:SetSize(16, 16)
    keyIcon:SetPoint("CENTER", row, "LEFT", keyOffset + (keyWidth / 2), 0)
    keyIcon:Hide()

    local keyBtn = CreateFrame("Button", nil, row)
    keyBtn:SetAllPoints(keyIcon)
    keyBtn:EnableMouse(false)

    local ks = (char.pve and char.pve.mythicPlus and char.pve.mythicPlus.keystone) or nil
    local kLevel = ks and ks.level or nil

    if kLevel and kLevel > 0 then
        keyText:SetText("")
        keyIcon:SetTexture(ks.icon or (GetItemInfoInstant and select(5, GetItemInfoInstant(180653))) or "Interface\\Icons\\INV_Relics_Hourglass")
        keyIcon:Show()
        keyBtn:EnableMouse(true)
        keyBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if ks.link then
                GameTooltip:SetHyperlink(ks.link)
            else
                GameTooltip:SetText("Mythic Keystone", 1, 1, 1)
                if ks.name then
                    GameTooltip:AddLine(ks.name, 0.9, 0.9, 0.9)
                end
                GameTooltip:AddLine(string.format("+%d", kLevel), 1, 0.82, 0)
            end
            GameTooltip:Show()
        end)
        keyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        keyText:SetText("|cff666666--|r")
        keyIcon:Hide()
        keyBtn:EnableMouse(false)
        keyBtn:SetScript("OnEnter", nil)
        keyBtn:SetScript("OnLeave", nil)
    end

    -- Gold (just the amount, right-aligned)
    local goldText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    goldText:SetPoint("LEFT", goldOffset, 0)
    goldText:SetWidth(goldAmountWidth)
    goldText:SetJustifyH("RIGHT")
    goldText:SetWordWrap(false)
    goldText:SetMaxLines(1)
    goldText:SetText("|cffffd700" .. FormatGold(char.gold or 0) .. "|r")
    
    -- Profession Icons
    if char.professions then
        local iconSize = 28 -- Match class icon size
        local iconSpacing = 4
        local currentProfX = profOffset
        
        -- Helper to draw icon
        local function DrawProfIcon(prof)
            if not prof or not prof.icon then return end
            
            local profIcon = row:CreateTexture(nil, "ARTWORK")
            profIcon:SetSize(iconSize, iconSize)
            profIcon:SetPoint("LEFT", currentProfX, 0)
            profIcon:SetTexture(prof.icon)
            
            -- Tooltip button
            local pBtn = CreateFrame("Button", nil, row)
            pBtn:SetAllPoints(profIcon)
            pBtn:SetScript("OnEnter", function(self)
                -- Hide row tooltip
                bg:SetColorTexture(unpack(row.bgColor))
                GameTooltip:Hide()
                
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(prof.name, 1, 1, 1)
                
                if prof.expansions and #prof.expansions > 0 then
                    GameTooltip:AddLine(" ")
                    -- Sort expansions: Newest (highest ID/skillLine) first
                    -- Creating a copy to sort if not already sorted properly
                    local expansions = {}
                    for _, exp in ipairs(prof.expansions) do table.insert(expansions, exp) end
                    table.sort(expansions, function(a, b) return (a.skillLine or 0) > (b.skillLine or 0) end)

                    for _, exp in ipairs(expansions) do
                        local color = (exp.rank == exp.maxRank) and {0, 1, 0} or {0.8, 0.8, 0.8}
                        -- Show all expansions found
                        GameTooltip:AddDoubleLine(exp.name, exp.rank .. "/" .. exp.maxRank, 1, 0.82, 0, color[1], color[2], color[3])
                    end
                else
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddDoubleLine("Skill", (prof.rank or 0) .. "/" .. (prof.maxRank or 0), 1, 1, 1, 1, 1, 1)
                    GameTooltip:AddLine("|cff888888Open Profession window to scan details|r", 0.5, 0.5, 0.5)
                end
                
                GameTooltip:Show()
            end)
            
            pBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
                -- Restore row hover effect
                if row:IsMouseOver() then
                    bg:SetColorTexture(0.18, 0.18, 0.25, 1)
                end
            end)
            
            currentProfX = currentProfX + iconSize + iconSpacing
        end
        
        -- Draw Primary Professions (1 & 2)
        if char.professions[1] then DrawProfIcon(char.professions[1]) end
        if char.professions[2] then DrawProfIcon(char.professions[2]) end
        
        -- Draw Secondary Professions
        if char.professions.cooking then DrawProfIcon(char.professions.cooking) end
        if char.professions.fishing then DrawProfIcon(char.professions.fishing) end
        if char.professions.archaeology then DrawProfIcon(char.professions.archaeology) end
    end
    
    -- Played time (total) positioned after professions area
    local playedText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    playedText:SetPoint("LEFT", playedOffset, 0)
    playedText:SetWidth(playedWidth)
    playedText:SetJustifyH("LEFT")

    local playedSeconds = char.playedTime or 0
    local playedStr = "--"
    if playedSeconds and playedSeconds > 0 then
        local days = math.floor(playedSeconds / 86400)
        local hours = math.floor((playedSeconds % 86400) / 3600)
        playedStr = string.format("%dd %dh", days, hours)
    end
    playedText:SetText("|cff888888" .. playedStr .. "|r")

    -- Last Seen positioned after played time

    local lastSeenText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lastSeenText:SetPoint("LEFT", lastSeenOffset, 0)  -- Positioned after profession area
    lastSeenText:SetWidth(lastSeenWidth)
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

function TheQuartermaster:ReorderCharacter(char, charList, listKey, direction)
    if not char or not listKey then return end
    
    local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
    
    -- Don't update lastSeen when reordering (keep current timestamps)
    local currentPlayerName = UnitName("player")
    local currentPlayerRealm = GetRealmName()
    local currentPlayerKey = currentPlayerName .. "-" .. currentPlayerRealm
    
    -- Get or initialize custom order
    if not self.db.profile.characterOrder then
        self.db.profile.characterOrder = {
            favorites = {},
            regular = {}
        }
    end
    
    if not self.db.profile.characterOrder[listKey] then
        self.db.profile.characterOrder[listKey] = {}
    end
    
    local customOrder = self.db.profile.characterOrder[listKey]
    
    -- If no custom order exists, create one from ALL characters in this category
    if #customOrder == 0 then
        -- Get all characters and rebuild the list for this category
        local allChars = self:GetAllCharacters()
        local currentPlayerName = UnitName("player")
        local currentPlayerRealm = GetRealmName()
        local currentPlayerKey = currentPlayerName .. "-" .. currentPlayerRealm
        
        for _, c in ipairs(allChars) do
            local key = (c.name or "Unknown") .. "-" .. (c.realm or "Unknown")
            -- Skip current player
            if key ~= currentPlayerKey then
                local isFav = self:IsFavoriteCharacter(key)
                -- Add to appropriate list
                if (listKey == "favorites" and isFav) or (listKey == "regular" and not isFav) then
                    table.insert(customOrder, key)
                end
            end
        end
    end
    
    -- Find current index in custom order
    local currentIndex = nil
    for i, key in ipairs(customOrder) do
        if key == charKey then
            currentIndex = i
            break
        end
    end
    
    if not currentIndex then 
        -- Character not in custom order, add it
        table.insert(customOrder, charKey)
        currentIndex = #customOrder
    end
    
    -- Calculate new index
    local newIndex = currentIndex + direction
    if newIndex < 1 or newIndex > #customOrder then return end
    
    -- Swap in custom order
    customOrder[currentIndex], customOrder[newIndex] = customOrder[newIndex], customOrder[currentIndex]
    
    -- Save and refresh
    self.db.profile.characterOrder[listKey] = customOrder
    
    -- Ensure current character's lastSeen stays as "now"
    if self.db.global.characters and self.db.global.characters[currentPlayerKey] then
        self.db.global.characters[currentPlayerKey].lastSeen = time()
    end
    
    self:RefreshUI()
end
