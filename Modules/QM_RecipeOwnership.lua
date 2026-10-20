local _, ns = ...
-- Base skill lines for primary professions and Cooking; auxiliary crafting UIs
-- are not character professions, regardless of their localized display name.
local roots = {[171]=true, [164]=true, [333]=true, [202]=true, [182]=true,
    [773]=true, [755]=true, [165]=true, [186]=true, [393]=true, [197]=true, [185]=true}
function ns.IsTrackedRecipeProfession(id) return roots[tonumber(id)] == true end
local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end
-- Expansion and specialised skill lines may have more than one parent.
-- Only a public, explicitly resolved tracked root establishes membership.
function ns.GetRecipeProfessionRoot(info)
    local seen = {}
    for _ = 1, 8 do
        if type(info) ~= "table" or not Public(info.professionID) or not Public(info.parentProfessionID) then return nil end
        local id, parent = info.professionID, info.parentProfessionID
        if roots[id] then return id end
        if roots[parent] then return parent end
        if type(parent) ~= "number" or parent <= 0 or seen[parent] then return nil end
        seen[parent] = true
        if not C_TradeSkillUI.GetProfessionInfoBySkillLineID then return nil end
        local ok, nextInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, parent)
        if not ok then return nil end
        info = nextInfo
    end
end
local function FalseFlag(api, name)
    if type(api[name]) ~= "function" then return false end
    local ok, result = pcall(api[name])
    return ok and Public(result) and result == false
end
function ns.GetOwnedRecipeContext(addon)
    local api = C_TradeSkillUI
    if not api or not FalseFlag(api, "IsTradeSkillLinked") or not FalseFlag(api, "IsTradeSkillGuild")
        or not FalseFlag(api, "IsNPCCrafting") then return nil end
    if not api.IsTradeSkillReady or not api.IsTradeSkillReady() then return nil end
    local info = api.GetBaseProfessionInfo and api.GetBaseProfessionInfo()
    if not info or not Public(info.professionID) or not Public(info.sourceCounter)
        or type(info.sourceCounter) ~= "number" or not ns.IsTrackedRecipeProfession(info.professionID) then return nil end
    if not GetProfessions or not GetProfessionInfo then return nil end
    local owned = false
    for _, index in pairs({GetProfessions()}) do
        local _, _, _, _, _, _, skillLine = GetProfessionInfo(index)
        if Public(skillLine) and skillLine == info.professionID then owned = true end
    end
    if not owned then return nil end
    local key = addon:GetCharacterKey()
    if not key then return nil end
    return {key = key, id = info.professionID, source = info.sourceCounter, info = info}
end
function ns.SameRecipeContext(a, b)
    return a and b and a.key == b.key and a.id == b.id and a.source == b.source
end
