local _, ns = ...
local Addon,W=ns.TheQuartermaster,ns.Wealth
local function Blocked() return InCombatLockdown and InCombatLockdown() end
local function Money()
    local result=W.Read(GetMoney)
    return result and W.Number(result[1]) and result[1] or nil
end
local function Bags()
    if Blocked() or not C_Container then return nil end
    local rows={}
    for bag=0,NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5 do
        local slots=W.Read(C_Container.GetContainerNumSlots,bag)
        if not slots or not W.Number(slots[1]) then return nil end
        for slot=1,slots[1] do
            local result=W.Read(C_Container.GetContainerItemInfo,bag,slot)
            if not result then return nil end
            local item=result[1]
            if item then
                if not W.Number(item.itemID) or not W.Number(item.stackCount) then return nil end
                local info=W.Read(C_Item and C_Item.GetItemInfo,item.hyperlink or item.itemID)
                if not info or not info[1] or not W.Number(info[11]) then return nil end
                local entry=rows[item.itemID] or {name=info[1],price=info[11],quantity=0}
                rows[item.itemID]=entry; entry.quantity=entry.quantity+item.stackCount
            end
        end
    end
    return rows
end
local function Active()
    return Addon._wealthTracking and not Addon._wealthTracking.suspended and Addon.db and Addon.db.profile.enabled~=false and not Blocked()
end
local function Buybacks()
    local rows={}
    for index=1,12 do
        local info=W.Read(GetBuybackItemInfo,index)
        if not info then return nil end
        if info[1] then
            if not W.Number(info[3]) or not W.Number(info[4]) then return nil end
            local key=info[1]..":"..info[3]..":"..info[4]
            local row=rows[key] or {name=info[1],amount=info[3],quantity=info[4],count=0}
            row.count=row.count+1; rows[key]=row
        end
    end
    return rows
