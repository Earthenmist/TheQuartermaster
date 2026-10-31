-- Additional profession snapshots never alter the verified learned crafting cache.
local _, ns = ...
local Addon, W = ns.TheQuartermaster, ns.Wealth
local function Read(fn, ...)
    local values = W.Read(fn, ...)
    return values and values[1]
end
local function Context(addon)
    if InCombatLockdown and InCombatLockdown() then return nil end
    if not (addon.db and addon.db.profile.trackProfessionRecipes) then return nil end
    return Read(ns.GetOwnedRecipeContext, addon)
end
local function Signature(ids)
    if type(ids) ~= "table" or #ids == 0 or #ids > 20000 then return nil end
    local sorted, seen = {}, {}
    for _, id in ipairs(ids) do
        if not W.Number(id) or id <= 0 or id ~= math.floor(id) then return nil end
        if not seen[id] then sorted[#sorted + 1], seen[id] = id, true end
    end
    table.sort(sorted)
    return table.concat(sorted, ","), sorted
end
local function Refresh(addon)
    local frame = addon.UI and addon.UI.mainFrame
    local editor = addon.recipeCraftEditor
    if frame and frame.currentTab == "recipes" and editor and editor.HasFocus and editor:HasFocus() then return end
    if frame and frame:IsShown() and (frame.currentTab == "recipes" or frame.currentTab == "concentration" or frame.currentTab == "cooldowns" or frame.currentTab == "knowledge") then addon:RefreshUI() end
end

function Addon:ScanProfessionDepth()
    local context = Context(self)
    if not context then self.professionDepthState = "unavailable"; Refresh(self); return end
    local api = C_TradeSkillUI
    local ids = Read(api.GetAllRecipeIDs)
    self:ScanConcentration(context)
    local signature, uniqueIDs = Signature(ids)
    if not signature then self.professionDepthState = "invalidList"; Refresh(self); return end
    ids = uniqueIDs
    local token, index, rows = {}, 1, {}
    local cooldownRows = {}
    local oldDetails = (self.db.global.characters[context.key].professionRecipeDetails or {})[context.id]
    if oldDetails and oldDetails.version~=1 then self.professionDepthState="unavailable";Refresh(self);return end
    local retries, missing, learnedSkills = {}, {}, {}
    self.professionDepthMissing=nil
    local oldCooldowns = (self.db.global.characters[context.key].professionCooldowns or {})[context.id]
    local cooldownSupported = type(api.GetRecipeCooldown) == "function" and (not oldCooldowns or oldCooldowns.version == 1)
    self._professionDepthJob = token
    self.professionDepthState = "scanning"
    local function Step()
        if self._professionDepthJob ~= token then return end
        if not ns.SameRecipeContext(context, Context(self)) then
            self._professionDepthJob = nil; self.professionDepthState = "contextChanged"; Refresh(self); return
        end
        for _ = 1, 30 do
            local id = ids[index]
            if not id then break end
            local info = Read(api.GetRecipeInfo, id)
            local profession = Read(api.GetProfessionInfoByRecipeID, id)
            if not info or type(info.learned) ~= "boolean" or type(info.name) ~= "string"
                or Read(ns.GetRecipeProfessionRoot, profession) ~= context.id then
                retries[id]=(retries[id] or 0)+1
                if retries[id]<=2 then C_Timer.After(0.2,Step);return end
                missing[#missing+1]=id
                -- Carry old observations without assigning them a fresh timestamp.
                if oldDetails and oldDetails.rows then rows[id]=oldDetails.rows[id] end
                if oldCooldowns and oldCooldowns.version==1 and oldCooldowns.rows then cooldownRows[id]=oldCooldowns.rows[id] end
            else
            if info.learned and W.Number(profession.professionID) then learnedSkills[profession.professionID]=profession end
            local source = not info.learned and Read(api.GetRecipeSourceText, id) or nil
            rows[id] = {name = info.name, learned = info.learned,
                firstCraft = type(info.firstCraft) == "boolean" and info.firstCraft or nil,
                expansion = type(profession.expansionName) == "string" and profession.expansionName or "",
                skillLineID = profession.professionID,
                source = type(source) == "string" and source ~= "" and source or nil}
            if cooldownSupported and info.learned then
                cooldownRows[id] = ns.ReadRecipeCooldown(id, rows[id], oldCooldowns and oldCooldowns.rows[id])
            end
            end
            index = index + 1
        end
        if index <= #ids then C_Timer.After(0.05, Step); return end
        if not ns.SameRecipeContext(context, Context(self)) then
            self._professionDepthJob = nil; self.professionDepthState = "contextChanged"; Refresh(self); return
        end
        if Signature(Read(api.GetAllRecipeIDs)) ~= signature then
            self._professionDepthJob = nil; self.professionDepthState = "listChanged"; Refresh(self); return
        end
        local char = self.db.global.characters[context.key]
        if not char then return end
        char.professionRecipeDetails = char.professionRecipeDetails or {}
        local old = char.professionRecipeDetails[context.id]
        if old and old.version ~= 1 then
            self._professionDepthJob = nil; self.professionDepthState = "unavailable"; Refresh(self); return
        end
        char.professionRecipeDetails[context.id] = {version = 1,
            checked = #missing==0 and time() or oldDetails and oldDetails.checked,
            attempted = time(), partial = #missing>0 or nil, missing = missing, rows = rows,
            professionName = context.info.professionName}
        if cooldownSupported then
            char.professionCooldowns = char.professionCooldowns or {}
            local checked=time()
            for _, observation in pairs(cooldownRows) do checked=math.min(checked,observation.checked) end
            char.professionCooldowns[context.id] = {version=1,checked=checked,rows=cooldownRows,partial=#missing>0 or nil,
                professionName=context.info.professionName}
        end
        self:ScanConcentration(context,learnedSkills)
        self.professionDepthMissing=#missing>0 and {count=#missing,id=missing[1]} or nil
        self._professionDepthJob = nil; self.professionDepthState = #missing>0 and "partial" or "complete"; Refresh(self)
    end
    C_Timer.After(0.05, Step)
end

function Addon:ScanConcentration(context, learnedSkills)
    context = context or Context(self)
    if not context then return end
    local char = self.db.global.characters[context.key]
    if not char then return end
    local api = C_TradeSkillUI
    local infos = Read(api.GetChildProfessionInfos) or {}
    local current = Read(api.GetChildProfessionInfo)
    if current then infos[#infos + 1] = current end
    -- A learned recipe with a resolved owner root also proves its expansion skill.
    -- Some child-profession listings omit that skill or its skillLevel on first open.
    for _,info in pairs(learnedSkills or {}) do infos[#infos+1]=info end
    local pools = {}
    for _, info in ipairs(infos) do
        if Read(ns.GetRecipeProfessionRoot, info) == context.id
            and ((W.Number(info.skillLevel) and info.skillLevel > 0) or (learnedSkills and learnedSkills[info.professionID])) then
            local currency = Read(api.GetConcentrationCurrencyID, info.professionID)
            if W.Number(currency) and currency > 0 then
                local pool = pools[currency] or {version = 1, professionID = context.id,
                    professionName = context.info.professionName, expansions = {}, skillLines = {}}
                pools[currency] = pool
                pool.skillLines[info.professionID] = true
                if type(info.expansionName) == "string" and info.expansionName ~= "" then pool.expansions[info.expansionName] = true end
            end
        end
    end
    local updated = false
    for currency, pool in pairs(pools) do
        local info = Read(C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo, currency)
        if info and W.Number(info.quantity) and info.quantity >= 0 and W.Number(info.maxQuantity) and info.maxQuantity > 0 then
            pool.amount, pool.cap, pool.checked, pool.icon = info.quantity, info.maxQuantity, time(), info.iconFileID
            if W.Number(info.rechargingCycleDurationMS) and info.rechargingCycleDurationMS > 0
                and W.Number(info.rechargingAmountPerCycle) and info.rechargingAmountPerCycle > 0 then
                pool.rate = info.rechargingAmountPerCycle / (info.rechargingCycleDurationMS / 1000)
            end
            if ns.SameRecipeContext(context, Context(self)) then
                char.professionConcentration = char.professionConcentration or {}
                local old = char.professionConcentration[currency]
                if not old or old.version == 1 then char.professionConcentration[currency] = pool; updated = true end
            end
        end
    end
    return updated
end

function ns.ConcentrationEstimate(pool, now)
    if pool.version ~= 1 or not W.Number(pool.amount) or not W.Number(pool.cap) or pool.cap <= 0
        or not W.Number(pool.checked) or now < pool.checked then return nil end
    local elapsed = now - pool.checked
    local rate = W.Number(pool.rate) and pool.rate > 0 and pool.rate or nil
    local amount = math.min(pool.cap, math.max(0, pool.amount + (rate and elapsed * rate or 0)))
    return {amount = math.floor(amount), cap = pool.cap, estimated = elapsed > 5,
        remaining = rate and math.ceil(math.max(0, pool.cap - amount) / rate) or nil,
        rateKnown = rate ~= nil}
end

function Addon:FindProfessionRecipes(query, options)
    options = options or {}
    local known = self:FindRecipeCraftersByName(query, {browse = true, professionID = options.professionID})
    local byID, selectedKnown = {}, {}
    for _, row in ipairs(known) do
        byID[row.recipeID] = row
        row.missing, row.learning = {}, {}
        if not options.charKey then selectedKnown[row.recipeID] = #row.crafters > 0
        else for _, key in ipairs(row.crafters) do if key == options.charKey then selectedKnown[row.recipeID] = true end end end
    end
    query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local observed, expansionMatch = {}, {}
    for key, char in pairs(self.db.global.characters or {}) do
        for root, snapshot in pairs(char.professionRecipeDetails or {}) do
            if snapshot.version == 1 and (not options.professionID or root == options.professionID) then
                for id, detail in pairs(snapshot.rows) do
                    if detail.name:lower():find(query, 1, true) then
                        local row = byID[id]
                        if not row then
                            row = {recipeID = id, name = detail.name, crafters = {}, sources = {}, missing = {}, learning = {}}
                            byID[id] = row
                        end
                        -- A new detail scan supersedes an older learned cache for this character.
                        for i = #row.crafters, 1, -1 do if row.crafters[i] == key then table.remove(row.crafters, i) end end
                        if detail.learned then row.crafters[#row.crafters + 1] = key else row.missing[#row.missing + 1] = key end
                        row.sources[key] = snapshot.checked
                        if detail.source then row.learning[key] = detail.source end
                        if not options.charKey or options.charKey == key then
                            observed[id] = true
                            if not options.expansion or options.expansion == detail.expansion then
                                expansionMatch[id] = true
                                if options.charKey then selectedKnown[id] = detail.learned end
                            end
                        end
                    end
                end
            end
        end
    end
    local result = {}
    for id, row in pairs(byID) do
        local learned = options.charKey and selectedKnown[id] or (not options.charKey and #row.crafters > 0)
        local missing = observed[id] and not learned
        if (not options.expansion or expansionMatch[id]) and
            ((options.mode == "unlearned" and missing) or (options.mode == "all" and (learned or observed[id]))
                or ((not options.mode or options.mode == "learned") and learned)) then
            table.sort(row.crafters); table.sort(row.missing)
            row.selectedLearned = learned
            result[#result + 1] = row
        end
    end
    table.sort(result, function(a, b) if a.name == b.name then return a.recipeID < b.recipeID end return a.name:lower() < b.name:lower() end)
    return result
end

function Addon:InitializeProfessionDepth()
    local frame = self.professionDepthEvents or CreateFrame("Frame")
    self.professionDepthEvents = frame
    for _, event in ipairs({"TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_CLOSE", "CURRENCY_DISPLAY_UPDATE", "PLAYER_REGEN_DISABLED"}) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent", function(_, event)
        if event == "TRADE_SKILL_CLOSE" or event == "PLAYER_REGEN_DISABLED" then
            self._professionDepthJob, self._professionDepthPending = nil, nil
            if self.professionDepthState == "scanning" then self.professionDepthState = "interrupted" end
            return
        end
        if event == "CURRENCY_DISPLAY_UPDATE" then
            if self._concentrationPending then return end
            self._concentrationPending = true
            C_Timer.After(0.5, function()
                self._concentrationPending = nil
                if self._professionDepthEnabled and self:ScanConcentration() then
                    local main = self.UI and self.UI.mainFrame
                    if main and main.currentTab == "concentration" then Refresh(self) end
                end
            end)
            return
        end
        self._professionDepthJob = nil
        if self._professionDepthPending then return end
        local token = {}; self._professionDepthPending = token
        C_Timer.After(0.5, function()
            if self._professionDepthPending ~= token then return end
            self._professionDepthPending = nil; self:ScanProfessionDepth()
        end)
    end)
    self._professionDepthEnabled = true
end
function Addon:StopProfessionDepth()
    if self.professionDepthEvents then self.professionDepthEvents:UnregisterAllEvents() end
    self._professionDepthJob, self._professionDepthPending, self._professionDepthEnabled = nil, nil, nil
end
