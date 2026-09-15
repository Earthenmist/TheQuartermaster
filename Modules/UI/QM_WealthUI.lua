local _,ns=...
local Addon,L=ns.TheQuartermaster,ns.L
local function Text(parent,value,x,y,width,font,color)
    local label=ns.UI_RenderFontString(parent,nil,"OVERLAY",font or "QuartermasterFontBody")
    label:SetPoint("TOPLEFT",x,-y); label:SetWidth(math.max(1,width)); label:SetJustifyH("LEFT")
    label:SetWordWrap(false); label:SetText(value); label:SetTextColor(unpack(color or ns.UI_COLORS.textNormal))
    return label
end
local function Panel(parent,x,y,width,height)
    local panel=ns.UI_RenderFrame("Button",nil,parent,"BackdropTemplate")
    panel:SetPoint("TOPLEFT",x,-y); panel:SetSize(width,height)
    panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    panel:SetBackdropColor(unpack(ns.UI_COLORS.bgCard)); panel:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
    return panel
end
local function Button(parent,label,x,y,width,callback)
    local button=Panel(parent,x,y,width,28); Text(button,label,8,7,width-16,"QuartermasterFontSmall")
    button:SetScript("OnClick",callback)
    button:SetScript("OnEnter",function(b) b:SetBackdropBorderColor(unpack(ns.UI_COLORS.accent)) end)
    button:SetScript("OnLeave",function(b) b:SetBackdropBorderColor(unpack(ns.UI_COLORS.border)) end)
    return button
end
local function Gold(value)
    if Addon.db.profile.discretionMode then return L.WL_HIDDEN end
    return (value<0 and "-" or "")..ns.UI_FormatGold(math.floor(math.abs(value)))
