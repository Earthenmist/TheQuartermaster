local _, ns = ...
local Addon, L = ns.TheQuartermaster, ns.L
local gathering = {[182] = true, [186] = true, [393] = true}
function Addon:GetSetupChecklist()
    local rows, now, complete, total = {}, time(), 0, 0
    local ownerKey, currentKey = nil, self.GetCharacterKey and self:GetCharacterKey()
    local function Check(domain, record, hint, label)
        local source = ({bags = 'inventory', bank = 'personal', warband = 'warband'})[domain]
        if source and self.scanStatus and self.scanStatus[source] == 'unavailable'
            and (domain == 'warband' or ownerKey == currentKey) then record.unavailable = true end
        local status = ns.DataFreshness.Resolve(record, now)
        status.domain, status.label, status.hint = domain, label or L['SETUP_' .. domain], hint
        status.ready = status.state == 'fresh' or status.state == 'cached'
        total = total + 1; if status.ready then complete = complete + 1 end
        return status
    end
    local function Bank(domain, data, hint)
        return Check(domain, {present = data ~= nil, timestamp = data and data.lastScan,
            empty = data and data.usedSlots == 0}, hint)
    end
    local shared = Bank('warband', self.db.global.warbandBank, L.SETUP_DO_WARBAND)
    for key, char in ns.OrderedCharacterPairs(self.db) do
        ownerKey = key
        local row = {key = key, checks = {}, ready = true}
        rows[#rows + 1] = row
        local inventory = char.inventory
        row.checks[1] = Bank('bags', inventory, L.SETUP_DO_BAGS)
        row.checks[2] = Check('bank', {present = char.personalBank ~= nil, timestamp = char.personalBankLastScan,
            empty = char.personalBankUsedSlots == 0}, L.SETUP_DO_BANK)
        local mail = self:GetMailCache(key)
        local attachment = mail and mail.attachments
        row.checks[3] = Check('mail', {present = mail ~= nil,
            timestamp = attachment and attachment.lastScan or (mail and mail.count == 0 and mail.lastScan),
            unknown = mail and mail.count ~= 0 and not attachment,
            stale = attachment and attachment.state ~= 'complete',
            empty = mail and mail.count == 0}, L.SETUP_DO_MAIL)
        local professions, unknown = {}, char.professions == nil
        for _, profession in pairs(char.professions or {}) do
            if type(profession) == 'table' then
                local id = tonumber(profession.skillLine)
                if not id then unknown = true
                elseif ns.IsTrackedRecipeProfession(id) and not gathering[id] then professions[id] = profession end
            end
        end
        local recipeChecks = {}
        row.recipeChecks = recipeChecks
        for id, profession in pairs(professions) do
            local cache = char.professionRecipes and (char.professionRecipes[id] or char.professionRecipes[tostring(id)])
            recipeChecks[#recipeChecks + 1] = Check('recipes', {present = cache ~= nil,
                timestamp = cache and cache.lastScan, unknown = cache and not cache.ownerVerified},
                string.format(L.SETUP_DO_RECIPE, profession.name or tostring(id)), profession.name or tostring(id))
        end
        table.sort(recipeChecks, function(a, b) return a.label < b.label end)
        if self.db.profile.trackProfessionRecipes == false then
            -- Disabled tracking is an intentional exclusion, not missing character data.
            for _, check in ipairs(recipeChecks) do total = total - 1; if check.ready then complete = complete - 1 end end
            row.recipeChecks = {}
            row.checks[4] = {domain = 'recipes', label = L.SETUP_recipes, state = 'disabled', ready = true, hint = L.SETUP_RECIPES_DISABLED}
        elseif unknown then
            row.checks[4] = Check('recipes', {}, L.SETUP_DO_LOGIN)
            recipeChecks[#recipeChecks + 1] = row.checks[4]
        elseif #recipeChecks == 0 then
            row.checks[4] = {domain = 'recipes', label = L.SETUP_recipes, state = 'not_applicable', ready = true, hint = L.SETUP_NO_PROFESSIONS}
        else
            local ready = true
            for _, check in ipairs(recipeChecks) do if not check.ready then ready = false end end
            row.checks[4] = {domain = 'recipes', label = L.SETUP_recipes, state = ready and 'cached' or 'not_collected', ready = ready,
                hint = L.SETUP_RECIPE_LISTS}
        end
        for _, check in ipairs(row.checks) do if not check.ready then row.ready = false end end
    end
    return rows, shared, complete, total
end
