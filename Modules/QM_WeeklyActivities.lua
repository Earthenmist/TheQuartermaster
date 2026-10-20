-- Public quest snapshots. Missing reads and expired snapshots never mean incomplete.
local _, ns = ...
local Addon = ns.TheQuartermaster
ns.WeeklyCatalogue = {
    {id=93784, group="delves", account=true, map=2393},
    {id=89289, group="silvermoon", map=2395},
    {id=90573, group="silvermoon", map=2395, pool="runestones"},
    {id=90574, group="silvermoon", map=2395, pool="runestones"},
    {id=90575, group="silvermoon", map=2395, pool="runestones"},
    {id=90576, group="silvermoon", map=2395, pool="runestones"},
    {id=89507, group="amani", map=2437}, {id=89268, group="harandar", map=2413},
    {id=90962, group="voidstorm", map=2405}, {id=94790, group="voidstorm", map=2405},
    {id=96995, group="coiled", map=2512, helpKey="ES_SURGE_HELP"},
    {id=95520, group="vaults", map=2509, helpKey="ES_VAULTS_HELP"},
    {id=98232, group="vaults", map=2509, rotating=true, helpKey="ES_VAULTS_META_HELP"},
    {id=92560, group="silvermoon", map=2395, rotating=true, boss=true},
    {id=92123, group="amani", map=2437, rotating=true, boss=true},
    {id=92034, group="harandar", map=2413, rotating=true, boss=true},
    {id=92636, group="voidstorm", map=2405, rotating=true, boss=true},
}
local function Public(value, depth)
    if issecretvalue and issecretvalue(value) then return false end
    if type(value)=="table" then
        if (depth or 0)>5 then return false end
        for k,v in pairs(value) do if not Public(k,(depth or 0)+1) or not Public(v,(depth or 0)+1) then return false end end
    end
    return true
end
local function Read(fn, ...)
    if type(fn)~="function" then return nil end
    local ok,value=pcall(fn,...)
    if ok and Public(value) then return value end
end
ns.WeeklyRead = Read
ns.WeeklyPublic = Public
function Addon:CollectWeeklyActivities(previous)
    if InCombatLockdown and InCombatLockdown() then return previous end
    local api=C_QuestLog
    if not api then return previous end
    local now, seconds=self:GetPvENow(),self:GetWeeklyResetSeconds()
    if not seconds or seconds<=0 then return previous end
    local rows, definitions={},{}
    for _, def in ipairs(ns.WeeklyCatalogue) do definitions[def.id]=def end
    -- Retain discovered weeklies so their completion remains visible after turn-in.
    for id, row in pairs(previous and previous.rows or {}) do
        if type(id)=="number" and not definitions[id] and row.group~="prey" then definitions[id]={id=id,group=row.dynamic and row.group or "accepted",dynamic=row.dynamic,name=row.name,account=row.account} end
    end
    local count=Read(api.GetNumQuestLogEntries)
    if type(count)=="number" then
        for index=1,math.min(count,200) do
            local info=Read(api.GetInfo,index)
            if info and not info.isHeader and not info.isHidden and info.questID and Enum and Enum.QuestFrequency and info.frequency==Enum.QuestFrequency.Weekly then
                definitions[info.questID]=definitions[info.questID] or {id=info.questID,group="accepted",name=info.title}
            end
        end
    end
    -- Only recurring/meta quests actually exposed on the city map enter this group.
    for _, info in ipairs(Read(api.GetQuestsOnMap,2393) or {}) do
        local classification=Read(C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification,info.questID)
        local kinds=Enum and Enum.QuestClassification
        if kinds and (classification==kinds.Recurring or classification==kinds.Meta or classification==kinds.Calling) then
            definitions[info.questID]=definitions[info.questID] or {id=info.questID,group="city",map=2393,dynamic=true}
        end
    end
    local prey=Read(api.GetActivePreyQuest)
    if type(prey)=="number" and prey>0 then definitions[prey]={id=prey,group="prey"} end
    for id,def in pairs(definitions) do
        local old=previous and previous.rows and previous.rows[id]
        local account=def.account or Read(api.IsAccountQuest,id)==true
        local done=Read(account and api.IsQuestFlaggedCompletedOnAccount or api.IsQuestFlaggedCompleted,id)
        local active=Read(api.IsOnQuest,id)
        local ready=active and Read(api.IsComplete,id)
        local name=Read(api.GetTitleForQuestID,id) or def.name or (old and old.name)
        if type(name)~="string" or name=="" then name=def.name or (old and old.name) end
        local state=done==true and "complete" or ready==true and "ready" or active==true and "active" or (done==false and active==false and "notstarted" or "unknown")
        -- A negative completion flag does not prove unlocks or current availability.
        local objectives=active and Read(api.GetQuestObjectives,id) or nil
        if done==nil or active==nil or ((state=="unknown" or state=="notstarted") and old and old.state=="complete" and old.resetAt and old.resetAt>now) then
            if old then rows[id]=old end
        else
            rows[id]={id=id,name=name,group=def.group,map=def.map,account=account,state=state,
                objectives=objectives,capturedAt=now,resetAt=now+seconds,pool=def.pool,rotating=def.rotating,boss=def.boss,dynamic=def.dynamic,helpKey=def.helpKey}
            if def.rotating then rows[id].available=Read(C_TaskQuest and C_TaskQuest.IsActive,id) end
            if self.CollectWeeklyQuestDetails then self:CollectWeeklyQuestDetails(rows[id],old) end
        end
    end
    if self.CollectWeeklyCounters then self:CollectWeeklyCounters(rows,previous,now,now+seconds) end
    return {rows=rows,capturedAt=now,resetAt=now+seconds}
