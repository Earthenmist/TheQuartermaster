-- Public slot observations only; unavailable reads keep the last-good record.
local _, ns = ...
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    return value
end
function ns.CollectEquipmentSlot(slotID, previous)
    if InCombatLockdown and InCombatLockdown() then return previous end
    local exists
    if C_Item and ItemLocation and ItemLocation.CreateFromEquipmentSlot then
        local location = Read(ItemLocation.CreateFromEquipmentSlot, ItemLocation, slotID)
        if location then
            exists = Read(C_Item.DoesItemExist, location)
            if exists == nil then return previous end
        else
            return previous
        end
    end
    if exists == false then return {empty = true, lastScan = time()} end
    local id = Read(GetInventoryItemID, "player", slotID)
    local link = Read(GetInventoryItemLink, "player", slotID)
    if not id and not link then return previous end
    local item = {}
    if previous and not previous.empty and ((id and id == previous.itemID) or (link and link == previous.itemLink)) then
        for k, v in pairs(previous) do item[k] = v end
    end
    item.itemID = id or item.itemID
    item.itemLink = link or item.itemLink
    item.iconFileID = Read(GetInventoryItemTexture, "player", slotID) or item.iconFileID
    item.itemLevel = (link and C_Item and Read(C_Item.GetDetailedItemLevelInfo, link)) or item.itemLevel
    if link and GetItemInfo then
        local ok, name, _, quality = pcall(GetItemInfo, link)
        if ok then
            if not (issecretvalue and issecretvalue(name)) then item.name = name or item.name end
            if not (issecretvalue and issecretvalue(quality)) then item.quality = quality or item.quality end
        end
    end
    item.lastScan = time()
    return item
end
function ns.EquipmentSlotState(item)
    if item and (item.itemID or item.itemLink or item.iconFileID) then return "item" end
    if item and item.empty == true and type(item.lastScan) == "number" then return "empty" end
    return "unknown"
end

-- A complete public profession snapshot can distinguish unlearned from unscanned.
function ns.CollectGearProfessions(previous)
    if InCombatLockdown and InCombatLockdown() then return previous end
    if not GetProfessions or not GetProfessionInfo then return previous end
    local result = {pcall(GetProfessions)}
    if not result[1] then return previous end
    local indices = {}
    for i = 2, 6 do
        local value = result[i]
        if issecretvalue and issecretvalue(value) then return previous end
        indices[i] = value
    end
    -- All-nil can occur while skills are loading; it is not proof of no professions.
    if not (indices[2] or indices[3] or indices[4] or indices[5] or indices[6]) then return previous end
    local out = {}
    for key, position in pairs({[1]=2, [2]=3, cooking=6, fishing=5}) do
        local index = indices[position]
        if index then
            local values = {pcall(GetProfessionInfo, index)}
            if not values[1] then return previous end
            for _, n in ipairs({2, 3, 8}) do
                if issecretvalue and issecretvalue(values[n]) then return previous end
            end
            if type(values[2]) ~= "string" or values[2] == "" then return previous end
            out[key] = {name=values[2], icon=values[3], skillLine=values[8], learned=true, lastScan=time()}
        else
            out[key] = {learned=false, lastScan=time()}
        end
    end
    return out
end
