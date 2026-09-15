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
function Addon:DrawAchievements(parent)
    local profile=self.db.profile
    profile.achievementView=profile.achievementView or {}
    local f=profile.achievementView
    local chars=self.db.global.characters or {}
    if f.character and not chars[f.character] then f.character=nil end
    local snapshot=self.db.global.achievementData
    if f.character then snapshot=chars[f.character].achievements end
    local supported=snapshot and snapshot.version==1
    local rows,categories=ns.Achievements.Filter(self.db,f)
    self.achievementsPool=self.achievementsPool or ns.UI_NewRenderPool(parent)
    local root=self.achievementsPool:Begin(parent:GetWidth())
    local width=math.max(400,parent:GetWidth()-20);local third=(width-16)/3
    local function Refresh() self:RefreshUI() end
    local function Set(key,value) f[key]=value;f.page=1;f.detail=nil;f.criteriaPage=1;Refresh() end
    Button(root,(f.character or L.AC_WARBAND).."  v",10,8,third,28,function(b)
        ns.UI_RecipeMenu(b,function(_,menu)
            menu:CreateButton(L.AC_WARBAND,function() Set("character",nil) end)
            for key in ns.OrderedCharacterPairs(self.db) do
                menu:CreateButton(key,function() Set("character",key) end)
            end
        end)
    end)
    Button(root,L.AC_SCAN,18+third,8,third,28,function() self:QueueAchievements() end)
    Button(root,L.AC_RESET,26+third*2,8,third,28,function()
        f.category=nil;f.kind=nil;f.state=nil;f.query=nil;f.detail=nil;f.page=1;Refresh()
    end)
    local stamp=supported and snapshot.checked
    local status=stamp and string.format(L.AC_CHECKED,date("%d %b %H:%M",stamp)) or L.AC_NOT_SCANNED
    if (not f.character or f.character==self:GetCharacterKey()) and self.achievementStatus and self.achievementStatus~="ready" then
        status=status.." | "..L["AC_SCAN_"..self.achievementStatus]
    end
    Text(root,status,10,46,width,ns.UI_COLORS.textDim)
    if not self.achievementSearch then
        local box=CreateFrame("EditBox",nil,root,"BackdropTemplate")
        box:SetAutoFocus(false);box:SetFontObject("QuartermasterFontSmall");box:SetTextInsets(8,8,0,0)
        box:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
        box:SetBackdropColor(unpack(ns.UI_COLORS.bgCard));box:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
        self.achievementSearch=box
    end
    local box=self.achievementSearch
    box:ClearAllPoints();box:SetPoint("TOPLEFT",10,-72);box:SetSize(width-110,28)
    if not box:HasFocus() then box:SetText(f.query or "") end
    box:SetScript("OnEnterPressed",function(b) b:ClearFocus();Set("query",b:GetText()) end)
    box:SetScript("OnEscapePressed",function(b) b:ClearFocus() end);box:Show()
    Button(root,L.AC_SEARCH,width-92,72,102,28,function() box:ClearFocus();Set("query",box:GetText()) end)
    local function Menu(field,label,options,x)
        Button(root,(f[field] and (field=="category" and f[field] or L["AC_"..f[field]]) or label).."  v",x,110,third,28,function(b)
            ns.UI_RecipeMenu(b,function(_,menu)
                menu:CreateButton(label,function() Set(field,nil) end)
                for _,value in ipairs(options) do menu:CreateButton(field=="category" and value or L["AC_"..value],function() Set(field,value) end) end
            end)
        end)
    end
    local names={};for name in pairs(categories) do names[#names+1]=name end;table.sort(names)
    Menu("category",L.AC_CATEGORIES,names,10)
    Menu("state",L.AC_STATES,{"complete","incomplete","progress","unknown"},18+third)
    local hint=Text(root,L.AC_HINT,10,150,width,ns.UI_COLORS.textDim)
    local y=150+hint:GetStringHeight()+16
    Text(root,string.format(L.AC_COUNT,#rows),10,y,width);y=y+26
    local pages=math.max(1,math.ceil(#rows/20));f.page=math.max(1,math.min(f.page or 1,pages))
    Button(root,L.RB_PREVIOUS,10,y,95,28,function() f.page=math.max(1,f.page-1);f.detail=nil;Refresh() end)
    Text(root,string.format(L.CMP_PAGE,f.page,pages),120,y+8,width-240)
    Button(root,L.RB_NEXT,width-85,y,95,28,function() f.page=math.min(pages,f.page+1);f.detail=nil;Refresh() end)
    y=y+40
    if #rows==0 then local empty=Text(root,supported and L.AC_EMPTY or L.AC_NOT_SCANNED,10,y,width);y=y+empty:GetStringHeight()+20 end
    for i=(f.page-1)*20+1,math.min(#rows,f.page*20) do
        local row=rows[i]
        local meta=row.meta
        local b=Button(root,(f.detail==row.id and "- " or "+ ")..meta.name,10,y,width,62,function() f.detail=f.detail~=row.id and row.id or nil;f.criteriaPage=1;Refresh() end)
        Text(b,meta.category.." | "..(meta.shared and L.AC_SHARED or L.AC_PERSONAL),10,29,width-205,ns.UI_COLORS.textDim)
        Text(b,L["AC_"..row.state],width-185,29,175,row.state=="complete" and ns.UI_COLORS.accent or ns.UI_COLORS.textDim)
        y=y+70
        if f.detail==row.id then
            local function Detail(value,color)
                local label=Text(root,value,20,y,width-20,color);y=y+label:GetStringHeight()+9
            end
            Detail(string.format(L.AC_ID,row.id,meta.points or 0),ns.UI_COLORS.textDim)
            if meta.description then Detail(meta.description) end
            if f.character then
                Detail(row.shared and row.shared.completed and L.AC_ACCOUNT_COMPLETE or L.AC_ACCOUNT_INCOMPLETE)
            end
            if row.record then Detail(string.format(L.AC_CHECKED,date("%d %b %H:%M",row.record.checked)),ns.UI_COLORS.textDim) end
            if meta.reward and meta.reward~="" then Detail(L.AC_REWARD..": "..meta.reward) end
            if row.record and row.record.criteria then
                Detail(L.AC_CRITERIA)
                local criteria=row.record.criteria
                local pages=math.max(1,math.ceil(#criteria/25))
                f.criteriaPage=math.max(1,math.min(f.criteriaPage or 1,pages))
                if pages>1 then
                    Button(root,L.RB_PREVIOUS,20,y,95,28,function() f.criteriaPage=math.max(1,f.criteriaPage-1);Refresh() end)
                    Text(root,string.format(L.CMP_PAGE,f.criteriaPage,pages),125,y+8,180)
                    Button(root,L.RB_NEXT,310,y,95,28,function() f.criteriaPage=math.min(pages,f.criteriaPage+1);Refresh() end)
                    y=y+38
                end
                for ci=(f.criteriaPage-1)*25+1,math.min(#criteria,f.criteriaPage*25) do
                    local c=criteria[ci]
                    local value=c.quantityText and c.quantityText~="" and c.quantityText or (tostring(c.quantity).." / "..tostring(c.required))
                    if profile.discretionMode and (c.kind==62 or c.kind==67) then value=L.WL_HIDDEN end
                    Detail((c.completed and "[x] " or "[ ] ")..c.text.." — "..value)
                end
                if #row.record.criteria==0 then Detail(L.AC_NO_CRITERIA,ns.UI_COLORS.textDim) end
            elseif row.state~="complete" then Detail(L.AC_DETAILS_UNKNOWN,ns.UI_COLORS.textDim) end
            if not meta.shared then
                local names={}
                for key,char in ns.OrderedCharacterPairs(self.db) do
                    local snap=char.achievements
                    if snap and snap.version==1 and snap.rows[row.id] and snap.rows[row.id].personal==true then names[#names+1]=key end
                end
                Detail(L.AC_EARNED_BY..": "..(#names>0 and table.concat(names,", ") or L.AC_NONE_RECORDED),ns.UI_COLORS.textDim)
            end
            y=y+14
        end
    end
    return self.achievementsPool:Finish(y+20)
end
