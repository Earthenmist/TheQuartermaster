--[[
    The Quartermaster - Profession Recipes (Option A)
    Stores *known* recipeIDs per character for the currently-open profession skill line.

    Design goals:
      - Keep SavedVariables small: store recipeIDs as a sorted numeric array (not a hash table).
      - Learning details live in the separate profession-depth snapshot.
      - No forced switching between expansion skill lines. We cache whatever the user has open.

    Usage:
      - Enable "Track Profession Recipes" in settings.
      - Log into a crafter, open their profession window, and the addon will cache recipes.
      - Query via: /tq recipes <text>
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

local function IsIgnoredProfessionID(id)
    return not ns.IsTrackedRecipeProfession(id)
end
local function GetPlayerKey()
    return TheQuartermaster:GetCharacterKey()
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


local function ReportScan(addon, state, changed)
    local previous = addon.recipeScanState
    addon.recipeScanState = state
    local frame = addon.UI and addon.UI.mainFrame
    if (previous ~= state or changed) and frame and frame:IsShown() and frame.currentTab == "recipes"
        and addon.RefreshUI then addon:RefreshUI() end
end

-- A single bounded retry chain; stale callbacks cannot restart after completion.
function TheQuartermaster:_ScheduleProfessionRecipeScanRetry()
    if not (self.db and self.db.profile and self.db.profile.trackProfessionRecipes) then return end
    if self._qmRecipeRetryPending then return end
    if (self._qmRecipeScanRetries or 0) >= 6 or not (C_Timer and C_Timer.After) then
        ReportScan(self, "unavailable")
        return
    end
    self._qmRecipeScanRetries = (self._qmRecipeScanRetries or 0) + 1
    local token = {}
    self._qmRecipeRetryPending = token
    ReportScan(self, "waiting")
    -- Keep six attempts, but allow delayed client metadata to arrive (15.75s).
    C_Timer.After(0.25 * 2 ^ (self._qmRecipeScanRetries - 1), function()
        if self._qmRecipeRetryPending ~= token then return end
        self._qmRecipeRetryPending = nil
        self:ScanProfessionRecipes(true)
    end)
end

--[[
    Scan and persist recipes for the currently-open profession (current skillLineID).
    @return boolean - true if SavedVariables were updated
]]
function TheQuartermaster:ScanProfessionRecipes(fromRetry)
    self.recipeScanDiagnostic = {reason = "starting"}
    local diagnostic = self.recipeScanDiagnostic
    if not self.db or not self.db.profile or not self.db.profile.trackProfessionRecipes then
        self._qmRecipeRetryPending = nil
        ReportScan(self, nil)
        return false
    end
    if not fromRetry and not self._qmRecipeRetryPending then self._qmRecipeScanRetries = 0 end

    local readyOK, ready = pcall(function()
        return C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillReady and C_TradeSkillUI.IsTradeSkillReady()
    end)
    if not readyOK or (issecretvalue and issecretvalue(ready)) or ready ~= true then
        diagnostic.reason = "profession-not-ready"
        -- On first open the skill may not be ready yet; queue a retry.
        self:_ScheduleProfessionRecipeScanRetry()
        return false
    end

    local contextOK, context = pcall(ns.GetOwnedRecipeContext, self)
    if not contextOK or not context then
        diagnostic.reason = "ownership-context-unavailable"
        self._qmPendingProfessionID = nil
        self._qmPendingRecipeSig = nil
        self._qmRecipeRetryPending = nil
        ReportScan(self, "unavailable")
        return false
    end

    diagnostic.profession = context.id

    if not ns.SameRecipeContext(self._qmRecipeScanContext, context) then
        self._qmRecipeScanContext = context
        self._qmRecipeRetryPending = nil
        self._qmRecipeScanRetries = 0
        self._qmPendingProfessionID = nil
        self._qmPendingRecipeSig = nil
        if self.StopRecipeIngredientScan then self:StopRecipeIngredientScan() end
        self.recipeIngredientScanStatus = nil
        self.recipeIngredientLastPass = nil
    end

    local complete, loading = false, false
    local ok, updated = pcall(function()
        local baseInfo = context.info
        if not baseInfo or not baseInfo.professionID then
            self:_ScheduleProfessionRecipeScanRetry()
            return false
        end

        -- Ignore Fishing/Archaeology entirely (Cooking is allowed).
        if IsIgnoredProfessionID(baseInfo.professionID) then
            return false
        end

        local key = context.key
        if not key then return false end

        local store = EnsureCharStore(self.db, key)
        if not store then return false end

        local nameStore = EnsureGlobalRecipeNameStore(self.db)
        local itemStore = EnsureGlobalRecipeItemStore(self.db)

        -- Current open skill line (this might be the "child" expansion skill line depending on UI state)
        local skillLineID = tonumber(baseInfo.professionID)
        if not skillLineID then return false end

        -- A filtered list cannot establish a complete learned snapshot.
        local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetAllRecipeIDs()

        if type(recipeIDs) ~= "table" or #recipeIDs == 0 then
            diagnostic.reason = "recipe-list-unavailable"
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
                    if issecretvalue and issecretvalue(rid) then return false end
                    diagnostic.recipe = type(rid) == "number" and rid or nil
                    local okInfo, info = pcall(C_TradeSkillUI.GetRecipeInfo, rid)
                    diagnostic.reason = "recipe-info-unavailable"
                    if not okInfo or type(info) ~= "table" then loading = true; return false end
                    if issecretvalue and issecretvalue(info.learned) then return false end
                    if info.learned then
                        diagnostic.reason = "profession-metadata-unavailable"
                        local professionOK, profession = pcall(function()
                            return C_TradeSkillUI.GetProfessionInfoByRecipeID and C_TradeSkillUI.GetProfessionInfoByRecipeID(rid)
                        end)
                        if not professionOK or not profession then loading = true; return false end
                        local rootID = ns.GetRecipeProfessionRoot(profession)
                        diagnostic.root = rootID
                        diagnostic.reason = "profession-root-mismatch-or-unavailable"
                        if rootID ~= skillLineID then loading = true; return false end
                        learned[#learned + 1] = rid
                    end
                end
            end
        else
            return false -- Learned state must be available.
        end

        if #learned == 0 then
            diagnostic.reason = "learned-list-empty"
            -- Often indicates the list isn't ready yet on first open.
            self:_ScheduleProfessionRecipeScanRetry()
            return false
        end

        local compact = SortedUniqueNumericArray(learned)

        -- Compare the exact list and source, including changes within one profession.
        local sig = tostring(context.source) .. ":" .. table.concat(compact, ",")
        diagnostic.reason = "list-stabilising"

        -- If we just switched professions, require the list to be stable across at least 2 observations
        -- before committing to SavedVariables. This avoids "previous profession count" bleed-through.
        if self._qmPendingProfessionID ~= skillLineID then
            self._qmPendingProfessionID = skillLineID
            self._qmPendingRecipeSig = sig
            self._qmPendingRecipeSigCount = 1
            self:_ScheduleProfessionRecipeScanRetry()
            return false
        end

        if self._qmPendingRecipeSig ~= sig then
            self._qmPendingRecipeSig = sig
            self._qmPendingRecipeSigCount = 1
            self:_ScheduleProfessionRecipeScanRetry()
            return false
        end

        self._qmPendingRecipeSigCount = (self._qmPendingRecipeSigCount or 0) + 1
        if self._qmPendingRecipeSigCount < 2 then
            self:_ScheduleProfessionRecipeScanRetry()
            return false
        end

        local existing = store[skillLineID]
        if not ns.SameRecipeContext(context, ns.GetOwnedRecipeContext(self)) then return false end
        if existing and not existing.ownerVerified then
            local char = self.db.global.characters[key]
            char.professionRecipeRecovery = char.professionRecipeRecovery or {}
            if not char.professionRecipeRecovery[skillLineID] then
                local backup = {}
                for field, value in pairs(existing) do
                    if type(value) == "table" then
                        backup[field] = {}; for k, v in pairs(value) do backup[field][k] = v end
                    else backup[field] = value end
                end
                char.professionRecipeRecovery[skillLineID] = backup
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
        complete = true
        local existingArr = existing and existing.recipes

        if ArraysEqual(existingArr, compact) then
            -- Update timestamp only (keeps UI "last scanned" accurate) without rewriting large arrays
            local wasVerified = existing and existing.ownerVerified
            if existing then
                existing.ownerVerified = true
                existing.lastScan = time()
                existing.professionName = baseInfo.professionName or existing.professionName
            end
            return not wasVerified
        end

        store[skillLineID] = {
            ingredients = existing and existing.ownerVerified and existing.ingredients or nil,
            ownerVerified = true,
            professionName = baseInfo.professionName,
            lastScan = time(),
            recipes = compact,
        }

        -- Record last observed list signature to help detect stale lists during profession swaps.
        self._qmLastObservedProfessionID = skillLineID
        self._qmLastObservedRecipeSig = sig

        return true
    end)

    if ok and complete then
        diagnostic.reason, diagnostic.recipe, diagnostic.root = "complete", nil, nil
        self._qmRecipeRetryPending = nil
        self._qmRecipeScanRetries = 0
        ReportScan(self, "complete", updated == true)
        if self.StartRecipeIngredientScan then self:StartRecipeIngredientScan(context) end
        if self.ScanProfessionDepth and not self._professionDepthJob then self:ScanProfessionDepth() end
    elseif ok and loading then
        -- Profession metadata and recipe lists can become ready on different ticks.
        -- Reject the partial snapshot, but keep the bounded retry chain alive.
        self:_ScheduleProfessionRecipeScanRetry()
    elseif not self._qmRecipeRetryPending then
        if not ok then diagnostic.reason = "api-call-failed:" .. diagnostic.reason end
        ReportScan(self, "unavailable")
    end
    return ok and updated == true
end

function TheQuartermaster:PrintRecipeScanDiagnostic()
    local d = self.recipeScanDiagnostic or {}
    self:Print(string.format(ns.L.RS_DIAGNOSTIC, self.recipeScanState or "idle", d.reason or "none",
        d.profession or 0, d.recipe or 0, d.root or 0, self._qmRecipeScanRetries or 0))
end

--[[
    Query cached recipes across all scanned characters.
    Returns an array of matches:
      { recipeID=number, name=string, crafters={ "Char-Realm", ... } }
]]
function TheQuartermaster:FindRecipeCraftersByName(query, options)
    options = options or {}
    query = tostring(query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" and not options.browse then return {} end

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
                if not IsIgnoredProfessionID(skillLineID) and entry and entry.ownerVerified
                    and (not options.professionID or tonumber(skillLineID) == options.professionID)
                    and (not options.charKey or charKey == options.charKey) then
                    local arr = entry and entry.recipes
                    if type(arr) == "table" then
                        for i = 1, #arr do
                            local recipeID = arr[i]
                            local name = GetRecipeName(recipeID)
                            if not name and options.browse then name = string.format(ns.L["RB_UNNAMED"], recipeID) end
                            if name then
                                if tostring(name):lower():find(query, 1, true) then
                                    local m = matches[recipeID]
                                    if not m then
                                        m = { recipeID = recipeID, name = name, itemID = GetRecipeItemID(recipeID), crafters = {}, sources = {}, seen = {} }
                                        matches[recipeID] = m
                                    end
                                    if not m.seen[charKey] then
                                        m.seen[charKey] = true
                                        m.crafters[#m.crafters + 1] = charKey
                                        m.sources[charKey] = entry.lastScan
                                    end
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
        v.seen = nil
        v.crafters = ns.SortCharacterRows(self.db, v.crafters, function(key) return key end)
        out[#out + 1] = v
    end

    table.sort(out, function(a, b)
        if tostring(a.name):lower() == tostring(b.name):lower() then return a.recipeID < b.recipeID end
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

    if c.professionRecipes or c.professionRecipeDetails then
        self._professionDepthJob = nil
        c.professionRecipeDetails = nil
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
        if type(c) == "table" and (c.professionRecipes or c.professionRecipeDetails) then
            self._professionDepthJob = nil
            c.professionRecipeDetails = nil
            c.professionRecipes = nil
            n = n + 1
        end
    end
    return n
end
