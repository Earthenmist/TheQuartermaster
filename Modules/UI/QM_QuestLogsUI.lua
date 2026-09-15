local _,ns=...
local Addon,L=ns.TheQuartermaster,ns.L
local function Text(parent,value,x,y,width,color)
    local t=ns.UI_RenderFontString(parent,nil,"OVERLAY","QuartermasterFontSmall")
    t:SetPoint("TOPLEFT",x,-y);t:SetWidth(math.max(1,width));t:SetJustifyH("LEFT");t:SetWordWrap(true)
    t:SetText(value);t:SetTextColor(unpack(color or ns.UI_COLORS.textNormal));return t
end
local function Button(parent,label,x,y,width,height,click)
    local b=ns.UI_RenderFrame("Button",nil,parent,"BackdropTemplate")
    b:SetPoint("TOPLEFT",x,-y);b:SetSize(width,height or 28)
    b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    b:SetBackdropColor(unpack(ns.UI_COLORS.bgCard));b:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
    Text(b,label,9,8,width-18):SetWordWrap(false)
    b:SetScript("OnClick",click)
    b:SetScript("OnEnter",function() b:SetBackdropBorderColor(unpack(ns.UI_COLORS.accent)) end)
    b:SetScript("OnLeave",function() b:SetBackdropBorderColor(unpack(ns.UI_COLORS.border)) end)
    return b
