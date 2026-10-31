local _,ns=...
local Addon,L=ns.TheQuartermaster,ns.L
local function Text(parent,value,x,y,width,color)
    local label=ns.UI_RenderFontString(parent,nil,"OVERLAY","QuartermasterFontBody")
    label:SetPoint("TOPLEFT",x,-y); label:SetWidth(math.max(1,width)); label:SetJustifyH("LEFT")
    label:SetWordWrap(false); label:SetText(value); label:SetTextColor(unpack(color or ns.UI_COLORS.textNormal))
    return label
end
local function Button(parent,label,x,y,width,callback,height)
    local button=ns.UI_RenderFrame("Button",nil,parent,"BackdropTemplate")
    button:SetPoint("TOPLEFT",x,-y); button:SetSize(width,height or 28)
    button:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    button:SetBackdropColor(unpack(ns.UI_COLORS.bgCard)); button:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
    if label then Text(button,label,10,7,width-20) end
    button:SetScript("OnClick",callback)
    button:SetScript("OnEnter",function(b) b:SetBackdropBorderColor(unpack(ns.UI_COLORS.accent)) end)
    button:SetScript("OnLeave",function(b) b:SetBackdropBorderColor(unpack(ns.UI_COLORS.border)); GameTooltip:Hide() end)
    return button
end
function Addon:AuctionTooltip(row)
    GameTooltip:AddLine(row.character,0.8,0.8,0.8)
    GameTooltip:AddLine(L["AU_STATE_"..row.state],0.3,0.85,0.8)
    GameTooltip:AddLine(L.AU_NOT_STOCK,1,0.75,0.3,true)
    GameTooltip:AddLine(L.AU_BUYOUT..": "..(row.item.buyout and ns.UI_FormatGold(row.item.buyout) or "--"),1,1,1)
    GameTooltip:AddLine(L.AU_BID..": "..(row.item.bid and ns.UI_FormatGold(row.item.bid) or "--"),1,1,1)
    if row.item.expires then GameTooltip:AddLine(L.AU_EXPIRY..": "..date("%d %b %H:%M",row.item.expires),0.8,0.8,0.8) end
    GameTooltip:AddLine(L.AU_CHECKED..": "..date("%d %b %H:%M",row.checked),0.8,0.8,0.8)
end
function Addon:DrawAuctions(parent)
    self.auctionPool=self.auctionPool or ns.UI_NewRenderPool(parent)
    local root=self.auctionPool:Begin(parent:GetWidth()); root:SetFrameLevel(parent:GetFrameLevel()+1)
    local width=parent:GetWidth()-20; local half=(width-10)/2
    Button(root,self.auctionCharacter or L.AU_ALL,10,10,half,function(button)
        MenuUtil.CreateContextMenu(button,function(_,menu)
            menu:CreateButton(L.AU_ALL,function() self.auctionCharacter=nil; self.auctionPage=1; self:RefreshUI() end)
            local store=self:GetAuctionStore(); local keys={}
            for key in pairs(store and store.characters or {}) do keys[#keys+1]=key end; table.sort(keys)
            for _,key in ipairs(keys) do menu:CreateButton(key,function() self.auctionCharacter=key; self.auctionPage=1; self:RefreshUI() end) end
        end)
    end)
    Button(root,L.AU_REFRESH,20+half,10,half,function() self:RequestAuctionScan(); self:RefreshUI() end)
    Text(root,L.AU_GUIDE,10,49,width,ns.UI_COLORS.textDim)
    Text(root,L.AU_NOT_STOCK,10,73,width,ns.UI_COLORS.textDim)
    if not self.auctionSearch then
        local box=CreateFrame("EditBox",nil,root,"BackdropTemplate")
        box:SetAutoFocus(false); box:SetFontObject("QuartermasterFontBody"); box:SetTextInsets(10,10,0,0)
        box:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
        box:SetScript("OnEnterPressed",function(b) self.auctionQuery=b:GetText(); self.auctionPage=1; b:ClearFocus(); self:RefreshUI() end)
        box:SetScript("OnEscapePressed",function(b) b:ClearFocus() end)
        self.auctionSearch=box
    end
    local box=self.auctionSearch; box:ClearAllPoints(); box:SetPoint("TOPLEFT",10,-101); box:SetSize(width-130,28)
    box:SetBackdropColor(unpack(ns.UI_COLORS.bgCard)); box:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
    box:SetText(self.auctionQuery or ""); box:Show()
    Button(root,L.WL_CLEAR,width-110,101,120,function() self.auctionQuery=nil; self.auctionPage=1; self:RefreshUI() end)
    Text(root,L.AU_SEARCH_HINT,10,137,width,ns.UI_COLORS.textDim)
    local state=self._auctionOpen and (self._auctionState or "loading") or "closed"
    Text(root,L["AU_SCAN_"..state],10,161,width,ns.UI_COLORS.accent)
    local rows=self:GetAuctionRows(self.auctionCharacter,self.auctionQuery)
    local y=194
    Text(root,L.WL_ITEM,20,y,width*0.36); Text(root,L.AU_QUANTITY,10+width*0.4,y,width*0.11)
    Text(root,L.AU_BUYOUT,10+width*0.54,y,width*0.23); Text(root,L.AU_STATUS,10+width*0.79,y,width*0.2); y=y+25
    local pages=math.max(1,math.ceil(#rows/20)); local page=math.min(self.auctionPage or 1,pages)
    for index=(page-1)*20+1,math.min(#rows,page*20) do
        local row=rows[index]; local item=row.item
        local button=Button(root,nil,10,y,width,nil,54)
        local icon=ns.UI_RenderTexture(button,nil,"ARTWORK"); icon:SetPoint("LEFT",8,0); icon:SetSize(28,28); icon:SetTexture(item.icon or 134400)
        Text(button,row.name,44,7,width*0.39-48)
        Text(button,row.character,44,30,width*0.39-48,ns.UI_COLORS.textDim)
        Text(button,tostring(item.quantity),width*0.4,18,width*0.11)
        Text(button,item.buyout and item.buyout>0 and ns.UI_FormatGold(item.buyout) or "--",width*0.54,18,width*0.23)
        Text(button,L["AU_STATE_"..row.state],width*0.79,18,width*0.20,ns.UI_COLORS.textDim)
        button:SetScript("OnEnter",function(b)
            GameTooltip:SetOwner(b,"ANCHOR_RIGHT")
            if item.itemLink then GameTooltip:SetHyperlink(item.itemLink) else GameTooltip:SetText(row.name) end
            self:AuctionTooltip(row); GameTooltip:Show()
        end)
        y=y+60
    end
    if #rows==0 then Text(root,L.AU_LISTINGS_EMPTY,10,y,width); y=y+35 end
    Button(root,L.WL_PREVIOUS,10,y,100,function() self.auctionPage=math.max(1,page-1); self:RefreshUI() end)
    Text(root,string.format(L.WL_PAGE,page,pages),125,y+7,180)
    Button(root,L.WL_NEXT,width-90,y,100,function() self.auctionPage=math.min(pages,page+1); self:RefreshUI() end)
    return self.auctionPool:Finish(y+45)
end
