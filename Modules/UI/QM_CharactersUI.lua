
--[[
    The Quartermaster - Characters Tab
    Display all tracked characters with gold, level, and last seen info
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
    
    self.characterDragRows = {}

    -- ===== SORT CHARACTERS: FAVORITES → REGULAR =====
    local favorites = {}
    local regular = {}
    
    for _, char in ipairs(characters) do
        local charKey = ns.CharacterOrderKey(char)
        
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
                yOffset = self:DrawCharacterRow(parent, char, i, width, yOffset, true, true, favorites, "favorites", i, #favorites, currentPlayerKey)
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

function TheQuartermaster:DrawCharacterRow(parent, char, index, width, yOffset, isFavorite, showReorder, charList, listKey, positionInList, totalInList, currentPlayerKey)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 38)  -- Taller row height
    row:SetPoint("TOPLEFT", 10, -yOffset)
    row:EnableMouse(true)
    
    -- Check if this is the current character
    local charKey = ns.CharacterOrderKey(char)
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
    -- Evenly distributed columns from left to right
    -- NOTE: widths are tuned so: name does not clip, money stays on one line, and new columns fit.
    local nameOffset = leftOffset
    local nameWidth = 230  -- Wider so long names + realm don't truncate as easily

    local levelOffset = nameOffset + nameWidth + 20
    local levelWidth = 25

    -- Item level (equipped)
    local ilvlOffset = levelOffset + levelWidth + 10
    local ilvlWidth = 80

    -- Keystone level
    local keyOffset = ilvlOffset + ilvlWidth + 10
    local keyWidth = 46

    local goldOffset = keyOffset + keyWidth + 15
    -- Wider gold column so the formatted "Xg Ys Zc" display stays on one line
    local goldAmountWidth = 140

    -- Professions
    local profOffset = goldOffset + goldAmountWidth + 15
    local profWidth = 160

    -- Last Seen positioned after professions
    local lastSeenOffset = profOffset + profWidth + 15
    local lastSeenWidth = 90
    
    -- Character name with realm (combined) (in class color)
    local nameText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    nameText:SetPoint("LEFT", nameOffset, 0)
    local nameReserve = 0
    nameText:SetWidth(nameWidth - nameReserve)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    -- Name in class color, realm in gray
    nameText:SetText(string.format("|cff%02x%02x%02x%s|r|cff808080-%s|r", 
        classColor.r * 255, classColor.g * 255, classColor.b * 255, 
        char.name or "Unknown",
        char.realm or "Unknown"))
    
    if showReorder and charList then self:EnableCharacterRowDrag(row, charKey, listKey) end

    -- Level (just the number, centered in its column)
    local levelText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    levelText:SetPoint("LEFT", levelOffset, 0)
    levelText:SetWidth(levelWidth)
    levelText:SetJustifyH("CENTER")
    levelText:SetText(string.format("|cff%02x%02x%02x%d|r", 
        classColor.r * 255, classColor.g * 255, classColor.b * 255, 
        char.level or 1))
    

    -- Item level (equipped)
    local ilvlText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    ilvlText:SetPoint("LEFT", ilvlOffset, 0)
    ilvlText:SetWidth(ilvlWidth)
    ilvlText:SetJustifyH("CENTER")
    local ilvl = char.ilvlEquipped or char.ilvlAvg
    if ilvl then
        ilvlText:SetText(string.format("|cffcccccciLvl %.1f|r", ilvl))
    else
        ilvlText:SetText(L["CFF666666_R"])
    end

    -- Keystone: show an icon when the character has a key, otherwise show dashes.
    -- The icon provides a tooltip (keystone link) on hover.
    local keyText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    keyText:SetPoint("LEFT", keyOffset, 0)
    keyText:SetWidth(keyWidth)
    keyText:SetJustifyH("CENTER")

    local keyIcon = row:CreateTexture(nil, "OVERLAY")
    keyIcon:SetSize(22, 22)
    keyIcon:SetPoint("CENTER", row, "LEFT", keyOffset + (keyWidth / 2), 0)
    keyIcon:Hide()

    -- Mail icon (shows when mailbox data is cached for this character)
    local mailIcon = row:CreateTexture(nil, "OVERLAY")
    mailIcon:SetSize(22, 22)
    mailIcon:SetPoint("CENTER", row, "LEFT", keyOffset + (keyWidth / 2), 0)
    mailIcon:SetTexture("Interface\\Minimap\\Tracking\\Mailbox")
    mailIcon:Hide()


    local keyBtn = CreateFrame("Button", nil, row)
    keyBtn:SetAllPoints(keyIcon)
    keyBtn:EnableMouse(false)


    local mailBtn = CreateFrame("Button", nil, row)
    mailBtn:SetAllPoints(mailIcon)
    mailBtn:EnableMouse(false)


    local pveView = TheQuartermaster:GetPvEView(char.pve)
    local ks = pveView.mythicPlus and pveView.mythicPlus.keystone
    local kLevel = ks and ks.level or nil

    local mailKey = (char and char.name and char.realm) and ((char.name or "Unknown") .. "-" .. char.realm) or charKey
    local mailData = TheQuartermaster:GetActiveMail(mailKey) or TheQuartermaster:GetActiveMail(charKey)

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
        keyText:SetText(L["CFF666666_R"])
        keyIcon:Hide()
        keyBtn:EnableMouse(false)
        keyBtn:SetScript("OnEnter", nil)
        keyBtn:SetScript("OnLeave", nil)
    end

    -- Mail icon + tooltip (cached when a mailbox is opened on that character)
    local showMail = mailData and (mailData.count or 0) > 0

    if showMail then
        mailIcon:SetDesaturated(mailData.stage > 0)
        mailIcon:SetVertexColor(unpack(mailData.color))
        mailIcon:Show()
        mailBtn:EnableMouse(true)

        mailBtn:SetScript("OnEnter", function(self)
            -- Hide row tooltip (prevents double-tooltips)
            bg:SetColorTexture(unpack(row.bgColor))
            GameTooltip:Hide()

            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["MAIL"] or "Mail", 1, 1, 1)

            GameTooltip:AddDoubleLine(L["MAIL_TOTAL"] or "Total", tostring(mailData.count or 0), 0.9, 0.9, 0.9, 1, 1, 1)

            local now = time()
            if mailData.soonestAt then
                local seconds = (mailData.soonestAt - now)
                if seconds < 0 then seconds = 0 end
                local fmt = (TheQuartermaster.FormatMailTimeLeft and TheQuartermaster:FormatMailTimeLeft(seconds)) or tostring(seconds)

                local warn = (seconds <= (24 * 3600))
                if warn then
                    GameTooltip:AddDoubleLine(L["MAIL_SOONEST_EXPIRY"] or "Soonest expiry", fmt, 1, 0.2, 0.2, 1, 0.2, 0.2)
                else
                    GameTooltip:AddDoubleLine(L["MAIL_SOONEST_EXPIRY"] or "Soonest expiry", fmt, 1, 0.82, 0, 1, 1, 1)
                end
            end

            -- Per-mail details (cached when mailbox is opened on that character)
            if mailData.details and type(mailData.details) == "table" and #mailData.details > 0 then
                GameTooltip:AddLine(" ")
                for i = 1, math.min(10, #mailData.details) do
                    local entry = mailData.details[i]
                    if entry and entry.expiresAt then
                        local seconds = (entry.expiresAt - now)
                        if seconds < 0 then seconds = 0 end
                        local fmt = (TheQuartermaster.FormatMailTimeLeft and TheQuartermaster:FormatMailTimeLeft(seconds)) or tostring(seconds)

                        local sender = entry.sender or "Unknown"
                        local left = string.format(L["MAIL_SENT_BY"] or "Mail sent by %s", sender)

                        local rightLabel
                        if entry.type == "DELETE" then
                            rightLabel = (L["MAIL_DELETING_IN"] or "Deleting in")
                        else
                            rightLabel = (L["MAIL_EXPIRING_IN"] or "Expiring in")
                        end

                        GameTooltip:AddDoubleLine(left, rightLabel .. " " .. fmt, 0.9, 0.9, 0.9, 1, 1, 1)
                    end
                end
            else
                -- Fallback (older cache versions)
                if mailData.returnSoonestAt then
                    local seconds = (mailData.returnSoonestAt - now)
                    if seconds < 0 then seconds = 0 end
                    local fmt = (TheQuartermaster.FormatMailTimeLeft and TheQuartermaster:FormatMailTimeLeft(seconds)) or tostring(seconds)
                    GameTooltip:AddDoubleLine(L["MAIL_RETURNING_IN"] or "Returning in", fmt, 0.9, 0.9, 0.9, 1, 1, 1)
                end

                if mailData.deleteSoonestAt then
                    local seconds = (mailData.deleteSoonestAt - now)
                    if seconds < 0 then seconds = 0 end
                    local fmt = (TheQuartermaster.FormatMailTimeLeft and TheQuartermaster:FormatMailTimeLeft(seconds)) or tostring(seconds)
                    GameTooltip:AddDoubleLine(L["MAIL_DELETING_IN"] or "Deleting in", fmt, 0.9, 0.9, 0.9, 1, 1, 1)
                end
            end

            if mailData.lastScan then
                if mailData.unknownCount > 0 then GameTooltip:AddLine(L.MAIL_EXPIRY_UNKNOWN, 1, 0.7, 0.3, true) end
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine(L["MAIL_LAST_SCANNED"] or "Last scanned", date("%Y-%m-%d %H:%M", mailData.lastScan), 0.7, 0.7, 0.7, 0.9, 0.9, 0.9)
                GameTooltip:AddLine(L["MAIL_UPDATES_NOTE"] or "|cff888888Updates when you open a mailbox on this character.|r", 0.7, 0.7, 0.7, true)
                GameTooltip:AddLine(L["MAIL_DETAILS_NOTE"] or "|cff888888Shows up to 10 soonest-expiring mails.|r", 0.7, 0.7, 0.7, true)
            end

            GameTooltip:Show()
        end)

        mailBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        mailIcon:Hide()
        mailBtn:EnableMouse(false)
        mailBtn:SetScript("OnEnter", nil)
        mailBtn:SetScript("OnLeave", nil)
    end

    -- Position keystone + mail icons nicely within the column
    do
        local centerX = keyOffset + (keyWidth / 2)
        keyIcon:ClearAllPoints()
        mailIcon:ClearAllPoints()

        if keyIcon:IsShown() and mailIcon:IsShown() then
            local pad = 6
            local dx = (keyIcon:GetWidth() / 2) + (mailIcon:GetWidth() / 2) + pad
            keyIcon:SetPoint("CENTER", row, "LEFT", centerX - (dx / 2), 0)
            mailIcon:SetPoint("CENTER", row, "LEFT", centerX + (dx / 2), 0)
        elseif keyIcon:IsShown() then
            keyIcon:SetPoint("CENTER", row, "LEFT", centerX, 0)
        elseif mailIcon:IsShown() then
            mailIcon:SetPoint("CENTER", row, "LEFT", centerX, 0)
        end
    end

    -- Gold (just the amount, right-aligned)
    local goldText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
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

            -- Click-to-open (current character only)
            pBtn:RegisterForClicks("LeftButtonUp")
            pBtn:SetScript("OnClick", function()
                if not isCurrent then
                    return
                end

                local skillLineID = prof.skillLine
                if not skillLineID and prof.expansions and prof.expansions[1] then
                    -- Fallback: newest expansion skillLine (if base skillLine is missing)
                    skillLineID = prof.expansions[1].skillLine
                end

                if not skillLineID then
                    TheQuartermaster:Print("Unable to open profession: missing skill line ID.")
                    return
                end

                local ok = pcall(function()
                    if C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
                        C_TradeSkillUI.OpenTradeSkill(skillLineID)
                    elseif TradeSkillFrame and TradeSkillFrame.OpenToSkillLine then
                        TradeSkillFrame:OpenToSkillLine(skillLineID)
                    else
                        error("TradeSkill UI not available")
                    end
                end)

                if not ok then
                    TheQuartermaster:Print("Could not open profession window for " .. (prof.name or "profession") .. ".")
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
    
    -- Last Seen (kept compact in the list; full details are in the tooltip)
    local lastSeenText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
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
            GameTooltip:SetText(L["CFFFF5555DELETE_CHARACTER_R_NCLICK_TO_REMOVE_THIS_CHARACTERS"])
            GameTooltip:Show()
        end)
        
        deleteBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
        
    -- Hover effect + Tooltip
    row:SetScript("OnEnter", function(self)
        if TheQuartermaster.characterDragging then return end
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
        if showReorder then GameTooltip:AddLine(L.CHAR_DRAGGING, 0.3, 0.8, 0.8, true) end

        
        
        GameTooltip:Show()
    end)
    
    row:SetScript("OnLeave", function(self)
        bg:SetColorTexture(unpack(self.bgColor))
        GameTooltip:Hide()
        
    end)
    
    return yOffset + 40  -- Row height (38) + spacing (2)
end
