local _,ns=...
local Addon,L=ns.TheQuartermaster,ns.L
local Read,Number=ns.Wealth.Read,ns.Wealth.Number
local function Accessible(self)
    return self._auctionOpen and not (InCombatLockdown and InCombatLockdown())
end
function Addon:GetAuctionStore()
    local global=self.db.global
    if global.ownedAuctions and global.ownedAuctions.version~=1 then return nil end
    global.ownedAuctions=global.ownedAuctions or {version=1,characters={}}
    return global.ownedAuctions
end
function Addon:CancelAuctionScan()
    if self._auctionTimer then self:CancelTimer(self._auctionTimer,true); self._auctionTimer=nil end
    if self._auctionTimeout then self:CancelTimer(self._auctionTimeout,true); self._auctionTimeout=nil end
    self._auctionJob=nil
end
function Addon:AuctionScanFailed()
    self._auctionState="incomplete"; self._auctionJob=nil
    local frame=self.UI and self.UI.mainFrame
    if frame and frame:IsShown() and frame.currentTab=="auctions" then self:RefreshUI() end
end
function Addon:RequestAuctionScan()
    if not Accessible(self) or not C_AuctionHouse then return end
    self:CancelAuctionScan()
    self._auctionRequested=true; self._auctionState="loading"
    local result=Read(C_AuctionHouse.QueryOwnedAuctions,{})
    if not result then self._auctionState="unavailable"; self._auctionRequested=nil end
    if result then self._auctionTimeout=self:ScheduleTimer("AuctionScanFailed",10) end
end
function Addon:CollectOwnedAuctions()
    self._auctionTimer=nil
    if not Accessible(self) or not self._auctionRequested then return end
    local full=Read(C_AuctionHouse.HasFullOwnedAuctionResults)
    local count=Read(C_AuctionHouse.GetNumOwnedAuctions)
    if not full or full[1]~=true or not count or not Number(count[1]) or count[1]<0 then
        self:AuctionScanFailed(); return
    end
    local job=self._auctionJob
    if not job then job={index=1,count=count[1],rows={},ids={},key=self:GetCharacterKey(),at=time()}; self._auctionJob=job end
    if job.count~=count[1] or job.key~=self:GetCharacterKey() then self:AuctionScanFailed(); return end
    for index=job.index,math.min(job.count,job.index+39) do
        local result=Read(C_AuctionHouse.GetOwnedAuctionInfo,index)
        local info=result and result[1]
        if not info or not Number(info.auctionID) or job.ids[info.auctionID] or type(info.itemKey)~="table"
            or not Number(info.itemKey.itemID) or not Number(info.quantity) or info.quantity<=0
            or not Number(info.status) or not Enum or not Enum.AuctionStatus
            or (info.status~=Enum.AuctionStatus.Active and info.status~=Enum.AuctionStatus.Sold)
            then self:AuctionScanFailed(); return end
        local expires,minExpires
        if Number(info.timeLeftSeconds) and info.timeLeftSeconds>=0 then
            expires=job.at+info.timeLeftSeconds; minExpires=expires
        elseif Number(info.timeLeft) then
            local band=Read(C_AuctionHouse.GetTimeLeftBandInfo,info.timeLeft)
            if band and Number(band[1]) and Number(band[2]) then minExpires=job.at+band[1]; expires=job.at+band[2] end
        end
        local item=Read(C_Item and C_Item.GetItemInfo,info.itemLink or info.itemKey.itemID)
        local name=item and item[1]
        if not name and type(info.itemLink)=="string" then name=info.itemLink:match("%[(.-)%]") end
        job.rows[#job.rows+1]={auctionID=info.auctionID,itemID=info.itemKey.itemID,itemLink=info.itemLink,
            name=name,icon=item and item[10],quantity=info.quantity,status=info.status,
            buyout=Number(info.buyoutAmount) and info.buyoutAmount or nil,
            bid=Number(info.bidAmount) and info.bidAmount or nil,expires=expires,minExpires=minExpires}
        job.ids[info.auctionID]=true
    end
    job.index=job.index+40
    if job.index<=job.count then self._auctionTimer=self:ScheduleTimer("CollectOwnedAuctions",0.05); return end
    local store=self:GetAuctionStore()
    if store then store.characters[job.key]={checked=job.at,rows=job.rows} end
    if self.InvalidateItemCache then self:InvalidateItemCache() end
    self._auctionJob=nil; self._auctionState="complete"
    local frame=self.UI and self.UI.mainFrame
    if frame and frame:IsShown() and (frame.currentTab=="auctions" or frame.currentTab=="search") then self:RefreshUI() end
