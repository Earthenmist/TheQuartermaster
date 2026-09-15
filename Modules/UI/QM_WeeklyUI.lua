local _, ns = ...
local Addon,L=ns.TheQuartermaster,ns.L
local function Text(parent,value,x,y,width,color)
    local label=ns.UI_RenderFontString(parent,nil,"OVERLAY","QuartermasterFontSmall")
    label:SetPoint("TOPLEFT",x,-y); label:SetWidth(math.max(1,width)); label:SetJustifyH("LEFT")
    label:SetWordWrap(false); label:SetText(value); label:SetTextColor(unpack(color or ns.UI_COLORS.textNormal))
    return label
end
local function Button(parent,value,x,y,width,callback)
    local button=ns.UI_RenderFrame("Button",nil,parent,"BackdropTemplate")
    button:SetSize(width,28); button:SetPoint("TOPLEFT",x,-y)
    button:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    button:SetBackdropColor(unpack(ns.UI_COLORS.bgCard)); button:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
    Text(button,value,8,8,width-16)
    button:SetScript("OnClick",callback)
    button:SetScript("OnEnter",function(b) b:SetBackdropBorderColor(unpack(ns.UI_COLORS.accent)) end)
    button:SetScript("OnLeave",function(b) b:SetBackdropBorderColor(unpack(ns.UI_COLORS.border)) end)
    return button