end
function Addon:GetWeeklyActivityRows(char)
    local rows, seen={},{}
    local function Add(id,source,definition)
        local row={}
        for k,v in pairs(source or {}) do row[k]=v end
        for k,v in pairs(definition or {}) do row[k]=v end
        row.id=id
        if not source or not row.resetAt or row.resetAt<=self:GetPvENow() then row.state="unknown"; row.objectives=nil; row.current=nil; row.maximum=nil; row.available=nil; row.details=nil; row.rewards=nil; row.description=nil end
        -- Only explicit account-scoped completions can be shared between alts.
        if row.account then
            for _,other in pairs(self.db.global.characters or {}) do
                local shared=other.weeklyActivities and other.weeklyActivities.rows and other.weeklyActivities.rows[id]
                if shared and shared.account and shared.state=="complete" and shared.resetAt and shared.resetAt>self:GetPvENow() then
                    row.state="complete"; row.capturedAt=shared.capturedAt; break
                end
            end
        end
        rows[#rows+1]=row; seen[id]=true
    end
    local saved=char.weeklyActivities and char.weeklyActivities.rows or {}
    for _,def in ipairs(ns.WeeklyCatalogue) do Add(def.id,saved[def.id],def) end
    for id,row in pairs(saved) do if not seen[id] then Add(id,row) end end
    for _,def in ipairs(ns.WeeklyCounterDefaults or {}) do if not seen[def.id] then Add(def.id,nil,def) end end
    -- Represent mutually exclusive quest variants once, choosing an observed variant.
    local result,pools={},{}
    local rank={complete=4,ready=3,active=2,notstarted=1,unknown=0}
    for _,row in ipairs(rows) do
        if row.pool then
            local prior=pools[row.pool]
            if not prior or (rank[row.state] or 0)>(rank[prior.state] or 0) then pools[row.pool]=row end
        elseif not row.rotating or row.available or row.state=="active" or row.state=="ready" or row.state=="complete" then
            result[#result+1]=row
        end
    end
    for _,row in pairs(pools) do
        if row.state=="unknown" or row.state=="notstarted" then row.name=nil; row.titleKey="ES_RUNESTONES" end
        result[#result+1]=row
    end
    rows=result
    table.sort(rows,function(a,b) if a.group~=b.group then return a.group<b.group end return tostring(a.id)<tostring(b.id) end)
    return rows
end
function Addon:OnWeeklyQuestChanged()
    if self.weeklyQuestPending then return end
    self.weeklyQuestPending=true
    C_Timer.After(2,function()
        self.weeklyQuestPending=nil
        local key=UnitName("player").."-"..GetRealmName()
        local char=self.db and self.db.global.characters[key]
        if char then char.weeklyActivities=self:CollectWeeklyActivities(char.weeklyActivities) end
        if self.UI and self.UI.mainFrame and self.UI.mainFrame:IsShown() and self.UI.mainFrame.currentTab=="pve" then self:RefreshUI() end
    end)
end
