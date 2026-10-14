local _, ns = ...
local Addon = ns.TheQuartermaster

local function Public(value, depth)
    if issecretvalue and issecretvalue(value) then return false end
    if type(value) == "table" then
        if (depth or 0) > 4 then return false end
        for key, child in pairs(value) do
            if not Public(key, (depth or 0)+1) or not Public(child, (depth or 0)+1) then return false end
        end
    end
    return true
end
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local result = {pcall(fn, ...)}
    if not result[1] or not Public(result) then return nil end
    return result
end
local function Number(value) return type(value) == "number" and value >= 0 and value == math.floor(value) end

-- Counts are journal scopes, not a promise that every entry is currently obtainable.
-- Never change the player's journal filters to collect a denominator.
function Addon:RequestAccountCollections()
    local now = GetTime()
    if self.accountCollectionJob or (self.accountCollectionChecked and now-self.accountCollectionChecked < 60)
        or (InCombatLockdown and InCombatLockdown()) then return end
    self.accountCollectionChecked = now
    self.accountCollectionJob = true
    self.accountCollections = self.accountCollections or {}
    local previous = self.accountCollections
    local nextCounts = {}
    local function Save(kind, owned, total, scope)
        if Number(owned) and (total == nil or (Number(total) and total > 0 and owned <= total)) then
            nextCounts[kind] = {owned=owned, total=total, scope=scope, capturedAt=time()}
        end
    end
    local function Scan()
        local ids = Read(C_MountJournal and C_MountJournal.GetMountIDs)
        if ids and type(ids[2]) == "table" and #ids[2] > 0 then
            local owned, total, valid, seen = 0, 0, true, {}
            for index, id in ipairs(ids[2]) do
                local info = Read(C_MountJournal.GetMountInfoByID, id)
                if not info or type(info[11]) ~= "boolean" or type(info[12]) ~= "boolean" then valid=false; break end
                if not seen[id] then
                    seen[id]=true
                    if info[12] or not info[11] then total=total+1; if info[12] then owned=owned+1 end end
                end
                if index % 100 == 0 then coroutine.yield() end
            end
            if valid then Save("mounts", owned, total, "AT_MOUNT_SCOPE") end
        end

        local ownedIDs = Read(C_PetJournal and C_PetJournal.GetOwnedPetIDs)
        local ownedSpecies, ownedCount, ownedValid = {}, 0, ownedIDs and type(ownedIDs[2]) == "table"
        if ownedValid then
            for index, id in ipairs(ownedIDs[2]) do
                local info = Read(C_PetJournal.GetPetInfoByPetID, id)
                if not info or not Number(info[2]) or info[2] == 0 then ownedValid=false; break end
                if not ownedSpecies[info[2]] then ownedSpecies[info[2]]=true; ownedCount=ownedCount+1 end
                if index % 100 == 0 then coroutine.yield() end
            end
        end
        local defaults = Read(C_PetJournal and C_PetJournal.IsUsingDefaultFilters)
        local search = Read(C_PetJournal and C_PetJournal.GetSearchFilter)
        local count = Read(C_PetJournal and C_PetJournal.GetNumPets)
        if defaults and defaults[2] == true and search and search[2] == "" and count and Number(count[2]) and count[2] > 0 then
            local seen, total, owned, valid = {}, 0, 0, true
            for index=1,count[2] do
                local info = Read(C_PetJournal.GetPetInfoByIndex, index)
                if not info or not Number(info[3]) or info[3] == 0 or type(info[4]) ~= "boolean" then valid=false; break end
                local species = info[3]
                if seen[species] == nil then total=total+1; seen[species]=false end
                if info[4] and not seen[species] then owned=owned+1; seen[species]=true end
                if index % 100 == 0 then coroutine.yield() end
            end
            -- Filtering/list updates during the batch invalidate its denominator.
            local afterDefaults = Read(C_PetJournal.IsUsingDefaultFilters)
            local afterSearch = Read(C_PetJournal.GetSearchFilter)
            local afterCount = Read(C_PetJournal.GetNumPets)
            if valid and afterDefaults and afterDefaults[2] == true and afterSearch and afterSearch[2] == ""
                and afterCount and afterCount[2] == count[2] and (not ownedValid or owned==ownedCount) then
                Save("pets", owned, total, "AT_PET_SCOPE")
            end
        end
        if not nextCounts.pets and ownedValid then
            local old = previous.pets
            Save("pets", ownedCount, nil, "AT_PET_FILTERED")
            if old and old.total and old.total >= ownedCount then
                nextCounts.pets.total=old.total; nextCounts.pets.scope="AT_PET_CACHED"; nextCounts.pets.totalCapturedAt=old.totalCapturedAt or old.capturedAt
            end
        end
        local total = Read(C_ToyBox and C_ToyBox.GetNumTotalDisplayedToys)
        local owned = Read(C_ToyBox and C_ToyBox.GetNumLearnedDisplayedToys)
        if total and owned then Save("toys", owned[2], total[2], "AT_TOY_SCOPE") end
    end
    local job = coroutine.create(Scan)
    local function Step()
        if InCombatLockdown and InCombatLockdown() then self.accountCollectionJob=nil; self.accountCollectionChecked=nil; return end
        local ok = coroutine.resume(job)
        if ok and coroutine.status(job) ~= "dead" then C_Timer.After(0.01, Step); return end
        self.accountCollectionJob=nil
        if ok then
            for kind, row in pairs(nextCounts) do previous[kind]=row end
            local frame = self.UI and self.UI.mainFrame
            if frame and frame:IsShown() and frame.currentTab == "totals" then self:RefreshUI() end
        end
    end
    C_Timer.After(0, Step)
end
