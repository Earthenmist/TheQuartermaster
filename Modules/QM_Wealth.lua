local _, ns = ...
local Addon = ns.TheQuartermaster
local W = {}; ns.Wealth = W
local function Pack(...) return {n=select("#",...),...} end

function W.Public(value, depth)
    if issecretvalue and issecretvalue(value) then return false end
    if type(value)=="table" then
        if (depth or 0)>6 then return false end
        for k,v in pairs(value) do if not W.Public(k,(depth or 0)+1) or not W.Public(v,(depth or 0)+1) then return false end end
    end
    return true
end
function W.Read(fn,...)
    if type(fn)~="function" then return nil end
    local result=Pack(pcall(fn,...))
    if not result[1] or not W.Public(result) then return nil end
    local values={}
    for index=2,result.n do values[index-1]=result[index] end
    return values
end
function W.Number(value) return W.Public(value) and type(value)=="number" and value==value and math.abs(value)<1e15 end
function W.Day(now) return date("%Y-%m-%d",now) end
function Addon:GetWealthStore()
    local global=self.db.global
    if global.wealth and global.wealth.version~=1 then return nil end
    if not global.wealth then global.wealth={version=1,started=time(),days={},recent={},sequence=0} end
    return global.wealth
end
function W.ItemKey(name,id)
    -- Invoice names do not carry item IDs. A locale-qualified name joins those receipts
    -- to vendor sales without guessing an ID from a localized subject line.
    return (GetLocale and GetLocale() or "enUS")..":"..(name or tostring(id or ""))
end
function Addon:RecordWealth(row)
    if not W.Public(row) or not W.Number(row.amount) or row.amount==0 or type(row.character)~="string" then return false end
    local store=self:GetWealthStore(); if not store then return false end
    row.at=row.at or time(); row.source=row.source or "unknown"
    row.quantity=row.quantity or 0
    if not W.Number(row.at) or not W.Number(row.quantity) then return false end
    local day=W.Day(row.at)
    store.days[day]=store.days[day] or {rows={},balances={}}
    local itemKey=row.name and W.ItemKey(row.name,row.itemID) or ""
    local key=row.character.."\031"..row.source.."\031"..itemKey
    local rows=store.days[day].rows
    local entry=rows[key]
    if not entry then
        entry={character=row.character,source=row.source,itemKey=itemKey,name=row.name,itemID=row.itemID,
            amount=0,quantity=0,fees=0,inflow=0,outflow=0,first=row.at,last=row.at}
        rows[key]=entry
    end
    entry.amount=entry.amount+row.amount; entry.quantity=entry.quantity+row.quantity
    entry.inflow=(entry.inflow or 0)+math.max(0,row.amount)
    entry.outflow=(entry.outflow or 0)+math.max(0,-row.amount)
    entry.fees=entry.fees+(row.fees or 0); entry.last=row.at
    store.sequence=store.sequence+1
    local saved={id=store.sequence,at=row.at,character=row.character,source=row.source,name=row.name,
        itemID=row.itemID,itemKey=itemKey,amount=row.amount,quantity=row.quantity,fees=row.fees,location=row.location}
    table.insert(store.recent,1,saved)
    if #store.recent>2000 then table.remove(store.recent) end
    return true
end
-- Reverse one retained receipt, not the independent balance snapshots.
function Addon:RemoveWealthTransaction(id)
    if self.db.profile.allowWealthTransactionRemoval ~= true then return false end
    local store=self:GetWealthStore()
    if not store or not W.Number(id) then return false end
    local index,record
    for i,row in ipairs(store.recent) do if row.id==id then index,record=i,row; break end end
    if not record or not W.Public(record) or not W.Number(record.at) or not W.Number(record.amount)
        or not W.Number(record.quantity) or not W.Number(record.fees or 0) then return false end
    local day=store.days[W.Day(record.at)]
    local key=record.character.."\031"..record.source.."\031"..(record.itemKey or "")
    local summary=day and day.rows and day.rows[key]
    if not summary or not W.Public(summary) then return false end
    for _,field in ipairs({"amount","quantity","fees","inflow","outflow"}) do
        if not W.Number(summary[field]) then return false end
    end
    local incoming,outgoing=math.max(0,record.amount),math.max(0,-record.amount)
    if summary.inflow<incoming or summary.outflow<outgoing then return false end
    summary.amount=summary.amount-record.amount
    summary.quantity=summary.quantity-record.quantity
    summary.fees=summary.fees-(record.fees or 0)
    summary.inflow=summary.inflow-incoming; summary.outflow=summary.outflow-outgoing
    if summary.amount==0 and summary.quantity==0 and summary.fees==0 and summary.inflow==0 and summary.outflow==0 then
        day.rows[key]=nil
    end
    table.remove(store.recent,index)
    return true
end