end
local function BuybackChanges(before,after,delta)
    if not before or not after then return nil end
    local rows,total={},0
    for key,old in pairs(before) do
        local count=old.count-(after[key] and after[key].count or 0)
        if count>0 then
            total=total+old.amount*count
            rows[#rows+1]={source="buyback",name=old.name,quantity=-old.quantity*count,amount=-old.amount*count}
        end
    end
    if total>0 and -total==delta then return rows end
end
local function VendorReceipts(before,after,delta)
    if not before or not after or delta<=0 then return nil end
    local rows,total={},0
    for key,new in pairs(after) do
        local count=new.count-(before[key] and before[key].count or 0)
        if count>0 then
            total=total+new.amount*count
            rows[#rows+1]={source="vendor",name=new.name,quantity=new.quantity*count,amount=new.amount*count}
        end
    end
    if total==delta and #rows>0 then return rows end
end
local function Candidate(row)
    if not Active() or not row or not W.Public(row) or not W.Number(row.cash) then return end
    row.at=time()
    local state=Addon._wealthTracking
    state.candidates[#state.candidates+1]=row
end
-- Observe posting requests without changing the protected auction action.
function Addon:WealthAuctionPost(commodity, location, duration, quantity)
    if not Active() or not W.Public(location) or not W.Number(duration) or not W.Number(quantity)
        or duration <= 0 or quantity <= 0 then return end
    local api = C_AuctionHouse
    if not api then return end
    local item = W.Read(C_Item and C_Item.GetItemID, location)
    local id = item and item[1]
    local deposit
    if commodity then
        if not W.Number(id) then return end
        deposit = W.Read(api.CalculateCommodityDeposit, id, duration, quantity)
    else
        deposit = W.Read(api.CalculateItemDeposit, location, duration, quantity)
    end
    local cost = deposit and deposit[1]
    if not W.Number(cost) or cost <= 0 then return end
    -- Matching the observed cash delta remains mandatory; a request alone earns no receipt.
    Candidate({source="auctionDeposit", amount=-cost, cash=-cost})
end

-- Quotes identify commodity costs; confirmation alone is not a completed purchase.
function Addon:WealthAuctionPurchase(action, id, quantity)
    if not Active() then return end
    local state=self._wealthTracking
    if action=="cancel" then state.auctionQuote=nil; state.auctionPurchase=nil; return end
    if not W.Number(id) or id<=0 or not W.Number(quantity) or quantity<=0 then return end
    if action=="start" then
        state.auctionQuote={itemID=id,quantity=quantity,at=time()}
    elseif action=="confirm" then
        local quote=state.auctionQuote; state.auctionQuote=nil
        if quote and quote.itemID==id and quote.quantity==quantity and time()-quote.at<=30 and quote.cost then
            state.auctionPurchase={source="auctionPurchase",itemID=id,quantity=quantity,
                amount=-quote.cost,cash=-quote.cost,at=time()}
        end
    elseif action=="bid" then
        local result=W.Read(C_AuctionHouse and C_AuctionHouse.GetAuctionInfoByID,id)
        local info=result and result[1]
        -- A bid below buyout is not an item purchase. Missing auction data stays unknown.
        if info and W.Number(info.buyoutAmount) and info.buyoutAmount==quantity then
            local itemID=info.itemKey and info.itemKey.itemID
            if W.Number(itemID) then
                local item=W.Read(C_Item and C_Item.GetItemInfo,itemID)
                Candidate({source="auctionPurchase",itemID=itemID,name=item and item[1],amount=-quantity,cash=-quantity})
            end
        end
    end
end

-- Capture the claimed order before fulfillment removes it from the public cache.
function Addon:WealthOrderRequest(orderID)
    if not Active() or not W.Number(orderID) then return end
    local result=W.Read(C_CraftingOrders and C_CraftingOrders.GetClaimedOrder)
    local order=result and result[1]
    local types=Enum and Enum.CraftingOrderType
    if not order or not types or order.orderID~=orderID or not W.Number(order.itemID)
        or not W.Number(order.tipAmount) or not W.Number(order.consortiumCut)
        or order.consortiumCut<0 or order.tipAmount<=order.consortiumCut then return end
    local patron=order.orderType==types.Npc
    if not patron and order.orderType~=types.Public and order.orderType~=types.Guild and order.orderType~=types.Personal then return end
    local item=W.Read(C_Item and C_Item.GetItemInfo,order.outputItemHyperlink or order.itemID)
    local amount=order.tipAmount-order.consortiumCut
    self._wealthTracking.orderRequest={orderID=orderID,at=time(),row={source=patron and "patronOrder" or "workOrder",
        itemID=order.itemID,name=item and item[1],amount=amount,cash=amount,fees=order.consortiumCut}}
end

function Addon:FlushWealth(final)
    local state=self._wealthTracking
    if not state or state.suspended then return end
    if state.timer then self:CancelTimer(state.timer,true) end
    state.timer=nil
    if Blocked() then state.money=nil; state.candidates={}; state.bags=nil; state.buybacks=nil; return end
    local current=Money()
    if not current then state.money=nil; state.candidates={}; state.bags=nil; return end
    local delta=state.money and current-state.money or 0
    local after=state.merchant and Bags() or nil
    local buybacks=state.merchant and Buybacks() or nil
    local rows,expected={},0
    for _,row in ipairs(state.candidates) do
        if time()-row.at<=5 then rows[#rows+1]=row; expected=expected+row.cash end
    end
    if delta~=0 then
        if #rows==0 or expected~=delta then
            rows=VendorReceipts(state.buybacks,buybacks,delta)
                or W.VendorDifference(state.bags,after,delta)
            if not rows and delta<0 then rows=BuybackChanges(state.buybacks,buybacks,delta) end
        end
        -- Money and merchant receipts can arrive in either order. Keep the original
        -- baseline while allowing two short, bounded retries for matching evidence.
        if not rows and (state.merchant or state.auctionPurchase or state.orderRequest or (state.mailRequests and #state.mailRequests>0)) and not final and (state.retry or 0)<2 then
            state.retry=(state.retry or 0)+1
            state.timer=self:ScheduleTimer("FlushWealth",0.15)
            return
        end
        if not rows then rows={{source=state.transfer and "transfer" or "unknown",amount=delta}} end
        local key=self:GetCharacterKey()
        for _,row in ipairs(rows) do
            if state.merchant then row.location=state.vendor end
            row.character=key; row.at=time(); self:RecordWealth(row)
            if row.deposit and row.deposit~=0 then
                self:RecordWealth({character=key,source="deposit",amount=row.deposit})
            end
        end
    end
    state.money=current; state.candidates=delta==0 and rows or {}; state.retry=nil
    if delta~=0 then state.bags=after; state.buybacks=buybacks end
    self:SnapshotWealth()
end
function Addon:QueueWealth()
    local state=self._wealthTracking; if not state or state.suspended then return end
    if not state.timer then state.timer=self:ScheduleTimer("FlushWealth",0.5) end
end
function Addon:WealthMailRequest(index)
    if not Active() or not W.Number(index) then return end
    local state=self._wealthTracking
    local requests=state.mailRequests or {}
    state.mailRequests=requests
    -- Expired requests must not block subsequent collection attempts.
    while requests[1] and time()-requests[1].at>5 do table.remove(requests,1) end
    local header=W.Read(GetInboxHeaderInfo,index)
    W.Read(GetInboxText,index)
    local invoice=W.Read(GetInboxInvoiceInfo,index)
    local row=W.Invoice(invoice,header)
    if not header or not W.Number(header[5]) or header[5]<=0 or type(header[4])~="string" then return end
    local last=requests[#requests]
    -- Nested AutoLoot/TakeInboxMoney hooks observe the same request twice.
    -- Inbox updates distinguish another identical receipt at a reused index.
    if last and last.index==index and last.generation==state.mailGeneration
        and last.subject==header[4] and last.cash==header[5] and last.sender==header[3] then
        last.row=last.row or row
        return
    end
    if #requests<50 then
        -- Keep an unverified money request in sequence too: its success must
        -- not consume the next message's verified auction receipt.
        requests[#requests+1]={row=row,index=index,at=time(),generation=state.mailGeneration,
            subject=header[4],sender=header[3],cash=header[5]}
    end
end
function Addon:PrimeWealthMail()
    local state=self._wealthTracking
    if not state then return end
    state.mailTimer=nil
    if not state.mailOpen or not Active() then return end
    local result=W.Read(GetInboxNumItems); local count=result and result[1]
    if not W.Number(count) then return end
    state.mailAttempts=state.mailAttempts or {}
    local index=state.mailIndex or 1
    for current=index,math.min(count,index+4) do
        local header=W.Read(GetInboxHeaderInfo,current)
        local row=W.Invoice(W.Read(GetInboxInvoiceInfo,current),header)
        if not row and header and type(header[4])=="string" and W.Number(header[5]) and header[5]>0 then
            local key=current..":"..header[4]..":"..header[5]
            local attempts=state.mailAttempts[key] or 0
            if attempts<2 then
                state.mailAttempts[key]=attempts+1
                W.Read(GetInboxText,current)
            end
        end
    end
    state.mailIndex=index+5
    if state.mailIndex<=count then state.mailTimer=self:ScheduleTimer("PrimeWealthMail",0.05) end
end
function Addon:WealthEvent(event, ...)
    local state=self._wealthTracking; if not state then return end
    if event=="CRAFTINGORDERS_FULFILL_ORDER_RESPONSE" then
        local result,orderID=...
        if not Active() or not W.Number(result) or not W.Number(orderID) then return end
        local pending=state.orderRequest
        if pending and pending.orderID==orderID then
            state.orderRequest=nil
            local success=Enum and Enum.CraftingOrderResult and Enum.CraftingOrderResult.Ok
            if success~=nil and result==success and time()-pending.at<=5 then Candidate(pending.row) end
            self:QueueWealth()
        end
        return
    elseif event=="COMMODITY_PRICE_UPDATED" then
        local _,total=...
        if Active() and state.auctionQuote and W.Number(total) and total>0 then state.auctionQuote.cost=total end
        return
    elseif event=="COMMODITY_PURCHASE_SUCCEEDED" then
        local row=state.auctionPurchase; state.auctionPurchase=nil
        if row and Active() and time()-row.at<=5 then
            local item=W.Read(C_Item and C_Item.GetItemInfo,row.itemID); row.name=item and item[1]
            Candidate(row)
        end
        self:QueueWealth(); return
    elseif event=="COMMODITY_PURCHASE_FAILED" or event=="AUCTION_HOUSE_CLOSED" then
        state.auctionQuote=nil; state.auctionPurchase=nil
        self:QueueWealth(); return
    end
    if event=="PLAYER_LEAVING_WORLD" or event=="PLAYER_LOGOUT" then
        -- Teardown can expose zero money. Retain the last valid snapshot instead.
        state.suspended=true; state.auctionQuote=nil; state.auctionPurchase=nil; state.orderRequest=nil
        if state.timer then self:CancelTimer(state.timer,true); state.timer=nil end
        if state.mailTimer then self:CancelTimer(state.mailTimer,true); state.mailTimer=nil end
        state.money=nil; state.candidates={}; state.mailRequests=nil
        state.bags=nil; state.buybacks=nil; state.merchant=nil; state.mailOpen=nil; state.transfer=nil
        return
    end
    if state.suspended and event~="PLAYER_ENTERING_WORLD" then return end
    if event=="PLAYER_REGEN_DISABLED" then
        state.auctionQuote=nil; state.auctionPurchase=nil; state.orderRequest=nil
        state.money=nil; state.bags=nil; state.buybacks=nil; state.candidates={}; state.mailRequests=nil
    elseif event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_REGEN_ENABLED" then
        state.suspended=nil
        state.money=Money(); state.candidates={}; state.bags=state.merchant and Bags() or nil
        state.buybacks=state.merchant and Buybacks() or nil; self:QueueWealth()
    elseif event=="MERCHANT_SHOW" then
        self:FlushWealth(); state.merchant=true; state.bags=Bags(); state.buybacks=Buybacks()
        local name=W.Read(UnitName,"npc"); state.vendor=name and name[1]
        local cost=W.Read(GetRepairAllCost); state.repair=cost and cost[1]
    elseif event=="MERCHANT_CLOSED" then
        self:FlushWealth(true); state.merchant=false; state.bags=nil; state.buybacks=nil
    elseif event=="MERCHANT_UPDATE" then
        self:QueueWealth()
        local cost=W.Read(GetRepairAllCost); state.repair=cost and cost[1]
    elseif event=="MAIL_SHOW" or event=="MAIL_INBOX_UPDATE" then
        state.mailGeneration=(state.mailGeneration or 0)+1
        if event=="MAIL_SHOW" then state.mailOpen=true; state.mailAttempts={} end
        if state.mailOpen then
            -- Finish the current bounded pass before restarting after an update.
            if not state.mailTimer then
                state.mailIndex=1
                state.mailTimer=self:ScheduleTimer("PrimeWealthMail",0.05)
            end
        end
    elseif event=="MAIL_SUCCESS" then
        local requests=state.mailRequests
        local pending=requests and table.remove(requests,1)
        if pending and time()-pending.at<=5 then Candidate(pending.row) end
        self:QueueWealth()
    elseif event=="MAIL_FAILED" then
        if state.mailRequests then table.remove(state.mailRequests,1) end
    elseif event=="MAIL_CLOSED" then
        self:FlushWealth(); state.mailRequests=nil; state.mailOpen=false; state.mailAttempts=nil
    elseif event=="BANKFRAME_OPENED" or event=="GUILDBANKFRAME_OPENED" or event=="TRADE_SHOW" then
        self:FlushWealth(); state.transfer=true
    elseif event=="BANKFRAME_CLOSED" or event=="GUILDBANKFRAME_CLOSED" or event=="TRADE_CLOSED" then
        self:FlushWealth(); state.transfer=nil

    else self:QueueWealth() end
end
function Addon:InitializeWealth()
    if self._wealthTracking or not self:GetWealthStore() then return end
    self._wealthTracking={money=Money(),candidates={}}
    self._wealthFrame=self._wealthFrame or CreateFrame("Frame")
    self._wealthFrame:SetScript("OnEvent",function(_,event,...) self:WealthEvent(event,...) end)
    for _,event in ipairs({"PLAYER_MONEY","ACCOUNT_MONEY","PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD","PLAYER_LOGOUT",
        "PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","MERCHANT_SHOW","MERCHANT_UPDATE","MERCHANT_CLOSED",
        "MAIL_SHOW","MAIL_INBOX_UPDATE","MAIL_SUCCESS","MAIL_FAILED","MAIL_CLOSED","BANKFRAME_OPENED","BANKFRAME_CLOSED",
        "GUILDBANKFRAME_OPENED","GUILDBANKFRAME_CLOSED","TRADE_SHOW","TRADE_CLOSED",
        "CRAFTINGORDERS_FULFILL_ORDER_RESPONSE","COMMODITY_PRICE_UPDATED","COMMODITY_PURCHASE_SUCCEEDED","COMMODITY_PURCHASE_FAILED","AUCTION_HOUSE_CLOSED"}) do
        self._wealthFrame:RegisterEvent(event)
    end
    if not self._wealthHooked then
        self._wealthHooked=true
        if C_CraftingOrders and type(C_CraftingOrders.FulfillOrder)=="function" then
            hooksecurefunc(C_CraftingOrders,"FulfillOrder",function(orderID) self:WealthOrderRequest(orderID) end)
        end
        if C_AuctionHouse then
            for name,action in pairs({StartCommoditiesPurchase="start",ConfirmCommoditiesPurchase="confirm",
                CancelCommoditiesPurchase="cancel",PlaceBid="bid"}) do
                if type(C_AuctionHouse[name])=="function" then
                    local kind=action
                    hooksecurefunc(C_AuctionHouse,name,function(id,quantity) self:WealthAuctionPurchase(kind,id,quantity) end)
                end
            end
            for _, name in ipairs({"PostItem", "PostCommodity"}) do
                if type(C_AuctionHouse[name]) == "function" then
                    local commodity = name == "PostCommodity"
                    hooksecurefunc(C_AuctionHouse, name, function(location, duration, quantity)
                        self:WealthAuctionPost(commodity, location, duration, quantity)
                    end)
                end
            end
        end
        for _,fn in ipairs({"TakeInboxMoney","AutoLootMailItem"}) do
            if type(_G[fn])=="function" then hooksecurefunc(fn,function(index) self:WealthMailRequest(index) end) end
        end
        if type(BuyMerchantItem)=="function" then hooksecurefunc("BuyMerchantItem",function(index,quantity)
            if not Active() or not W.Public(index) or not W.Public(quantity) then return end
            local result=W.Read(C_MerchantFrame and C_MerchantFrame.GetItemInfo,index)
            local info=result and result[1]
            quantity=quantity or 1
            if not info or not W.Number(info.price) or not W.Number(info.stackCount) or info.stackCount<=0 or not W.Number(quantity) then return end
            local link=W.Read(GetMerchantItemLink,index)
            local id=link and type(link[1])=="string" and tonumber(link[1]:match("item:(%d+)"))
            local cost=info.price*quantity/info.stackCount
            Candidate({source="purchase",name=info.name,itemID=id,quantity=quantity,amount=-cost,cash=-cost})
        end) end
        if type(RepairAllItems)=="function" then hooksecurefunc("RepairAllItems",function(guild)
            if not Active() or not W.Public(guild) or guild then return end
            local cost=self._wealthTracking.repair
            if W.Number(cost) and cost>0 then Candidate({source="repair",amount=-cost,cash=-cost}) end
        end) end
    end
    self:QueueWealth()
end
function Addon:StopWealth()
    local state=self._wealthTracking
    if state and state.timer then self:CancelTimer(state.timer) end
    if state and state.mailTimer then self:CancelTimer(state.mailTimer) end
    if self._wealthFrame then self._wealthFrame:UnregisterAllEvents() end
    self._wealthTracking=nil
end
