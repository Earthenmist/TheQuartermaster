
-- Guild reputation helpers
local GUILD_FACTION_ID = 1168  -- "Guild" reputation faction
local function GetGuildRepData()
    -- Returns: repText, standingID, pct
    -- Preferred path: GetFactionInfoByID / C_Reputation.GetFactionDataByID (works reliably without guild frame)
    local standingID, barMin, barMax, barValue = nil, nil, nil, nil

    if type(C_Reputation) == "table" and type(C_Reputation.GetFactionDataByID) == "function" then
        local data = C_Reputation.GetFactionDataByID(GUILD_FACTION_ID)
        if data then
            standingID = data.reaction
            barMin = data.currentReactionThreshold
            barMax = data.nextReactionThreshold
            barValue = data.currentStanding
        end
    end

    if not standingID and type(GetFactionInfoByID) == "function" then
        local name, description, sID, bMin, bMax, bValue = GetFactionInfoByID(GUILD_FACTION_ID)
        if sID then
            standingID, barMin, barMax, barValue = sID, bMin, bMax, bValue
        end
    end

    -- Fallback: legacy guild API
    if not standingID and type(GetGuildFactionInfo) == "function" then
        local _, _, sID, bMin, bMax, bValue = GetGuildFactionInfo()
        if sID then
            standingID, barMin, barMax, barValue = sID, bMin, bMax, bValue
        end
    end

    if type(standingID) ~= "number" then
        return nil, nil, nil
    end

    local standingLabel = (_G and _G["FACTION_STANDING_LABEL" .. standingID]) or nil
    if type(standingLabel) ~= "string" then
        standingLabel = "Standing " .. standingID
    end

    local pct = nil
    if type(barMax) == "number" and type(barMin) == "number" and type(barValue) == "number" and (barMax - barMin) > 0 then
        pct = math.floor(((barValue - barMin) / (barMax - barMin)) * 100 + 0.5)
    end

    if pct ~= nil then
        return string.format("%s (%d%%)", standingLabel, pct), standingID, pct
    end

    return standingLabel, standingID, nil
end

