-- Knowledge observations are character/expansion scoped; source rules never imply availability.
local _, ns = ...
local Addon, W, Data = ns.TheQuartermaster, ns.Wealth, ns.KnowledgeData
local K = {}; ns.Knowledge = K
local function Read(fn, ...)
    local result = W.Read(fn, ...)
    if result then return result[1] end
end
local function Count(value) return W.Number(value) and value >= 0 and value == math.floor(value) end
local function Enabled(addon)
    return addon.db and addon.db.profile.trackProfessionRecipes and not (InCombatLockdown and InCombatLockdown())
end
local function Refresh(addon)
    local frame = addon.UI and addon.UI.mainFrame
    if frame and frame:IsShown() and frame.currentTab == "knowledge" then addon:RefreshUI() end
end
local function OwnedRoots()
    local slots = W.Read(GetProfessions)
    if not slots then return {} end
    local roots = {}
    for _, slot in pairs(slots) do
        local info = W.Read(GetProfessionInfo, slot)
        if info and Count(info[7]) then roots[info[7]] = true end
    end
    return roots
end
local bySkill, sources, sourceByID = {}, {}, {}
for _, profile in ipairs(Data.professions) do bySkill[profile.skill] = profile; sources[profile.skill] = {} end
for _, source in ipairs(Data.sources) do
    local list = sources[source.skill]; list[#list + 1] = source; sourceByID[source.id]=source
end
K.profiles, K.sources = bySkill, sources

function K.CatchUpRemaining(profile, snapshot, now)
    if not profile or not profile.catchUpRule then return nil, "unverified" end
    local observation = snapshot and snapshot.catchup
    if not observation or not Count(observation.used) or not Count(observation.cap)
        or (observation.basis ~= "quantity" and observation.basis ~= "totalEarned")
        or not Count(observation.checked) or observation.checked > now then return nil, "unknown" end
    if not Count(observation.resetAt) or now >= observation.resetAt then return nil, "stale" end
    local missing=0
    for _,id in ipairs(profile.catchUpSources or {}) do
        local source=sourceByID[id]
        local state,done=K.SourceState(source,snapshot,now)
        if state=="unknown" or state=="stale" or state=="unverified" then return nil,state end
        local left=source.completion=="any" and (state=="complete" and 0 or 1) or source.cap-(done or 0)
        missing=missing+left*source.points
    end
    local remaining=math.max(0, observation.cap - observation.used - missing)
    return remaining, missing>0 and "weeklyRequired" or "remaining"
end

-- Deduplicate shared completion mechanisms, including first-craft aliases.
function K.SourceState(source, snapshot, now)
    if source.category == "catch_up" and bySkill[source.skill] and bySkill[source.skill].catchUpRule then
        local remaining, state = K.CatchUpRemaining(bySkill[source.skill], snapshot, now)
        if remaining == 0 and state=="remaining" then return "complete", 0 end
        return state, remaining
    end
    if source.completion == "none" then return "unverified" end
    local flags = snapshot and snapshot.flags
    if not flags or not Count(flags.checked) or flags.checked > now or snapshot.revision ~= Data.revision then return "unknown" end
    if source.reset == "weekly" and (not Count(flags.resetAt) or now >= flags.resetAt) then return "stale" end
    -- Darkmoon flags are observations; a calendar month is not the Faire reset.
    if source.reset == "observed" and now - flags.checked > 60 then return "stale" end
    local done = 0
    for _, quest in ipairs(source.quests) do
        if type(flags.values[quest]) ~= "boolean" then return "unknown" end
        if flags.values[quest] then done = done + 1 end
    end
    local complete = source.completion == "any" and done > 0 or source.completion == "each" and done == #source.quests
    if complete then return source.event == "loot" and "collected" or "complete", done end
    if source.minSkill and snapshot.skillLevel and snapshot.skillLevel < source.minSkill then return "locked", done end
    return "unchecked", done
end

function K.SourceCounts(profile, snapshot, now)
    local result, seen = {complete=0, tracked=0, unverified=0}, {}
    for _, source in ipairs(sources[profile.skill] or {}) do
        if not seen[source.shared] then
            seen[source.shared] = true
            local state = K.SourceState(source, snapshot, now)
            if state == "unverified" then result.unverified = result.unverified + 1
            elseif state ~= "stale" and state ~= "unknown" then
                result.tracked = result.tracked + 1
                if state == "complete" or state == "collected" then result.complete = result.complete + 1 end
            end
        end
    end
    return result
end

function K.FirstCraftRows(character, skill)
    local profile, rows, seen = bySkill[skill], {}, {}
    local snapshot = character.professionRecipeDetails and character.professionRecipeDetails[profile.root]
    if not snapshot or snapshot.version ~= 1 then return rows end
    local ids = {}; for id in pairs(snapshot.rows or {}) do ids[#ids + 1] = id end; table.sort(ids)
    for _, id in ipairs(ids) do
        local recipe = snapshot.rows[id]
        local mechanism = (Data.firstCrafts[skill] or {})[id]
        if recipe.skillLineID == skill and recipe.learned and recipe.firstCraft == true and mechanism and not seen[mechanism] then
            seen[mechanism] = true
            rows[#rows + 1] = {id=id, name=recipe.name, checked=snapshot.checked}
        end
    end
    table.sort(rows, function(a,b) if a.name == b.name then return a.id < b.id end return a.name < b.name end)
    return rows
end

function Addon:GetKnowledgeProfiles()
    local result = {}
    for key, character in pairs(self.db.global.characters or {}) do
        for skill, snapshot in pairs(character.professionKnowledge or {}) do
            local profile = bySkill[skill]
            if profile and snapshot.version == 1 then
                result[#result + 1] = {key=key, character=character, profile=profile, snapshot=snapshot}
            end
        end
    end
    table.sort(result, function(a,b)
        if a.key ~= b.key then return a.key < b.key end
        if a.profile.expansion ~= b.profile.expansion then return a.profile.expansion < b.profile.expansion end
        return a.profile.name < b.profile.name
    end)
    return result
end

function Addon:ScanKnowledge()
    if not Enabled(self) then self.knowledgeState = "unavailable"; Refresh(self); return end
    local key = self:GetCharacterKey()
    local character = self.db.global.characters[key]
    if not character then return end
    local owned = OwnedRoots()
    local context = Read(ns.GetOwnedRecipeContext, self)
    local api, spec, traits = C_TradeSkillUI or {}, C_ProfSpecs or {}, C_Traits or {}
    for _, flag in ipairs({"IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting"}) do
        if Read(api[flag]) ~= false then self.knowledgeState="unavailable"; Refresh(self); return end
    end
    local infos = context and Read(api.GetChildProfessionInfos) or {}
    infos = infos or {}
    local current = context and Read(api.GetChildProfessionInfo)
    if current then infos[#infos + 1] = current end
    local learned = {}
    for _, info in ipairs(infos) do
        if bySkill[info.professionID] and owned[bySkill[info.professionID].root]
            and bySkill[info.professionID].root == context.id and Count(info.skillLevel) and info.skillLevel > 0 then
            learned[info.professionID] = info
        end
    end
    -- Quest/currency events may arrive with the profession closed. Refresh previously
    -- verified expansion skills only when the public API still confirms they are learned.
    for skill, old in pairs(character.professionKnowledge or {}) do
        local profile = bySkill[skill]
        if profile and owned[profile.root] and old.version == 1 and not learned[skill] then
            local info = Read(api.GetProfessionInfoBySkillLineID, skill)
            if info and Count(info.skillLevel) and info.skillLevel > 0 and info.professionID == skill then learned[skill] = info end
        end
    end
    local jobs, now = {}, time()
    for skill, info in pairs(learned) do
        local old = character.professionKnowledge and character.professionKnowledge[skill]
        if not old or old.version == 1 then
            local snapshot = {version=1, checked=now, revision=Data.revision, skillLevel=info.skillLevel,
                summary=old and old.summary, catchup=old and old.catchup}
            local seconds = Read(C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset)
            snapshot.flags = {checked=now, values={}, resetAt=Count(seconds) and seconds > 0 and seconds <= 604800 and now + seconds or nil}
            local job = {skill=skill, snapshot=snapshot, sourceIndex=1, queue={}, nodeIndex=1, seen={}, spent=0, capacity=0}
            if context and context.id == bySkill[skill].root then
                local currency = Read(spec.GetCurrencyInfoForSkillLine, skill)
                if currency and Count(currency.numAvailable) then
                    job.summary = {checked=now, unspent=currency.numAvailable}
                    local config = Read(spec.GetConfigIDForSkillLine, skill)
                    local tabs = Read(spec.GetSpecTabIDsForSkillLine, skill)
                    if Count(config) and config > 0 and Read(traits.ConfigHasStagedChanges, config) == true then job.summary = nil end
                    if Count(config) and config > 0 and type(tabs) == "table" and #tabs > 0 and #tabs <= 20
                        and Read(traits.ConfigHasStagedChanges, config) == false then
                        job.config, job.treeValid = config, true
                        for _, tab in ipairs(tabs) do
                            local tabInfo = Read(spec.GetTabInfo, tab)
                            if tabInfo and Count(tabInfo.rootNodeID) and tabInfo.rootNodeID > 0 then
                                job.queue[#job.queue + 1] = tabInfo.rootNodeID
                            else job.treeValid = false end
                        end
                    end
                end
            end
            local tracker = Read(C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo, bySkill[skill].tracker)
            if tracker and Count(tracker.maxQuantity) and tracker.maxQuantity >= 0 then
                local basis = type(tracker.useTotalEarnedForMaxQty) == "boolean"
                    and (tracker.useTotalEarnedForMaxQty and "totalEarned" or "quantity") or nil
                local used = basis and tracker[basis]
                if Count(used) then
                    snapshot.catchup = {checked=now, cap=tracker.maxQuantity, earned=Count(tracker.totalEarned) and tracker.totalEarned or used,
                        used=used, basis=basis, resetAt=snapshot.flags.resetAt}
                end
            end
            jobs[#jobs + 1] = job
        end
    end
    if #jobs == 0 then self.knowledgeState = "unavailable"; Refresh(self); return end
    local token, index = {}, 1
    self._knowledgeJob, self.knowledgeState = token, "scanning"
    local function Step()
        if self._knowledgeJob ~= token then return end
        if not Enabled(self) or self:GetCharacterKey() ~= key or self.db.global.characters[key] ~= character
            or context and not ns.SameRecipeContext(context, Read(ns.GetOwnedRecipeContext, self)) then
            self._knowledgeJob=nil; self.knowledgeState="interrupted"; Refresh(self); return
        end
        for _ = 1, 25 do
            local job = jobs[index]
            if not job then break end
            local source = sources[job.skill][job.sourceIndex]
            if source then
                job.sourceIndex = job.sourceIndex + 1
                for _, quest in ipairs(source.quests) do
                    if job.snapshot.flags.values[quest] == nil then
                        local complete = Read(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, quest)
                        if type(complete) ~= "boolean" then job.failed=true else job.snapshot.flags.values[quest]=complete end
                    end
                end
            elseif job.treeValid and job.queue[job.nodeIndex] then
                local node = job.queue[job.nodeIndex]; job.nodeIndex = job.nodeIndex + 1
                if not job.seen[node] then
                    job.seen[node] = true
                    local info = Read(traits.GetNodeInfo, job.config, node)
                    local children = Read(spec.GetChildrenForPath, node)
                    if not info or not Count(info.activeRank) or not Count(info.maxRanks) or info.maxRanks < 1
                        or info.activeRank > info.maxRanks or type(children) ~= "table" or #children > 100 then
                        job.treeValid = false
                    else
                        -- Profession paths include one free unlock rank.
                        job.spent = job.spent + math.max(0, info.activeRank - 1)
                        job.capacity = job.capacity + info.maxRanks - 1
                        for _, child in ipairs(children) do
                            if not Count(child) or child <= 0 or #job.queue >= 500 then job.treeValid=false; break end
                            job.queue[#job.queue + 1] = child
                        end
                    end
                end
            else
                if job.summary then
                    if job.treeValid and Read(traits.ConfigHasStagedChanges, job.config) == false then
                        job.summary.spent, job.summary.capacity = job.spent, job.capacity
                    elseif job.snapshot.summary then
                        job.summary = job.snapshot.summary
                    end
                    job.snapshot.summary = job.summary
                end
                index = index + 1
            end
        end
        if index <= #jobs then C_Timer.After(0.05, Step); return end
        local liveOwned, updated = OwnedRoots(), false
        character.professionKnowledge = character.professionKnowledge or {}
        for _, job in ipairs(jobs) do
            local old = character.professionKnowledge[job.skill]
            if not job.failed and liveOwned[bySkill[job.skill].root] and (not old or old.version == 1) then
                character.professionKnowledge[job.skill] = job.snapshot; updated = true
            end
        end
        self._knowledgeJob=nil; self.knowledgeState=updated and "complete" or "interrupted"; Refresh(self)
    end
    C_Timer.After(0.05, Step)
end

function Addon:InitializeKnowledge()
    local frame = self.knowledgeEvents or CreateFrame("Frame"); self.knowledgeEvents = frame
    for _, event in ipairs({"TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
        "TRADE_SKILL_CLOSE", "CURRENCY_DISPLAY_UPDATE", "QUEST_LOG_UPDATE", "SKILL_LINE_SPECS_RANKS_CHANGED",
        "PLAYER_REGEN_DISABLED", "PLAYER_LEAVING_WORLD"}) do frame:RegisterEvent(event) end
    self._knowledgeEnabled = true
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD" or event == "TRADE_SKILL_CLOSE" then
            self._knowledgeJob, self._knowledgePending = nil, nil; return
        end
        if not Enabled(self) or self._knowledgePending then return end
        local token = {}; self._knowledgePending = token
        C_Timer.After(0.75, function()
            if self._knowledgeEnabled and self._knowledgePending == token then
                self._knowledgePending = nil; self:ScanKnowledge()
            end
        end)
    end)
end
function Addon:StopKnowledge()
    if self.knowledgeEvents then self.knowledgeEvents:UnregisterAllEvents() end
    self._knowledgeEnabled, self._knowledgePending, self._knowledgeJob = nil, nil, nil
end
