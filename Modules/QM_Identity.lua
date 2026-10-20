local _, ns = ...
local Addon = ns.TheQuartermaster
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = Copy(child) end
    return out
end
local function RealmKey(realm)
    return realm and realm:gsub("[%s%-']", "")
end
function Addon:GetCharacterKey(unit)
    unit = unit or "player"
    local name, realm = UnitName(unit)
    if unit == "player" or not realm or realm == "" then realm = GetRealmName() end
    if not name or name == "" or not realm or realm == "" then return nil end
    return name .. "-" .. realm
end
function Addon:GetGuildIdentity()
    local name, _, _, realm = GetGuildInfo("player")
    if not name or name == "" then return nil end
    realm = RealmKey(realm and realm ~= "" and realm or GetRealmName())
    if not realm or realm == "" then return nil end
    return "guild:" .. #realm .. ":" .. realm .. ":" .. name, name, realm
end
function Addon:GetGuildBankLabel(data, fallback)
    if data and data.name and data.realm then return data.name .. " - " .. data.realm end
    return fallback or ""
end

local function MoveRecord(map, oldKey, newKey, archive, category)
    if not map or map[oldKey] == nil or oldKey == newKey then return end
    local old, current = map[oldKey], map[newKey]
    archive[category] = archive[category] or {}
    archive[category][oldKey] = Copy(old)
    if current ~= nil then archive[category][newKey] = Copy(current) end
    if type(old) == "table" and type(current) == "table" then
        local oldTime = old.lastScan or old.lastSeen or 0
        local currentTime = current.lastScan or current.lastSeen or 0
        local primary, secondary = current, old
        if oldTime > currentTime then primary, secondary = old, current end
        local merged = Copy(primary)
        for key, value in pairs(secondary) do
            if merged[key] == nil then merged[key] = Copy(value) end
        end
        map[newKey] = merged
    elseif current == nil then
        map[newKey] = old
    elseif type(old) == "number" and type(current) == "number" then
        map[newKey] = math.max(old, current)
    end
    map[oldKey] = nil
end
local function MoveList(list, oldKey, newKey)
    if not list then return end
    local seen = {}
    local index = 1
    while index <= #list do
        if list[index] == oldKey then list[index] = newKey end
        if seen[list[index]] then table.remove(list, index)
        else seen[list[index]] = true; index = index + 1 end
    end
end
function Addon:ReconcileCurrentCharacterIdentity()
    if not self.db or not self.db.global then return end
    local name, realm = UnitName("player"), GetRealmName()
    local currentKey = self:GetCharacterKey()
    if not name or not realm or not currentKey then return end
    local normalized = (GetNormalizedRealmName and GetNormalizedRealmName()) or RealmKey(realm)
    if not normalized or normalized == "" then return end
    local oldKey = name .. "-" .. normalized
    if oldKey == currentKey then return end
    local global = self.db.global
    global.identityArchive = global.identityArchive or {}
    local archive = global.identityArchive
    global.identityAliases = global.identityAliases or {}
    global.identityAliases[oldKey] = currentKey
    MoveRecord(global.characters, oldKey, currentKey, archive, "characters")
    if global.characters and global.characters[currentKey] then
        global.characters[currentKey].name, global.characters[currentKey].realm = name, realm
    end
    for _, domain in ipairs({"mail", "currencies", "reputation", "statistics"}) do
        MoveRecord(global[domain] and global[domain].perCharacter, oldKey, currentKey, archive, domain)
    end
    MoveRecord(global.lastScans, oldKey, currentKey, archive, "lastScans")
    MoveList(global.favoriteCharacters, oldKey, currentKey)
    local order = self.db.profile and self.db.profile.characterOrder
    if order then
        MoveList(order.favorites, oldKey, currentKey)
        MoveList(order.regular, oldKey, currentKey)
    end
    if self.ClearAllCaches then self:ClearAllCaches() end
end
function Addon:RemoveIdentityRecovery(characterKey)
    local global = self.db.global
    for _, records in pairs(global.identityArchive or {}) do
        records[characterKey] = nil
        for oldKey, currentKey in pairs(global.identityAliases or {}) do
            if currentKey == characterKey then records[oldKey] = nil end
        end
    end
    for oldKey, currentKey in pairs(global.identityAliases or {}) do
        if currentKey == characterKey then global.identityAliases[oldKey] = nil end
    end
end
function Addon:PreserveUnscopedGuildBanks()
    local global = self.db and self.db.global
    if not global or not global.guildBank then return end
    for key, data in pairs(global.guildBank) do
        if type(data) == "table" and data.identityVersion ~= 1 then
            global.legacyGuildBanks = global.legacyGuildBanks or {}
            -- Keep every legacy snapshot, including data reintroduced by older code.
            global.legacyGuildBanks[key] = global.legacyGuildBanks[key] or {}
            table.insert(global.legacyGuildBanks[key], Copy(data))
            global.guildBank[key] = nil
        end
    end
end
