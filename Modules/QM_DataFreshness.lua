-- Source-specific coverage. Character login time is never a bank/progression timestamp.
local _, ns = ...
local Addon = ns.TheQuartermaster
local Freshness = {}
ns.DataFreshness = Freshness
Freshness.states = {"unavailable", "stale", "not_collected", "unknown", "cached", "fresh"}

function Freshness.Resolve(record, now)
    local stamp = record.timestamp
    if type(stamp) ~= "number" or stamp ~= stamp or stamp <= 0 or stamp > now then stamp = nil end
    local state
    if record.unavailable then state = "unavailable"
    elseif record.stale then state = "stale"
    elseif not record.present then state = "not_collected"
    elseif record.unknown or not stamp then state = "unknown"
    elseif now - stamp <= 60 then state = "fresh"
    else state = "cached" end
    return {state = state, timestamp = stamp,
        empty = record.empty == true and stamp ~= nil and not record.unavailable and not record.unknown}
end

local screenSources = {
    setup = {"inventory", "personal", "warband", "mailAttachments", "recipes"},
    totals = {"character", "inventory", "personal", "warband", "collections"},
    stats = {"character", "inventory", "personal", "warband", "collections", "pve"},
    chars = {"character", "inventory", "personal", "mail", "pve"},
    exp = {"character"}, guild = {"membership", "guild"},
    equip = {"equipment"}, profequip = {"professionEquipment"},
    currency = {"currency"}, reputations = {"reputation"}, pve = {"pve"},
    quests = {"questLog"}, achievements = {"achievements"},
    recipes = {"recipes", "recipeDetails"},
    auctions = {"auctions"}, wealth = {"wealth"}, concentration = {"concentration"}, cooldowns = {"cooldowns"}, knowledge = {"knowledge"},
    materials = {"inventory", "personal", "warband", "guild", "equipment", "professionEquipment", "mailAttachments"},
    storage = {"inventory", "personal", "warband", "guild", "auctions"},
    search = {"inventory", "personal", "warband", "guild", "equipment", "currency", "mailAttachments", "auctions"},
    watchlist = {"inventory", "personal", "warband", "guild", "currency", "equipment", "professionEquipment", "mailAttachments"},
}