end
function Addon:DrawQuestLogs(parent)
    local profile=self.db.profile
    profile.questLogView=profile.questLogView or {}
    local f=profile.questLogView
    local chars=self.db.global.characters or {}
    if not f.character or not chars[f.character] then f.character=self:GetCharacterKey() end
    local snapshot=chars[f.character] and chars[f.character].questLog
    local supported=snapshot and snapshot.version==1
    local rows,categories=ns.QuestLogs.Filter(snapshot,f)
    self.questLogsPool=self.questLogsPool or ns.UI_NewRenderPool(parent)
    local root=self.questLogsPool:Begin(parent:GetWidth())
    local width=math.max(400,parent:GetWidth()-20);local third=(width-16)/3
    local function Refresh() self:RefreshUI() end
    local function Set(key,value) f[key]=value;f.page=1;f.detail=nil;Refresh() end
    Button(root,(f.character or L.QL_CHARACTER).."  v",10,8,third,28,function(b)
        ns.UI_RecipeMenu(b,function(_,menu)
            for key in ns.OrderedCharacterPairs(self.db) do
                menu:CreateButton(key,function() Set("character",key) end)
            end
        end)
    end)
    Button(root,L.QL_SCAN,18+third,8,third,28,function() self:QueueQuestLogs() end)
    Button(root,L.QL_RESET,26+third*2,8,third,28,function()
        f.category=nil;f.kind=nil;f.state=nil;f.query=nil;f.detail=nil;f.page=1;Refresh()
    end)
    local stamp=supported and snapshot.checked
    local status=stamp and string.format(L.QL_CHECKED,date("%d %b %H:%M",stamp)) or L.QL_NOT_SCANNED
    if f.character==self:GetCharacterKey() and self.questLogStatus and self.questLogStatus~="ready" then
        status=status.." | "..L["QL_SCAN_"..self.questLogStatus]
    end
    Text(root,status,10,46,width,ns.UI_COLORS.textDim)
    if not self.questLogSearch then
        local box=CreateFrame("EditBox",nil,root,"BackdropTemplate")
        box:SetAutoFocus(false);box:SetFontObject("QuartermasterFontSmall");box:SetTextInsets(8,8,0,0)
        box:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
        box:SetBackdropColor(unpack(ns.UI_COLORS.bgCard));box:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
        self.questLogSearch=box
    end
    local box=self.questLogSearch
    box:ClearAllPoints();box:SetPoint("TOPLEFT",10,-72);box:SetSize(width-110,28)
    if not box:HasFocus() then box:SetText(f.query or "") end
    box:SetScript("OnEnterPressed",function(b) b:ClearFocus();Set("query",b:GetText()) end)
    box:SetScript("OnEscapePressed",function(b) b:ClearFocus() end);box:Show()
    Button(root,L.QL_SEARCH,width-92,72,102,28,function() box:ClearFocus();Set("query",box:GetText()) end)
    local function Menu(field,label,options,x)
        Button(root,(f[field] and (field=="category" and f[field] or L["QL_"..f[field]]) or label).."  v",x,110,third,28,function(b)
            ns.UI_RecipeMenu(b,function(_,menu)
                menu:CreateButton(label,function() Set(field,nil) end)
                for _,value in ipairs(options) do menu:CreateButton(field=="category" and value or L["QL_"..value],function() Set(field,value) end) end
            end)
        end)
    end
    local names={};for name in pairs(categories) do names[#names+1]=name end;table.sort(names)
    Menu("category",L.QL_CATEGORIES,names,10)
    Menu("kind",L.QL_TYPES,{"normal","campaign","daily","weekly"},18+third)
    Menu("state",L.QL_STATES,{"active","ready","failed","unknown"},26+third*2)
    local hint=Text(root,L.QL_HINT,10,150,width,ns.UI_COLORS.textDim)
    local y=150+hint:GetStringHeight()+16
    Text(root,string.format(L.QL_COUNT,#rows),10,y,width);y=y+26
    local pages=math.max(1,math.ceil(#rows/20));f.page=math.max(1,math.min(f.page or 1,pages))
    Button(root,L.RB_PREVIOUS,10,y,95,28,function() f.page=math.max(1,f.page-1);f.detail=nil;Refresh() end)
    Text(root,string.format(L.CMP_PAGE,f.page,pages),120,y+8,width-240)
    Button(root,L.RB_NEXT,width-85,y,95,28,function() f.page=math.min(pages,f.page+1);f.detail=nil;Refresh() end)
    y=y+40
    if #rows==0 then local empty=Text(root,supported and L.QL_EMPTY or L.QL_NOT_SCANNED,10,y,width);y=y+empty:GetStringHeight()+20 end
    for i=(f.page-1)*20+1,math.min(#rows,f.page*20) do
        local row=rows[i]
        local b=Button(root,(f.detail==row.id and "- " or "+ ")..row.name,10,y,width,62,function() f.detail=f.detail~=row.id and row.id or nil;Refresh() end)
        local details=(row.category or L.QL_UNGROUPED).." | "..L["QL_"..row.kind]
        if row.level then details=details.." | "..string.format(L.QL_LEVEL,row.level) end
        Text(b,details,10,29,width-200,ns.UI_COLORS.textDim)
        Text(b,L["QL_"..row.state],width-180,29,170,row.state=="ready" and ns.UI_COLORS.accent or ns.UI_COLORS.textDim)
        y=y+70
        if f.detail==row.id then
            local function Detail(text,color)
                local label=Text(root,text,20,y,width-20,color);y=y+label:GetStringHeight()+9
            end
            Detail(string.format(L.QL_ID,row.id),ns.UI_COLORS.textDim)
            if row.tag then Detail(row.tag) end
            if row.summary then Detail(row.summary) end
            Detail(L.QL_OBJECTIVES)
            if row.objectives then
                if #row.objectives==0 then Detail(L.QL_NO_OBJECTIVES,ns.UI_COLORS.textDim) end
                for _,objective in ipairs(row.objectives) do Detail((objective.finished and "[x] " or "[ ] ")..objective.text) end
            else Detail(L.QL_DETAILS_UNKNOWN,ns.UI_COLORS.textDim) end
            if row.description then Detail(row.description,ns.UI_COLORS.textDim) end
            Detail(L.QL_REWARDS)
            if row.money and row.money>0 then
                Detail(L.QL_GOLD..": "..(profile.discretionMode and L.WL_HIDDEN or GetCoinTextureString(row.money)))
            end
            if row.xp and row.xp>0 then Detail(string.format(L.QL_XP,row.xp)) end
            for _,reward in ipairs(row.rewards or {}) do
                Detail(string.format(L.QL_REWARD_ITEM,L["QL_"..reward.kind],reward.quantity,reward.name))
            end
            if not row.rewards or row.rewardsIncomplete then Detail(L.QL_DETAILS_UNKNOWN,ns.UI_COLORS.textDim) end
            y=y+14
        end
    end
    return self.questLogsPool:Finish(y+20)
end