end
function Addon:AuctionEvent(event)
    if event=="AUCTION_HOUSE_SHOW" then
        self._auctionOpen=true; self._auctionRequested=nil; self:RequestAuctionScan()
    elseif event=="AUCTION_HOUSE_CLOSED" or event=="PLAYER_REGEN_DISABLED" then
        self:CancelAuctionScan(); self._auctionRequested=nil
        if event=="AUCTION_HOUSE_CLOSED" then self._auctionOpen=false end
    elseif event=="PLAYER_REGEN_ENABLED" then
        if self._auctionOpen then self:RequestAuctionScan() end
    elseif event=="OWNED_AUCTIONS_UPDATED" and Accessible(self) and self._auctionRequested then
        self:CancelAuctionScan()
        self._auctionTimer=self:ScheduleTimer("CollectOwnedAuctions",0.1)
    end
end
function Addon:InitializeAuctionTracking()
    if self._auctionFrame then return end
    local frame=CreateFrame("Frame"); self._auctionFrame=frame
    for _,event in ipairs({"AUCTION_HOUSE_SHOW","AUCTION_HOUSE_CLOSED","OWNED_AUCTIONS_UPDATED","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED"}) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent",function(_,event) self:AuctionEvent(event) end)
end
function Addon:StopAuctionTracking()
    self:CancelAuctionScan()
    if self._auctionFrame then self._auctionFrame:UnregisterAllEvents(); self._auctionFrame:SetScript("OnEvent",nil) end
    self._auctionFrame=nil; self._auctionOpen=false; self._auctionRequested=nil
end
function Addon:GetAuctionRows(character,query)
    local store=self:GetAuctionStore(); local rows={}
    if not store then return rows end
    local now=time(); query=query and query:lower() or ""
    for key,snapshot in pairs(store.characters) do
        if not character or key==character then
            for _,item in ipairs(snapshot.rows) do
                local name=item.name or string.format(L.AU_ITEM_ID,item.itemID)
                if query=="" or name:lower():find(query,1,true) or tostring(item.itemID)==query then
                    local state="cached"
                    if Enum and Enum.AuctionStatus and item.status==Enum.AuctionStatus.Sold then state="sold"
                    elseif item.expires and now>=item.expires then state="expired"
                    elseif not item.minExpires or now>=item.minExpires then state="uncertain" end
                    rows[#rows+1]={character=key,item=item,name=name,state=state,checked=snapshot.checked}
                end
            end
        end
    end
    table.sort(rows,function(a,b)
        if a.character~=b.character then return a.character<b.character end
        if a.name~=b.name then return a.name<b.name end
        return a.item.auctionID<b.item.auctionID
    end)
    return rows
end
function Addon:GetAuctionSearchRows(query)
    local result={}
    for _,row in ipairs(self:GetAuctionRows(nil,query)) do
        -- Historical expired/sold listings remain in Auctions, but not item locations.
        if row.state=="cached" or row.state=="uncertain" then
            local item=row.item
            result[#result+1]={character=row.character,characterKey=row.character,location=L.AU_TITLE,
                locationDetail=row.character.." - "..L["AU_STATE_"..row.state],auction=row,
                item={itemID=item.itemID,name=row.name,itemLink=item.itemLink or "item:"..item.itemID,
                    iconFileID=item.icon,stackCount=item.quantity}}
        end
    end
    return result
end
