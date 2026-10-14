-- Optional, user-triggered shopping lists. Auctionator owns serialization and UI updates.
local _, ns = ...
local Addon = ns.TheQuartermaster
local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end
local function Number(value)
    return Public(value) and type(value) == "number" and value == value
        and value >= 0 and value < math.huge
end
function Addon:HasAuctionatorShoppingAPI()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    return api and type(api.CreateShoppingList) == "function"
        and type(api.ConvertToSearchString) == "function" and api or nil
end
function Addon:SendWatchlistToAuctionator(scope)
    local api = self:HasAuctionatorShoppingAPI()
    if not api then return false, ns.L.AU_UNAVAILABLE end
    local view = self:GetRecipeWatchlistView(scope)
    local terms, ids, skipped = {}, {}, 0
    for id in pairs(view.reagents) do
        if Number(id) and id > 0 then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local entry = view.reagents[id]
        local target = type(entry) == "table" and entry.target or 0
        if not Number(target) then return false, ns.L.AU_WAIT end
        if target > 0 then
            local readOK, owned = pcall(self.CountItemTotals, self, id, view.includeGuildBank)
            if not readOK or not Number(owned) then return false, ns.L.AU_WAIT end
            local missing = math.max(0, math.ceil(target - owned))
            if missing > 0 then
                local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
                local ok, name, bindType = pcall(function()
                    local values = {getInfo(id)}
                    return values[1], values[14]
                end)
                if not ok or not Public(name) or not Public(bindType)
                    or type(name) ~= "string" or name == "" or not Number(bindType) then
                    if C_Item and C_Item.RequestLoadItemDataByID then
                        pcall(C_Item.RequestLoadItemDataByID, id)
                    end
                    return false, ns.L.AU_WAIT
                end
                if bindType == 1 then
                    skipped = skipped + 1
                else
                    local qualityAPI = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
                    if not qualityAPI then return false, ns.L.AU_WAIT end
                    local tierOK, tier = pcall(qualityAPI, id)
                    if not tierOK or not Public(tier) then return false, ns.L.AU_WAIT end
                    if tier ~= nil and (not Number(tier) or tier < 1 or tier > 5 or tier % 1 ~= 0) then
                        return false, ns.L.AU_WAIT
                    end
                    -- tier is crafting quality; Auctionator's quality field is item rarity.
                    local converted, term = pcall(api.ConvertToSearchString, "TheQuartermaster", {
                        searchString = name, isExact = true, quantity = missing, tier = tier,
                    })
                    if not converted or not Public(term) or type(term) ~= "string" or term == "" then
                        return false, ns.L.AU_FAILED
                    end
                    terms[#terms + 1] = term
                end
            end
        end
    end
    if #terms == 0 then return false, ns.L.AU_EMPTY end
    -- Stable names avoid a new list whenever the craft count changes.
    local label = scope == "all" and ns.L.RW_ALL or ns.L.RW_GENERAL
    if type(scope) == "number" then
        label = (self.db.global.recipeNames[scope] or string.format(ns.L.RB_UNNAMED, scope))
            .. " (#" .. scope .. ")"
    end
    local name = "The Quartermaster - " .. label
    local ok = pcall(api.CreateShoppingList, "TheQuartermaster", name, terms)
    if not ok then return false, ns.L.AU_FAILED end
    return true, string.format(ns.L.AU_SENT, #terms, name, skipped)
end
