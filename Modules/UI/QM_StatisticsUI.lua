--[[
    The Quartermaster - Statistics Tab
    Display account-wide statistics: gold, collections, storage overview
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local FormatGold = ns.UI_FormatGold
local function GetCOLORS()
    return ns.UI_COLORS
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

-- Performance: Local function references
local format = string.format
local date = date
local floor = math.floor

--============================================================================
-- DRAW STATISTICS (Modern Design)
--============================================================================

function TheQuartermaster:DrawStatistics(parent)
    local yOffset = 8 -- Top padding for breathing room
    local width = parent:GetWidth() - 20
    local cardWidth = (width - 15) / 2
    
    -- ===== HEADER CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    -- Dynamic theme color for title
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Dashboard|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText(L["COLLECTION_PROGRESS_GOLD_AND_STORAGE_OVERVIEW"])
    
    yOffset = yOffset + 75 -- Reduced spacing
    
    -- Get statistics
    local stats = self:GetBankStatistics()
    
    -- ===== PLAYER STATS CARDS =====
    -- TWW Note: Achievements are now account-wide (warband), no separate character score
    local achievementPoints = GetTotalAchievementPoints() or 0

    -- Account-wide aggregates (from saved character cache)
    local characters = (TheQuartermaster and TheQuartermaster.db and TheQuartermaster.db.global and TheQuartermaster.db.global.characters) or {}
    local totalCharacters = 0
    local totalGold = 0
    local totalPlayedSeconds = 0
    local highestIlvl = 0
    local highestIlvlName = nil
    local highestIlvlRealm = nil
    local highestIlvlClassFile = nil
    local mostPlayedCharacterName = nil
    local mostPlayedCharacterRealm = nil
    local mostPlayedCharacterClassFile = nil
    local mostPlayedSeconds = 0

    for _, char in pairs(characters) do
        totalCharacters = totalCharacters + 1

        local g = tonumber(char and char.gold) or 0
        totalGold = totalGold + g

        local played = tonumber(char and char.playedTime) or 0
        totalPlayedSeconds = totalPlayedSeconds + played

        -- Track highest equipped item level (account-wide)
        local ilvl = tonumber(char and (char.ilvlEquipped or char.ilvlAvg)) or 0
        if ilvl > highestIlvl then
            highestIlvl = ilvl
            highestIlvlName = char.name or highestIlvlName
            highestIlvlRealm = char.realm or highestIlvlRealm
            highestIlvlClassFile = char.classFile or highestIlvlClassFile
        end

        if played > mostPlayedSeconds then
            mostPlayedSeconds = played
            mostPlayedCharacterName = char.name or mostPlayedCharacterName
            mostPlayedCharacterRealm = char.realm or mostPlayedCharacterRealm
            mostPlayedCharacterClassFile = char.classFile or mostPlayedCharacterClassFile
        end
    end

    -- Include Warband Bank gold (if available) in the account-wide total
    local wb = (TheQuartermaster and TheQuartermaster.db and TheQuartermaster.db.global and TheQuartermaster.db.global.warbandBank) or nil
    if wb and tonumber(wb.gold) then
        totalGold = totalGold + (tonumber(wb.gold) or 0)
    end

    
    -- Calculate card width for 3 cards in a row
    -- Formula: (Total width - left margin - right margin - total spacing) / 3
    local leftMargin = 10
    local rightMargin = 10
    local cardSpacing = 10
    local totalSpacing = cardSpacing * 2  -- 2 gaps between 3 cards
    local threeCardWidth = (width - leftMargin - rightMargin - totalSpacing) / 3
    
    -- Get mount count using proper API
    local numCollectedMounts = 0
    local numTotalMounts = 0
    if C_MountJournal then
        local mountIDs = C_MountJournal.GetMountIDs()
        numTotalMounts = #mountIDs
        
        -- Count collected mounts
        for _, mountID in ipairs(mountIDs) do
            local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            if isCollected then
                numCollectedMounts = numCollectedMounts + 1
            end
        end
    end
    
    -- Get companion (battle pet) counts
    -- We want: collected / total species in game.
    -- C_PetJournal.GetNumPets() returns multiple values (commonly: numDisplayed, numCollected).
    -- The first value can be affected by Pet Journal filters/search; the second is the account-wide collected count.
    local TOTAL_COMPANIONS_IN_GAME = 1964 -- confirmed total companions (pets) available in game
    local numPets = TOTAL_COMPANIONS_IN_GAME
    local numCollectedPets = 0
    if C_PetJournal and C_PetJournal.GetNumPets then
        local displayed, collected = C_PetJournal.GetNumPets()
        numCollectedPets = tonumber(collected) or tonumber(displayed) or 0
    end

    -- Get toy count
    local numCollectedToys = 0
    local numTotalToys = 0
    if C_ToyBox then
        -- TWW API: Count toys manually
        numTotalToys = C_ToyBox.GetNumTotalDisplayedToys() or 0
        numCollectedToys = C_ToyBox.GetNumLearnedDisplayedToys() or 0
    end
    
    -- Row 1 (3-column layout): Achievement Points, Total Characters, Total Gold
    local achCard = CreateCard(parent, 90)
    achCard:SetWidth(threeCardWidth)
    achCard:SetPoint("TOPLEFT", leftMargin, -yOffset)

    local achIcon = achCard:CreateTexture(nil, "ARTWORK")
    achIcon:SetSize(36, 36)
    achIcon:SetPoint("LEFT", 15, 0)
    achIcon:SetTexture("Interface\\Icons\\Achievement_General_StayClassy")

    local achLabel = achCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    achLabel:SetPoint("TOPLEFT", achIcon, "TOPRIGHT", 12, -2)
    achLabel:SetText(L["ACHIEVEMENT_POINTS"])
    achLabel:SetTextColor(0.6, 0.6, 0.6)

    local achValue = achCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    achValue:SetPoint("BOTTOMLEFT", achIcon, "BOTTOMRIGHT", 12, 0)
    achValue:SetText("|cffffcc00" .. achievementPoints .. "|r")

    local achNote = achCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    achNote:SetPoint("BOTTOMRIGHT", -10, 10)
    achNote:SetText(L["CFF888888ACCOUNT_WIDE_R"])
    achNote:SetTextColor(0.5, 0.5, 0.5)

    -- Total Characters
    local charCard = CreateCard(parent, 90)
    charCard:SetWidth(threeCardWidth)
    charCard:SetPoint("TOPLEFT", achCard, "TOPRIGHT", cardSpacing, 0)

    local charIcon = charCard:CreateTexture(nil, "ARTWORK")
    charIcon:SetSize(36, 36)
    charIcon:SetPoint("LEFT", 15, 0)
    charIcon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")

    local charLabel = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charLabel:SetPoint("TOPLEFT", charIcon, "TOPRIGHT", 12, -2)
    charLabel:SetText(L["TOTAL_CHARACTERS"])
    charLabel:SetTextColor(0.6, 0.6, 0.6)

    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local themeHex = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)

    local charValue = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    charValue:SetPoint("BOTTOMLEFT", charIcon, "BOTTOMRIGHT", 12, 0)
    charValue:SetText("|cff" .. themeHex .. totalCharacters .. "|r")

    local charNote = charCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charNote:SetPoint("BOTTOMRIGHT", -10, 10)
    charNote:SetText(L["CFF888888ACCOUNT_WIDE_R"])
    charNote:SetTextColor(0.5, 0.5, 0.5)

    -- Total Gold (respects Discretion Mode via FormatGold)
    local goldCard = CreateCard(parent, 90)
    goldCard:SetWidth(threeCardWidth)
    goldCard:SetPoint("TOPLEFT", charCard, "TOPRIGHT", cardSpacing, 0)
    goldCard:SetPoint("RIGHT", -rightMargin, 0)

    local goldIcon = goldCard:CreateTexture(nil, "ARTWORK")
    goldIcon:SetSize(36, 36)
    goldIcon:SetPoint("LEFT", 15, 0)
    goldIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")

    local goldLabel = goldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goldLabel:SetPoint("TOPLEFT", goldIcon, "TOPRIGHT", 12, -2)
    goldLabel:SetText(L["TOTAL_GOLD"])
    goldLabel:SetTextColor(0.6, 0.6, 0.6)

    local goldValue = goldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    goldValue:SetPoint("BOTTOMLEFT", goldIcon, "BOTTOMRIGHT", 12, 0)
    goldValue:SetText(FormatGold(totalGold))

    local goldNote = goldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goldNote:SetPoint("BOTTOMRIGHT", -10, 10)
    goldNote:SetText(L["CFF888888ACCOUNT_WIDE_R"])
    goldNote:SetTextColor(0.5, 0.5, 0.5)

    yOffset = yOffset + 100

    
    -- Mount Card (3-column layout)
    local mountCard = CreateCard(parent, 90)
    mountCard:SetWidth(threeCardWidth)
    mountCard:SetPoint("TOPLEFT", leftMargin, -yOffset)
    
    local mountIcon = mountCard:CreateTexture(nil, "ARTWORK")
    mountIcon:SetSize(36, 36)
    mountIcon:SetPoint("LEFT", 15, 0)
    mountIcon:SetTexture("Interface\\Icons\\Ability_Mount_RidingHorse")
    
    local mountLabel = mountCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mountLabel:SetPoint("TOPLEFT", mountIcon, "TOPRIGHT", 12, -2)
    mountLabel:SetText(L["MOUNTS_COLLECTED"])
    mountLabel:SetTextColor(0.6, 0.6, 0.6)
    
    local mountValue = mountCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    mountValue:SetPoint("BOTTOMLEFT", mountIcon, "BOTTOMRIGHT", 12, 0)
    mountValue:SetText("|cff0099ff" .. numCollectedMounts .. "/" .. numTotalMounts .. "|r")
    
    local mountNote = mountCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mountNote:SetPoint("BOTTOMRIGHT", -10, 10)
    mountNote:SetText(L["CFF888888ACCOUNT_WIDE_R"])
    mountNote:SetTextColor(0.5, 0.5, 0.5)
    
    -- Pet Card (Center)
    local petCard = CreateCard(parent, 90)
    petCard:SetWidth(threeCardWidth)
    petCard:SetPoint("LEFT", mountCard, "RIGHT", cardSpacing, 0)
    
    local petIcon = petCard:CreateTexture(nil, "ARTWORK")
    petIcon:SetSize(36, 36)
    petIcon:SetPoint("LEFT", 15, 0)
    petIcon:SetTexture("Interface\\Icons\\INV_Box_PetCarrier_01")
    
    local petLabel = petCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    petLabel:SetPoint("TOPLEFT", petIcon, "TOPRIGHT", 12, -2)
    petLabel:SetText(L["TOTAL_COMPANIONS"])
    petLabel:SetTextColor(0.6, 0.6, 0.6)
    
    local petValue = petCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    petValue:SetPoint("BOTTOMLEFT", petIcon, "BOTTOMRIGHT", 12, 0)
    petValue:SetText("|cffff69b4" .. numCollectedPets .. "/" .. numPets .. "|r")
    
    local petNote = petCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    petNote:SetPoint("BOTTOMRIGHT", -10, 10)
    petNote:SetText(L["CFF888888ACCOUNT_WIDE_R"])
    petNote:SetTextColor(0.5, 0.5, 0.5)
    
    -- Toys Card (Right)
    local toyCard = CreateCard(parent, 90)
    toyCard:SetWidth(threeCardWidth)
    toyCard:SetPoint("LEFT", petCard, "RIGHT", cardSpacing, 0)
    -- Also anchor to right to ensure it fills the space
    toyCard:SetPoint("RIGHT", -rightMargin, 0)
    
    local toyIcon = toyCard:CreateTexture(nil, "ARTWORK")
    toyIcon:SetSize(36, 36)
    toyIcon:SetPoint("LEFT", 15, 0)
    toyIcon:SetTexture("Interface\\Icons\\INV_Misc_Toy_10")
    
    local toyLabel = toyCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toyLabel:SetPoint("TOPLEFT", toyIcon, "TOPRIGHT", 12, -2)
    toyLabel:SetText("TOYS")
    toyLabel:SetTextColor(0.6, 0.6, 0.6)
    
    local toyValue = toyCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    toyValue:SetPoint("BOTTOMLEFT", toyIcon, "BOTTOMRIGHT", 12, 0)
    toyValue:SetText("|cffff66ff" .. numCollectedToys .. "/" .. numTotalToys .. "|r")
    
    local toyNote = toyCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toyNote:SetPoint("BOTTOMRIGHT", -10, 10)
    toyNote:SetText(L["CFF888888ACCOUNT_WIDE_R"])
    toyNote:SetTextColor(0.5, 0.5, 0.5)
    
    yOffset = yOffset + 100
    
    -- ===== STORAGE STATS =====
    local storageCard = CreateCard(parent, 120)
    storageCard:SetPoint("TOPLEFT", 10, -yOffset)
    storageCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local stTitle = storageCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    stTitle:SetPoint("TOPLEFT", 15, -12)
    -- Dynamic theme color for title
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    stTitle:SetText("|cff" .. hexColor .. "Storage Overview|r")
    
    -- Stats grid
    local function AddStat(parent, label, value, x, y, color)
        local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", x, y)
        l:SetText(label)
        l:SetTextColor(0.6, 0.6, 0.6)
        
        local v = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        v:SetPoint("TOPLEFT", x, y - 14)
        v:SetText(value)
        if color then v:SetTextColor(unpack(color)) end
    end
    
    -- Use warband stats from new structure
    local wb = stats.warband or {}
    local pb = stats.personal or {}
    local inv = stats.inventory or {}

    local totalSlots = (wb.totalSlots or 0) + (pb.totalSlots or 0) + (inv.totalSlots or 0)
    local usedSlots = (wb.usedSlots or 0) + (pb.usedSlots or 0) + (inv.usedSlots or 0)
    local freeSlots = (wb.freeSlots or 0) + (pb.freeSlots or 0) + (inv.freeSlots or 0)
    local usedPct = totalSlots > 0 and floor((usedSlots / totalSlots) * 100) or 0
    
    AddStat(storageCard, "WARBAND SLOTS", (wb.usedSlots or 0) .. "/" .. (wb.totalSlots or 0), 15, -40)
    AddStat(storageCard, "BANK SLOTS", (pb.usedSlots or 0) .. "/" .. (pb.totalSlots or 0), 150, -40)
    AddStat(storageCard, "INVENTORY SLOTS", (inv.usedSlots or 0) .. "/" .. (inv.totalSlots or 0), 285, -40)
    AddStat(storageCard, "TOTAL FREE", tostring(freeSlots), 420, -40, {0.3, 0.9, 0.3})
    AddStat(storageCard, "TOTAL ITEMS", tostring((wb.itemCount or 0) + (pb.itemCount or 0) + (inv.itemCount or 0)), 535, -40)

    -- Progress bar (Total storage usage)
    -- NOTE: In Midnight, frame widths can be 0 during initial layout, so we use a real StatusBar
    -- and refresh its value on show/resize.
    local function ApplyBarColor(pct)
        if pct > 90 then
            storageCard.__tqStorageBar:SetStatusBarColor(0.9, 0.3, 0.3, 1)
        elseif pct > 70 then
            storageCard.__tqStorageBar:SetStatusBarColor(0.9, 0.7, 0.2, 1)
        else
            storageCard.__tqStorageBar:SetStatusBarColor(0, 0.8, 0.9, 1)
        end
    end

    local function UpdateStorageBar()
        local latest = (self.GetBankStatistics and self:GetBankStatistics()) or stats or {}
        local wb2 = latest.warband or wb or {}
        local pb2 = latest.personal or pb or {}
        local inv2 = latest.inventory or inv or {}

        local total = (tonumber(wb2.totalSlots) or 0) + (tonumber(pb2.totalSlots) or 0) + (tonumber(inv2.totalSlots) or 0)
        local used = (tonumber(wb2.usedSlots) or 0) + (tonumber(pb2.usedSlots) or 0) + (tonumber(inv2.usedSlots) or 0)

        if total <= 0 then
            total = 1
            used = 0
        end

        storageCard.__tqStorageBar:SetMinMaxValues(0, total)
        storageCard.__tqStorageBar:SetValue(used)

        -- Cache tooltip values
        storageCard.__tqStorageBar.__tqUsed = used
        storageCard.__tqStorageBar.__tqTotal = total
        storageCard.__tqStorageBar.__tqPct = (total > 0) and ((used / total) * 100) or 0

        local pct = floor((used / total) * 100)
        ApplyBarColor(pct)
    end

    -- Create once per draw
    local bar = CreateFrame("StatusBar", nil, storageCard)
    storageCard.__tqStorageBar = bar
    bar:SetHeight(10)
    bar:SetPoint("BOTTOMLEFT", 15, 15)
    bar:SetPoint("BOTTOMRIGHT", -15, 15)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetFrameLevel(storageCard:GetFrameLevel() + 2)

    -- Background
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints(bar)
    barBg:SetColorTexture(0.2, 0.2, 0.2, 1)

    -- Tooltip (total slots used)
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local used = tonumber(self.__tqUsed) or 0
        local total = tonumber(self.__tqTotal) or 0
        local pct = tonumber(self.__tqPct) or 0
        GameTooltip:AddLine("Storage Usage", 1, 0.82, 0)
        GameTooltip:AddLine(string.format("%d / %d total slots used (%.1f%%)", used, total, pct), 1, 1, 1)
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Initial update + refresh after layout
    UpdateStorageBar()
    bar:HookScript("OnShow", UpdateStorageBar)
    bar:HookScript("OnSizeChanged", UpdateStorageBar)
    
    yOffset = yOffset + 130

    -- Row 4 (3-column layout): Total Played, Oldest Character, Most Played Character
    local playedCard = CreateCard(parent, 90)
    playedCard:SetWidth(threeCardWidth)
    playedCard:SetPoint("TOPLEFT", leftMargin, -yOffset)

    local playedIcon = playedCard:CreateTexture(nil, "ARTWORK")
    playedIcon:SetSize(36, 36)
    playedIcon:SetPoint("LEFT", 15, 0)
    playedIcon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")

    local playedLabel = playedCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playedLabel:SetPoint("TOPLEFT", playedIcon, "TOPRIGHT", 12, -2)
    playedLabel:SetText(L["TOTAL_PLAYED_TIME"])
    playedLabel:SetTextColor(0.6, 0.6, 0.6)

    local playedValue = playedCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    playedValue:SetPoint("BOTTOMLEFT", playedIcon, "BOTTOMRIGHT", 12, 0)
    playedValue:SetText("|cffffcc00" .. FormatPlayedTime(totalPlayedSeconds) .. "|r")

    local playedNote = playedCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playedNote:SetPoint("BOTTOMRIGHT", -10, 10)
    playedNote:SetText(L["CFF888888ACCOUNT_WIDE_R"])
    playedNote:SetTextColor(0.5, 0.5, 0.5)

    -- Highest Item Level
    local ilvlCard = CreateCard(parent, 90)
    ilvlCard:SetWidth(threeCardWidth)
    ilvlCard:SetPoint("TOPLEFT", playedCard, "TOPRIGHT", cardSpacing, 0)

    local ilvlIcon = ilvlCard:CreateTexture(nil, "ARTWORK")
    ilvlIcon:SetSize(36, 36)
    ilvlIcon:SetPoint("LEFT", 15, 0)
    ilvlIcon:SetTexture("Interface\\Icons\\ui_mission_itemupgrade")

    local ilvlLabel = ilvlCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvlLabel:SetPoint("TOPLEFT", ilvlIcon, "TOPRIGHT", 12, -2)
    ilvlLabel:SetText(L["HIGHEST_ITEM_LEVEL"])
    ilvlLabel:SetTextColor(0.6, 0.6, 0.6)

    local ilvlNameText = ilvlCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ilvlNameText:SetPoint("BOTTOMLEFT", ilvlIcon, "BOTTOMRIGHT", 12, 6)
    ilvlNameText:SetWordWrap(false)
    ilvlNameText:SetMaxLines(1)
    ilvlNameText:SetJustifyH("LEFT")
    ilvlNameText:SetWidth(threeCardWidth - 15 - 36 - 12 - 20)

    do
        local font, size, flags = ilvlNameText:GetFont()
        if font and size then
            ilvlNameText:SetFont(font, size + 1, flags)
        end
    end

    if highestIlvlName then
        local cc = (highestIlvlClassFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[highestIlvlClassFile]) or { r = 1, g = 1, b = 1 }
        if highestIlvlRealm and highestIlvlRealm ~= "" then
            ilvlNameText:SetText(string.format("|cff%02x%02x%02x%s|r|cff808080-%s|r",
                (cc.r or 1) * 255, (cc.g or 1) * 255, (cc.b or 1) * 255,
                highestIlvlName,
                highestIlvlRealm))
        else
            ilvlNameText:SetText(string.format("|cff%02x%02x%02x%s|r",
                (cc.r or 1) * 255, (cc.g or 1) * 255, (cc.b or 1) * 255,
                highestIlvlName))
        end
    else
        ilvlNameText:SetText(L["CFF9AA0A6_R"])
    end

    local ilvlSub = ilvlCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvlSub:SetPoint("TOPLEFT", ilvlNameText, "BOTTOMLEFT", 0, -2)
    if highestIlvl and highestIlvl > 0 then
        ilvlSub:SetText("|cff888888iLvl " .. string.format("%.1f", highestIlvl) .. "|r")
    else
        ilvlSub:SetText(L["CFF888888_R"])
    end
    ilvlSub:SetTextColor(0.5, 0.5, 0.5)

    -- Most Played Character
    local mostCard = CreateCard(parent, 90)
    mostCard:SetWidth(threeCardWidth)
    mostCard:SetPoint("TOPLEFT", ilvlCard, "TOPRIGHT", cardSpacing, 0)
    mostCard:SetPoint("RIGHT", -rightMargin, 0)

    local mostIcon = mostCard:CreateTexture(nil, "ARTWORK")
    mostIcon:SetSize(36, 36)
    mostIcon:SetPoint("LEFT", 15, 0)
    mostIcon:SetTexture("Interface\\Icons\\Achievement_General_StayClassy")

    local mostLabel = mostCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mostLabel:SetPoint("TOPLEFT", mostIcon, "TOPRIGHT", 12, -2)
    mostLabel:SetText(L["MOST_PLAYED_CHARACTER"])
    mostLabel:SetTextColor(0.6, 0.6, 0.6)

    local mostValue = mostCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mostValue:SetPoint("BOTTOMLEFT", mostIcon, "BOTTOMRIGHT", 12, 6)
    mostValue:SetWordWrap(false)
    mostValue:SetMaxLines(1)
    mostValue:SetJustifyH("LEFT")
    mostValue:SetWidth(threeCardWidth - 15 - 36 - 12 - 20)

    do
        local font, size, flags = mostValue:GetFont()
        if font and size then
            mostValue:SetFont(font, size + 1, flags)
        end
    end

    if mostPlayedCharacterName then
        local cc = (mostPlayedCharacterClassFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[mostPlayedCharacterClassFile]) or { r = 1, g = 1, b = 1 }
        if mostPlayedCharacterRealm and mostPlayedCharacterRealm ~= "" then
            mostValue:SetText(string.format("|cff%02x%02x%02x%s|r|cff808080-%s|r",
                (cc.r or 1) * 255, (cc.g or 1) * 255, (cc.b or 1) * 255,
                mostPlayedCharacterName,
                mostPlayedCharacterRealm))
        else
            mostValue:SetText(string.format("|cff%02x%02x%02x%s|r",
                (cc.r or 1) * 255, (cc.g or 1) * 255, (cc.b or 1) * 255,
                mostPlayedCharacterName))
        end
        mostValue:SetTextColor(1, 1, 1)
    else
        mostValue:SetText(L["CFF9AA0A6_R"])
        mostValue:SetTextColor(1, 1, 1)
    end

    local mostSub = mostCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mostSub:SetPoint("TOPLEFT", mostValue, "BOTTOMLEFT", 0, -2)
    mostSub:SetText("|cff888888" .. FormatPlayedTime(mostPlayedSeconds) .. "|r")
    mostSub:SetTextColor(0.5, 0.5, 0.5)

    yOffset = yOffset + 100

    -- Last scan info removed - now only shown in footer

    yOffset = yOffset + 30
    return yOffset
end