--[[
    The Quartermaster - Data Service Module
    Centralized data collection, processing, and retrieval
    
    Handles:
    - Character data collection (gold, level, class, etc.)
    - PvE data collection (Great Vault, lockouts, M+)
    - Item data aggregation (bank, bags, storage)
    - Cross-character data queries
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

-- ============================================================================
-- EXPERIENCE / RESTED XP HELPERS
-- ============================================================================

local function ComputeFullyRestedSeconds(maxXP, restedXP, isResting)
    if type(maxXP) ~= "number" or maxXP <= 0 then return nil end
    restedXP = (type(restedXP) == "number" and restedXP) or 0

    -- Rested cap is 150% of the XP needed for the next level.
    local cap = maxXP * 1.5
    local remaining = cap - restedXP
    if remaining <= 0 then
        return 0
    end

    -- Approximate rates:
    -- Resting (inn/city): +5% of a level per 8 hours
    -- Not resting: +2.5% of a level per 8 hours
    local percentPer8 = isResting and 0.05 or 0.025
    local ratePerHour = maxXP * (percentPer8 / 8)
    if ratePerHour <= 0 then return nil end

    return math.floor((remaining / ratePerHour) * 3600)
end


-- ============================================================================
-- CHARACTER DATA COLLECTION
-- ============================================================================

--[[
    Collect basic profession data
    @return table - Profession data
]]
function TheQuartermaster:CollectProfessionData()
    local success, result = pcall(function()
        local professions = {}
        
        -- GetProfessions returns indices for the profession UI
        local prof1, prof2, arch, fish, cook = GetProfessions()
        
        local function getProfData(index)
            if not index then return nil end
            -- name, icon, rank, maxRank, numSpells, spellOffset, skillLine, rankModifier, specializationIndex, specializationOffset
            local name, icon, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
            
            if not name then return nil end
            
            return {
                name = name,
                icon = icon,
                rank = rank,
                maxRank = maxRank,
                skillLine = skillLine,
                index = index
            }
        end

        if prof1 then professions[1] = getProfData(prof1) end
        if prof2 then professions[2] = getProfData(prof2) end
        if cook then professions.cooking = getProfData(cook) end
        if fish then professions.fishing = getProfData(fish) end
        if arch then professions.archaeology = getProfData(arch) end
        
        return professions
    end)
    
    if not success then
        return {}
    end
    
    return result
end

--[[
    Collect detailed expansion data for currently open profession
    Called when TRADE_SKILL_SHOW or related events fire
    @return boolean - Success
]]
function TheQuartermaster:UpdateDetailedProfessionData()
    local success, result = pcall(function()
        if not C_TradeSkillUI or not C_TradeSkillUI.IsTradeSkillReady() then
            return false
        end
        
        -- Get information about the currently open profession
        local baseInfo = C_TradeSkillUI.GetBaseProfessionInfo()
        if not baseInfo or not baseInfo.professionID then return false end
        
        -- Get all child profession infos (expansions)
        -- This returns a table of { professionID, professionName, ... }
        local childInfos = C_TradeSkillUI.GetChildProfessionInfos()
        if not childInfos then return false end
        
        -- Identify which profession this belongs to in our storage
        local name = UnitName("player")
        local realm = GetRealmName()
        local key = name .. "-" .. realm
        
        if not self.db.global.characters[key] then return false end
        if not self.db.global.characters[key].professions then 
            self.db.global.characters[key].professions = {} 
        end
        
        local professions = self.db.global.characters[key].professions
        
        -- Find which profession slot matches the open profession
        local targetProf = nil
        
        -- Check primary professions
        for i = 1, 2 do
            if professions[i] and professions[i].skillLine == baseInfo.professionID then
                targetProf = professions[i]
                break
            end
        end
        
        -- Check secondary
        if not targetProf then
            if professions.cooking and professions.cooking.skillLine == baseInfo.professionID then targetProf = professions.cooking end
            if professions.fishing and professions.fishing.skillLine == baseInfo.professionID then targetProf = professions.fishing end
            if professions.archaeology and professions.archaeology.skillLine == baseInfo.professionID then targetProf = professions.archaeology end
        end
        
        -- If we found the matching profession, update its expansion data
        if targetProf then
            targetProf.expansions = {}
            
            for _, child in ipairs(childInfos) do
                -- child contains: professionID, professionName, parentProfessionID, expansionName
                -- We also need the skill level for this specific expansion
                
                -- We can get the info for this specific child ID
                local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(child.professionID)
                if info then
                    table.insert(targetProf.expansions, {
                        name = child.expansionName or info.professionName, -- Expansion name like "Dragon Isles Alchemy"
                        skillLine = child.professionID,
                        rank = info.skillLevel,
                        maxRank = info.maxSkillLevel,
                    })
                end
            end
            
            -- Sort expansions by ID or something meaningful (usually highest ID = newest)
            table.sort(targetProf.expansions, function(a, b) 
                return a.skillLine > b.skillLine 
            end)
            
            
            -- Invalidate cache so UI refreshes
            if self.InvalidateCharacterCache then
                self:InvalidateCharacterCache()
            end
            
            return true
        end
        
        return false
    end)
    
    if not success then
        return false
    end
    
    return result
end

--[[
    Save complete character data
    Called on login/reload and when significant changes occur
    @return boolean - Success status
]]
function TheQuartermaster:SaveCurrentCharacterData()
    local name = UnitName("player")
    local realm = GetRealmName()
    
    -- Safety check
    if not name or name == "" or name == "Unknown" then
        return false
    end
    if not realm or realm == "" then
        return false
    end
    
    local key = name .. "-" .. realm

    -- Preserve previously stored fields that are populated by other scanners (e.g. reputations).
    -- This function is called from multiple scan paths (bank scans, currency scans, etc.)
    -- and must not wipe data it does not actively refresh.
    local existing = nil
    if self.db.global.characters and self.db.global.characters[key] then
        existing = self.db.global.characters[key]
    end
    
    -- Get character info
    local className, classFile, classID = UnitClass("player")
    local level = UnitLevel("player")
    local gold = GetMoney()
    local faction = UnitFactionGroup("player")
    local _, race = UnitRace("player")

    -- Capture current specialization name (best-effort)
    local specName = nil
    if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        if specIndex then
            local _, sName = GetSpecializationInfo(specIndex)
            specName = sName
        end
    end
    
    -- Validate we have critical info
    if not classFile or not level or level == 0 then
        return false
    end
    
    -- Initialize characters table if needed
    if not self.db.global.characters then
        self.db.global.characters = {}
    end
    
    -- Check if new character
    local isNew = (self.db.global.characters[key] == nil)
    
    -- Collect PvE data (Great Vault, Lockouts, M+)
    local pveData = self:CollectPvEData()
    
    -- Collect Profession data (only if new character or professions don't exist)
    local professionData = nil
    if isNew or not self.db.global.characters[key] or not self.db.global.characters[key].professions then
        professionData = self:CollectProfessionData()
    else
        -- Preserve existing profession data (will be updated by SKILL_LINES_CHANGED event if needed)
        professionData = self.db.global.characters[key].professions
    end
    
    -- Collect Currency data (always collect for current character)
    local currencyData, currencyHeaders = self:CollectCurrencyData()
    
    -- Copy personal bank data to global (for cross-character search and storage browser)
    local personalBank = nil
    local inventory = nil

    if self.db.char.personalBank and self.db.char.personalBank.items then
        personalBank = {}
        for bagIndex, bagData in pairs(self.db.char.personalBank.items) do
            personalBank[bagIndex] = {}
            for slotID, item in pairs(bagData) do
                -- Deep copy all item fields
                personalBank[bagIndex][slotID] = {
                    itemID = item.itemID,
                    itemLink = item.itemLink,
                    stackCount = item.stackCount,
                    quality = item.quality,
                    iconFileID = item.iconFileID,
                    name = item.name,
                    itemLevel = item.itemLevel,
                    itemType = item.itemType,
                    itemSubType = item.itemSubType,
                    classID = item.classID,
                    subclassID = item.subclassID,
                }
            end
        end
    end

    -- Inventory (bags) cache for Storage search
    -- Stored in the same structure as Personal Bank: inventory.items[bagIndex][slotID] = item
    if self.db.char.inventory and self.db.char.inventory.items then
        inventory = {
            items = {},
            bagSizes = self.db.char.inventory.bagSizes,
            bagIDs = self.db.char.inventory.bagIDs,
            usedSlots = self.db.char.inventory.usedSlots,
            totalSlots = self.db.char.inventory.totalSlots,
            lastScan = self.db.char.inventory.lastScan,
        }
        for bagIndex, bagData in pairs(self.db.char.inventory.items) do
            inventory.items[bagIndex] = {}
            for slotID, item in pairs(bagData) do
                inventory.items[bagIndex][slotID] = {
                    itemID = item.itemID,
                    itemLink = item.itemLink,
                    stackCount = item.stackCount,
                    quality = item.quality,
                    iconFileID = item.iconFileID,
                    name = item.name,
                    itemLevel = item.itemLevel,
                    itemType = item.itemType,
                    itemSubType = item.itemSubType,
                    classID = item.classID,
                    subclassID = item.subclassID,
                }
            end
        end
    end

-- Preserve previously captured values (some update asynchronously)
    local priorPlayedTime = nil
    local priorSpecName = nil
    if existing then
        priorPlayedTime = existing.playedTime
        priorSpecName = existing.specName
    end

    if not specName or specName == "" then
        specName = priorSpecName
    end

    -- Item level (only accurate for current character at time of scan)
    local avgIlvl, equippedIlvl = nil, nil
    if GetAverageItemLevel then
        avgIlvl, equippedIlvl = GetAverageItemLevel()
    end

    -- Equipped items (per-slot) (best-effort, current character only)
    -- Stored so other screens can do offline "gear checks" for alts.
    local function CollectEquippedItems()
        local equipment = {}

        -- Slot order roughly matches the character pane.
        local slotNames = {
            "HeadSlot",
            "NeckSlot",
            "ShoulderSlot",
            "BackSlot",
            "ChestSlot",
            "WristSlot",
            "HandsSlot",
            "WaistSlot",
            "LegsSlot",
            "FeetSlot",
            "Finger0Slot",
            "Finger1Slot",
            "Trinket0Slot",
            "Trinket1Slot",
            "MainHandSlot",
            "SecondaryHandSlot",
        }

        for _, slotName in ipairs(slotNames) do
            local slotId = (GetInventorySlotInfo and GetInventorySlotInfo(slotName)) or nil
            local previous = existing and existing.equipment and existing.equipment[slotName]
            equipment[slotName] = slotId and ns.CollectEquipmentSlot(slotId, previous) or previous
        end

        return equipment
    end

    local equipment = CollectEquippedItems()

    -- Share the guarded slot collector with regular equipment; keep last-good data.
    local professionEquipment = {}
    for slotID = 20, 30 do
        local previous = existing and existing.professionEquipment and existing.professionEquipment[slotID]
        professionEquipment[slotID] = ns.CollectEquipmentSlot(slotID, previous)
    end
    local gearProfessions = ns.CollectGearProfessions(existing and existing.gearProfessions)

    -- Experience / Rested XP (best-effort)
    local currentXP, maxXP, restedXP, fullyRestedIn = nil, nil, nil, nil
    local maxPlayerLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 80
    if level and level < maxPlayerLevel then
        currentXP = UnitXP("player")
        maxXP = UnitXPMax("player")
        restedXP = (GetXPExhaustion and GetXPExhaustion()) or 0
        if restedXP == nil then restedXP = 0 end

        local isResting = false
        if IsResting then
            isResting = IsResting()
        elseif GetRestState then
            local restState = GetRestState()
            isResting = (restState == 1)
        end

        fullyRestedIn = ComputeFullyRestedSeconds(maxXP, restedXP, isResting)
    end

    
    -- Guild (Name / Rank / Reputation) (best-effort, current character only)
    local guildName, guildRankName, guildRankIndex = nil, nil, nil
    if IsInGuild and IsInGuild() and GetGuildInfo then
        local gName, gRank, gIndex = GetGuildInfo("player")
        if type(gName) == "string" and gName ~= "" then guildName = gName end
        if type(gRank) == "string" and gRank ~= "" then guildRankName = gRank end
        if type(gIndex) == "number" then guildRankIndex = gIndex end
    end

    local guildRepText, guildStandingID, guildRepPct = nil, nil, nil
    if IsInGuild and IsInGuild() then
        guildRepText, guildStandingID, guildRepPct = GetGuildRepData()
    end


-- Store character data
    local firstSeen = nil
    if existing and existing.firstSeen then
        firstSeen = existing.firstSeen
    elseif existing and existing.lastSeen then
        firstSeen = existing.lastSeen
    else
        firstSeen = time()
    end

    local guildKey, _, guildRealm = self:GetGuildIdentity()
    local newRecord = {
        name = name,
        realm = realm,
        class = className,
        classFile = classFile,
        classID = classID,
        level = level,
        ilvl = equippedIlvl,
        ilvlEquipped = equippedIlvl,
        ilvlAvg = avgIlvl,
        equipment = equipment,
        professionEquipment = professionEquipment,
        gearProfessions = gearProfessions,
        gold = gold,
        faction = faction,
        race = race,
        specName = specName,
        guildName = guildName or false,
        guildKey = guildKey or false,
        guildRealm = guildRealm or false,
        guildRank = guildRankName,
        guildRankIndex = guildRankIndex,
        guildRep = guildRepText,
        guildRepStandingID = guildStandingID,
        guildRepPct = guildRepPct,
        currentXP = currentXP,
        maxXP = maxXP,
        restXP = restedXP,
        fullyRestedIn = fullyRestedIn,
        playedTime = priorPlayedTime,
        firstSeen = firstSeen,
        lastSeen = time(),
        professions = professionData, -- Store Profession data
        pve = pveData,  -- Store PvE data
        weeklyActivities = self.CollectWeeklyActivities and self:CollectWeeklyActivities(existing and existing.weeklyActivities),
        currencies = currencyData, -- Store Currency data
        currencyHeaders = currencyHeaders, -- Store Currency headers
        equipment = equipment, -- Equipped items per slot (offline gear check)
        professionEquipment = professionEquipment, -- Profession equipment slots (tools/accessories)
        personalBank = personalBank,  -- Store personal bank for search
        personalBankLastScan = self.db.char.personalBank and self.db.char.personalBank.lastScan,
        personalBankUsedSlots = self.db.char.personalBank and self.db.char.personalBank.usedSlots,
        inventory = inventory,  -- Store inventory for storage search
    }

    -- Preserve any fields populated by other scanners/modules.
    -- This prevents bank/currency/profession refreshes from wiping reputation data (and others).
    if existing then
        for k, v in pairs(existing) do
            if newRecord[k] == nil then
                newRecord[k] = v
            end
        end
    end

    self.db.global.characters[key] = newRecord
    
    -- Notify only for new characters
    if isNew then
        self:Print("|cff00ff00" .. name .. "|r registered.")
    end
    
    if self.InvalidateCharacterCache then
        self:InvalidateCharacterCache()
    end
    
    return true
end

--[[
    Update only profession data (lightweight)
]]
function TheQuartermaster:UpdateProfessionData()
    local success, err = pcall(function()
        local name = UnitName("player")
        local realm = GetRealmName()
        local key = name .. "-" .. realm

        if not self.db.global.characters or not self.db.global.characters[key] then return end

        local professionData = self:CollectProfessionData()

        -- Preserve detailed expansion data
        local oldProfs = self.db.global.characters[key].professions or {}
        for k, v in pairs(professionData) do
            if oldProfs[k] and oldProfs[k].expansions then
                v.expansions = oldProfs[k].expansions
            end
        end

        self.db.global.characters[key].professions = professionData
        self.db.global.characters[key].lastSeen = time()

        -- Invalidate cache so UI refreshes
        if self.InvalidateCharacterCache then
            self:InvalidateCharacterCache()
        end

    end)
    
    if not success then
    end
end

--[[
    Reset profession data for current character (Debug)
]]
function TheQuartermaster:ResetProfessionData()
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    if self.db.global.characters and self.db.global.characters[key] then
        self.db.global.characters[key].professions = nil
        
        if self.InvalidateCharacterCache then
            self:InvalidateCharacterCache()
        end
        
        if self.RefreshUI then
            self:RefreshUI()
        end
        
        self:Print("Professions reset for " .. key)
    end
end

--[[
    Update only gold for current character (lightweight, called on PLAYER_MONEY)
    @return boolean - Success status
]]
function TheQuartermaster:UpdateCharacterGold()
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    if self.db.global.characters and self.db.global.characters[key] then
        self.db.global.characters[key].gold = GetMoney()
        self.db.global.characters[key].lastSeen = time()
        return true
    end
    

--[[
    Update Guild data for current character (lightweight)
    Called on guild changes and reputation updates
]]
function TheQuartermaster:UpdateGuildData()
    local name = UnitName("player")
    local realm = GetRealmName()
    if not name or name == "" or not realm or realm == "" then return end
    local key = name .. "-" .. realm

    if not self.db or not self.db.global or not self.db.global.characters or not self.db.global.characters[key] then
        return
    end

    local char = self.db.global.characters[key]

    -- Guild name / rank
    local guildName, guildRankName, guildRankIndex = nil, nil, nil
    if IsInGuild and IsInGuild() and GetGuildInfo then
        local gName, gRank, gIndex = GetGuildInfo("player")
        if type(gName) == "string" and gName ~= "" then guildName = gName end
        if type(gRank) == "string" and gRank ~= "" then guildRankName = gRank end
        if type(gIndex) == "number" then guildRankIndex = gIndex end
    end

    -- Guild reputation
    local guildRepText, guildStandingID, guildRepPct = nil, nil, nil
    if IsInGuild and IsInGuild() then
        guildRepText, guildStandingID, guildRepPct = GetGuildRepData()
    end

    -- Store (keep previous values if we couldn't fetch right now)
    if guildName then char.guildName = guildName end
    if guildRankName then char.guildRank = guildRankName end
    if guildRankIndex ~= nil then char.guildRankIndex = guildRankIndex end
    if guildRepText then char.guildRep = guildRepText end
    if guildStandingID ~= nil then char.guildRepStandingID = guildStandingID end
    if guildRepPct ~= nil then char.guildRepPct = guildRepPct end

    char.lastSeen = time()

    if self.InvalidateCharacterCache then
        self:InvalidateCharacterCache()
    end
end

    return false
end

--[[
    Update Experience/Rested XP for current character (lightweight)
    Called on PLAYER_XP_UPDATE / PLAYER_UPDATE_RESTING / PLAYER_LEVEL_UP.
    @return boolean - Success status
]]
function TheQuartermaster:UpdateCurrentCharacterExperience()
    local function IsAtEffectiveMaxLevel()
        -- Retail pre-patch can report a future level cap via GetMaxPlayerLevel().
        -- Prefer "effective max level" checks so level 80 characters at the real cap are treated as max level.
        if type(IsPlayerAtEffectiveMaxLevel) == "function" then
            local ok, v = pcall(IsPlayerAtEffectiveMaxLevel)
            if ok and v == true then
                return true
            end
        end
        local xpMax = UnitXPMax("player")
        return (type(xpMax) == "number" and xpMax == 0) or false
    end

    local name = UnitName("player")
    local realm = GetRealmName()
    if not name or name == "" or name == "Unknown" then return false end
    if not realm or realm == "" then return false end

    local key = name .. "-" .. realm
    if not (self.db and self.db.global and self.db.global.characters and self.db.global.characters[key]) then
        return false
    end

    local char = self.db.global.characters[key]
    local level = UnitLevel("player")
    local isMaxLevel = IsAtEffectiveMaxLevel()

    if level and not isMaxLevel then
        local maxXP = UnitXPMax("player")
        local restedXP = (GetXPExhaustion and GetXPExhaustion()) or 0
        if restedXP == nil then restedXP = 0 end

        local isResting = false
        if IsResting then
            isResting = IsResting()
        elseif GetRestState then
            local restState = GetRestState()
            isResting = (restState == 1)
        end

        char.level = level
        char.isMaxLevel = false
        char.currentXP = UnitXP("player")
        char.maxXP = maxXP
        char.restXP = restedXP
        char.fullyRestedIn = ComputeFullyRestedSeconds(maxXP, restedXP, isResting)
        char.lastSeen = time()
    else
        -- Max level: no XP progress / rest to show
        char.level = level
        char.isMaxLevel = true
        char.currentXP = nil
        char.maxXP = nil
        char.restXP = nil
        char.fullyRestedIn = nil
        char.lastSeen = time()
    end

    return true
end

--[[
    Get all tracked characters
    @return table - Array of character data sorted by level then name
]]
function TheQuartermaster:GetAllCharacters()
    local characters = {}
    
    if not self.db.global.characters then
        return characters
    end
    
    for key, data in pairs(self.db.global.characters) do
        data._key = key  -- Include key for reference
        table.insert(characters, data)
    end
    
    return ns.SortCharacterRows(self.db, characters)

end

-- ============================================================================
-- PVE DATA COLLECTION
-- ============================================================================

--[[
    Collect comprehensive PvE data (Great Vault, Lockouts, M+)
    @return table - PvE data structure
]]
function TheQuartermaster:CollectPvEData()
    local key = self:GetCharacterKey()
    local previous = key and self.db.global.characters and self.db.global.characters[key]
    previous = previous and previous.pve
    local success, result = pcall(function()
    assert(C_WeeklyRewards and C_WeeklyRewards.GetActivities and C_WeeklyRewards.HasAvailableRewards, "vault unavailable")
    assert(GetNumSavedInstances and GetSavedInstanceInfo, "lockouts unavailable")
    assert(C_MythicPlus and C_MythicPlus.GetRunHistory and C_ChallengeMode, "mythic data unavailable")
    local capturedAt = self:GetPvENow()
    local secondsUntilReset = self:GetWeeklyResetSeconds()
    local pve = {
        capturedAt = capturedAt,
        weeklyResetAt = secondsUntilReset and capturedAt + secondsUntilReset or nil,
        seasonID = self:GetPvESeason(),
        greatVault = {},
        lockouts = {},
        mythicPlus = {},
    }
    
    -- ===== GREAT VAULT PROGRESS =====
    if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
        local activities = C_WeeklyRewards.GetActivities()
        assert(type(activities) == "table", "vault not ready")
        if activities then
            for _, activity in ipairs(activities) do
                table.insert(pve.greatVault, {
                    type = activity.type,
                    index = activity.index,
                    progress = activity.progress,
                    threshold = activity.threshold,
                    level = activity.level,
                    rewardItemLevel = ns.WeeklyVaultRewardLevel and ns.WeeklyVaultRewardLevel(activity),
                })
            end
        end
    end
    
    -- ===== CHECK FOR UNCLAIMED VAULT REWARDS =====
    -- This checks if the player has rewards waiting from LAST week (not current progress)
    -- NOTE: This data is only accurate when you're logged in as that character
    -- The indicator will update automatically when you claim vault rewards (via WEEKLY_REWARDS_UPDATE event)
    if C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards then
        pve.hasUnclaimedRewards = C_WeeklyRewards.HasAvailableRewards()
        assert(type(pve.hasUnclaimedRewards) == "boolean", "reward state unavailable")
    else
        pve.hasUnclaimedRewards = false
    end
    
    -- ===== RAID/INSTANCE LOCKOUTS =====
    if GetNumSavedInstances then
        local numSaved = GetNumSavedInstances()
        assert(type(numSaved) == "number" and numSaved >= 0, "lockouts not ready")
        for i = 1, numSaved do
            local instanceName, lockoutID, resetTime, difficultyID, locked, extended, 
                  instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters, 
                  encounterProgress, extendDisabled, instanceID = GetSavedInstanceInfo(i)
            assert(type(instanceName) == "string" and type(locked) == "boolean"
                and type(extended) == "boolean", "lockout record unavailable")
            
            if locked or extended then
                assert(type(resetTime) == "number" and resetTime >= 0, "lockout expiry unavailable")
                table.insert(pve.lockouts, {
                    name = instanceName,
                    id = lockoutID,
                    reset = resetTime,
                    capturedAt = capturedAt,
                    expiresAt = capturedAt + resetTime,
                    difficultyID = difficultyID,
                    difficultyName = difficultyName,
                    isRaid = isRaid,
                    maxPlayers = maxPlayers,
                    progress = encounterProgress,
                    total = numEncounters,
                    extended = extended,
                })
            end
        end
    end
    
    -- ===== MYTHIC+ DATA =====
    if C_MythicPlus then
        -- Current keystone (Retail): use C_MythicPlus API for level/map, and scan bags for an item hyperlink for tooltip.
        local keystoneLevel = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel() or nil
        local keystoneMapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID() or nil

        local keystoneName
        if keystoneMapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
            -- Returns: name, id, timeLimit, texture, backgroundTexture
            keystoneName = (C_ChallengeMode.GetMapUIInfo(keystoneMapID))
        end

        local keystoneLink
        local keystoneIcon

        -- Prefer the real keystone item link from bags (so GameTooltip shows dungeon + level).
        local keystoneItemID = (C_KeystoneInfo and C_KeystoneInfo.GetKeystoneItemID and C_KeystoneInfo.GetKeystoneItemID()) or 180653
        if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
            for bagID = 0, (NUM_BAG_SLOTS or 4) do
                local numSlots = C_Container.GetContainerNumSlots(bagID)
                if numSlots then
                    for slotID = 1, numSlots do
                        local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
                        if itemInfo and itemInfo.itemID and itemInfo.hyperlink then
                            if itemInfo.itemID == keystoneItemID then
                                keystoneLink = itemInfo.hyperlink
                                break
                            end
                        end
                    end
                end
                if keystoneLink then break end
            end

            -- Fallback: find any "Keystone" link that matches the owned level.
            if not keystoneLink and keystoneLevel then
                for bagID = 0, (NUM_BAG_SLOTS or 4) do
                    local numSlots = C_Container.GetContainerNumSlots(bagID)
                    if numSlots then
                        for slotID = 1, numSlots do
                            local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
                            if itemInfo and itemInfo.hyperlink then
                                local link = itemInfo.hyperlink
                                if link:find("Keystone", 1, true) and link:find("+" .. tostring(keystoneLevel), 1, true) then
                                    keystoneLink = link
                                    break
                                end
                            end
                        end
                    end
                    if keystoneLink then break end
                end
            end
        end

        -- Standard keystone icon (item icon). Safe even if item data isn't cached.
        if keystoneItemID and GetItemInfoInstant then
            local _, _, _, _, icon = GetItemInfoInstant(keystoneItemID)
            keystoneIcon = icon
        end

        if keystoneLevel and keystoneLevel > 0 then
            pve.mythicPlus.keystone = {
                mapID = keystoneMapID,
                name = keystoneName,
                level = keystoneLevel,
                link = keystoneLink,
                icon = keystoneIcon,
            }
        end
        
        -- Run history this week
        if C_MythicPlus.GetRunHistory then
            local includeIncomplete = false
            local includePreviousWeeks = false
            local runs = C_MythicPlus.GetRunHistory(includeIncomplete, includePreviousWeeks)
            assert(type(runs) == "table", "run history unavailable")
            if runs then
                pve.mythicPlus.runsThisWeek = #runs
                -- Get highest run level for weekly best
                local bestLevel = 0
                for _, run in ipairs(runs) do
                    if run.level and run.level > bestLevel then
                        bestLevel = run.level
                    end
                end
                if bestLevel > 0 then
                    pve.mythicPlus.weeklyBest = bestLevel
                end
            else
                pve.mythicPlus.runsThisWeek = 0
            end
        end
        
        -- ===== MYTHIC+ DUNGEON PROGRESS =====
        if C_ChallengeMode then
            pve.mythicPlus.dungeons = {}
            pve.mythicPlus.overallScore = C_ChallengeMode.GetOverallDungeonScore()
            assert(type(pve.mythicPlus.overallScore) == "number", "dungeon score unavailable")
            
            -- Get all map scores (returns indexed table with mapChallengeModeID keys)
            local allScores = C_ChallengeMode.GetMapScoreInfo()
            assert(type(allScores) == "table", "dungeon scores unavailable")
            
            -- Create lookup table by mapChallengeModeID
            local scoresByMapID = {}
            for _, scoreData in ipairs(allScores) do
                if scoreData.mapChallengeModeID then
                    scoresByMapID[scoreData.mapChallengeModeID] = scoreData
                end
            end
            
            local mapTable = C_ChallengeMode.GetMapTable()
            assert(type(mapTable) == "table", "dungeon list unavailable")
            if mapTable then
                for _, mapID in ipairs(mapTable) do
                    local name, id, timeLimit, texture = C_ChallengeMode.GetMapUIInfo(mapID)
                    if name then
                        local bestLevel = 0
                        local bestScore = 0
                        local isCompleted = false
                        
                        -- Lookup score data for this mapID
                        local scoreData = scoresByMapID[mapID]
                        if scoreData then
                            bestLevel = scoreData.level or 0
                            bestScore = scoreData.dungeonScore or 0
                            isCompleted = (scoreData.completedInTime == 1) or false
                        end
                        
                        -- Insert dungeon regardless of completion status
                        table.insert(pve.mythicPlus.dungeons, {
                            mapID = mapID,
                            name = name,
                            texture = texture,
                            bestLevel = bestLevel,
                            score = bestScore,
                            completed = isCompleted,
                        })
                    end
                end
            end
        end
    end
    
    return pve
    end)
    
    if not success then
        local retained = {}
        for field, value in pairs(previous or {}) do retained[field] = value end
        retained.greatVault = retained.greatVault or {}
        retained.lockouts = retained.lockouts or {}
        retained.mythicPlus = retained.mythicPlus or {}
        retained.scanState = previous and previous.scanState ~= "unavailable" and "stale" or "unavailable"
        return retained
    end
    result.lastScan = time()
    result.scanState = "fresh"
    return result
end

-- ============================================================================
-- ITEM SEARCH & AGGREGATION
-- ============================================================================

--[[
    Perform item search across all characters and banks
    @param searchTerm string - Search query (item name or ID)
    @return table - Array of search results with location info
]]
function TheQuartermaster:PerformItemSearch(searchTerm, browseAll)
    if not searchTerm or (searchTerm == "" and not browseAll) then
        return {}
    end
    
    local results = {}
    local searchLower = searchTerm:lower()
    local searchID = tonumber(searchTerm)
    
    -- Search Warband Bank
    if self.db.global.warbandBank and self.db.global.warbandBank.items then
        for bagID, bagData in pairs(self.db.global.warbandBank.items) do
            for slotID, item in pairs(bagData) do
                local match = browseAll and item and item.itemID and true or false
                
                -- Match by name
                if item.name and item.name:lower():find(searchLower, 1, true) then
                    match = true
                end
                
                -- Match by ID
                if searchID and item.itemID == searchID then
                    match = true
                end
                
                if match then
                    table.insert(results, {
                        item = item,
                        location = "Warband Bank",
                        locationDetail = "Tab " .. (bagID - 12), -- Convert bagID to tab number
                        character = nil,
                    })
                end
            end
        end
    end
    
    -- Search Personal Banks (all characters)
    if self.db.global.characters then
        for charKey, charData in pairs(self.db.global.characters) do
            if charData.personalBank then
                for bagID, bagData in pairs(charData.personalBank) do
                    for slotID, item in pairs(bagData) do
                        local match = browseAll and item and item.itemID and true or false
                        
                        -- Match by name
                        if item.name and item.name:lower():find(searchLower, 1, true) then
                            match = true
                        end
                        
                        -- Match by ID
                        if searchID and item.itemID == searchID then
                            match = true
                        end
                        
                        if match then
                            table.insert(results, {
                                item = item,
                                location = "Personal Bank",
                                locationDetail = charData.name .. " (" .. charData.realm .. ")",
                                character = charData.name,
                            })
                        end
                    end
                end
            end
        end
    end
    
    -- Search Inventories (all characters)
    if self.db.global.characters then
        for charKey, charData in pairs(self.db.global.characters) do
            if charData.inventory and charData.inventory.items then
                for bagIndex, bagData in pairs(charData.inventory.items) do
                    for slotID, item in pairs(bagData) do
                        local match = browseAll and item and item.itemID and true or false
                        if item.name and item.name:lower():find(searchLower, 1, true) then match = true end
                        if searchID and item.itemID == searchID then match = true end
                        if match then
                            table.insert(results, {
                                item = item,
                                location = "Bags",
                                locationDetail = (charData.name or charKey) .. " (" .. (charData.realm or "Unknown") .. ")",
                                character = charData.name,
                            })
                        end
                    end
                end
            end
        end
    end

    -- Search Equipped Gear (all characters)
    if self.db.global.characters then
        for charKey, charData in pairs(self.db.global.characters) do
            if charData.equipment then
                for slotName, item in pairs(charData.equipment) do
                    local match = browseAll and item and item.itemID and true or false
                    if item and item.name and item.name:lower():find(searchLower, 1, true) then match = true end
                    if item and searchID and item.itemID == searchID then match = true end
                    if match then
                        table.insert(results, {
                            item = item,
                            location = "Equipped",
                            locationDetail = (charData.name or charKey) .. " (" .. (charData.realm or "Unknown") .. ") - " .. tostring(slotName),
                            character = charData.name,
                        })
                    end
                end
            end
        end
    end

    -- Search Profession Equipment (all characters)
    if self.db.global.characters then
        for charKey, charData in pairs(self.db.global.characters) do
            if charData.professionEquipment then
                for slotID, item in pairs(charData.professionEquipment) do
                    local match = browseAll and item and item.itemID and true or false
                    if item and item.name and item.name:lower():find(searchLower, 1, true) then match = true end
                    if item and searchID and item.itemID == searchID then match = true end
                    if match then
                        table.insert(results, {
                            item = item,
                            location = "Profession Equipment",
                            locationDetail = (charData.name or charKey) .. " (" .. (charData.realm or "Unknown") .. ") - " .. (item.slotName or ("Slot " .. tostring(slotID))),
                            character = charData.name,
                        })
                    end
                end
            end
        end
    end

    -- Auction locations are separate from the available-stock aggregation path.
    if self.GetAuctionSearchRows then
        for _, result in ipairs(self:GetAuctionSearchRows(searchTerm)) do results[#results + 1] = result end
    end

    -- Search active mailbox attachments.
    if self.GetMailItemRows then
        for _, result in ipairs(self:GetMailItemRows()) do
            local item = result.item
            if browseAll or (searchID and item.itemID == searchID) or (item.name and item.name:lower():find(searchLower, 1, true)) then
                results[#results + 1] = result
            end
        end
    end

    -- Search Guild Banks (cached)
    if self.db.global.guildBank then
        for guildName, guildData in pairs(self.db.global.guildBank) do
            if guildData and guildData.tabs then
                for tabIndex, tab in pairs(guildData.tabs) do
                    if tab and tab.items then
                        for slotIndex, item in pairs(tab.items) do
                            local match = browseAll and item and item.itemID and true or false
                            if item.name and item.name:lower():find(searchLower, 1, true) then match = true end
                            if searchID and item.itemID == searchID then match = true end
                            if match then
                                table.insert(results, {
                                    item = item,
                                    location = "Guild Bank",
                                    locationDetail = self:GetGuildBankLabel(guildData, guildName) .. " - " .. (tab.name or ("Tab " .. tabIndex)),
                                    character = nil,
                                    guild = guildName,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    return results
end

--[[
    Perform currency search across all characters
    @param searchTerm string
    @return table results
]]
function TheQuartermaster:PerformCurrencySearch(searchTerm)
    if not searchTerm or searchTerm == "" then
        return {}
    end

    local results = {}
    local searchLower = searchTerm:lower()
    local searchID = tonumber(searchTerm)

    local characters = self.GetAllCharacters and self:GetAllCharacters() or {}
    for _, char in ipairs(characters) do
        if char.currencies then
            for currencyID, cur in pairs(char.currencies) do
                local match = false
                local name = cur.name or cur.currencyName
                if name and tostring(name):lower():find(searchLower, 1, true) then
                    match = true
                end
                if searchID and tonumber(currencyID) == searchID then
                    match = true
                end
                if match then
                    table.insert(results, {
                        currencyID = tonumber(currencyID),
                        currency = cur,
                        character = char.name,
                        realm = char.realm,
                    })
                end
            end
        end
    end

    return results
end

-- ============================================================================
-- CURRENCY DATA
-- ============================================================================

--[[
    Important Currency IDs organized by expansion
]]
-- ============================================================================
-- CURRENCY COLLECTION (Direct from Blizzard API)
-- ============================================================================
-- NOTE: We no longer use a hardcoded currency list.
-- Instead, we collect ALL currencies from C_CurrencyInfo.GetCurrencyListSize()
-- This ensures we always match Blizzard's Currency UI exactly.
-- ============================================================================

--[[
    Collect all currency data for current character
    Collects ALL currencies directly from Blizzard API with their header structure
    @return table, table - currencies data, headers data
]]
-- Build stable keys for the currency headers currently visible in Blizzard's
-- currency list. The occurrence suffix protects against duplicate header names.
local function GetVisibleCurrencyHeaders()
    local rows = {}
    local occurrences = {}
    local listSize = C_CurrencyInfo.GetCurrencyListSize()

    for i = 1, listSize do
        local info = C_CurrencyInfo.GetCurrencyListInfo(i)
        if info and info.isHeader and info.name and info.name ~= "" then
            local depth = tonumber(info.currencyListDepth) or 0
            local baseKey = tostring(depth) .. "\031" .. info.name
            occurrences[baseKey] = (occurrences[baseKey] or 0) + 1

            rows[#rows + 1] = {
                index = i,
                key = baseKey .. "\031" .. occurrences[baseKey],
                isExpanded = info.isHeaderExpanded and true or false,
            }
        end
    end

    return rows
end

-- Queue a complete scan rather than trying to expand every nested header in one
-- Lua frame. On the PTR, newly revealed Legacy headers are not always available
-- until a later frame, so a synchronous loop can save only the currently visible
-- currencies and overwrite the previously complete character cache.
function TheQuartermaster:QueueFullCurrencyScan()
    if self.currencyHeaderScanQueued or self.currencyHeaderScanInProgress then
        return
    end

    if not C_Timer or not C_Timer.After then
        return
    end

    self.currencyHeaderScanQueued = true
    C_Timer.After(0.20, function()
        if not TheQuartermaster then
            return
        end

        TheQuartermaster.currencyHeaderScanQueued = false
        TheQuartermaster:RefreshCurrencyDataWithExpandedHeaders()
    end)
end

-- Expand one visible collapsed header at a time, waiting briefly between each
-- expansion. This allows child headers beneath Legacy (and any future nested
-- groups) to become available before the next pass.
function TheQuartermaster:RefreshCurrencyDataWithExpandedHeaders()
    if self.currencyHeaderScanInProgress or not C_CurrencyInfo then
        return
    end

    self.currencyHeaderScanInProgress = true

    local originalHeaderState = {}
    for _, row in ipairs(GetVisibleCurrencyHeaders()) do
        originalHeaderState[row.key] = row.isExpanded
    end

    local attemptsByHeader = {}
    local ignoredHeaders = {}
    local steps = 0
    local MAX_STEPS = 300
    local MAX_ATTEMPTS_PER_HEADER = 4

    local function FinishScan()
        if not TheQuartermaster then
            return
        end

        -- Collect while the complete hierarchy is visible. Passing true prevents
        -- this collection from queueing another expansion scan.
        TheQuartermaster:UpdateCurrencyData(true)

        -- Restore headers that were visibly collapsed before the scan. Process
        -- from bottom to top so collapsing a parent does not invalidate indexes
        -- that still need to be handled.
        local rows = GetVisibleCurrencyHeaders()
        for i = #rows, 1, -1 do
            local row = rows[i]
            if originalHeaderState[row.key] == false and row.isExpanded then
                C_CurrencyInfo.ExpandCurrencyList(row.index, false)
            end
        end

        TheQuartermaster.currencyHeaderScanInProgress = false

        if TheQuartermaster.RefreshUI then
            TheQuartermaster:RefreshUI()
        end
    end

    local function ExpandNextHeader()
        if not TheQuartermaster or not C_CurrencyInfo then
            return
        end

        steps = steps + 1
        if steps > MAX_STEPS then
            FinishScan()
            return
        end

        local rows = GetVisibleCurrencyHeaders()
        local target = nil

        -- Work from the bottom upwards. Newly revealed children then appear near
        -- the current position and are handled before moving to earlier groups.
        for i = #rows, 1, -1 do
            local row = rows[i]
            if not row.isExpanded and not ignoredHeaders[row.key] then
                target = row
                break
            end
        end

        if not target then
            FinishScan()
            return
        end

        attemptsByHeader[target.key] = (attemptsByHeader[target.key] or 0) + 1
        if attemptsByHeader[target.key] > MAX_ATTEMPTS_PER_HEADER then
            -- Some empty/system headers can report as collapsed even though they
            -- have no expandable children. Ignore those rather than looping.
            ignoredHeaders[target.key] = true
            C_Timer.After(0, ExpandNextHeader)
            return
        end

        C_CurrencyInfo.ExpandCurrencyList(target.index, true)
        C_Timer.After(0.05, ExpandNextHeader)
    end

    ExpandNextHeader()
end

function TheQuartermaster:CollectCurrencyData(headersAlreadyExpanded)
    local currencies = {}
    local headers = {}
    
    local success, err = pcall(function()
        if not C_CurrencyInfo then
            return
        end

        -- Always return the currencies that are currently available immediately,
        -- then complete a staged nested-header scan in the background.
        if not headersAlreadyExpanded and self.QueueFullCurrencyScan then
            self:QueueFullCurrencyScan()
        end
        
        local listSize = C_CurrencyInfo.GetCurrencyListSize()
        
        local currentHeader = nil
        local scannedCount = 0
        local currencyCount = 0
        
        for i = 1, listSize do
            local listInfo = C_CurrencyInfo.GetCurrencyListInfo(i)
            
            if listInfo and listInfo.name and listInfo.name ~= "" then
                scannedCount = scannedCount + 1
                
                if listInfo.isHeader then
                    -- This is a HEADER
                    currentHeader = {
                        name = listInfo.name,
                        index = i,
                        currencies = {}
                    }
                    table.insert(headers, currentHeader)
                else
                    -- This is a CURRENCY entry
                    -- Try multiple methods to get currency ID
                    local currencyID = nil
                    
                    -- Method 1: From link (most reliable if it exists)
                    local currencyLink = C_CurrencyInfo.GetCurrencyListLink(i)
                    if currencyLink then
                        currencyID = tonumber(currencyLink:match("currency:(%d+)"))
                    end
                    
                    -- Method 2: If listInfo has the ID directly (some versions)
                    if not currencyID then
                        currencyID = listInfo.currencyTypesID
                    end
                    
                    -- Method 3: Search by name (fallback, less reliable)
                    if not currencyID and listInfo.name then
                        -- We can't reliably get ID from name, skip this
                    end
                    
                    if currencyID and currencyID > 0 then
                        -- Get FULL currency info using the ID
                        local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID)
                        
                        if currencyInfo and currencyInfo.name then
                            currencyCount = currencyCount + 1
                            
                            -- Hidden criteria
                            local nameHidden = currencyInfo.name and 
                                              (currencyInfo.name:find("%(Hidden%)") or 
                                               currencyInfo.name:match("^%d+%.%d+%.%d+"))
                            
                            local isReallyHidden = nameHidden or false
                            
                            -- Store currency data
                            local currencyData = {
                                checked = time(),
                                name = currencyInfo.name,
                                quantity = currencyInfo.quantity or 0,
                                maxQuantity = currencyInfo.maxQuantity or 0,
                                iconFileID = currencyInfo.iconFileID,
                                quality = currencyInfo.quality or 1,
                                useTotalEarnedForMaxQty = currencyInfo.useTotalEarnedForMaxQty,
                                totalEarned = ns.Wealth and ns.Wealth.Number(currencyInfo.totalEarned) and currencyInfo.totalEarned or nil,
                                maxWeeklyQuantity = ns.Wealth and ns.Wealth.Number(currencyInfo.maxWeeklyQuantity) and currencyInfo.maxWeeklyQuantity or nil,
                                canEarnPerWeek = currencyInfo.canEarnPerWeek,
                                quantityEarnedThisWeek = currencyInfo.quantityEarnedThisWeek or 0,
                                isCapped = (currencyInfo.maxQuantity and currencyInfo.maxQuantity > 0 and
                                           currencyInfo.quantity >= currencyInfo.maxQuantity),
                                isAccountWide = currencyInfo.isAccountWide or false,
                                isAccountTransferable = currencyInfo.isAccountTransferable or false,
                                discovered = currencyInfo.discovered or false,
                                isHidden = isReallyHidden,
                                headerName = currentHeader and currentHeader.name or "Other",
                                listIndex = i,
                            }
                            
                            -- Auto-assign expansion and category based on name patterns
                            local name = currencyData.name:lower()
                            local headerName = currencyData.headerName:lower()
                            
                            -- Expansion detection
                            if name:find("ethereal") or name:find("carved ethereal") or name:find("runed ethereal") or name:find("weathered ethereal") then
                                currencyData.expansion = "The War Within"
                                currencyData.category = "Crest"
                                currencyData.season = "Season 3"  -- Mark as Season 3
                            elseif name:find("undercoin") or name:find("restored coffer") or name:find("coffer key") or name:find("voidsplinter") then
                                currencyData.expansion = "The War Within"
                                currencyData.category = "Currency"
                                currencyData.season = "Season 3"  -- Mark as Season 3
                            elseif name:find("kej") or name:find("resonance") or name:find("valorstone") or name:find("flame%-blessed") or name:find("mereldar") or name:find("hellstone") or name:find("corrupted mementos") or name:find("kaja'cola") or name:find("finery") or name:find("residual memories") or name:find("untethered coin") or name:find("trader's tender") or name:find("bronze celebration") then
                                currencyData.expansion = "The War Within"
                                currencyData.category = name:find("valorstone") and "Upgrade" or "Currency"
                            elseif name:find("drake") or name:find("whelp") or name:find("aspect") or name:find("dragon isles") or name:find("dragonf") then
                                currencyData.expansion = "Dragonflight"
                                currencyData.category = name:find("crest") and "Crest" or "Currency"
                            elseif name:find("soul") or name:find("cinders") or name:find("stygia") or name:find("shadowlands") or name:find("anima") or name:find("infused ruby") or name:find("reservoir anima") or name:find("grateful offering") then
                                currencyData.expansion = "Shadowlands"
                                currencyData.category = "Currency"
                            elseif name:find("war resource") or name:find("seafarer") or name:find("7th legion") or name:find("honorbound") or name:find("polished pet charm") or name:find("prismatic manapearl") or name:find("war supplies") then
                                currencyData.expansion = "Battle for Azeroth"
                                currencyData.category = "Currency"
                            elseif name:find("legion") or name:find("order resource") or name:find("nethershard") or name:find("curious coin") or name:find("legionfall") or name:find("wakening") or name:find("shadowy coin") or name:find("seal of broken fate") then
                                currencyData.expansion = "Legion"
                                currencyData.category = "Currency"
                            elseif name:find("apexis") or name:find("garrison") or name:find("primal spirit") or name:find("oil") or name:find("seal of tempered fate") or name:find("seal of inevitable fate") then
                                currencyData.expansion = "Warlords of Draenor"
                                currencyData.category = "Currency"
                            elseif name:find("timeless") or name:find("warforged") or name:find("bloody coin") or name:find("lesser charm") or name:find("elder charm") or name:find("mogu rune") or name:find("valor point") then
                                currencyData.expansion = "Mists of Pandaria"
                                currencyData.category = "Currency"
                            elseif name:find("mote") or name:find("sidereal") or name:find("essence of corrupted") or name:find("illustrious") or name:find("mark of the world tree") or name:find("tol barad") or name:find("conquest point") then
                                currencyData.expansion = "Cataclysm"
                                currencyData.category = "Currency"
                            elseif name:find("champion's seal") or name:find("emblem") or name:find("stone keeper") or name:find("defiler's") or name:find("wintergrasp") or name:find("shard of") or name:find("frozen orb") then
                                currencyData.expansion = "Wrath of the Lich King"
                                currencyData.category = "Currency"
                            elseif name:find("badge") or name:find("venture coin") or name:find("halaa") or name:find("spirit shard") or name:find("mark of honor hold") or name:find("mark of thrallmar") then
                                currencyData.expansion = "The Burning Crusade"
                                currencyData.category = "Currency"
                            elseif currencyData.isAccountWide then
                                currencyData.expansion = "Account-Wide"
                                currencyData.category = "Currency"
                            else
                                -- Use header name to determine expansion if still unknown
                                if headerName:find("war within") or headerName:find("tww") then
                                    currencyData.expansion = "The War Within"
                                elseif headerName:find("dragonflight") or headerName:find("df") then
                                    currencyData.expansion = "Dragonflight"
                                elseif headerName:find("shadowlands") or headerName:find("sl") then
                                    currencyData.expansion = "Shadowlands"
                                elseif headerName:find("battle for azeroth") or headerName:find("bfa") then
                                    currencyData.expansion = "Battle for Azeroth"
                                elseif headerName:find("legion") then
                                    currencyData.expansion = "Legion"
                                elseif headerName:find("warlords") or headerName:find("wod") then
                                    currencyData.expansion = "Warlords of Draenor"
                                elseif headerName:find("mists of pandaria") or headerName:find("mop") then
                                    currencyData.expansion = "Mists of Pandaria"
                                elseif headerName:find("cataclysm") then
                                    currencyData.expansion = "Cataclysm"
                                elseif headerName:find("wrath") or headerName:find("lich king") or headerName:find("wotlk") then
                                    currencyData.expansion = "Wrath of the Lich King"
                                elseif headerName:find("burning crusade") or headerName:find("tbc") or headerName:find("bc") then
                                    currencyData.expansion = "The Burning Crusade"
                                else
                                    currencyData.expansion = "Other"
                                end
                            end
                            
                            -- Category refinement and special handling
                            if not currencyData.category then
                                if name:find("crest") or name:find("fragment") then
                                    currencyData.category = "Crest"
                                elseif name:find("valorstone") or name:find("upgrade") then
                                    currencyData.category = "Upgrade"
                                elseif name:find("supplies") then
                                    currencyData.category = "Supplies"
                                elseif name:find("research") or name:find("knowledge") or name:find("artisan") then
                                    currencyData.category = "Profession"
                                elseif headerName:find("pvp") or name:find("honor") or name:find("conquest") or name:find("bloody token") or name:find("vicious") then
                                    currencyData.category = "PvP"
                                elseif headerName:find("event") or name:find("timewarped") or name:find("darkmoon") or name:find("love token") or name:find("tricky treat") or name:find("brewfest") or name:find("celebration token") or name:find("prize ticket") or name:find("epicurean") then
                                    currencyData.category = "Event"
                                elseif name:find("trophy") or name:find("tender") then
                                    currencyData.category = "Cosmetic"
                                else
                                    currencyData.category = "Currency"
                                end
                            end
                            
                            -- Special handling for PvP and Event currencies - assign to correct expansion
                            if currencyData.expansion == "Other" then
                                if currencyData.category == "PvP" then
                                    -- PvP currencies go to Account-Wide if account-wide
                                    if currencyData.isAccountWide or name:find("bloody") or name:find("vicious") or name:find("honor") or name:find("conquest") then
                                        currencyData.expansion = "Account-Wide"
                                    end
                                elseif currencyData.category == "Event" then
                                    -- Most event currencies are account-wide
                                    if currencyData.isAccountWide or name:find("timewarped") or name:find("darkmoon") or name:find("celebration") or name:find("epicurean") then
                                        currencyData.expansion = "Account-Wide"
                                    end
                                elseif currencyData.category == "Cosmetic" then
                                    -- Cosmetic currencies are usually account-wide
                                    if currencyData.isAccountWide or name:find("tender") then
                                        currencyData.expansion = "Account-Wide"
                                    end
                                end
                            end
                            
                            currencies[currencyID] = currencyData
                            
                            -- Add to current header's currency list
                            if currentHeader then
                                table.insert(currentHeader.currencies, currencyID)
                            end
                        end
                    end
                end
            end
        end
    end)
    
    if not success then
        return {}, {}
    end
    
    return currencies, headers
end

--[[
    Update currency data for current character
]]
function TheQuartermaster:UpdateCurrencyData(headersAlreadyExpanded)
    -- Header expansion fires CURRENCY_DISPLAY_UPDATE. Ignore those intermediate
    -- events so a partial visible list cannot overwrite the completed scan.
    if self.currencyHeaderScanInProgress and not headersAlreadyExpanded then
        return
    end

    local success, err = pcall(function()
        local name = UnitName("player")
        local realm = GetRealmName()
        local key = name .. "-" .. realm
        
        if not self.db.global.characters or not self.db.global.characters[key] then return end
        
        local currencyData, headerData = self:CollectCurrencyData(headersAlreadyExpanded)
        self.db.global.characters[key].currencies = currencyData
        self.db.global.characters[key].currencyHeaders = headerData  -- Store headers too
        self.db.global.characters[key].lastSeen = time()
        
        -- Invalidate cache
        if self.InvalidateCharacterCache then
            self:InvalidateCharacterCache()
        end
    end)
    
    if not success then
    end
end

--[[
    Helper: Count table entries
]]
function TheQuartermaster:TableCount(tbl)
    if not tbl then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- ============================================================================
-- COLLECTION DATA
-- ============================================================================

--[[
    Get collection statistics for current character
    @return table - Collection stats (mounts, pets, toys, achievements)
]]
function TheQuartermaster:GetCollectionStats()
    local success, result = pcall(function()
    local stats = {
        mounts = 0,
        pets = 0,
        toys = 0,
        achievements = 0,
    }
    
    -- Mounts
    if C_MountJournal and C_MountJournal.GetNumMounts then
        stats.mounts = C_MountJournal.GetNumMounts() or 0
    end
    
    -- Pets
    if C_PetJournal and C_PetJournal.GetNumPets then
        stats.pets = C_PetJournal.GetNumPets() or 0
    end
    
    -- Toys
    if C_ToyBox and C_ToyBox.GetNumToys then
        stats.toys = C_ToyBox.GetNumToys() or 0
    end
    
    -- Achievement Points
    if GetTotalAchievementPoints then
        stats.achievements = GetTotalAchievementPoints() or 0
    end
    
    return stats
    end)
    
    if not success then
        return {
            mounts = 0,
            pets = 0,
            toys = 0,
            achievements = 0,
        }
    end
    
    return result
end

--[[
    Export character data for external use (CSV/JSON compatible)
    @param characterKey string - Character key (name-realm)
    @return table - Simplified character data structure
]]
function TheQuartermaster:ExportCharacterData(characterKey)
    if not self.db.global.characters or not self.db.global.characters[characterKey] then
        return nil
    end
    
    local char = self.db.global.characters[characterKey]
    
    local pveView = self:GetPvEView(char.pve)
    -- Create simplified export structure
    return {
        name = char.name,
        realm = char.realm,
        class = char.class,
        level = char.level,
        gold = char.gold,
        faction = char.faction,
        race = char.race,
        lastSeen = char.lastSeen,
        pve = {
            periodState = pveView.periodState,
            greatVaultProgress = #(pveView and pveView.greatVault or {}),
            lockoutCount = #(pveView and pveView.lockouts or {}),
            mythicPlusWeeklyBest = (pveView and pveView.mythicPlus and pveView.mythicPlus.weeklyBest) or 0,
            mythicPlusRuns = (pveView and pveView.mythicPlus and pveView.mythicPlus.runsThisWeek) or 0,
        },
    }
end

-- ============================================================================
-- DATA VALIDATION & CLEANUP
-- ============================================================================

--[[
    Validate character data integrity
    @param characterKey string - Character key to validate
    @return boolean, string - Valid status and error message if invalid
]]
function TheQuartermaster:ValidateCharacterData(characterKey)
    if not self.db.global.characters or not self.db.global.characters[characterKey] then
        return false, "Character not found"
    end
    
    local char = self.db.global.characters[characterKey]
    
    -- Check required fields
    local required = {"name", "realm", "class", "classFile", "level"}
    for _, field in ipairs(required) do
        if not char[field] then
            return false, "Missing required field: " .. field
        end
    end
    
    -- Check data types
    if type(char.level) ~= "number" or char.level < 1 or char.level > 80 then
        return false, "Invalid level: " .. tostring(char.level)
    end
    
    if type(char.gold) ~= "number" or char.gold < 0 then
        return false, "Invalid gold: " .. tostring(char.gold)
    end
    
    return true, nil
end

-- Retained for callers from older builds. Age never authorizes deletion of an alt.
-- Use the confirmed per-character deletion action to remove saved character data.
function TheQuartermaster:CleanupStaleCharacters(daysThreshold)
    return 0
end
