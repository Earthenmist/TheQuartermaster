local _, ns = ...
local Addon, L, K = ns.TheQuartermaster, ns.L, ns.Knowledge
local function Text(parent, value, x, y, width, color, font)
    local label = ns.UI_RenderFontString(parent, nil, "OVERLAY", font or "QuartermasterFontSmall")
    label:SetPoint("TOPLEFT", x, -y); label:SetWidth(math.max(1, width)); label:SetJustifyH("LEFT")
    label:SetText(value); label:SetTextColor(unpack(color or ns.UI_COLORS.textNormal))
    return label
end
local function Panel(parent, x, y, width, height, kind)
    local frame = ns.UI_RenderFrame(kind or "Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", x, -y); frame:SetSize(width, height)
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1})
    frame:SetBackdropColor(unpack(ns.UI_COLORS.bgCard)); frame:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
    return frame
end
local function Button(parent, label, x, y, width, click)
    local b = Panel(parent, x, y, width, 28, "Button")
    Text(b, label, 9, 8, width-18):SetWordWrap(false)
    b:SetScript("OnClick", click)
    b:SetScript("OnEnter", function() b:SetBackdropBorderColor(unpack(ns.UI_COLORS.accent)) end)
    b:SetScript("OnLeave", function() b:SetBackdropBorderColor(unpack(ns.UI_COLORS.border)) end)
    return b
end
local function Waypoint(addon, source)
    if InCombatLockdown and InCombatLockdown() then return end
    local point = ns.Wealth.Read(UiMapPoint and UiMapPoint.CreateFromCoordinates, source.map, source.x, source.y)
    if point and point[1] and C_Map and C_Map.SetUserWaypoint then
        local result = ns.Wealth.Read(C_Map.SetUserWaypoint, point[1])
        if result then
            ns.Wealth.Read(C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint, true)
            return
        end
    end
    if addon.Print then addon:Print(L.KP_WAYPOINT_FAILED) end
end
local categories = {"book", "treasure", "treatise", "weekly_quest", "weekly_drop", "patron_order", "catch_up", "darkmoon", "first_craft", "first_gather"}

