--[[
    The Quartermaster - Guilds Tab
    Foundation for the Guilds tab (currently mirrors Characters)
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Import shared UI components (always get fresh reference)
local function GetCOLORS()
    return ns.UI_COLORS
end
local CreateCard = ns.UI_CreateCard
local FormatGold = ns.UI_FormatGold
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader


local function FormatGuildRep(char, isCurrent)
    -- Prefer explicit stored string
    if type(char.guildRep) == "string" and char.guildRep ~= "" then
        return char.guildRep
    end

    -- Build from stored standing/pct if present
    local standingID = tonumber(char.guildRepStandingID)
    local pct = tonumber(char.guildRepPct)
    if standingID then
        local standingLabel = (_G and _G["FACTION_STANDING_LABEL" .. standingID]) or ("Standing " .. standingID)
        if pct then
            return string.format("%s (%d%%)", standingLabel, pct)
        end
        return standingLabel
    end

    -- Live lookup (current char only) using faction 1168 if available
    if isCurrent and IsInGuild and IsInGuild() then
        local standingID2, barMin, barMax, barValue = nil, nil, nil, nil
        if type(C_Reputation) == "table" and type(C_Reputation.GetFactionDataByID) == "function" then
            local data = C_Reputation.GetFactionDataByID(1168)
            if data then
                standingID2 = data.reaction
                barMin = data.currentReactionThreshold
                barMax = data.nextReactionThreshold
                barValue = data.currentStanding
            end
        end
        if not standingID2 and type(GetFactionInfoByID) == "function" then
            local _, _, sID, bMin, bMax, bValue = GetFactionInfoByID(1168)
            standingID2, barMin, barMax, barValue = sID, bMin, bMax, bValue
        end
        if type(standingID2) == "number" then
            local standingLabel = (_G and _G["FACTION_STANDING_LABEL" .. standingID2]) or ("Standing " .. standingID2)
            if type(barMax) == "number" and type(barMin) == "number" and type(barValue) == "number" and (barMax - barMin) > 0 then
                local pct2 = math.floor(((barValue - barMin) / (barMax - barMin)) * 100 + 0.5)
                return string.format("%s (%d%%)", standingLabel, pct2)
            end
            return standingLabel
        end
    end

    return nil
end

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

function TheQuartermaster:DrawGuildSummaryList(parent)
    local yOffset = 8 -- Top padding for breathing room
    local width = parent:GetWidth() - 20
    
    -- Get all characters (cached for performance)
    local characters = self.GetCachedCharacters and self:GetCachedCharacters() or self:GetAllCharacters()
    
    -- Get current player key
    local currentPlayerName = UnitName("player")
    local currentPlayerRealm = GetRealmName()
    local currentPlayerKey = currentPlayerName .. "-" .. currentPlayerRealm
    
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
    local function sortCharacters(list)
        return ns.SortCharacterRows(self.db, list)
    end

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
        
        local emptyText = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontHeading")
        emptyText:SetPoint("TOP", 0, -yOffset - 90)
        emptyText:SetText(L["CFF666666NO_CHARACTERS_TRACKED_YET_R"])
        
        local emptyDesc = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
        emptyDesc:SetPoint("TOP", 0, -yOffset - 115)
        emptyDesc:SetTextColor(0.5, 0.5, 0.5)
        emptyDesc:SetText(L["CHARACTERS_ARE_AUTOMATICALLY_REGISTERED_ON_LOGIN"])
        
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
        local maxX   = restX + 150 + 14
        local fullX  = maxX + 110 + 14
        local statusX = fullX + 110 + 16

        local function AddLabel(text, x, w, justify)
            local fs = header:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
            fs:SetPoint("LEFT", x, 0)
            fs:SetWidth(w)
            fs:SetJustifyH(justify or "LEFT")
            fs:SetText("|cffaaaaaa" .. text .. "|r")
            return fs
        end

        AddLabel("Character", nameX, 240, "LEFT")
        AddLabel("Lvl", levelX, 25, "CENTER")
        AddLabel("Guild Name", restX, 150, "LEFT")
        AddLabel("Guild Rank", maxX, 110, "LEFT")
        AddLabel("Guild Rep", fullX, 110, "LEFT")
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
                yOffset = self:DrawGuildSummaryRow(parent, char, i, width, yOffset, true, currentPlayerKey)
            end
        else
            -- Empty state
            local emptyText = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
            emptyText:SetPoint("TOPLEFT", 30, -yOffset)
            emptyText:SetTextColor(0.5, 0.5, 0.5)
            emptyText:SetText(L["NO_FAVORITE_CHARACTERS_YET_CLICK_THE_STAR_ICON_TO_FAVORITE_A"])
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
                yOffset = self:DrawGuildSummaryRow(parent, char, i, width, yOffset, false, currentPlayerKey)
            end
        else
            -- Empty state
            local emptyText = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
            emptyText:SetPoint("TOPLEFT", 30, -yOffset)
            emptyText:SetTextColor(0.5, 0.5, 0.5)
            emptyText:SetText(L["ALL_CHARACTERS_ARE_FAVORITED"])
            yOffset = yOffset + 35
        end
    end
    
    return yOffset
end

--============================================================================
-- DRAW SINGLE CHARACTER ROW
--============================================================================

function TheQuartermaster:DrawGuildSummaryRow(parent, char, index, width, yOffset, isFavorite, currentPlayerKey)
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
            GameTooltip:SetText(L["CFFFFD700FAVORITE_CHARACTER_R_NCLICK_TO_REMOVE_FROM_FAVORITE"])
        else
            GameTooltip:SetText(L["CLICK_TO_ADD_TO_FAVORITES_N_CFF888888FAVORITES_ARE_ALWAYS_SH"])
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
    local restWidth   = 150

    local maxOffset   = restOffset + restWidth + 14
    local maxWidth    = 110

    local fullOffset  = maxOffset + maxWidth + 14
    local fullWidth   = 110

    local statusOffset = fullOffset + fullWidth + 16
    local statusWidth  = 90

-- Character name with realm (combined) (in class color)
    local nameText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    nameText:SetPoint("LEFT", nameOffset, 0)
    nameText:SetWidth(nameWidth)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    -- Name in class color, realm in gray
    nameText:SetText(string.format("|cff%02x%02x%02x%s|r|cff808080-%s|r", 
        classColor.r * 255, classColor.g * 255, classColor.b * 255, 
        char.name or "Unknown",
        char.realm or "Unknown"))
    
    -- Level (just the number, centered in its column)
    local levelText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    levelText:SetPoint("LEFT", levelOffset, 0)
    levelText:SetWidth(levelWidth)
    levelText:SetJustifyH("CENTER")
    levelText:SetText(string.format("|cff%02x%02x%02x%d|r", 
        classColor.r * 255, classColor.g * 255, classColor.b * 255, 
        char.level or 1))

    -- Guild columns (Guild Name / Guild Rank / Guild Rep)
    local guildName = nil
    local guildRank = nil

    -- Prefer stored values (for offline characters)
    if type(char.guildName) == "string" and char.guildName ~= "" then
        guildName = char.guildName
    elseif type(char.guild) == "table" and type(char.guild.name) == "string" then
        guildName = char.guild.name
    end

    if type(char.guildRank) == "string" and char.guildRank ~= "" then
        guildRank = char.guildRank
    elseif type(char.guild) == "table" and type(char.guild.rank) == "string" then
        guildRank = char.guild.rank
    end

    -- Current character live lookup (most reliable)
    if isCurrent and IsInGuild and IsInGuild() and GetGuildInfo then
        local gName, gRankName = GetGuildInfo("player")
        if type(gName) == "string" and gName ~= "" then
            guildName = gName
        end
        if type(gRankName) == "string" and gRankName ~= "" then
            guildRank = gRankName
        end
    end

    local guildRepText = FormatGuildRep(char, isCurrent)

    if not guildName or guildName == "" then guildName = "|cff666666--|r" end
    if not guildRank or guildRank == "" then guildRank = "|cff666666--|r" end
    if not guildRepText or guildRepText == "" then guildRepText = "|cff666666--|r" end

    local guildNameText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    guildNameText:SetPoint("LEFT", restOffset, 0)
    guildNameText:SetWidth(restWidth)
    guildNameText:SetJustifyH("LEFT")
    guildNameText:SetText(type(guildName)=="string" and guildName:find("|c") and guildName or ("|cffcccccc" .. tostring(guildName) .. "|r"))

    AttachColumnTooltip(row, restOffset, restWidth, "Guild Name", "Character's current guild (if known)")

    local guildRankTextFS = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    guildRankTextFS:SetPoint("LEFT", maxOffset, 0)
    guildRankTextFS:SetWidth(maxWidth)
    guildRankTextFS:SetJustifyH("LEFT")
    guildRankTextFS:SetText(type(guildRank)=="string" and guildRank:find("|c") and guildRank or ("|cffcccccc" .. tostring(guildRank) .. "|r"))

    AttachColumnTooltip(row, maxOffset, maxWidth, "Guild Rank", "Rank name in the guild (if known)")

    local guildRepTextFS = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    guildRepTextFS:SetPoint("LEFT", fullOffset, 0)
    guildRepTextFS:SetWidth(fullWidth)
    guildRepTextFS:SetJustifyH("LEFT")
    guildRepTextFS:SetText(type(guildRepText)=="string" and guildRepText:find("|c") and guildRepText or ("|cffcccccc" .. tostring(guildRepText) .. "|r"))

    AttachColumnTooltip(row, fullOffset, fullWidth, "Guild Reputation", "Standing and progress (stored per character when available)")

    local lastSeenText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
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
            GameTooltip:SetText(L["CFFFF5555DELETE_CHARACTER_R_NCLICK_TO_REMOVE_THIS_CHARACTERS"])
            GameTooltip:Show()
        end)
        
        deleteBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
        
    -- Hover effect + Tooltip
    row:SetScript("OnEnter", function(self)
        bg:SetColorTexture(0.18, 0.18, 0.25, 1)
        
        
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

        --  time (best-effort: expects seconds if available)
        local playedSeconds = tonumber(char.playedTime or char.total or char.playedSeconds)
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
        GameTooltip:AddDoubleLine(" time:", playedText, 1, 1, 1, 0.7, 0.7, 0.7)

        
        
        GameTooltip:Show()
    end)
    
    row:SetScript("OnLeave", function(self)
        bg:SetColorTexture(unpack(self.bgColor))
        GameTooltip:Hide()
        
    end)
    
    return yOffset + 40  -- Row height (38) + spacing (2)
end

--============================================================================
-- REORDER CHARACTER IN LIST
--============================================================================
