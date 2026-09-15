-- Detail and counter adapters keep public source data separate from presentation.
local _,ns=...
local Addon,Read=ns.TheQuartermaster,ns.WeeklyRead
local function Values(fn,...)
    if type(fn)~="function" then return nil end
    local values={pcall(fn,...)}
    if not values[1] or not ns.WeeklyPublic(values) then return nil end
    table.remove(values,1)
    return values
end
local function CleanText(value)
    return type(value)=="string" and value~="" and value or nil
end
function Addon:CollectWeeklyQuestDetails(row,old)
    local id=row.id
    self.weeklyRequested=self.weeklyRequested or {}
    if not self.weeklyRequested[id] then
        self.weeklyRequested[id]=true
        Read(C_QuestLog.RequestLoadQuestByID,id)
        Read(C_TaskQuest and C_TaskQuest.RequestPreloadRewardData,id)
    end
    row.location=CleanText(Read(C_QuestLog.GetNextWaypointText,id))
    local map=row.map and Read(C_Map and C_Map.GetMapInfo,row.map)
    row.mapName=map and map.name or (old and old.mapName)
    local tooltip=Read(C_TooltipInfo and C_TooltipInfo.GetHyperlink,"quest:"..id)
    local lines={}
    for index,line in ipairs(tooltip and tooltip.lines or {}) do
        if index>=3 and index<=8 and CleanText(line.leftText) then lines[#lines+1]=line.leftText end
    end
    row.description=#lines>0 and table.concat(lines,"\n") or (old and old.description)
    local rewards={}
    for _,reward in ipairs(Read(C_QuestLog.GetQuestRewardCurrencies,id) or {}) do
        if CleanText(reward.name) and type(reward.totalRewardAmount)=="number" then
            rewards[#rewards+1]={name=reward.name,icon=reward.texture,quantity=reward.totalRewardAmount}
        end
    end
    local count=Read(GetNumQuestLogRewards,id)
    for index=1,math.min(type(count)=="number" and count or 0,16) do
        local item=Values(GetQuestLogRewardInfo,index,id)
        if item and CleanText(item[1]) and type(item[3])=="number" then
            rewards[#rewards+1]={name=item[1],icon=item[2],quantity=item[3],quality=item[4]}
        end
    end
    row.rewards=#rewards>0 and rewards or nil
    -- Old rewards can vary with rotations; never substitute a previous week's amounts.
    if not row.rewards and old and old.resetAt and old.resetAt>self:GetPvENow() then row.rewards=old.rewards end
end

local currencies={
    {3310,"delves","ES_SHARDS_HELP"}, {3028,"delves","ES_KEYS_HELP"},
    {3376,"amani","ES_ABUNDANCE_HELP"}, {3400,"voidstorm","ES_RESEARCH_HELP"},
    {3448,"vaults","ES_CORROSIVE_HELP"},
}
ns.WeeklyCounterDefaults={
    {id="delve:renown",kind="counter",group="delves",titleKey="ES_BONUS_RENOWN",account=true,icon=3726261},
    {id="delve:bounty",kind="counter",group="delves",titleKey="ES_BOUNTY",icon=1064187},
    {id="delve:stash",kind="counter",group="delves",titleKey="ES_GILDED",icon=5872049,helpKey="ES_GILDED_HELP"},
    {id="prey:1",kind="counter",group="prey",titleKey="ES_PREY_1",icon=132177},
}
for _,def in ipairs(currencies) do
    ns.WeeklyCounterDefaults[#ns.WeeklyCounterDefaults+1]={id="currency:"..def[1],kind="currency",group=def[2],titleKey="ES_CURRENCY_"..def[1],helpKey=def[3],icon=133016}
end
local renownFlags={{93821,2710},{93819,2696},{93822,2704},{93820,2699}}
-- Public quest completion identifiers, grouped by hunt difficulty.
local preyFlags={
    {91095,91096,91097,91098,91099,91100,91101,91102,91103,91104,91105,91106,91107,91108,91109,91110,91111,91112,91113,91114,91115,91116,91117,91118,91119,91120,91121,91122,91123,91124},
    {91210,91212,91214,91216,91218,91220,91222,91224,91226,91228,91230,91232,91234,91236,91238,91240,91242,91243,91244,91245,91246,91247,91248,91249,91250,91251,91252,91253,91254,91255},
    {91211,91213,91215,91217,91219,91221,91223,91225,91227,91229,91231,91233,91235,91237,91239,91241,91256,91257,91258,91259,91260,91261,91262,91263,91264,91265,91266,91267,91268,91269,95021,95022,95023,95024},
}
function Addon:CollectWeeklyCounters(rows,previous,now,resetAt)
    local function Save(id,data)
        if data then
            data.id=id; data.capturedAt=now; data.resetAt=data.resetAt or resetAt
            data.state=data.state or (data.maximum and data.current and data.current>=data.maximum and "complete" or "active")
            local old=previous and previous.rows and previous.rows[id]
            -- Unverified reports must neither replace verified progress nor block its correction.
            if data.kind=="counter" and old and old.resetAt and old.resetAt>now and old.state~="unverified"
                and type(old.current)=="number" and type(data.current)=="number"
                and (data.state=="unverified" or old.current>data.current) then
                rows[id]=old
            else rows[id]=data end
        elseif previous and previous.rows and previous.rows[id] then rows[id]=previous.rows[id] end
    end
    for _,def in ipairs(currencies) do
        local info=Read(C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo,def[1])
        local row
        if info and CleanText(info.name) and type(info.quantity)=="number" then
            row={kind="currency",name=info.name,icon=info.iconFileID,group=def[2],helpKey=def[3],quantity=info.quantity,
                description=info.description,account=info.isAccountWide==true,current=info.quantity}
            if type(info.maxWeeklyQuantity)=="number" and info.maxWeeklyQuantity>0 and type(info.quantityEarnedThisWeek)=="number" then
                row.current=info.quantityEarnedThisWeek; row.maximum=info.maxWeeklyQuantity; row.capKey="ES_WEEKLY_CAP"
            elseif info.useTotalEarnedForMaxQty and type(info.totalEarned)=="number" and type(info.maxQuantity)=="number" and info.maxQuantity>0 then
                row.current=info.totalEarned; row.maximum=info.maxQuantity; row.capKey="ES_EARNED_CAP"
            end
        end
        Save("currency:"..def[1],row)
    end
    local done,known,details=0,true,{}
    for index,pair in ipairs(renownFlags) do
        local flag=Read(C_QuestLog.IsQuestFlaggedCompletedOnAccount,pair[1])
        if type(flag)~="boolean" then known=false end
        if flag then done=done+1 end
        local faction=Read(C_Reputation and C_Reputation.GetFactionDataByID,pair[2])
        details[#details+1]={name=faction and faction.name or ns.L["ES_RENOWN_"..index],complete=flag}
    end
    Save("delve:renown",known and {kind="counter",titleKey="ES_BONUS_RENOWN",group="delves",icon=3726261,
        current=done,maximum=#renownFlags,details=details,account=true,helpKey="ES_RENOWN_HELP"} or nil)
    local bounty=Read(C_QuestLog.IsQuestFlaggedCompleted,86371)
    Save("delve:bounty",type(bounty)=="boolean" and {kind="counter",titleKey="ES_BOUNTY",group="delves",icon=1064187,
        current=bounty and 1 or 0,maximum=1,helpKey="ES_BOUNTY_HELP"} or nil)
    local widget=Read(C_UIWidgetManager and C_UIWidgetManager.GetSpellDisplayVisualizationInfo,7591)
    local stash
    if widget and widget.spellInfo and widget.spellInfo.spellID==1216211 then
        local description=CleanText(widget.spellInfo.tooltip)
        local current,maximum
        if description then current,maximum=description:match("(%d+)%s*/%s*(%d+)") end
        if current and maximum and tonumber(maximum)>0 then
            stash={kind="counter",group="delves",titleKey="ES_GILDED",icon=5872049,current=tonumber(current),maximum=tonumber(maximum),description=description,helpKey="ES_GILDED_HELP"}
            if widget.spellInfo.shownState~=1 then stash.state="unverified" end
        end
    end
    Save("delve:stash",stash)
    local renown=Read(C_MajorFactions and C_MajorFactions.GetCurrentRenownLevel,2764)
    for difficulty,ids in ipairs(preyFlags) do
        if difficulty==1 or (type(renown)=="number" and renown>=(difficulty==2 and 1 or 4)) then
            local count,valid,hunts=0,true,{}
            for _,id in ipairs(ids) do
                local flag=Read(C_QuestLog.IsQuestFlaggedCompleted,id)
                if type(flag)~="boolean" then valid=false end
                if flag then
                    count=count+1
                    hunts[#hunts+1]={name=Read(C_QuestLog.GetTitleForQuestID,id) or string.format(ns.L.WEEKLY_QUEST_ID,id),complete=true}
                end
            end
            Save("prey:"..difficulty,valid and {kind="counter",group="prey",titleKey="ES_PREY_"..difficulty,icon=132177,
                current=count,maximum=4,details=hunts,helpKey="ES_PREY_HELP"} or nil)
        elseif type(renown)~="number" then Save("prey:"..difficulty,nil)
        end
    end
    self.weeklyWidgetIDs={}
    local widgets=Read(C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID,1843)
    if not widgets then
        for id,row in pairs(previous and previous.rows or {}) do
            if type(id)=="string" and id:sub(1,5)=="hunt:" then rows[id]=row end
        end
    end
    for index,entry in ipairs(widgets or {}) do
        if index>12 then break end
        if entry.widgetType==2 then
            self.weeklyWidgetIDs[entry.widgetID]=true
            local info=Read(C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo,entry.widgetID)
            if info and info.shownState==1 and CleanText(info.text) and type(info.barValue)=="number" and type(info.barMax)=="number" then
                Save("hunt:"..entry.widgetID,{kind="currency",group="prey",name=info.text,icon=132177,current=info.barValue,
                    maximum=info.barMax,resetAt=now+600,state="active",helpKey="ES_HUNT_HELP"})
            end
        end
    end
    -- Abundance location is taken from the current public event marker, not a timetable.
    local locations={[8672]=2395,[8671]=2437,[8676]=2413,[8675]=2405}
    local events=Read(C_AreaPoiInfo and C_AreaPoiInfo.GetEventsForMap,2537)
    if not events then Save("event:abundance",nil) end
    for _,id in ipairs(events or {}) do
        if locations[id] then
            local info=Read(C_AreaPoiInfo.GetAreaPOIInfo,2537,id)
            local map=Read(C_Map and C_Map.GetMapInfo,locations[id])
            if info then Save("event:abundance",{kind="event",group="amani",name=info.name,icon=info.icon or 134400,
                mapName=map and map.name,description=info.description,state="active",resetAt=now+600,helpKey="ES_ABUNDANCE_HELP"}) end
            break
        end
    end
end

function ns.WeeklyVaultRewardLevel(activity)
    if InCombatLockdown and InCombatLockdown() then return nil end
    if not ns.WeeklyPublic(activity) or type(activity.id)~="number" then return nil end
    local link=Read(C_WeeklyRewards and C_WeeklyRewards.GetExampleRewardItemHyperlinks,activity.id)
    if type(link)~="string" or not link:find("item:",1,true) then return nil end
    local level=Read(C_Item and C_Item.GetDetailedItemLevelInfo,link)
    if type(level)=="number" and level>0 then return level end
end

function Addon:OnWeeklyWidgetChanged(_,info)
    if not ns.WeeklyPublic(info) or type(info)~="table" then return end
    if info.widgetID==7591 or (self.weeklyWidgetIDs and self.weeklyWidgetIDs[info.widgetID]) then self:OnWeeklyQuestChanged() end
end
