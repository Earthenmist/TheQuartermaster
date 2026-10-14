-- Cached profession gear, grouped by skill and using the shared character order.
local _, ns = ...
local Addon, L = ns.TheQuartermaster, ns.L
local groups = {
    {key=1, title="PG_PRIMARY_ONE", slots={20,21,22}},
    {key=2, title="PG_PRIMARY_TWO", slots={23,24,25}},
    {key="cooking", title="PG_COOKING", slots={26,27}},
    {key="fishing", title="PG_FISHING", slots={28}},
}
local function Profession(char, key)
    return (char.gearProfessions and char.gearProfessions[key]) or (char.professions and char.professions[key])
end
local function FilterKey(prof)
    return prof and prof.name and tostring(prof.skillLine or prof.name)
end
local function Text(parent, value, x, y, width, color)
    local text = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
    text:SetPoint("TOPLEFT", x, -y); text:SetWidth(width); text:SetJustifyH("LEFT")
    text:SetWordWrap(false); text:SetText(value); text:SetTextColor(unpack(color))
    return text
end
local function Skin(frame, color)
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1})
    frame:SetBackdropColor(unpack(color)); frame:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
end
function Addon:DrawProfessionEquipmentList(parent)
    local colors = ns.UI_COLORS
    local characters = ns.SortCharacterRows(self.db, self.GetCachedCharacters and self:GetCachedCharacters() or self:GetAllCharacters(), nil)
    local width = parent:GetWidth()-20
    local nameWidth = math.min(210, width*0.23)
    local groupWidth = (width-nameWidth-20)/4
    local choices, seen = {{key="all", name=L.PG_ALL}}, {}
    for _, char in ipairs(characters) do
        for _, group in ipairs(groups) do
            local prof = Profession(char, group.key)
            local key = FilterKey(prof)
            if key and not seen[key] then choices[#choices+1]={key=key,name=prof.name}; seen[key]=true end
        end
    end
    table.sort(choices, function(a,b) if a.key=="all" then return b.key~="all" elseif b.key=="all" then return false end return a.name<b.name end)
    local selected = self.professionGearFilter or "all"
    if selected~="all" and not seen[selected] then selected="all"; self.professionGearFilter=nil end
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(220,26); button:SetPoint("TOPLEFT",10,-8); Skin(button,colors.bgCard)
    local current = L.PG_ALL
    for _, choice in ipairs(choices) do if choice.key==selected then current=choice.name end end
    Text(button, current, 8, 6, 186, colors.textNormal)
    local arrow=button:CreateTexture(nil,"ARTWORK")
    arrow:SetSize(12,12); arrow:SetPoint("RIGHT",-6,0)
    arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up"); arrow:SetVertexColor(unpack(colors.accent))
    button:SetScript("OnEnter",function(b) b:SetBackdropBorderColor(unpack(colors.accent)) end)
    button:SetScript("OnLeave",function(b) b:SetBackdropBorderColor(unpack(colors.border)) end)
    local menu = CreateFrame("Frame",nil,button,"BackdropTemplate")
    menu:SetSize(220,#choices*24+8); menu:SetPoint("TOPLEFT",button,"BOTTOMLEFT",0,-2)
    menu:SetFrameStrata("DIALOG"); Skin(menu,colors.bgCard); menu:Hide()
    for i, choice in ipairs(choices) do
        local option=CreateFrame("Button",nil,menu,"BackdropTemplate")
        option:SetSize(212,24); option:SetPoint("TOPLEFT",4,-4-(i-1)*24); Skin(option,colors.bgCard)
        Text(option,choice.name,6,5,200,choice.key==selected and colors.accent or colors.textNormal)
        option:SetScript("OnEnter",function(b) b:SetBackdropBorderColor(unpack(colors.accent)) end)
        option:SetScript("OnLeave",function(b) b:SetBackdropBorderColor(unpack(colors.border)) end)
        option:SetScript("OnClick",function() self.professionGearFilter=choice.key; menu:Hide(); self:RefreshUI() end)
    end
    button:SetScript("OnClick",function() if menu:IsShown() then menu:Hide() else menu:Show() end end)
    Text(parent,L.PG_LEGEND,244,15,width-244,colors.textDim)
    Text(parent,L.PG_CHARACTER,22,47,nameWidth-12,colors.textDim)
    for i,group in ipairs(groups) do Text(parent,L[group.title],20+nameWidth+(i-1)*groupWidth,47,groupWidth-8,colors.textDim) end
    local y, visible = 70, 0
    for _, char in ipairs(characters) do
        local matches = selected=="all"
        for _, group in ipairs(groups) do if FilterKey(Profession(char,group.key))==selected then matches=true end end
        if matches then
            visible=visible+1
            local row=CreateFrame("Frame",nil,parent,"BackdropTemplate")
            row:SetSize(width,76); row:SetPoint("TOPLEFT",10,-y)
            row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); row:SetBackdropColor(unpack(visible%2==0 and colors.bg or colors.bgCard))
            local class=RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.classFile or ""]
            local color=class and {class.r,class.g,class.b,1} or colors.textNormal
            local nameLabel = Text(row,char.name or "?",12,20,nameWidth-16,color)
            nameLabel:SetFontObject("QuartermasterFontBody")
            Text(row,char.realm or "",12,39,nameWidth-16,colors.textDim)
            for i,group in ipairs(groups) do
                local prof=Profession(char,group.key)
                local unlearned=prof and prof.learned==false and prof.lastScan
                local title=unlearned and L.PG_NOT_LEARNED or prof and prof.name or L.PG_UNSCANNED
                local x=nameWidth+10+(i-1)*groupWidth
                local caption=Text(row,title,x,8,groupWidth-8,unlearned and colors.textDim or colors.textNormal)
                local nameHit=CreateFrame("Frame",nil,row); nameHit:SetPoint("TOPLEFT",x,-4); nameHit:SetSize(groupWidth-8,22); nameHit:EnableMouse(true)
                nameHit:SetScript("OnEnter",function(b)
                    GameTooltip:SetOwner(b,"ANCHOR_TOP"); GameTooltip:SetText(title)
                    GameTooltip:AddLine(L.PG_REFRESH,0.7,0.7,0.7,true); GameTooltip:Show()
                end)
                nameHit:SetScript("OnLeave",function() GameTooltip:Hide() end)
                if not unlearned then
                    local size=math.min(30,(groupWidth-16)/3)
                    for j,slot in ipairs(group.slots) do
                        local item=char.professionEquipment and char.professionEquipment[slot]
                        local state=ns.EquipmentSlotState(item)
                        local cell=CreateFrame("Button",nil,row,"BackdropTemplate")
                        cell:SetSize(size,size); cell:SetPoint("TOPLEFT",x+(j-1)*(size+5),-32); Skin(cell,colors.bg)
                        local slotLabel=j==1 and L.PG_TOOL or string.format(L.PG_ACCESSORY,j-1)
                        if state=="item" then
                            local icon=cell:CreateTexture(nil,"ARTWORK"); icon:SetPoint("TOPLEFT",2,-2); icon:SetPoint("BOTTOMRIGHT",-2,2)
                            icon:SetTexture(item.iconFileID or "Interface\\Icons\\INV_Misc_QuestionMark")
                            local hex=type(item.itemLink)=="string" and item.itemLink:match("|c%x%x(%x%x%x%x%x%x)")
                            local quality=item.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
                            if hex then cell:SetBackdropBorderColor(tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255,1)
                            elseif quality then cell:SetBackdropBorderColor(quality.r,quality.g,quality.b,1) end
                        else
                            Text(cell,state=="empty" and "-" or "?",9,8,size-10,state=="empty" and colors.textDim or colors.warning)
                        end
                        cell:SetScript("OnEnter",function(b)
                            GameTooltip:SetOwner(b,"ANCHOR_TOP")
                            if state=="item" and (item.itemLink or item.itemID) then GameTooltip:SetHyperlink(item.itemLink or "item:"..item.itemID)
                            else GameTooltip:SetText(state=="empty" and L.EQ_EMPTY or L.EQ_UNSCANNED) end
                            GameTooltip:AddLine(title.." - "..slotLabel,1,1,1)
                            GameTooltip:AddLine(item and item.lastScan and string.format(L.EQ_SCANNED,date("%Y-%m-%d %H:%M",item.lastScan)) or L.EQ_SCAN_UNKNOWN,0.7,0.7,0.7,true)
                            GameTooltip:AddLine(L.PG_REFRESH,0.7,0.7,0.7,true); GameTooltip:Show()
                        end)
                        cell:SetScript("OnLeave",function() GameTooltip:Hide() end)
                    end
                end
            end
            y=y+78
        end
    end
    if visible==0 then Text(parent,L.PG_NO_MATCH,20,y,width-20,colors.textDim); y=y+30 end
    return y+10
end
