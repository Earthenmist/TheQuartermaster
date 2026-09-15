-- Public achievement observations: shared completion is never personal completion.
local _,ns=...
local Addon,W=ns.TheQuartermaster,ns.Wealth
local A={};ns.Achievements=A
local function Read(fn,...) return W.Read(fn,...) end
local function Value(fn,...) local v=Read(fn,...);return v and v[1] end
local function Number(v) return W.Number(v) and v>=0 and v==math.floor(v) end
local function Refresh(self)
    local f=self.UI and self.UI.mainFrame
    if f and f:IsShown() and f.currentTab=="achievements" then self:RefreshUI() end
end
function Addon:ScanAchievements()
    if self._achievementJob or not self._achievementsEnabled then return end
    if not bit or not Number(ACHIEVEMENT_FLAGS_ACCOUNT) then self.achievementStatus="unavailable";Refresh(self);return end
    if InCombatLockdown and InCombatLockdown() then self.achievementStatus="paused";Refresh(self);return end
    local key=self:GetCharacterKey();local g=self.db.global;local char=g.characters[key]
    if not char then return end
    if (g.achievementData and g.achievementData.version~=1) or (char.achievements and char.achievements.version~=1) then
        self.achievementStatus="unavailable";Refresh(self);return
    end
    local cats=Value(GetCategoryList)
    if type(cats)~="table" or #cats==0 or #cats>1000 then self.achievementStatus="unavailable";Refresh(self);return end
    local token={};self._achievementJob=token;self.achievementStatus="scanning";Refresh(self)
    local ci,ai,count,category=1,1,nil,nil
    local ids,seen,metadata,observations={},{},{},{}
    local index,active,criterion=1,nil,1
    local commitIndex=1
    local partial=false
    local function Fail() self._achievementJob=nil;self.achievementStatus="unavailable";Refresh(self) end
    local function Add(id,cat)
        if not Number(id) or id<=0 then return false end
        if not seen[id] then seen[id]=true;ids[#ids+1]={id=id,category=cat} end
        return #ids<=30000
    end
    local function Save()
        observations[active.id]=active.observation;metadata[active.id]=active.meta
        active=nil;index=index+1
    end
    local function Step()
        if self._achievementJob~=token then return end
        if not self._achievementsEnabled or self:GetCharacterKey()~=key or (InCombatLockdown and InCombatLockdown()) then
            self._achievementJob=nil;self.achievementStatus="paused";Refresh(self);return
        end
        for _=1,25 do
            if ci<=#cats then
                if count==nil then
                    local info=Read(GetCategoryInfo,cats[ci]);count=Value(GetCategoryNumAchievements,cats[ci])
                    if not info or type(info[1])~="string" or not Number(count) or count>30000 then Fail();return end
                    category=info[1];ai=1
                elseif ai<=count then
                    if not Add(Value(GetAchievementInfo,cats[ci],ai),category) then Fail();return end
                    ai=ai+1
                else ci=ci+1;count=nil end
            elseif active then
                if criterion<=active.count then
                    local v=Read(GetAchievementCriteriaInfo,active.id,criterion)
                    if not v or type(v[1])~="string" or type(v[3])~="boolean" or not Number(v[4]) or not Number(v[5]) then
                        partial=true;active=nil;index=index+1
                    else
                        active.observation.criteria[#active.observation.criteria+1]={id=v[10],text=v[1],completed=v[3],quantity=v[4],required=v[5],quantityText=v[9],asset=v[8],kind=v[2]}
                        criterion=criterion+1
                    end
                else Save() end
            elseif index<=#ids then
                local entry=ids[index];local id=entry.id;local v=Read(GetAchievementInfo,id)
                if not v or v[1]~=id or type(v[2])~="string" or type(v[4])~="boolean" or not Number(v[9]) then
                    partial=true;index=index+1
                elseif v[12] or v[15] then index=index+1
                else
                    local previous=Value(GetPreviousAchievement,id)
                    if previous and previous~=0 and not Add(previous,entry.category) then Fail();return end
                    local shared=bit.band(v[9],ACHIEVEMENT_FLAGS_ACCOUNT)~=0
                    active={id=id,meta={id=id,name=v[2],points=v[3],description=v[8],flags=v[9],icon=v[10],reward=v[11],category=entry.category,shared=shared},
                        observation={completed=v[4],personal=type(v[13])=="boolean" and v[13] or nil,checked=time()}}
                    -- Keep explicit false rather than collapsing it into unknown.
                    if v[13]==false then active.observation.personal=false end
                    local n=Value(GetAchievementNumCriteria,id)
                    if not Number(n) or n>2000 then partial=true;active=nil;index=index+1
                    elseif (shared and v[4]) or (not shared and v[13]==true) then Save()
                    else active.count=n;active.observation.criteria={};criterion=1 end
                end
            else
                if #ids==0 then Fail();return end
                -- Merge only complete public row observations; never erase unseen faction entries.
                g.achievementData=g.achievementData or {version=1,metadata={},shared={}}
                char.achievements=char.achievements or {version=1,rows={}}
                local store=g.achievementData;local snapshot=char.achievements
                if commitIndex<=#ids then
                    snapshot.partial=true;store.partial=true
                    local id=ids[commitIndex].id;local meta=metadata[id]
                    if meta then
                        local row=observations[id];store.metadata[id]=meta
                        store.shared[id]={completed=row.completed,checked=row.checked,criteria=meta.shared and row.criteria or nil}
                        if not meta.shared then snapshot.rows[id]=row end
                    end
                    commitIndex=commitIndex+1
                else
                snapshot.checked=time();snapshot.partial=partial or nil
                store.checked=time();store.partial=partial or nil
                local build=Read(GetBuildInfo);snapshot.build=build and build[2]
                self._achievementJob=nil;self.achievementStatus=partial and "partial" or "ready";Refresh(self)
                if self._achievementDirty then self._achievementDirty=nil;self:QueueAchievements() end
                return
                end
            end
        end
        C_Timer.After(0.05,Step)
    end
    C_Timer.After(0.05,Step)
end
function Addon:QueueAchievements()
    if not self._achievementsEnabled or self._achievementPending or self._achievementJob then return end
    local token={};self._achievementPending=token
    C_Timer.After(2,function()
        if self._achievementPending~=token then return end
        self._achievementPending=nil;self:ScanAchievements()
    end)
end
function Addon:InitializeAchievements()
    self._achievementsEnabled=true
    local f=self.achievementEvents or CreateFrame("Frame");self.achievementEvents=f
    for _,event in ipairs({"PLAYER_ENTERING_WORLD","ACHIEVEMENT_EARNED","CRITERIA_UPDATE","PLAYER_REGEN_ENABLED","PLAYER_REGEN_DISABLED","PLAYER_LOGOUT"}) do f:RegisterEvent(event) end
    f:SetScript("OnEvent",function(_,event)
        if event=="PLAYER_LOGOUT" then self:StopAchievements()
        elseif event=="PLAYER_REGEN_DISABLED" then self._achievementJob=nil;self.achievementStatus="paused"
        else
            if self._achievementJob then self._achievementDirty=true else self:QueueAchievements() end
        end
    end)
    self:QueueAchievements()
end
function Addon:StopAchievements()
    self._achievementsEnabled=nil;self._achievementJob=nil;self._achievementPending=nil;self._achievementDirty=nil
    if self.achievementEvents then self.achievementEvents:UnregisterAllEvents() end
end
function A.Filter(db,f)
    local store=db.global.achievementData
    local rows,categories={},{}
    if not store or store.version~=1 then return rows,categories end
    local char=db.global.characters[f.character];local snapshot=char and char.achievements
    local query=(f.query or ""):lower()
    for id,meta in pairs(store.metadata) do
        if not f.character or not meta.shared then
            categories[meta.category]=true
            local observed=f.character and snapshot and snapshot.version==1 and snapshot.rows[id] or nil
            local shared=store.shared[id]
            local complete
            if f.character then
                if observed then complete=observed.personal end
            elseif shared then complete=shared.completed end
            local state=complete==true and "complete" or complete==false and "incomplete" or "unknown"
            local record=shared
            if f.character then record=observed end
            local progress=false
            for _,c in ipairs(record and record.criteria or {}) do if c.quantity>0 then progress=true end end
            if (not f.category or f.category==meta.category) and (query=="" or meta.name:lower():find(query,1,true) or tostring(id)==query)
                and (not f.state or f.state==state or f.state=="progress" and state=="incomplete" and progress) then
                rows[#rows+1]={id=id,meta=meta,record=record,shared=shared,state=state}
            end
        end
    end
    table.sort(rows,function(a,b) if a.meta.name==b.meta.name then return a.id<b.id end return a.meta.name:lower()<b.meta.name:lower() end)
    return rows,categories
end
