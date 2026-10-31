local _,ns=...
local Addon,L,C=ns.TheQuartermaster,ns.L,ns.Comparison
local function Text(parent,value,x,y,width,color)
    local t=ns.UI_RenderFontString(parent,nil,"OVERLAY","QuartermasterFontSmall")
    t:SetPoint("TOPLEFT",x,-y);t:SetWidth(math.max(1,width));t:SetJustifyH("LEFT");t:SetWordWrap(false)
    t:SetText(value);t:SetTextColor(unpack(color or ns.UI_COLORS.textNormal));return t
end
local function Panel(parent,x,y,width,height)
    local b=ns.UI_RenderFrame("Button",nil,parent,"BackdropTemplate")
    b:SetPoint("TOPLEFT",x,-y);b:SetSize(width,height)
    b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    b:SetBackdropColor(unpack(ns.UI_COLORS.bgCard));b:SetBackdropBorderColor(unpack(ns.UI_COLORS.border));return b
end
local function Button(parent,label,x,y,width,fn)
    local b=Panel(parent,x,y,width,28);Text(b,label,9,8,width-18);b:SetScript("OnClick",fn)
    b:SetScript("OnEnter",function() b:SetBackdropBorderColor(unpack(ns.UI_COLORS.accent)) end)
    b:SetScript("OnLeave",function() b:SetBackdropBorderColor(unpack(ns.UI_COLORS.border)) end);return b
