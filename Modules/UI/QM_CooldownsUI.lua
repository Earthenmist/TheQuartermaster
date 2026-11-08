local _, ns = ...
local Addon,L=ns.TheQuartermaster,ns.L
local function Text(parent,value,x,y,width,color)
    local label=ns.UI_RenderFontString(parent,nil,"OVERLAY","QuartermasterFontSmall")
    label:SetPoint("TOPLEFT",x,-y); label:SetWidth(math.max(1,width)); label:SetJustifyH("LEFT")
    label:SetText(value); label:SetTextColor(unpack(color or ns.UI_COLORS.textNormal))
    return label
end
local function Button(parent,value,x,y,width,click)
    local b=ns.UI_RenderFrame("Button",nil,parent,"BackdropTemplate")
    b:SetPoint("TOPLEFT",x,-y); b:SetSize(width,28)
    b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    b:SetBackdropColor(unpack(ns.UI_COLORS.bgCard)); b:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
    Text(b,value,8,8,width-16):SetWordWrap(false)
    b:SetScript("OnClick",click)
    b:SetScript("OnEnter",function() b:SetBackdropBorderColor(unpack(ns.UI_COLORS.accent)) end)
    b:SetScript("OnLeave",function() b:SetBackdropBorderColor(unpack(ns.UI_COLORS.border)) end)
    return b
end
function Addon:DrawProfessionCooldowns(parent)
    if self.recipeDropdown then self.recipeDropdown:Hide() end
    self.cooldownPool=self.cooldownPool or ns.UI_NewRenderPool(parent)
    local root=self.cooldownPool:Begin(parent:GetWidth())
    local width=math.max(420,parent:GetWidth()-20)
    self.cooldownFilters=self.cooldownFilters or {}
    local filters=self.cooldownFilters
    local rows,counts=self:GetProfessionCooldownRows()
    local function Refresh() self:RefreshUI() end
    local function Filter(field,choices,label,x)
        Button(root,label.."  v",x,10,(width-16)/3,function(b)
            ns.UI_RecipeMenu(b,function(_,menu)
                menu:CreateButton(L.CD_ALL,function() filters[field]=nil; filters.page=1; Refresh() end)
                local names={}; for name in pairs(choices) do names[#names+1]=name end; table.sort(names)
                for _,name in ipairs(names) do menu:CreateButton(name,function() filters[field]=name; filters.page=1; Refresh() end) end
            end)
        end)
    end
    local chars,professions={},{}
    for _,row in ipairs(rows) do chars[row.character]=true; professions[row.profession]=true end
    local third=(width-16)/3
    Filter("character",chars,filters.character or L.RB_ALL_CRAFTERS,10)
    Filter("profession",professions,filters.profession or L.RB_ALL_PROFESSIONS,18+third)
    Button(root,filters.ready and L.CD_READY_ONLY or L.CD_ALL_STATES,26+2*third,10,third,function()
        filters.ready=not filters.ready; filters.page=1; Refresh()
    end)
    local hint=Text(root,L.CD_HINT,10,50,width)
    local y=50+math.max(40,hint:GetStringHeight()+12)
    Button(root,L.CD_SCAN,10,y,190,function() self:ScanProfessionDepth() end)
    Text(root,string.format(L.CD_COUNTS,counts.ready,counts.estimated,counts.cooling,counts.stale),210,y+7,width-200)
    y=y+40
    if self.professionDepthState then
        local status=Text(root,L["PD_SCAN_"..self.professionDepthState],10,y,width,ns.UI_COLORS.textDim)
        y=y+math.max(28,status:GetStringHeight()+10)
    end
    local matching={}
    for _,row in ipairs(rows) do
        if (not filters.character or filters.character==row.character) and (not filters.profession or filters.profession==row.profession)
            and (not filters.ready or row.state=="ready" or row.state=="estimated") then matching[#matching+1]=row end
    end
    local pages=math.max(1,math.ceil(#matching/20)); filters.page=math.max(1,math.min(pages,filters.page or 1))
    for i=(filters.page-1)*20+1,math.min(#matching,filters.page*20) do
        local row=matching[i]
        local state=L["CD_STATE_"..row.state]
        if row.remaining then
            local minutes = math.ceil(row.remaining / 60)
            state = string.format(L.CD_REMAINING, math.floor(minutes / 60), minutes % 60)
        end
        local label=Text(root,row.data.name,18,y,width*0.60,ns.UI_COLORS.accent)
        Text(root,state,width*0.64,y,width*0.35)
        Text(root,row.character.." | "..row.profession.." | "..(row.data.expansion or ""),18,y+20,width-20)
        local details=L.COVERAGE_COLLECTED..date("%d %b %H:%M",row.data.checked)
        if row.data.maxCharges and row.data.maxCharges>0 then details=details.." | "..string.format(L.CD_CHARGES,row.data.charges,row.data.maxCharges) end
        if row.data.daily then details=details.." | "..L.CD_DAILY end
        Text(root,details,18,y+38,width-20,ns.UI_COLORS.textDim)
        y=y+66
    end
    if #matching==0 then
        local empty=Text(root,L.CD_EMPTY,18,y,width-20); y=y+math.max(60,empty:GetStringHeight()+16)
    end
    Button(root,L.RB_PREVIOUS,10,y,100,function() filters.page=math.max(1,filters.page-1); Refresh() end)
    Text(root,string.format(L.RB_PAGE,filters.page,pages),125,y+8,180)
    Button(root,L.RB_NEXT,width-90,y,100,function() filters.page=math.min(pages,filters.page+1); Refresh() end)
    if not self._cooldownViewTimer and C_Timer and C_Timer.After then
        self._cooldownViewTimer=true
        C_Timer.After(60,function()
            self._cooldownViewTimer=nil
            local frame=self.UI and self.UI.mainFrame
            if frame and frame:IsShown() and frame.currentTab=="cooldowns" then Refresh() end
        end)
    end
    return self.cooldownPool:Finish(y+44)
end