function Addon:DrawKnowledge(parent)
    if self.recipeDropdown then self.recipeDropdown:Hide() end
    self.knowledgePool = self.knowledgePool or ns.UI_NewRenderPool(parent)
    local root = self.knowledgePool:Begin(parent:GetWidth())
    local width = math.max(420, parent:GetWidth()-20)
    self.knowledgeFilters = self.knowledgeFilters or {expansion="Midnight"}
    local filters, records = self.knowledgeFilters, self:GetKnowledgeProfiles()
    local hideComplete = self.db.profile.knowledgeHideCompleted == true
    local function Refresh() self:RefreshUI() end
    local function Choose(field, value) filters[field]=value; filters.page=1; filters.detail=nil; Refresh() end
    local chars, professions = {}, {}
    for _, row in ipairs(records) do
        chars[row.key] = true
        if row.profile.expansion == filters.expansion then professions[row.profile.name] = true end
    end
    if not filters.character or not chars[filters.character] then
        filters.character = chars[self:GetCharacterKey()] and self:GetCharacterKey() or records[1] and records[1].key
    end
    local third = (width-16)/3
    Button(root, (filters.character or L.RB_ALL_CRAFTERS).."  v", 10, 10, third, function(b)
        ns.UI_RecipeMenu(b, function(_, menu)
            local keys={}; for key in pairs(chars) do keys[#keys+1]=key end; table.sort(keys)
            for _, key in ipairs(keys) do menu:CreateButton(key, function() Choose("character", key) end) end
        end)
    end)
    Button(root, (filters.expansion == "TWW" and L.KP_TWW or L.KP_MIDNIGHT).."  v", 18+third, 10, third, function(b)
        ns.UI_RecipeMenu(b, function(_, menu)
            menu:CreateButton(L.KP_MIDNIGHT, function() Choose("expansion", "Midnight") end)
            menu:CreateButton(L.KP_TWW, function() Choose("expansion", "TWW") end)
        end)
    end)
    local selected
    for _, row in ipairs(records) do
        if row.key == filters.character and row.profile.expansion == filters.expansion then
            if not selected or row.profile.name == filters.profession then selected=row end
        end
    end
    if selected then filters.profession = selected.profile.name end
    Button(root, (selected and selected.profile.name or L.RB_ALL_PROFESSIONS).."  v", 26+2*third, 10, third, function(b)
        ns.UI_RecipeMenu(b, function(_, menu)
            local names={}
            for _, row in ipairs(records) do
                if row.key == filters.character and row.profile.expansion == filters.expansion then names[#names+1]=row.profile.name end
            end
            table.sort(names)
            for _, name in ipairs(names) do menu:CreateButton(name, function() Choose("profession", name) end) end
        end)
    end)
    Button(root, L.CD_SCAN, 10, 48, 180, function() self:ScanKnowledge(); self:ScanProfessionDepth() end)
    local status = self.knowledgeState and L["KP_SCAN_"..self.knowledgeState] or L.KP_OPEN
    local statusText = Text(root, status, 200, 55, width-190, ns.UI_COLORS.textDim)
    local y=55+math.max(32, statusText:GetStringHeight()+12)
    if not selected then
        local empty=Text(root,L.KP_EMPTY,10,y,width)
        return self.knowledgePool:Finish(y+math.max(80,empty:GetStringHeight()+20))
    end
    local snapshot, profile = selected.snapshot, selected.profile
    local summary = snapshot.summary
    local function Card(title, value, hint, x)
        local card=Panel(root,x,y,third,82)
        Text(card,title,10,10,third-20,ns.UI_COLORS.textDim)
        Text(card,value,10,30,third-20,ns.UI_COLORS.accent,"QuartermasterFontBody")
        Text(card,hint,10,55,third-20,ns.UI_COLORS.textDim)
    end
    local valid = summary and summary.checked and summary.checked <= time()
    Card(L.KP_UNSPENT,valid and tostring(summary.unspent) or L.KP_UNKNOWN,L.KP_SNAPSHOT,10)
    Card(L.KP_SPENT,valid and summary.spent and string.format(L.KP_FRACTION,summary.spent,summary.capacity) or L.KP_UNKNOWN,L.KP_SPECIALIZATIONS,18+third)
    Card(L.KP_NEEDED,valid and summary.capacity and tostring(math.max(0,summary.capacity-summary.spent-summary.unspent)) or L.KP_UNKNOWN,L.KP_AFTER_UNSPENT,26+2*third)
    y=y+94
    local checked=Text(root,L.COVERAGE_COLLECTED..date("%d %b %H:%M",snapshot.checked),10,y,width,ns.UI_COLORS.textDim)
    y=y+22
    if valid and summary.checked ~= snapshot.checked then
        Text(root,L.KP_SUMMARY_DATE..date("%d %b %H:%M",summary.checked),10,y,width,ns.UI_COLORS.textDim); y=y+22
    end
    Button(root, (filters.category and L["KP_CATEGORY_"..filters.category] or L.KP_ALL_SOURCES).."  v",10,y,third,function(b)
        ns.UI_RecipeMenu(b,function(_,menu)
            menu:CreateButton(L.KP_ALL_SOURCES,function() Choose("category",nil) end)
            for _, category in ipairs(categories) do menu:CreateButton(L["KP_CATEGORY_"..category],function() Choose("category",category) end) end
        end)
    end)
    Button(root,hideComplete and L.KP_UNFINISHED or L.KP_ALL_STATES,18+third,y,third,function()
        self.db.profile.knowledgeHideCompleted = not hideComplete
        filters.page=1; filters.detail=nil; Refresh()
    end)
    Button(root,filters.help and L.KP_HIDE_HELP or L.KP_HELP_BUTTON,26+2*third,y,third,function() filters.help=not filters.help; Refresh() end)
    y=y+40
    if filters.help then
        local help=Text(root,L.KP_HELP,10,y,width,ns.UI_COLORS.textDim)
        y=y+math.max(60,help:GetStringHeight()+16)
    end
    local counts=K.SourceCounts(profile,snapshot,time())
    Text(root,string.format(L.KP_COUNTS,counts.complete,counts.tracked,counts.unverified),10,y,width)
    y=y+28
    if snapshot.catchup and (not filters.category or filters.category=="catch_up") then
        local catchup=snapshot.catchup
        local text=string.format(L.KP_TRACKER,catchup.earned,catchup.cap).." "..date("%d %b %H:%M",catchup.checked)
        if profile.catchUpRule then
            local remaining, state = K.CatchUpRemaining(profile,snapshot,time())
            text=(remaining and string.format(L.KP_CATCHUP_REMAINING,remaining) or L["KP_STATE_"..state])
                ..(state=="weeklyRequired" and " | "..L.KP_STATE_weeklyRequired or "")
                .." | "..L.COVERAGE_COLLECTED..date("%d %b %H:%M",catchup.checked)
        elseif not catchup.resetAt or time() >= catchup.resetAt then text=text.." | "..L.KP_STATE_stale end
        local label=Text(root,text,10,y,width,ns.UI_COLORS.textDim); y=y+math.max(28,label:GetStringHeight()+10)
    end
    local rows={}
    for _, source in ipairs(K.sources[profile.skill]) do
        if (not filters.category or source.category==filters.category) and source.category~="first_craft" then
            local state,done=K.SourceState(source,snapshot,time())
            if not hideComplete or state~="complete" and state~="collected" then
                rows[#rows+1]={source=source,state=state,done=done}
            end
        end
    end
    if not filters.category or filters.category=="first_craft" then
        for _, recipe in ipairs(K.FirstCraftRows(selected.character,profile.skill)) do
            rows[#rows+1]={recipe=recipe}
        end
        if filters.category=="first_craft" and #rows==0 then
            local label=Text(root,L.KP_FIRST_EMPTY,10,y,width); y=y+math.max(50,label:GetStringHeight()+16)
        end
    end
    local pages=math.max(1,math.ceil(#rows/12)); filters.page=math.max(1,math.min(pages,filters.page or 1))
    for i=(filters.page-1)*12+1,math.min(#rows,filters.page*12) do
        local row=rows[i]; local source=row.source
        local id=source and source.id or "recipe:"..row.recipe.id
        local name=source and source.name or row.recipe.name
        local panel=Panel(root,10,y,width,58,"Button")
        local heading=Text(panel,name,10,9,width*0.59,ns.UI_COLORS.textNormal,"QuartermasterFontBody")
        heading:SetWordWrap(false)
        local state=source and L["KP_STATE_"..row.state] or L.KP_FIRST_AVAILABLE
        if source and row.state=="remaining" then state=string.format(L.KP_CATCHUP_POINTS,row.done) end
        Text(panel,state,width*0.63,10,width*0.35, (row.state=="complete" or row.state=="collected") and ns.UI_COLORS.accent or ns.UI_COLORS.textDim)
        local detail=source and L["KP_CATEGORY_"..source.category] or L.KP_CATEGORY_first_craft
        if source and source.points then detail=detail.." | "..string.format(L.KP_REWARD,source.points) end
        if row.recipe then detail=detail.." | "..L.KP_FIRST_REWARD end
        if source and source.completion=="each" and row.done then detail=detail.." | "..string.format(L.KP_FRACTION,row.done,source.cap) end
        Text(panel,detail,10,34,width-20,ns.UI_COLORS.textDim)
        panel:SetScript("OnClick",function() filters.detail=filters.detail~=id and id or nil; Refresh() end)
        panel:SetScript("OnEnter",function() panel:SetBackdropBorderColor(unpack(ns.UI_COLORS.accent)) end)
        panel:SetScript("OnLeave",function() panel:SetBackdropBorderColor(unpack(ns.UI_COLORS.border)) end)
        y=y+66
        if filters.detail==id then
            local help=source and L["KP_GUIDE_"..source.category] or L.KP_FIRST_HELP
            if source and source.category=="catch_up" and profile.catchUpRule=="patron" then help=L.KP_PATRON_CATCHUP_HELP
            elseif source and source.category=="catch_up" and profile.catchUpRule=="weekly" then help=L.KP_WEEKLY_CATCHUP_HELP end
            if source and source.completion~="none" and source.category=="weekly_drop" then help=L.KP_WEEKLY_DROP_HELP
            elseif source and source.completion~="none" and source.category=="weekly_quest" then help=L.KP_WEEKLY_QUEST_HELP end
            if source and source.requirements~="" then help=help.."\n"..source.requirements end
            if source and source.group then help=help.."\n"..L.KP_GROUP_HELP end
            if row.recipe then help=help.."\n"..L.COVERAGE_COLLECTED..date("%d %b %H:%M",row.recipe.checked) end
            local label=Text(root,help,20,y,width-20,ns.UI_COLORS.textDim); y=y+math.max(38,label:GetStringHeight()+12)
            if source and source.map then
                Button(root,string.format(L.KP_WAYPOINT,source.x*100,source.y*100),20,y,220,function() Waypoint(self,source) end); y=y+38
            elseif row.recipe then
                Button(root,L.NAV_RECIPES,20,y,180,function() self:OpenDashboardDestination("recipes") end); y=y+38
            end
        end
    end
    if #rows==0 and filters.category~="first_craft" then Text(root,L.KP_NO_SOURCES,10,y,width); y=y+38 end
    Button(root,L.RB_PREVIOUS,10,y,100,function() filters.page=math.max(1,filters.page-1); filters.detail=nil; Refresh() end)
    Text(root,string.format(L.RB_PAGE,filters.page,pages),125,y+8,180)
    Button(root,L.RB_NEXT,width-90,y,100,function() filters.page=math.min(pages,filters.page+1); filters.detail=nil; Refresh() end)
    if not self._knowledgeViewTimer and C_Timer and C_Timer.After then
        self._knowledgeViewTimer=true
        C_Timer.After(60,function() self._knowledgeViewTimer=nil
            local main=self.UI and self.UI.mainFrame
            if main and main:IsShown() and main.currentTab=="knowledge" then Refresh() end
        end)
    end
    return self.knowledgePool:Finish(y+44)
end