end
local function Menu(button,values,choose,all,sort)
    ns.UI_RecipeMenu(button,function(_,menu)
        if all then menu:CreateButton(all,function() choose(nil) end) end
        local names={};for name in pairs(values) do names[#names+1]=name end;table.sort(names,sort)
        for _,name in ipairs(names) do menu:CreateButton(name,function() choose(name) end) end
    end)
end
function Addon:DrawComparison(parent,domain)
    local settings=C.Settings(self,domain)
    if domain=="currency" then settings.query=ns.currencySearchText or ""
    elseif domain=="reputations" then settings.query=ns.reputationSearchText or "" end
    local model=C.Build(self,domain,settings)
    self.comparisonPool=self.comparisonPool or ns.UI_NewRenderPool(parent)
    local root=self.comparisonPool:Begin(parent:GetWidth())
    local width=math.max(400,parent:GetWidth()-20)
    local function Refresh() self:RefreshUI() end
    local function Set(field,value) settings[field]=value;settings.page=1;Refresh() end
    local third=(width-16)/3
    Button(root,L.CMP_CHARACTERS.."  v",10,8,third,function(b)
        ns.UI_RecipeMenu(b,function(_,menu)
            menu:CreateButton(L.CMP_ALL,function() settings.characters=nil;settings.column=1;Refresh() end)
            menu:CreateButton(L.CMP_FAVORITES,function()
                settings.characters={};for _,key in ipairs(self.db.global.favoriteCharacters or {}) do settings.characters[key]=true end
                settings.column=1;Refresh()
            end)
            for key in ns.OrderedCharacterPairs(self.db) do
                local checked=not settings.characters or settings.characters[key]
                menu:CreateButton((checked and "[x] " or "[ ] ")..key,function()
                    if not settings.characters then settings.characters={};for k in pairs(self.db.global.characters) do settings.characters[k]=true end end
                    settings.characters[key]=not settings.characters[key] or nil;settings.column=1;Refresh()
                end)
            end
        end)
    end)
    Button(root,(settings.expansion or L.PD_ALL_EXPANSIONS).."  v",18+third,8,third,function(b)
        Menu(b,model.expansions,function(value) Set("expansion",value) end,L.PD_ALL_EXPANSIONS,ns.ExpansionNewestFirst)
    end)
    if domain=="professions" then
        Button(root,(model.profession or L.RB_ALL_PROFESSIONS).."  v",26+third*2,8,third,function(b)
            Menu(b,model.professions,function(value) Set("profession",value) end)
        end)
    else
        Button(root,L.CMP_RESET,26+third*2,8,third,function() settings.expansion=nil;settings.characters=nil;settings.column=1;settings.page=1;Refresh() end)
    end
    Text(root,L.CMP_HINT,10,46,width,ns.UI_COLORS.textDim):SetWordWrap(true)
    local nameWidth=math.min(230,width*0.29)
    local columns=math.max(1,math.min(5,math.floor((width-nameWidth)/145)))
    local maxOffset=math.max(1,#model.characters-columns+1)
    settings.column=math.max(1,math.min(settings.column or 1,maxOffset))
    local cellWidth=(width-nameWidth)/columns
    Button(root,"<",10,80,32,function() settings.column=math.max(1,settings.column-1);Refresh() end)
    Button(root,">",48,80,32,function() settings.column=math.min(maxOffset,settings.column+1);Refresh() end)
    Text(root,string.format(L.CMP_COLUMNS,math.min(settings.column,#model.characters),math.min(#model.characters,settings.column+columns-1),#model.characters),90,89,width-90)
    if not self.comparisonSlider then
        local slider=CreateFrame("Slider",nil,root,"BackdropTemplate")
        slider:SetOrientation("HORIZONTAL");slider:SetValueStep(1);slider:SetObeyStepOnDrag(true)
        slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        slider:GetThumbTexture():SetVertexColor(unpack(ns.UI_COLORS.accent));slider:GetThumbTexture():SetSize(8,14)
        slider:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});slider:SetBackdropColor(unpack(ns.UI_COLORS.border))
        self.comparisonSlider=slider
    end
    local slider=self.comparisonSlider;slider:SetScript("OnValueChanged",nil)
    slider:ClearAllPoints();slider:SetPoint("TOPRIGHT",root,"TOPRIGHT",-10,-91);slider:SetSize(math.max(80,width*0.25),4)
    slider:SetMinMaxValues(1,maxOffset);slider:SetValue(settings.column);slider:SetShown(maxOffset>1)
    slider:SetScript("OnValueChanged",function(_,value)
        local offset=math.floor(value+0.5)
        if offset~=settings.column then settings.column=offset;Refresh() end
    end)
    local y=118
    Text(root,domain=="professions" and model.profession or L.CMP_MEASURE,10,y,nameWidth)
    for index=settings.column,math.min(#model.characters,settings.column+columns-1) do
        local character=model.characters[index]
        local b=Panel(root,10+nameWidth+(index-settings.column)*cellWidth,y-5,cellWidth-4,32)
        local classColor=RAID_CLASS_COLORS and RAID_CLASS_COLORS[character.class]
        Text(b,character.name,8,10,cellWidth-20,classColor and {classColor.r,classColor.g,classColor.b,1})
        b:SetScript("OnEnter",function() GameTooltip:SetOwner(b,"ANCHOR_RIGHT");GameTooltip:SetText(character.key);GameTooltip:Show() end)
        b:SetScript("OnLeave",function() GameTooltip:Hide() end)
    end
    y=y+36
    local pages=math.max(1,math.ceil(#model.rows/20));settings.page=math.min(settings.page or 1,pages)
    local group
    local function DrawCell(cell,x,w,row,key)
        local b=Panel(root,x,y,w-4,42)
        local dated=cell and cell.checked
        Text(b,cell and cell.text or L.CMP_MISSING,8,8,w-20,dated and ns.UI_COLORS.textNormal or ns.UI_COLORS.textDim)
        if cell and ns.Wealth.Number(cell.current) and ns.Wealth.Number(cell.cap) and cell.cap>0 then
            local bar=ns.UI_RenderTexture(b,nil,"ARTWORK");bar:SetColorTexture(unpack(ns.UI_COLORS.accent))
            bar:SetPoint("BOTTOMLEFT",8,6);bar:SetSize(math.max(1,(w-20)*math.max(0,math.min(1,cell.current/cell.cap))),3)
        end
        b:SetScript("OnEnter",function()
            GameTooltip:SetOwner(b,"ANCHOR_RIGHT");GameTooltip:SetText(row.name)
            GameTooltip:AddLine(cell and cell.text or L.CMP_MISSING,1,1,1,true)
            if cell and cell.note then GameTooltip:AddLine(cell.note,0.8,0.8,0.8,true) end
            GameTooltip:AddLine(dated and L.COVERAGE_COLLECTED..date("%d %b %H:%M",dated) or L.CMP_DATE_UNKNOWN,0.8,0.8,0.8,true)
            if row.shared then GameTooltip:AddLine(L.CMP_SHARED..": "..(row.observedOn or ""),0.8,0.8,0.8,true) end
            if cell and cell.target then GameTooltip:AddLine(L.CMP_OPEN,0.8,0.8,0.8,true) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave",function() GameTooltip:Hide() end)
        if cell and cell.target then b:SetScript("OnClick",function() self:OpenComparisonDetail(key,cell) end) end
    end
    for index=(settings.page-1)*20+1,math.min(#model.rows,settings.page*20) do
        local row=model.rows[index];local label=(row.shared and L.CMP_SHARED.." · " or "")..row.expansion
        if group~=label then Text(root,label,10,y,width,ns.UI_COLORS.accent);y=y+24;group=label end
        Text(root,row.name,10,y+10,nameWidth-12):SetWordWrap(true)
        if row.shared then DrawCell(row.sharedCell,10+nameWidth,width-nameWidth,row,row.observedOn)
        else
            for col=settings.column,math.min(#model.characters,settings.column+columns-1) do
                local key=model.characters[col].key
                DrawCell(row.cells[key],10+nameWidth+(col-settings.column)*cellWidth,cellWidth,row,key)
            end
        end
        y=y+48
    end
    if #model.rows==0 or #model.characters==0 then Text(root,L.CMP_EMPTY,10,y,width);y=y+40 end
    Button(root,L.RB_PREVIOUS,10,y,100,function() settings.page=math.max(1,settings.page-1);Refresh() end)
    Text(root,string.format(L.CMP_PAGE,settings.page,pages),122,y+8,width-240)
    Button(root,L.RB_NEXT,width-90,y,100,function() settings.page=math.min(pages,settings.page+1);Refresh() end)
    return self.comparisonPool:Finish(y+42)
end