end
local function Source(source) return L["WL_SOURCE_"..source] end
local function Tip(button,title,lines)
    button:SetScript("OnEnter",function(b)
        b:SetBackdropBorderColor(unpack(ns.UI_COLORS.accent))
        GameTooltip:SetOwner(b,"ANCHOR_RIGHT"); GameTooltip:SetText(title)
        for _,line in ipairs(lines) do GameTooltip:AddLine(line,0.85,0.85,0.85,true) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave",function(b) b:SetBackdropBorderColor(unpack(ns.UI_COLORS.border)); GameTooltip:Hide() end)
end
local function Chart(parent,points,x,y,width,title)
    local panel=Panel(parent,x,y,width,185)
    Text(panel,title,12,10,width-24,"QuartermasterFontHeading",ns.UI_COLORS.accent)
    if Addon.db.profile.discretionMode then Text(panel,L.WL_HIDDEN,12,70,width-24); return end
    if #points==0 then Text(panel,L.WL_NO_HISTORY,12,70,width-24); return end
    local low,high=points[1].value,points[1].value
    for _,point in ipairs(points) do low=math.min(low,point.value); high=math.max(high,point.value) end
    Text(panel,Gold(high),12,37,width-24,"QuartermasterFontSmall",ns.UI_COLORS.textDim)
    Text(panel,Gold(low),12,138,width-24,"QuartermasterFontSmall",ns.UI_COLORS.textDim)
    Text(panel,points[1].day,100,163,width/2-100,"QuartermasterFontSmall",ns.UI_COLORS.textDim)
    local endLabel=Text(panel,points[#points].day,width/2,163,width/2-12,"QuartermasterFontSmall",ns.UI_COLORS.textDim)
    endLabel:SetJustifyH("RIGHT")
    local plotWidth=math.max(1,width-125)
    local function Stamp(day)
        local year,month,dayOfMonth=day:match("(%d+)%-(%d+)%-(%d+)")
        return year and time({year=tonumber(year),month=tonumber(month),day=tonumber(dayOfMonth),hour=12}) or 0
    end
    local first,last=Stamp(points[1].day),Stamp(points[#points].day)
    local prior
    for index,point in ipairs(points) do
        local stamp=Stamp(point.day)
        local px=100+(stamp-first)/math.max(1,last-first)*plotWidth
        local py=high==low and 95 or 145-(point.value-low)/(high-low)*90
        if prior and stamp-prior.stamp<36*3600 then
            local dx,dy=px-prior.x,prior.y-py
            local stroke=ns.UI_RenderTexture(panel,nil,"ARTWORK")
            stroke:SetColorTexture(unpack(ns.UI_COLORS.accent)); stroke:SetSize(math.sqrt(dx*dx+dy*dy),2)
            stroke:SetPoint("CENTER",panel,"TOPLEFT",(px+prior.x)/2,-(py+prior.y)/2)
            stroke:SetRotation(math.atan2(dy,dx))
        end
        local dot=Panel(panel,px-3,py-3,6,6)
        dot:SetBackdropColor(unpack(ns.UI_COLORS.accent))
        Tip(dot,point.day,{Gold(point.value),L.WL_SNAPSHOT_HELP})
        prior={x=px,y=py,stamp=stamp}
    end
end
function Addon:DrawWealth(parent)
    local allowRemoval = self.db.profile.allowWealthTransactionRemoval == true
    if not allowRemoval then self.wealthRemoveID = nil end
    self.wealthPool=self.wealthPool or ns.UI_NewRenderPool(parent)
    local pool=self.wealthPool; local root=pool:Begin(parent:GetWidth())
    root:SetFrameLevel(parent:GetFrameLevel()+1)
    local width=math.max(420,parent:GetWidth()-20)
    self.wealthOptions=self.wealthOptions or {days=30,sort="amount"}
    local options=self.wealthOptions
    local function Refresh() self:RefreshUI() end
    local function Change(key,value) options[key]=value; self.wealthPage=1; self.wealthItem=nil; Refresh() end
    local gap=8; local filterWidth=(width-3*gap)/4
    Button(root,L["WL_PERIOD_"..options.days],10,10,filterWidth,function(button)
        MenuUtil.CreateContextMenu(button,function(_,menu)
            for _,days in ipairs({1,7,30,0}) do menu:CreateButton(L["WL_PERIOD_"..days],function() Change("days",days) end) end
        end)
    end)
    Button(root,options.character or L.WL_ACCOUNT,10+filterWidth+gap,10,filterWidth,function(button)
        MenuUtil.CreateContextMenu(button,function(_,menu)
            menu:CreateButton(L.WL_ACCOUNT,function() Change("character",nil) end)
            for key in ns.OrderedCharacterPairs(self.db) do
                local charKey=key; menu:CreateButton(key,function() Change("character",charKey) end)
            end
        end)
    end)
    Button(root,options.source and Source(options.source) or L.WL_ALL_SOURCES,10+2*(filterWidth+gap),10,filterWidth,function(button)
        MenuUtil.CreateContextMenu(button,function(_,menu)
            menu:CreateButton(L.WL_ALL_SOURCES,function() Change("source",nil) end)
            for _,source in ipairs({"vendor","auction","patronOrder","workOrder","auctionPurchase","purchase","repair"}) do menu:CreateButton(Source(source),function() Change("source",source) end) end
        end)
    end)
    Button(root,L.WL_REFRESH,10+3*(filterWidth+gap),10,filterWidth,function() self:FlushWealth(); Refresh() end)
    local view=self:GetWealthView(options)
    local y=48
    local cards={{L.WL_BALANCE,view.balance,L.WL_SNAPSHOT_HELP},{L.WL_INCOME,view.income,L.WL_INCOME_HELP},
        {L.WL_SPENDING,view.spending,L.WL_SPENDING_HELP},{L.WL_NET,view.net,L.WL_NET_HELP}}
    for index,entry in ipairs(cards) do
        local card=Panel(root,10+(index-1)*(filterWidth+gap),y,filterWidth,72)
        Text(card,entry[1],12,12,filterWidth-24,"QuartermasterFontSmall",ns.UI_COLORS.textDim)
        Text(card,Gold(entry[2]),12,34,filterWidth-24,"QuartermasterFontHeading",ns.UI_COLORS.accent)
        Tip(card,entry[1],{entry[3]})
    end
    y=y+82
    Chart(root,view.history,10,y,width,L.WL_GRAPH); y=y+195
    Text(root,L.WL_COVERAGE,10,y,width,"QuartermasterFontSmall",ns.UI_COLORS.textDim); y=y+24
    Text(root,string.format(L.WL_UNCLASSIFIED,Gold(view.unknown),Gold(view.transfers)),10,y,width,"QuartermasterFontSmall",ns.UI_COLORS.textDim); y=y+30
    Text(root,L.WL_BREAKDOWN,10,y,width,"QuartermasterFontHeading",ns.UI_COLORS.accent); y=y+26
    local breakdown={{Source("vendor"),(view.sources.vendor or 0)+(view.sources.buyback or 0)},
        {Source("patronOrder"),view.sources.patronOrder or 0},{Source("workOrder"),view.sources.workOrder or 0},
        {Source("auction"),view.sources.auction or 0},{Source("purchase"),view.sources.purchase or 0},
        {Source("auctionPurchase"),view.sources.auctionPurchase or 0},{Source("repair"),view.sources.repair or 0},{L.WL_INFLOW,view.unknownIn},{L.WL_OUTFLOW,-view.unknownOut}}
    for index,entry in ipairs(breakdown) do
        local column=(index-1)%3; local line=math.floor((index-1)/3)
        local cell=Panel(root,10+column*(width+8)/3,y+line*46,(width-16)/3,40)
        Text(cell,entry[1],8,5,(width-16)/3-16,"QuartermasterFontSmall",ns.UI_COLORS.textDim)
        Text(cell,Gold(entry[2]),8,21,(width-16)/3-16,"QuartermasterFontSmall")
    end
    y=y+math.ceil(#breakdown/3)*46+8
    Text(root,L.WL_TOP,10,y,width-210,"QuartermasterFontHeading",ns.UI_COLORS.accent)
    Button(root,options.sort=="average" and L.WL_SORT_AVERAGE or L.WL_SORT_TOTAL,width-190,y-5,200,function()
        Change("sort",options.sort=="average" and "amount" or "average")
    end); y=y+30
    if not self.wealthSearch then
        local box=CreateFrame("EditBox",nil,root,"BackdropTemplate")
        box:SetAutoFocus(false); box:SetFontObject("QuartermasterFontBody"); box:SetTextInsets(10,10,0,0)
        box:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
        box:SetScript("OnEnterPressed",function(b) options.query=b:GetText(); self.wealthPage=1; self.wealthItem=nil; b:ClearFocus(); Refresh() end)
        box:SetScript("OnEscapePressed",function(b) b:ClearFocus() end)
        self.wealthSearch=box
    end
    local search=self.wealthSearch; search:ClearAllPoints(); search:SetPoint("TOPLEFT",10,-y); search:SetSize(width-150,28)
    search:SetBackdropColor(unpack(ns.UI_COLORS.bgCard)); search:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
    search:SetText(options.query or ""); search:Show()
    Button(root,L.WL_CLEAR,width-130,y,140,function() Change("query",nil) end)
    y=y+34; Text(root,L.WL_SEARCH_HINT,10,y,width,"QuartermasterFontSmall",ns.UI_COLORS.textDim); y=y+25
    local itemWidth=width*0.36
    Text(root,L.WL_ITEM,20,y,itemWidth-20,"QuartermasterFontSmall",ns.UI_COLORS.textDim)
    Text(root,L.WL_QUANTITY,10+itemWidth,y,width*0.12,"QuartermasterFontSmall",ns.UI_COLORS.textDim)
    Text(root,L.WL_EARNED,10+width*0.50,y,width*0.24,"QuartermasterFontSmall",ns.UI_COLORS.textDim)
    Text(root,L.WL_AVERAGE,10+width*0.75,y,width*0.23,"QuartermasterFontSmall",ns.UI_COLORS.textDim); y=y+24
    local pages=math.max(1,math.ceil(#view.items/12)); local page=math.min(self.wealthPage or 1,pages)
    for index=(page-1)*12+1,math.min(page*12,#view.items) do
        local item=view.items[index]; local row=Panel(root,10,y,width,36)
        Text(row,item.name,10,10,itemWidth-20)
        Text(row,tostring(item.quantity),itemWidth,10,width*0.12)
        Text(row,Gold(item.amount),width*0.50,10,width*0.24,nil,ns.UI_COLORS.accent)
        Text(row,Gold(item.average),width*0.75,10,width*0.23)
        Tip(row,item.name,{L.WL_VENDOR..": "..Gold(item.vendor),L.WL_AUCTION..": "..Gold(item.auction),L.WL_FEES..": "..Gold(item.fees),L.WL_OPEN_ITEM})
        row:SetScript("OnClick",function() self.wealthItem=self.wealthItem==item.key and nil or item.key; Refresh() end)
        y=y+40
    end
    if #view.items==0 then Text(root,L.WL_NO_SALES,20,y,width-20); y=y+40 end
    Button(root,L.WL_PREVIOUS,10,y,100,function() self.wealthPage=math.max(1,page-1); Refresh() end)
    Text(root,string.format(L.WL_PAGE,page,pages),125,y+7,160,"QuartermasterFontSmall")
    Button(root,L.WL_NEXT,width-90,y,100,function() self.wealthPage=math.min(pages,page+1); Refresh() end); y=y+40
    if self.wealthItem then
        local detail={}; for k,v in pairs(options) do detail[k]=v end; detail.item=self.wealthItem
        local points={}; local store=self:GetWealthStore()
        for day,data in pairs(store and store.days or {}) do
            if options.days==0 or day>=ns.Wealth.Day(time()-(options.days-1)*86400) then
                local total=0
                for _,row in pairs(data.rows) do
                    if row.itemKey==detail.item and (row.source=="auction" or row.source=="vendor" or row.source=="buyback")
                        and (not options.character or options.character==row.character)
                        and (not options.source or options.source==row.source or options.source=="vendor" and row.source=="buyback") then total=total+row.amount end
                end
                points[#points+1]={day=day,value=total}
            end
        end
        table.sort(points,function(a,b) return a.day<b.day end)
        Chart(root,points,10,y,width,L.WL_ITEM_GRAPH); y=y+195
        view=self:GetWealthView(detail)
    end
    Text(root,self.wealthItem and L.WL_ITEM_HISTORY or L.WL_TRANSACTIONS,10,y,width,"QuartermasterFontHeading",ns.UI_COLORS.accent); y=y+28
    Text(root,L.WL_DETAIL_LIMIT,10,y,width,"QuartermasterFontSmall",ns.UI_COLORS.textDim); y=y+25
    for index=1,math.min(30,#view.transactions) do
        local entry=view.transactions[index]; local row=Panel(root,10,y,width,44)
        Text(row,entry.name or Source(entry.source),10,6,width*0.55)
        Text(row,date("%d %b %H:%M",entry.at).." · "..entry.character.." · "..Source(entry.source),10,26,width*0.60,"QuartermasterFontSmall",ns.UI_COLORS.textDim)
        Text(row,Gold(entry.amount),width*0.60,12,width*0.40-110)
        if allowRemoval then
            Button(row,L.WL_REMOVE,width-100,8,90,function()
                if self.db.profile.allowWealthTransactionRemoval == true then self.wealthRemoveID=entry.id; Refresh() end
            end)
        end
        Tip(row,entry.name or Source(entry.source),{Source(entry.source),tostring(entry.quantity).." · "..Gold(entry.amount),entry.character,entry.location or ""})
        y=y+48
        if allowRemoval and self.wealthRemoveID==entry.id then
            local warning=Text(root,L.WL_REMOVE_CONFIRM,20,y,width-20,"QuartermasterFontSmall")
            warning:SetWordWrap(true)
            y=y+math.max(28,warning:GetStringHeight()+10)
            Button(root,L.WL_REMOVE_YES,20,y,170,function()
                local removed=self:RemoveWealthTransaction(entry.id)
                self.wealthRemoveID=nil
                if not removed then self:Print(L.WL_REMOVE_FAILED) end
                Refresh()
            end)
            Button(root,L.WL_REMOVE_CANCEL,200,y,100,function() self.wealthRemoveID=nil; Refresh() end)
            y=y+40
        end
    end
    if #view.transactions==0 then Text(root,L.WL_NO_TRANSACTIONS,10,y,width); y=y+25 end
    return pool:Finish(y+15)
end