end
function ns.UI_DrawWeeklyControls(parent,y,characters)
    local selected=Addon.pveSelectedCharacter
    if selected=="all" then selected=nil end
    local current=UnitName("player").."-"..GetRealmName()
    local chosen,currentCharacter
    for _,char in ipairs(characters) do
        local key=char.name.."-"..char.realm
        if key==current then currentCharacter=char end
        if key==(selected or current) then chosen=char end
    end
    chosen=chosen or currentCharacter or characters[1]
    if chosen then Addon.pveSelectedCharacter=chosen.name.."-"..chosen.realm end
    local label=chosen and (chosen.name.." - "..chosen.realm) or L.WEEKLY_NO_CHARACTER
    local button=Button(parent,label,10,y,260,function() end)
    local arrow=ns.UI_RenderTexture(button,nil,"ARTWORK")
    arrow:SetSize(12,12); arrow:SetPoint("RIGHT",-6,0)
    arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    arrow:SetVertexColor(unpack(ns.UI_COLORS.accent))
    local menu=ns.UI_RenderFrame("Frame",nil,button,"BackdropTemplate")
    menu:SetSize(260,#characters*28+4); menu:SetPoint("TOPLEFT",button,"BOTTOMLEFT",0,-2)
    menu:SetFrameLevel(button:GetFrameLevel()+10)
    for index,char in ipairs(characters) do
        Button(menu,char.name.." - "..char.realm,0,(index-1)*28,260,function()
            Addon.pveSelectedCharacter=char.name.."-"..char.realm
            menu:Hide(); Addon:RefreshUI()
        end)
    end
    menu:Hide()
    button:SetScript("OnClick",function() if menu:IsShown() then menu:Hide() else menu:Show() end end)
    characters=chosen and {chosen} or {}
    return y+40,characters
end

local groups={"coiled","vaults","city","delves","prey","zuljarra","silvermoon","amani","harandar","voidstorm","accepted"}
local groupHelp={coiled="ES_COILED_GUIDE",vaults="ES_VAULTS_GUIDE"}
local function Title(row)
    if row.titleKey then return L[row.titleKey] end
    if row.name and row.name~="" then return row.name end
    local key="WEEKLY_QUEST_"..row.id
    return L[key]~=key and L[key] or string.format(L.WEEKLY_QUEST_ID,row.id)
end
local function Status(row)
    if type(row.current)=="number" then
        if type(row.maximum)=="number" and row.maximum>0 then
            return row.current.." / "..row.maximum..(row.state=="unverified" and " *" or "")
        end
        return tostring(row.current).." "..L.ES_HELD
    end
    if row.state=="active" and row.objectives then
        local current,maximum=0,0
        for _,objective in ipairs(row.objectives) do
            if type(objective.numFulfilled)=="number" and type(objective.numRequired)=="number" then
                current=current+objective.numFulfilled; maximum=maximum+objective.numRequired
            end
        end
        if maximum>0 then return current.." / "..maximum end
    end
    return L["WEEKLY_STATE_"..(row.state or "unknown")]
end
function ns.UI_WeeklyTooltip(frame,row)
    local tip=GameTooltip
    tip:SetOwner(frame,"ANCHOR_RIGHT")
    tip:SetText(Title(row),1,0.82,0,1,true)
    local completed=row.state=="complete"
    tip:AddLine(Status(row),completed and 0.3 or 1,completed and 0.85 or 0.65,completed and 0.55 or 0.3)
    if row.state=="notstarted" then tip:AddLine(L.ES_AVAILABILITY,0.65,0.65,0.65,true) end
    if row.mapName then tip:AddLine(row.mapName,0.4,0.85,0.8) end
    if row.location and row.location~="" then tip:AddLine(row.location,1,1,1,true) end
    if row.helpKey then tip:AddLine(" "); tip:AddLine(L[row.helpKey],1,1,1,true) end
    if row.description then tip:AddLine(" "); tip:AddLine(row.description,0.9,0.9,0.9,true) end
    if row.state=="unverified" then tip:AddLine(" "); tip:AddLine(L.ES_GILDED_UNVERIFIED,1,0.65,0.3,true) end
    if row.capKey and row.maximum then
        tip:AddDoubleLine(L[row.capKey],row.current.." / "..row.maximum,1,0.82,0,1,1,1)
    end
    if row.quantity then tip:AddDoubleLine(L.ES_OWNED,tostring(row.quantity),0.8,0.8,0.8,1,1,1) end
    for _,objective in ipairs(row.objectives or {}) do
        if objective.text then tip:AddLine(objective.text,0.85,0.85,0.85,true) end
    end
    for _,detail in ipairs(row.details or {}) do
        tip:AddLine((detail.complete and "|cff4cd787" or "|cff8a8f9c")..(detail.name or "").."|r",1,1,1,true)
    end
    if row.rewards and #row.rewards>0 then
        tip:AddLine(" "); tip:AddLine(L.ES_REWARDS,1,0.82,0)
        for _,reward in ipairs(row.rewards) do
            local icon=reward.icon and "|T"..reward.icon..":16:16|t " or ""
            tip:AddDoubleLine(icon..reward.name,tostring(reward.quantity),0.9,0.9,0.9,1,1,1)
        end
    elseif type(row.id)=="number" and row.state~="complete" then
        tip:AddLine(L.ES_REWARDS_LOADING,0.6,0.6,0.6,true)
    end
    tip:AddLine(" ")
    tip:AddLine(L[row.account and "WEEKLY_ACCOUNT" or "WEEKLY_CHARACTER"],0.4,0.8,0.75)
    if row.capturedAt then tip:AddLine(L.ES_CHECKED..date("%d %b %H:%M",row.capturedAt),0.55,0.55,0.55) end
    if row.state=="unknown" then tip:AddLine(L[row.id=="delve:stash" and "ES_GILDED_REFRESH" or "ES_REFRESH"],0.65,0.65,0.65,true) end
    tip:Show()
end
function ns.UI_DrawWeeklyActivities(parent,y,char)
    local width=parent:GetWidth()-20
    local key=char.name.."-"..char.realm
    Addon.db.profile.weeklyHidden=Addon.db.profile.weeklyHidden or {}
    local hidden=Addon.db.profile.weeklyHidden[key] or {}
    Addon.db.profile.weeklyHidden[key]=hidden
    Addon.weeklyCollapsed=Addon.weeklyCollapsed or {}
    local controlWidth=(width-12)/3
    Button(parent,L[Addon.weeklyOther and "ES_MIDNIGHT_ONLY" or "ES_SHOW_OTHER"],10,y,controlWidth,function()
        Addon.weeklyOther=not Addon.weeklyOther; Addon:RefreshUI()
    end)
    Button(parent,L[Addon.weeklyHideComplete and "WEEKLY_SHOW_COMPLETE" or "WEEKLY_HIDE_COMPLETE"],16+controlWidth,y,controlWidth,function()
        Addon.weeklyHideComplete=not Addon.weeklyHideComplete; Addon:RefreshUI()
    end)
    Button(parent,L[Addon.weeklyManage and "WEEKLY_FINISH_MANAGE" or "WEEKLY_MANAGE"],22+controlWidth*2,y,controlWidth,function()
        Addon.weeklyManage=not Addon.weeklyManage; Addon:RefreshUI()
    end)
    y=y+38
    local rows=Addon:GetWeeklyActivityRows(char)
    for _,group in ipairs(groups) do
        local list,done={},0
        for _,row in ipairs(rows) do
            local id=row.pool or row.id
            if row.group==group and (Addon.weeklyManage or not hidden[id]) then
                if row.state=="complete" then done=done+1 end
                if Addon.weeklyManage or not Addon.weeklyHideComplete or row.state~="complete" then list[#list+1]=row end
            end
        end
        if #list>0 and (group~="accepted" or Addon.weeklyOther or Addon.weeklyManage) then
            local open=not Addon.weeklyCollapsed[group]
            local heading=L["ES_GROUP_"..group]
            if done>0 then heading=heading.."  |cff8a8f9c"..string.format(L.ES_COMPLETED,done).."|r" end
            local header=ns.UI_CreateCollapsibleHeader(parent,heading,group,open,function(value)
                Addon.weeklyCollapsed[group]=not value; Addon:RefreshUI()
            end)
            header:SetPoint("TOPLEFT",10,-y); header:SetWidth(width); header:SetHeight(28); y=y+32
            if groupHelp[group] then
                local onEnter,onLeave=header:GetScript("OnEnter"),header:GetScript("OnLeave")
                header:SetScript("OnEnter",function(frame)
                    if onEnter then onEnter(frame) end
                    GameTooltip:SetOwner(frame,"ANCHOR_RIGHT")
                    GameTooltip:SetText(L["ES_GROUP_"..group],1,0.82,0)
                    GameTooltip:AddLine(L[groupHelp[group]],1,1,1,true)
                    GameTooltip:Show()
                end)
                header:SetScript("OnLeave",function(frame)
                    if onLeave then onLeave(frame) end
                    GameTooltip:Hide()
                end)
            end
            if open then
                for _,row in ipairs(list) do
                    local id=row.pool or row.id
                    local frame=Button(parent,"",20,y,width-10,function() end)
                    frame:SetBackdropBorderColor(0,0,0,0)
                    local icon=ns.UI_RenderTexture(frame,nil,"ARTWORK")
                    icon:SetSize(18,18); icon:SetPoint("LEFT",7,0)
                    icon:SetTexture(row.icon or (row.state=="complete" and "Interface\\RAIDFRAME\\ReadyCheck-Ready" or row.boss and "Interface\\Icons\\Achievement_Boss_Archimonde" or "Interface\\GossipFrame\\DailyQuestIcon"))
                    if row.state=="complete" then icon:SetDesaturated(true) end
                    local name=Text(frame,Title(row),33,7,math.max(80,width-190-(Addon.weeklyManage and 70 or 0)),row.state=="complete" and ns.UI_COLORS.textDim or ns.UI_COLORS.textNormal)
                    name:SetFontObject("QuartermasterFontBody")
                    local progress=Status(row)
                    local space=Addon.weeklyManage and 80 or 0
                    local progressColor=row.state=="unverified" and {1,0.65,0.3} or row.state=="complete" and ns.UI_COLORS.accent or ns.UI_COLORS.textDim
                    Text(frame,progress,width-150-space,8,123,progressColor):SetJustifyH("RIGHT")
                    if type(row.maximum)=="number" and row.maximum>0 and type(row.current)=="number" then
                        local track=ns.UI_RenderTexture(frame,nil,"BACKGROUND")
                        track:SetPoint("BOTTOMRIGHT",-12-space,2); track:SetSize(125,2); track:SetColorTexture(0.15,0.18,0.2,1)
                        local fill=ns.UI_RenderTexture(frame,nil,"ARTWORK")
                        fill:SetPoint("BOTTOMLEFT",track,"BOTTOMLEFT"); fill:SetSize(math.max(1,125*math.min(1,row.current/row.maximum)),2)
                        fill:SetColorTexture(unpack(row.state=="unverified" and progressColor or ns.UI_COLORS.accent))
                    end
                    if Addon.weeklyManage then
                        Button(frame,L[hidden[id] and "WEEKLY_TRACK" or "WEEKLY_HIDE"],width-89,0,74,function()
                            hidden[id]=not hidden[id] or nil; Addon:RefreshUI()
                        end)
                    end
                    frame:SetScript("OnEnter",function(b)
                        b:SetBackdropColor(unpack(ns.UI_COLORS.bgLight)); ns.UI_WeeklyTooltip(b,row)
                    end)
                    frame:SetScript("OnLeave",function(b) b:SetBackdropColor(unpack(ns.UI_COLORS.bgCard)); GameTooltip:Hide() end)
                    y=y+30
                end
            end
            y=y+6
        end
    end
    return y+8
end
