--[[
    The Quartermaster - Profession Recipes (Option A)
    Stores *known* recipeIDs per character for the currently-open profession skill line.

    Design goals:
      - Keep SavedVariables small: store recipeIDs as a sorted numeric array (not a hash table).
      - No attempt to store "missing" recipes or a global master list.
      - No forced switching between expansion skill lines. We cache whatever the user has open.

    Usage:
      - Enable "Track Profession Recipes" in settings.
      - Log into a crafter, open their profession window, and the addon will cache recipes.
      - Query via: /tq recipes <text>
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

-- We intentionally do NOT cache recipes for certain secondary professions.
-- Cooking is explicitly allowed (requested), but Fishing and Archaeology are ignored.
-- professionID values come from C_TradeSkillUI.GetBaseProfessionInfo().professionID
local IGNORED_PROFESSION_IDS = {
    [356] = true, -- Fishing
    [794] = true, -- Archaeology
}

local function IsIgnoredProfessionID(professionID)
    professionID = tonumber(professionID)
    return professionID and IGNORED_PROFESSION_IDS[professionID] == true
end

local function GetPlayerKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    if not (name and realm) then return nil end
    -- Match the normalization used elsewhere in the addon (strip spaces in realm only)
    realm = realm:gsub("%s+", "")
    return name .. "-" .. realm
end

local function EnsureCharStore(db, key)
    if not db or not db.global or not db.global.characters then return nil end
    db.global.characters[key] = db.global.characters[key] or {}
    local c = db.global.characters[key]
    c.professionRecipes = c.professionRecipes or {}
    return c.professionRecipes
end

local function EnsureGlobalRecipeNameStore(db)
    if not db or not db.global then return nil end
    db.global.recipeNames = db.global.recipeNames or {}
    return db.global.recipeNames
end

local function EnsureGlobalRecipeItemStore(db)
    if not db or not db.global then return nil end
    db.global.recipeOutputItems = db.global.recipeOutputItems or {}
    return db.global.recipeOutputItems
end

local function SortedUniqueNumericArray(t)
    if type(t) ~= "table" then return {} end
    local out = {}
    for i = 1, #t do
        local id = tonumber(t[i])
        if id then
            out[#out + 1] = id
        end
    end
    table.sort(out)

    -- de-dupe in-place
    local w = 0
    local last
    for i = 1, #out do
        local v = out[i]
        if v ~= last then
            w = w + 1
            out[w] = v
            last = v
        end
    end
    for i = #out, w + 1, -1 do
        out[i] = nil
    end

    return out
end

local function ArraysEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end


-- Internal: schedule a few retries when the profession UI isn't fully ready yet.
-- First open on a character often fires TRADE_SKILL_SHOW before recipe data is populated.
function TheQuartermaster:_ScheduleProfessionRecipeScanRetry()
    -- Only retry if feature is enabled
    if not (self.db and self.db.profile and self.db.profile.trackProfessionRecipes) then return end
    self._qmRecipeScanRetries = (self._qmRecipeScanRetries or 0)
    if self._qmRecipeScanRetries >= 6 then
        self._qmRecipeScanRetries = 0
        return
    end
    self._qmRecipeScanRetries = self._qmRecipeScanRetries + 1
    if C_Timer and C_Timer.After then
        C_Timer.After(0.25, function()
            if TheQuartermaster and TheQuartermaster.ScanProfessionRecipes then
                -- Don't recurse endlessly; ScanProfessionRecipes will decide whether to schedule again.
                TheQuartermaster:ScanProfessionRecipes(true)
            end
        end)
    end
end

--[[
    Scan and persist recipes for the currently-open profession (current skillLineID).
    @return boolean - true if SavedVariables were updated
]]
function TheQuartermaster:ScanProfessionRecipes(fromRetry)
    if not self.db or not self.db.profile or not self.db.profile.trackProfessionRecipes then
        return false
    end

    -- One-time cleanup: if we previously cached ignored professions (e.g. Fishing), remove them.
    if not self._qmPrunedIgnoredRecipeCaches then
        self._qmPrunedIgnoredRecipeCaches = true
        local chars = self.db and self.db.global and self.db.global.characters
        if type(chars) == "table" then
            for _, c in pairs(chars) do
                local ps = c and c.professionRecipes
                if type(ps) == "table" then
                    for profID in pairs(IGNORED_PROFESSION_IDS) do
                        if ps[profID] ~= nil then
                            ps[profID] = nil
                        end
                    end
                end
            end
        end
    end

    if not C_TradeSkillUI or not C_TradeSkillUI.IsTradeSkillReady or not C_TradeSkillUI.IsTradeSkillReady() then
        -- On first open the skill may not be ready yet; queue a retry.
        if not fromRetry then self._qmRecipeScanRetries = 0 end
        self:_ScheduleProfessionRecipeScanRetry()
        return false
    end

    local ok, updated = pcall(function()
        local baseInfo = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo() or nil
        if not baseInfo or not baseInfo.professionID then
            self:_ScheduleProfessionRecipeScanRetry()
            return false
        end

        -- Ignore Fishing/Archaeology entirely (Cooking is allowed).
        if IsIgnoredProfessionID(baseInfo.professionID) then
            return false
        end

        local key = GetPlayerKey()
        if not key then return false end

        local store = EnsureCharStore(self.db, key)
        if not store then return false end

        local nameStore = EnsureGlobalRecipeNameStore(self.db)
        local itemStore = EnsureGlobalRecipeItemStore(self.db)

        -- Current open skill line (this might be the "child" expansion skill line depending on UI state)
        local skillLineID = tonumber(baseInfo.professionID)
        if not skillLineID then return false end

        local recipeIDs
        if C_TradeSkillUI.GetAllRecipeIDs then
            recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
        elseif C_TradeSkillUI.GetFilteredRecipeIDs then
            recipeIDs = C_TradeSkillUI.GetFilteredRecipeIDs()
        end

        if type(recipeIDs) ~= "table" or #recipeIDs == 0 then
            -- Data sometimes arrives a tick after TRADE_SKILL_SHOW; retry a few times.
            self:_ScheduleProfessionRecipeScanRetry()
            return false
        end
        -- Guard: when swapping professions, TRADE_SKILL events can fire before the underlying
        -- recipe list has fully switched over. In that case, GetAllRecipeIDs() may still return
        -- the *previous* profession's recipe list for a short window.
        --
        -- Additionally, GetAllRecipeIDs() can include recipes you *don't* know (depending on UI/state).
        -- We only persist *known/learned* recipes to keep counts meaningful and stable.

        local learned = {}
        if C_TradeSkillUI.GetRecipeInfo then
            for i = 1, #recipeIDs do
                local rid = recipeIDs[i]
                if rid then
                    local okInfo, info = pcall(C_TradeSkillUI.GetRecipeInfo, rid)
                    if okInfo and type(info) == "table" and info.learned then
                        learned[#learned + 1] = rid
                    end
                end
            end
        else
            -- If we can't introspect learned state, fall back to whatever the UI returns.
            learned = recipeIDs
        end

        if #learned == 0 then
            -- Often indicates the list isn't ready yet on first open.
            if not fromRetry then self._qmRecipeScanRetries = 0 end
            self:_ScheduleProfessionRecipeScanRetry()
            return false
        end

        local compact = SortedUniqueNumericArray(learned)

        -- Build a cheap signature for stability checks (count + first/last after sort).
        local firstID = compact[1]
        local lastID  = compact[#compact]
        local sig = tostring(#compact) .. ":" .. tostring(firstID) .. ":" .. tostring(lastID)

        -- If we just switched professions, require the list to be stable across at least 2 observations
        -- before committing to SavedVariables. This avoids "previous profession count" bleed-through.
        if self._qmPendingProfessionID ~= skillLineID then
            self._qmPendingProfessionID = skillLineID
            self._qmPendingRecipeSig = sig
            self._qmPendingRecipeSigCount = 1
            if not fromRetry then self._qmRecipeScanRetries = 0 end
            self:_ScheduleProfessionRecipeScanRetry()
            return false
        end

        if self._qmPendingRecipeSig ~= sig then
            self._qmPendingRecipeSig = sig
            self._qmPendingRecipeSigCount = 1
            if not fromRetry then self._qmRecipeScanRetries = 0 end
            self:_ScheduleProfessionRecipeScanRetry()
            return false
        end

        self._qmPendingRecipeSigCount = (self._qmPendingRecipeSigCount or 0) + 1
        if self._qmPendingRecipeSigCount < 2 then
            if not fromRetry then self._qmRecipeScanRetries = 0 end
            self:_ScheduleProfessionRecipeScanRetry()
            return false
        end

        -- Extra safety: if we already have data for this profession on this character and the new count
        -- is wildly different, require stability (above) and only then overwrite.
        local existing = store[skillLineID]
        if existing and type(existing.recipes) == "table" then
            local oldCount = #existing.recipes
            local newCount = #compact
            if oldCount > 0 and (newCount > oldCount + 500 or newCount + 500 < oldCount) then
                -- Don't immediately overwrite with an extreme jump; wait for another stable pass.
                self._qmPendingRecipeSigCount = 1
                if not fromRetry then self._qmRecipeScanRetries = 0 end
                self:_ScheduleProfessionRecipeScanRetry()
                return false
            end
        end

        -- Cache recipe names globally (only for scanned recipeIDs)
        if (nameStore or itemStore) and (C_TradeSkillUI.GetRecipeInfo or C_TradeSkillUI.GetRecipeOutputItemData) then
            for i = 1, #compact do
                local rid = compact[i]
                if rid then
                    -- Name
                    if nameStore and nameStore[rid] == nil and C_TradeSkillUI.GetRecipeInfo then
                        local okInfo, info = pcall(C_TradeSkillUI.GetRecipeInfo, rid)
                        if okInfo and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
                            nameStore[rid] = info.name
                        else
                            -- store false so we don't repeatedly try during scan
                            nameStore[rid] = false
                        end
                    end

                    -- Output item (best-effort). Stored as itemID if we can resolve it while the profession is open.
                    if itemStore and itemStore[rid] == nil and C_TradeSkillUI.GetRecipeOutputItemData then
                        local okOut, out = pcall(C_TradeSkillUI.GetRecipeOutputItemData, rid)
                        if okOut then
                            local itemID
                            if type(out) == "number" then
                                itemID = out
                            elseif type(out) == "table" then
                                itemID = tonumber(out.itemID or out.id)
                            end
                            if itemID and itemID > 0 then
                                itemStore[rid] = itemID
                            else
                                itemStore[rid] = false
                            end
                        else
                            itemStore[rid] = false
                        end
                    end
                end
            end
        end
        local existingArr = existing and existing.recipes

        if ArraysEqual(existingArr, compact) then
            -- Update timestamp only (keeps UI "last scanned" accurate) without rewriting large arrays
            if existing then
                existing.lastScan = time()
                existing.professionName = baseInfo.professionName or existing.professionName
            end
            return false
        end

        store[skillLineID] = {
            professionName = baseInfo.professionName,
            lastScan = time(),
            recipes = compact,
        }

        -- Record last observed list signature to help detect stale lists during profession swaps.
        self._qmLastObservedProfessionID = skillLineID
        self._qmLastObservedRecipeSig = sig

        return true
    end)

    if not ok then
        return false
    end

    return updated == true
end

--[[
    Query cached recipes across all scanned characters.
    Returns an array of matches:
      { recipeID=number, name=string, crafters={ "Char-Realm", ... } }
]]
function TheQuartermaster:FindRecipeCraftersByName(query)
    query = tostring(query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return {} end

    local chars = self.db and self.db.global and self.db.global.characters
    if type(chars) ~= "table" then return {} end

    local matches = {} -- [recipeID] = {recipeID,name,crafters}

    local nameStore = self.db and self.db.global and self.db.global.recipeNames
    local itemStore = self.db and self.db.global and self.db.global.recipeOutputItems
    local function GetRecipeName(recipeID)
        recipeID = tonumber(recipeID)
        if not recipeID then return nil end
        if type(nameStore) == "table" then
            local v = nameStore[recipeID]
            if type(v) == "string" and v ~= "" then
                return v
            end
        end
        return nil
    end

    local function GetRecipeItemID(recipeID)
        recipeID = tonumber(recipeID)
        if not recipeID then return nil end
        if type(itemStore) == "table" then
            local v = itemStore[recipeID]
            if type(v) == "number" and v > 0 then
                return v
            end
        end
        return nil
    end

    for charKey, charData in pairs(chars) do
        local profStore = charData and charData.professionRecipes
        if type(profStore) == "table" then
            for skillLineID, entry in pairs(profStore) do
                -- Never show ignored professions in results.
                -- Note: WoW's Lua does not support 'goto', so we use a simple guard.
                if not IsIgnoredProfessionID(skillLineID) then
                    local arr = entry and entry.recipes
                    if type(arr) == "table" then
                        for i = 1, #arr do
                            local recipeID = arr[i]
                            local name = GetRecipeName(recipeID)
                            if name then
                                if tostring(name):lower():find(query, 1, true) then
                                    local m = matches[recipeID]
                                    if not m then
                                        m = { recipeID = recipeID, name = name, itemID = GetRecipeItemID(recipeID), crafters = {} }
                                        matches[recipeID] = m
                                    end
                                    m.crafters[#m.crafters + 1] = charKey
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local out = {}
    for _, v in pairs(matches) do
        table.sort(v.crafters)
        out[#out + 1] = v
    end

    table.sort(out, function(a, b)
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)

    return out
end

--[[
    Clear cached profession recipes.
    @param charKey string|nil - "Name-Realm". If nil, clears current player.
    @return boolean - true if something was cleared
]]
function TheQuartermaster:ClearProfessionRecipeCache(charKey)
    if not self.db or not self.db.global or not self.db.global.characters then
        return false
    end

    if not charKey or charKey == "" then
        charKey = GetPlayerKey()
    end
    if not charKey then return false end

    local c = self.db.global.characters[charKey]
    if not c or type(c) ~= "table" then
        return false
    end

    if c.professionRecipes then
        c.professionRecipes = nil
        return true
    end
    return false
end

-- Clear all cached recipe data for all characters
function TheQuartermaster:ClearAllProfessionRecipeCaches()
    if not self.db or not self.db.global or not self.db.global.characters then
        return 0
    end
    local n = 0
    for _, c in pairs(self.db.global.characters) do
        if type(c) == "table" and c.professionRecipes then
            c.professionRecipes = nil
            n = n + 1
        end
    end
    return n
end
