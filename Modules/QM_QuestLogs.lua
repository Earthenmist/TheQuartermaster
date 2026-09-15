-- Dated accepted-quest snapshots; incomplete reads never replace a saved log.
local _, ns = ...
local Addon, W = ns.TheQuartermaster, ns.Wealth
local Q = {}; ns.QuestLogs = Q
local function Read(fn, ...) return W.Read(fn, ...) end
local function Value(fn, ...) local result=Read(fn,...); return result and result[1] end
local function Number(n) return W.Number(n) and n>=0 and n or nil end
local function Text(s) return type(s)=="string" and s~="" and s or nil end
local function Usable(self)
    return self._questLogsEnabled and not self._questLogsLeaving and self.db and self.db.profile.enabled~=false
        and not (InCombatLockdown and InCombatLockdown())
end
local function Clock() return GetTime and GetTime() or time() end
local function Settle(self)
    -- Header/selection APIs also emit log-update notifications on a later frame.
    self._questLogsQuietUntil=Clock()+0.2
end
local function Character(self)
    return self.db.global.characters[self:GetCharacterKey()]
end
local function Refresh(self)
    local frame=self.UI and self.UI.mainFrame
    if frame and frame:IsShown() and frame.currentTab=="quests" then self:RefreshUI() end
end
-- Header changes are restored within this synchronous read, before any timer yields.
local function Enumerate(self)
    local api=C_QuestLog
    if not api then return nil end
    local collapsed={}
    self._questLogsReading=true
    local ok, rows = pcall(function()
        local counts=Read(api.GetNumQuestLogEntries)
        assert(counts and Number(counts[1]) and counts[1]<=500)
        for i=counts[1],1,-1 do
            local info=Value(api.GetInfo,i); assert(info and type(info.isHeader)=="boolean")
            if info.isHeader and info.isCollapsed then
                assert(type(ExpandQuestHeader)=="function" and type(CollapseQuestHeader)=="function")
                collapsed[#collapsed+1]=i
                ExpandQuestHeader(i)
            end
        end
        local expanded=Read(api.GetNumQuestLogEntries); assert(expanded and Number(expanded[1]) and expanded[1]<=500)
        local list,category={},nil
        for i=1,expanded[1] do
            local info=Value(api.GetInfo,i);assert(info and type(info.isHeader)=="boolean")
            if info.isHeader then category=Text(info.title)
            else
                assert(Number(info.questID) and info.questID>0 and Text(info.title))
                list[#list+1]={id=info.questID,name=info.title,level=Number(info.level),category=category,
                    hidden=info.isHidden or info.isInternalOnly or info.isTask or info.isBounty,
                    frequency=Number(info.frequency),campaignID=Number(info.campaignID),isStory=info.isStory}
            end
        end
        if expanded[2] and expanded[2]>0 then assert(#list>0) end
        return list
    end)
    -- Original indices become valid again when restoring in ascending order.
    local restored=true
    for i=#collapsed,1,-1 do if not pcall(CollapseQuestHeader,collapsed[i]) then restored=false end end
    self._questLogsReading=nil
    Settle(self)
    return ok and restored and rows or nil
end
local function Rewards(row)
    row.money=Number(Value(GetQuestLogRewardMoney))
    row.xp=Number(Value(GetQuestLogRewardXP))
    row.rewards={}
    if row.money==nil or row.xp==nil then row.rewardsIncomplete=true end
    for _,kind in ipairs({"reward","choice"}) do
        local count=Value(kind=="reward" and GetNumQuestLogRewards or GetNumQuestLogChoices)
        if not Number(count) or count>50 then row.rewardsIncomplete=true
        else
            for i=1,count do
                local values=Read(kind=="reward" and GetQuestLogRewardInfo or GetQuestLogChoiceInfo,i)
                if values and Text(values[1]) and Number(values[3]) then
                    row.rewards[#row.rewards+1]={name=values[1],quantity=values[3],kind=kind,itemID=Number(values[6])}
                else row.rewardsIncomplete=true end
            end
        end
    end
end
local function Collect(row)
    local api=C_QuestLog
    if Value(api.IsOnQuest,row.id)~=true then return nil end
    local complete,failed=Value(api.IsComplete,row.id),Value(api.IsFailed,row.id)
    row.state=failed==true and "failed" or complete==true and "ready" or (complete==false and failed==false) and "active" or "unknown"
    local objectives=Value(api.GetQuestObjectives,row.id)
    if type(objectives)=="table" then
        row.objectives={}
        for _,objective in ipairs(objectives) do
            if not Text(objective.text) or type(objective.finished)~="boolean" then row.objectives=nil;break end
            row.objectives[#row.objectives+1]={text=objective.text,finished=objective.finished,
                have=Number(objective.numFulfilled),need=Number(objective.numRequired)}
        end
    end
    local tag=Value(api.GetQuestTagInfo,row.id)
    row.tag=tag and Text(tag.tagName)
    local frequency=Enum and Enum.QuestFrequency or {}
    row.kind=row.frequency~=nil and row.frequency==frequency.Daily and "daily" or row.frequency~=nil and row.frequency==frequency.Weekly and "weekly"
        or row.campaignID and row.campaignID>0 and "campaign" or "normal"
    -- Selected-quest APIs are read together, and selection is restored before yielding.
    local selected=Value(api.GetSelectedQuest)
    if Number(selected) and type(api.SetSelectedQuest)=="function" then
        local ok=pcall(function()
            api.SetSelectedQuest(row.id)
            assert(Value(api.GetSelectedQuest)==row.id)
            local details=Read(GetQuestLogQuestText)
            row.description=details and Text(details[1]);row.summary=details and Text(details[2])
            Rewards(row)
        end)
        local restored=pcall(api.SetSelectedQuest,selected)
        if not ok or not restored then row.description=nil;row.summary=nil;row.money=nil;row.xp=nil;row.rewards=nil end
    end
    return row
end
function Addon:ScanQuestLogs()
    if not Usable(self) or not Character(self) then return end
    local character=Character(self)
    if character.questLog and character.questLog.version~=1 then return end
    local list=Enumerate(self)
    if not list then self.questLogStatus="unavailable";Refresh(self);return end
    local job={list=list,rows={},index=1,key=self:GetCharacterKey()}
    self._questLogJob=job;self.questLogStatus="scanning";Refresh(self)
    local function Step()
        if self._questLogJob~=job or not Usable(self) or self:GetCharacterKey()~=job.key then return end
        for i=job.index,math.min(#list,job.index+3) do
            local row=list[i]
            if not row.hidden then
                self._questLogsReading=true
                local ok,result=pcall(Collect,row)
                self._questLogsReading=nil
                Settle(self)
                if not ok or not result then self._questLogJob=nil;self.questLogStatus="unavailable";Refresh(self);return end
                job.rows[#job.rows+1]=result
            end
        end
        job.index=job.index+4
        if job.index<=#list then C_Timer.After(0.05,Step);return end
        local final=Enumerate(self)
        if not final or #final~=#list then self._questLogJob=nil;self.questLogStatus="unavailable";Refresh(self);return end
        for i,row in ipairs(final) do
            if row.id~=list[i].id then self._questLogJob=nil;self.questLogStatus="unavailable";Refresh(self);return end
        end
        -- A transient empty log at login is not proof all accepted quests disappeared.
        if #list==0 and not self._questEmptyConfirmed then
            self._questEmptyConfirmed=true;self._questLogJob=nil;self:QueueQuestLogs();return
        end
        self._questEmptyConfirmed=#list==0 or nil
        character.questLog={version=1,checked=time(),rows=job.rows}
        self._questLogJob=nil;self.questLogStatus="ready";Refresh(self)
    end
    Step()
end
function Addon:QueueQuestLogs()
    if not Usable(self) or self._questLogTimer or self._questLogJob then return end
    self._questLogTimer=self:ScheduleTimer(function()
        self._questLogTimer=nil;self:ScanQuestLogs()
    end,0.5)
end
function Addon:InitializeQuestLogs()
    self._questLogsEnabled=true
    local frame=self.questLogEvents or CreateFrame("Frame");self.questLogEvents=frame
    for _,event in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD","PLAYER_LOGOUT","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","QUEST_LOG_UPDATE","QUEST_WATCH_UPDATE","QUEST_ACCEPTED","QUEST_REMOVED","QUEST_TURNED_IN","QUEST_DATA_LOAD_RESULT"}) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent",function(_,event)
        if self._questLogsReading then return end
        local notification=event=="QUEST_LOG_UPDATE" or event=="QUEST_DATA_LOAD_RESULT"
        if notification and (self._questLogJob or Clock()<(self._questLogsQuietUntil or 0)) then return end
        self._questLogJob=nil
        if event=="PLAYER_LEAVING_WORLD" or event=="PLAYER_LOGOUT" then self._questLogsLeaving=true end
        if event=="PLAYER_ENTERING_WORLD" then self._questLogsLeaving=nil;self._questEmptyConfirmed=nil end
        if event=="PLAYER_REGEN_DISABLED" then self.questLogStatus="paused";Refresh(self) end
        self:QueueQuestLogs()
    end)
    self:QueueQuestLogs()
end
function Addon:StopQuestLogs()
    self._questLogsEnabled=nil;self._questLogJob=nil
    if self._questLogTimer then self:CancelTimer(self._questLogTimer,true);self._questLogTimer=nil end
    if self.questLogEvents then self.questLogEvents:UnregisterAllEvents() end
end
function Q.Filter(snapshot,settings)
    local result,categories={},{}
    local query=(settings.query or ""):lower()
    for _,row in ipairs(snapshot and snapshot.version==1 and snapshot.rows or {}) do
        local category=row.category or ns.L.QL_UNGROUPED
        categories[category]=true
        if (not settings.category or settings.category==category) and (not settings.kind or settings.kind==row.kind)
            and (not settings.state or settings.state==row.state)
            and (query=="" or row.name:lower():find(query,1,true) or tostring(row.id)==query) then result[#result+1]=row end
    end
    table.sort(result,function(a,b) if a.category~=b.category then return (a.category or "")<(b.category or "") end return a.name<b.name end)
    return result,categories
end