function Addon:SnapshotWealth()
    local store=self:GetWealthStore(); if not store then return end
    local money=W.Read(GetMoney); if not money or not W.Number(money[1]) then return end
    local key=self:GetCharacterKey(); local now=time(); local day=W.Day(now)
    local balances={}
    for charKey,char in pairs(self.db.global.characters or {}) do
        if W.Number(char.gold) then balances[charKey]=char.gold end
    end
    balances[key]=money[1]
    local bank=W.Read(C_Bank and C_Bank.FetchDepositedMoney,Enum and Enum.BankType and Enum.BankType.Account)
    local cached=(self.db.global.warbandBank or {}).gold
    if bank and W.Number(bank[1]) then balances.warband=bank[1]
    elseif W.Number(cached) then balances.warband=cached end
    store.days[day]=store.days[day] or {rows={},balances={}}
    store.days[day].balances=balances; store.days[day].checked=now
    -- Daily summaries retain a year; recent detail is a bounded supplementary view.
    local cutoff=W.Day(now-365*86400)
    for recorded in pairs(store.days) do if recorded<cutoff then store.days[recorded]=nil end end
end
local sales={vendor=true,auction=true,buyback=true}
local expense={purchase=true,auctionPurchase=true,repair=true}
function Addon:GetWealthView(options)
    options=options or {}; local store=self:GetWealthStore()
    local view={items={},history={},transactions={},sources={},income=0,spending=0,unknown=0,unknownIn=0,unknownOut=0,transfers=0,balance=0,net=0}
    if not store then return view end
    view.started=store.started
    local days=options.days or 30
    local cutoff=days==0 and "" or W.Day(time()-(days-1)*86400)
    local map={}; local selected=options.character
    local function Match(row)
        return (not selected or row.character==selected) and (not options.source or row.source==options.source
            or options.source=="vendor" and row.source=="buyback")
    end
    local dates={}; for day in pairs(store.days) do dates[#dates+1]=day end; table.sort(dates)
    for _,day in ipairs(dates) do
        local data=store.days[day]
        if day>=cutoff then
            local balance=0; local known=false
            for key,value in pairs(data.balances) do
                if not selected or selected==key then balance=balance+value; known=true end
            end
            if known then view.history[#view.history+1]={day=day,value=balance,at=data.checked}; view.balance=balance end
            for _,row in pairs(data.rows) do
                if Match(row) then
                    view.sources[row.source]=(view.sources[row.source] or 0)+row.amount
                    if sales[row.source] or row.source=="patronOrder" or row.source=="workOrder" then view.income=view.income+row.amount
                    elseif expense[row.source] then view.spending=view.spending-row.amount
                    elseif row.source=="transfer" or row.source=="deposit" or row.source=="auctionDeposit" then view.transfers=view.transfers+row.amount
                    else
                        view.unknown=view.unknown+row.amount
                        view.unknownIn=view.unknownIn+(row.inflow or math.max(0,row.amount))
                        view.unknownOut=view.unknownOut+(row.outflow or math.max(0,-row.amount))
                    end
                    if sales[row.source] and row.name
                        and (not options.query or string.find(string.lower(row.name),string.lower(options.query),1,true)) then
                        local item=map[row.itemKey] or {key=row.itemKey,name=row.name,itemID=row.itemID,amount=0,quantity=0,fees=0,vendor=0,auction=0}
                        map[row.itemKey]=item; item.amount=item.amount+row.amount; item.quantity=item.quantity+row.quantity
                        item.fees=item.fees+row.fees
                        if row.source=="auction" then item.auction=item.auction+row.amount else item.vendor=item.vendor+row.amount end
                    end
                end
            end
        end
    end
    for _,item in pairs(map) do
        item.average=item.quantity>0 and item.amount/item.quantity or 0
        view.items[#view.items+1]=item
    end
    table.sort(view.items,function(a,b)
        local field=options.sort=="average" and "average" or "amount"
        if a[field]==b[field] then return a.name<b.name end
        return a[field]>b[field]
    end)
    for _,row in ipairs(store.recent) do
        if W.Day(row.at)>=cutoff and Match(row) and (not options.item or row.itemKey==options.item) then
            view.transactions[#view.transactions+1]=row
        end
    end
    view.net=view.income-view.spending
    return view
end

-- A receipt only attributes an observed cash movement when all components reconcile.
function W.Invoice(invoice,header)
    if not W.Public(invoice) or not W.Public(header) or not invoice or not header then return nil end
    local kind,name,_,bid,_,deposit,fee=unpack(invoice)
    local count=invoice[11]; local money=header[5]
    if kind~="seller" or type(name)~="string" or not W.Number(bid) or not W.Number(deposit)
        or not W.Number(fee) or not W.Number(count) or count<=0 or not W.Number(money)
        or money<=0 or bid<0 or deposit<0 or fee<0 or fee>bid or bid+deposit-fee~=money then return nil end
    return {source="auction",name=name,quantity=count,amount=bid-fee,fees=fee,deposit=deposit,cash=money}
end

-- Vendor attribution needs both an item-count decrease and the matching money change.
function W.VendorDifference(before,after,delta)
    if not before or not after or delta<=0 then return nil end
    local rows,total={},0
    for id,old in pairs(before) do
        local quantity=old.quantity-(after[id] and after[id].quantity or 0)
        if quantity<0 then return nil end
        if quantity>0 then
            if not old.price or old.price<=0 then return nil end
            local amount=quantity*old.price; total=total+amount
            rows[#rows+1]={source="vendor",itemID=id,name=old.name,quantity=quantity,amount=amount}
        end
    end
    for id,new in pairs(after) do if not before[id] and new.quantity>0 then return nil end end
    if total==delta and #rows>0 then return rows end
end
