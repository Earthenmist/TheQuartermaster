-- Small, explicitly requested snapshots; never scan every schematic on redraw.
local _, ns = ...
local Addon = ns.TheQuartermaster
local function Public(v) return not (issecretvalue and issecretvalue(v)) end
local function Table(v) return Public(v) and type(v) == "table" end
local function Integer(v) return Public(v) and type(v) == "number" and v > 0 and v < 100000000 and v == math.floor(v) end

function ns.NormalizeRecipeIngredients(data, recipeID)
    if not Table(data) or not Public(data.recipeID) or data.recipeID ~= recipeID
        or not Public(data.isRecraft) or data.isRecraft ~= false
        or not Table(data.reagentSlotSchematics) or #data.reagentSlotSchematics > 30 then return nil end
    local slots = {}
    for _, slot in ipairs(data.reagentSlotSchematics) do
        if not Table(slot) or not Public(slot.required) or type(slot.required) ~= "boolean" then return nil end
        if slot.required then
            if not Integer(slot.quantityRequired) or not Table(slot.reagents) or #slot.reagents == 0
                or #slot.reagents > 20 or not Table(slot.variableQuantities) or #slot.variableQuantities > 0 then return nil end
            local ids, seen = {}, {}
            for _, reagent in ipairs(slot.reagents) do
                if not Table(reagent) or not Integer(reagent.itemID) then return nil end
                if not seen[reagent.itemID] then ids[#ids + 1], seen[reagent.itemID] = reagent.itemID, true end
            end
            table.sort(ids)
            slots[#slots + 1] = {quantity = slot.quantityRequired, itemIDs = ids}
        end
    end
    -- Empty requirements can be a loading state. Preserve the previous snapshot.
    if #slots == 0 then return nil end
    return {slots = slots, version = 1}
end

function Addon:CollectRecipeIngredients(recipeID)
    if not Integer(recipeID) or not (self.db and self.db.profile and self.db.profile.trackProfessionRecipes)
        or (InCombatLockdown and InCombatLockdown()) then return false end
    local ok, snapshot, key, professionID = pcall(function()
        local context = ns.GetOwnedRecipeContext(self)
        if not context then return end
        local api = C_TradeSkillUI
        local info = api.GetRecipeInfo(recipeID)
        local profession = api.GetProfessionInfoByRecipeID(recipeID)
        if not Table(info) or not Public(info.learned) or info.learned ~= true or not Table(profession) then return end
        if not Public(profession.parentProfessionID) or not Public(profession.professionID) then return end
        if ns.GetRecipeProfessionRoot(profession) ~= context.id then return end
        local char = self.db.global.characters[context.key]
        local entry = char and char.professionRecipes and char.professionRecipes[context.id]
        if not entry or not entry.ownerVerified then return end
        local known = false
        for _, id in ipairs(entry.recipes or {}) do if id == recipeID then known = true; break end end
        if not known or not api.GetRecipeSchematic then return end
        local result = ns.NormalizeRecipeIngredients(api.GetRecipeSchematic(recipeID, false), recipeID)
        if not result or not ns.SameRecipeContext(context, ns.GetOwnedRecipeContext(self)) then return end
        result.collectedAt = time()
        return result, context.key, context.id
    end)
    if not ok or not snapshot then return false end
    local entry = self.db.global.characters[key].professionRecipes[professionID]
    entry.ingredients = entry.ingredients or {}
    entry.ingredients[recipeID] = snapshot
    return true
end

function Addon:GetRecipeIngredients(recipeID, crafters)
    local newest, owner
    for _, key in ipairs(crafters or {}) do
        local char = self.db.global.characters[key]
        for id, entry in pairs(char and char.professionRecipes or {}) do
            local snapshot = entry.ownerVerified and ns.IsTrackedRecipeProfession(id) and entry.ingredients and entry.ingredients[recipeID]
            if snapshot and snapshot.version == 1 and (not newest or snapshot.collectedAt > newest.collectedAt) then
                newest, owner = snapshot, key
            end
        end
    end
    return newest, owner
end

-- Combine repeated fixed slots. Alternatives remain choices, never double-counted stock.
function ns.RecipeCraftCount(value)
    local count = tonumber(value)
    if not count or count < 1 or count > 10000 or count ~= math.floor(count) then return nil end
    return count
end

function ns.RecipeMaterialRows(snapshot, crafts)
    crafts = ns.RecipeCraftCount(crafts or 1)
    if not crafts then return {} end
    local rows, byID = {}, {}
    for _, slot in ipairs(snapshot.slots) do
        if #slot.itemIDs == 1 then
            local id = slot.itemIDs[1]
            if not byID[id] then
                byID[id] = {itemID = id, quantity = 0}
                rows[#rows + 1] = byID[id]
            end
            byID[id].quantity = byID[id].quantity + slot.quantity * crafts
        else rows[#rows + 1] = {itemIDs = slot.itemIDs, quantity = slot.quantity * crafts} end
    end
    return rows
end