function Addon:GetDataCoverage(screen, itemSource)
    local db = self.db or {}
    local global, charDB = db.global or {}, db.char or {}
    local now = time()
    local season = self.GetPvESeason and self:GetPvESeason()
    local currentCharacter = self.GetCharacterKey and self:GetCharacterKey()
    local sources = screen == "items" and {itemSource or "inventory"} or screenSources[screen] or {"character"}
    local groups = {}
    local function Add(group, record)
        local status = Freshness.Resolve(record, now)
        group.total = group.total + 1
        group.counts[status.state] = (group.counts[status.state] or 0) + 1
        if status.empty then group.empty = group.empty + 1 end
        if status.timestamp then
            group.oldest = math.min(group.oldest or status.timestamp, status.timestamp)
            group.newest = math.max(group.newest or status.timestamp, status.timestamp)
        end
    end
    local function Bank(group, snapshot, failure)
        Add(group, {present = snapshot and (snapshot.lastScan or 0) > 0 or snapshot and next(snapshot.items or {}) ~= nil,
            timestamp = snapshot and snapshot.lastScan,
            empty = snapshot and snapshot.usedSlots == 0, unavailable = failure})
    end
    for _, domain in ipairs(sources) do
        local group = {domain = domain, total = 0, empty = 0, counts = {}}
        groups[#groups + 1] = group
        local failed = self.scanStatus and self.scanStatus[domain] == "unavailable"
        if domain == "warband" then
            Bank(group, global.warbandBank, failed)
        elseif screen == "items" and (domain == "inventory" or domain == "personal") then
            Bank(group, charDB[domain == "personal" and "personalBank" or "inventory"], failed)
        elseif domain == "guild" then
            local banks = global.guildBank or {}
            if screen == "items" then
                local key = self:GetGuildIdentity()
                banks = key and banks[key] and {[key] = banks[key]} or {}
            end
            local currentGuild = self.GetGuildIdentity and self:GetGuildIdentity()
            for key, bank in pairs(banks) do
                for _, tab in pairs(bank.tabs or {}) do
                    Add(group, {present = true, timestamp = tab.lastScan,
                        empty = tab.items ~= nil and not next(tab.items), unavailable = key == currentGuild and failed})
                end
            end
            group.legacy = global.legacyGuildBanks and next(global.legacyGuildBanks) ~= nil
        elseif domain == "wealth" then
            -- History capture time describes the aggregate observation, not every alt balance.
            local store, latest = global.wealth, nil
            if store and store.version == 1 then
                for _, day in pairs(store.days or {}) do
                    local stamp = day.checked
                    if type(stamp) == "number" and stamp > 0 and stamp <= now then
                        latest = math.max(latest or stamp, stamp)
                    end
                end
            end
            Add(group, {present = store ~= nil, timestamp = latest,
                unknown = store and store.version ~= 1})
        elseif domain == "collections" then
            Add(group, {present = true}) -- Live/cached mix has no common captured timestamp.
        else
            for key, character in pairs(global.characters or {}) do
                if domain == "character" then
                    Add(group, {present = true, timestamp = character.lastSeen})
                elseif domain == "inventory" then
                    Bank(group, character.inventory, key == currentCharacter and failed)
                elseif domain == "personal" then
                    Add(group, {present = character.personalBank ~= nil, timestamp = character.personalBankLastScan,
                        empty = character.personalBankUsedSlots == 0, unavailable = key == currentCharacter and failed})
                elseif domain == "mailAttachments" then
                    local mail = self.GetMailCache and self:GetMailCache(key)
                    local attachments = mail and mail.attachments
                    Add(group, {present = mail ~= nil,
                        timestamp = attachments and attachments.lastScan or (mail and mail.count == 0 and mail.lastScan),
                        unknown = mail and mail.count ~= 0 and not attachments,
                        stale = attachments and attachments.state ~= "complete", empty = mail and mail.count == 0})
                elseif domain == "mail" then
                    local mail = self.GetMailCache and self:GetMailCache(key)
                    Add(group, {present = mail ~= nil, timestamp = mail and mail.lastScan})
                elseif domain == "recipes" then
                    local found = false
                    for id, profession in pairs(character.professionRecipes or {}) do
                        if ns.IsTrackedRecipeProfession(id) then
                        found = true
                        Add(group, {present = true, timestamp = profession.lastScan,
                            unknown = not profession.ownerVerified, empty = profession.recipes ~= nil and not next(profession.recipes)})
                        end
                    end
                    if not found then Add(group, {}) end
                elseif domain == "auctions" then
                    local store = global.ownedAuctions
                    local supported = store and store.version == 1
                    local snapshot = supported and store.characters and store.characters[key]
                    Add(group, {present = snapshot ~= nil or store and not supported,
                        timestamp = snapshot and snapshot.checked,
                        unknown = store and not supported,
                        empty = snapshot and snapshot.rows and not next(snapshot.rows),
                        unavailable = key == currentCharacter and self._auctionState == "incomplete"})
                elseif domain == "recipeDetails" or domain == "concentration" or domain == "cooldowns" or domain == "knowledge" then
                    local records = character[domain == "knowledge" and "professionKnowledge" or domain == "recipeDetails" and "professionRecipeDetails" or domain == "cooldowns" and "professionCooldowns" or "professionConcentration"] or {}
                    local found = false
                    for _, snapshot in pairs(records) do
                        found = true
                        Add(group, {present = true, timestamp = snapshot.version == 1 and snapshot.checked,
                            unknown = snapshot.version ~= 1 or (domain == "recipeDetails" or domain == "cooldowns") and snapshot.partial or domain == "knowledge" and (not ns.KnowledgeData or snapshot.revision ~= ns.KnowledgeData.revision),
                            stale = domain == "knowledge" and snapshot.flags and (not snapshot.flags.resetAt or now >= snapshot.flags.resetAt),
                            empty = domain == "recipeDetails" and snapshot.version == 1
                                and snapshot.rows and not next(snapshot.rows)})
                    end
                    if not found then Add(group, {}) end
                elseif domain == "achievements" then
                    local snapshot=character.achievements
                    Add(group,{present=snapshot~=nil,timestamp=snapshot and snapshot.checked,
                        unknown=snapshot and (snapshot.version~=1 or snapshot.partial)})
                elseif domain == "questLog" then
                    local snapshot=character.questLog
                    Add(group,{present=snapshot~=nil,timestamp=snapshot and snapshot.checked,
                        unknown=snapshot and snapshot.version~=1,
                        empty=snapshot and snapshot.version==1 and snapshot.rows and #snapshot.rows==0})
                elseif domain == "pve" then
                    local pve = character.pve
                    local expired = pve and ((pve.weeklyResetAt and now >= pve.weeklyResetAt)
                        or (season and pve.seasonID and season ~= pve.seasonID))
                    Add(group, {present = pve ~= nil, timestamp = pve and (pve.capturedAt or pve.lastScan),
                        stale = expired or pve and pve.scanState == "stale",
                        unavailable = pve and pve.scanState == "unavailable",
                        unknown = pve and (not pve.weeklyResetAt or not pve.seasonID or not season)})
                else
                    local field = ({currency = "currencies", reputation = "reputations", membership = "guildName"})[domain] or domain
                    Add(group, {present = character[field] ~= nil})
                end
            end
        end
        if group.total == 0 then Add(group, {unavailable = screen == "items" and failed}) end
    end
    return groups
end
