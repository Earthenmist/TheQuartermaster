-- Recipe requirements are independent of general pins and other recipes.
local _, ns = ...
local Addon = ns.TheQuartermaster
local function Plans(self)
    return self.db and self.db.profile and self.db.profile.recipeWatchlists or {}
end
local function RemoveEmpty(self, recipeID, plan)
    if type(plan.reagents) == "table" and next(plan.reagents) == nil then
        self.recipeCraftCounts = self.recipeCraftCounts or {}
        self.recipeCraftCounts[recipeID] = nil
        Plans(self)[recipeID] = nil
    end
end
function Addon:GetRecipeWatchlist(recipeID)
    return Plans(self)[recipeID]
end
function Addon:GetRecipeWatchlistCrafts(recipeID)
    local plan = self:GetRecipeWatchlist(recipeID)
    return plan and plan.crafts or (self.recipeCraftCounts and self.recipeCraftCounts[recipeID]) or 1
end
function Addon:IsRecipeIngredientTracked(recipeID, itemID)
    local plan = self:GetRecipeWatchlist(recipeID)
    return plan and plan.reagents[itemID] ~= nil or false
end
function Addon:ToggleRecipeIngredient(recipeID, itemID, quantity, crafts)
    if type(recipeID) ~= "number" or type(itemID) ~= "number" then return false end
    local plan = self:GetRecipeWatchlist(recipeID)
    if plan and plan.reagents[itemID] then
        plan.reagents[itemID] = nil
        RemoveEmpty(self, recipeID, plan)
    else
        crafts = ns.RecipeCraftCount(crafts)
        if not crafts or type(quantity) ~= "number" or quantity <= 0 or quantity == math.huge then return false end
        self.db.profile.recipeWatchlists = self.db.profile.recipeWatchlists or {}
        plan = plan or {crafts = crafts, reagents = {}}
        self.db.profile.recipeWatchlists[recipeID] = plan
        plan.reagents[itemID] = {target = quantity}
    end
    if self.RefreshUI then self:RefreshUI() end
    return true
end
function Addon:UpdateRecipeIngredientTargets(recipeID, snapshot, crafts)
    crafts = ns.RecipeCraftCount(crafts)
    if not crafts then return false end
    local plan = self:GetRecipeWatchlist(recipeID)
    if not plan then return true end
    local targets = {}
    for _, row in ipairs(ns.RecipeMaterialRows(snapshot, crafts)) do
        for _, id in ipairs(row.itemID and {row.itemID} or row.itemIDs) do
            if plan.reagents[id] then targets[id] = (targets[id] or 0) + row.quantity end
        end
    end
    -- Unavailable/removed requirements keep their last explicit target.
    for id, quantity in pairs(targets) do plan.reagents[id].target = quantity end
    plan.crafts = crafts
    return true
end
function Addon:GetRecipeWatchlistScopes()
    local scopes = {{id = "general", name = ns.L.RW_GENERAL}, {id = "all", name = ns.L.RW_ALL}}
    local ids = {}
    for id, plan in pairs(Plans(self)) do RemoveEmpty(self, id, plan) end
    for id in pairs(Plans(self)) do ids[#ids + 1] = id end
    if type(self.recipeWatchlistScope) == "number" and not Plans(self)[self.recipeWatchlistScope] then
        self.recipeWatchlistScope = #ids > 0 and "all" or "general"
        self.watchlistReagentPage = 1
    end
    table.sort(ids)
    local names = self.db.global.recipeNames or {}
    for _, id in ipairs(ids) do
        scopes[#scopes + 1] = {id = id, name = string.format(ns.L.RW_RECIPE,
            names[id] or string.format(ns.L.RB_UNNAMED, id), self:GetRecipeWatchlistCrafts(id))}
    end
    return scopes
end
function Addon:WatchlistIncludesGuildBank()
    return self.db.profile.watchlistIncludeGuildBank == true
end
function Addon:GetRecipeWatchlistView(scope)
    local general = self.db.profile.watchlist or {}
    if scope == nil or scope == "general" then
        return {items = general.items or {}, currencies = general.currencies or {},
            reagents = general.reagents or {}, includeGuildBank = self:WatchlistIncludesGuildBank()}
    end
    local view = {items = {}, currencies = {}, reagents = {}, includeGuildBank = self:WatchlistIncludesGuildBank()}
    local function Add(entries)
        for id, entry in pairs(entries or {}) do
            local target = type(entry) == "table" and tonumber(entry.target) or 0
            view.reagents[id] = view.reagents[id] or {target = 0}
            view.reagents[id].target = view.reagents[id].target + (target or 0)
        end
    end
    if scope == "all" then
        Add(general.reagents)
        for _, plan in pairs(Plans(self)) do Add(plan.reagents) end
    else
        local plan = self:GetRecipeWatchlist(scope)
        if plan then Add(plan.reagents) end
    end
    return view
end

-- Scale only this plan's explicit requirements; no live profession API is needed.
function Addon:SetRecipeWatchlistCrafts(recipeID, value)
    local crafts = ns.RecipeCraftCount(value)
    local plan = self:GetRecipeWatchlist(recipeID)
    local previous = plan and ns.RecipeCraftCount(plan.crafts)
    if not crafts or not previous then return false end
    local targets = {}
    for id, entry in pairs(plan.reagents) do
        if type(entry) ~= "table" or type(entry.target) ~= "number" then return false end
        local perCraft = entry.target / previous
        if perCraft <= 0 or perCraft ~= math.floor(perCraft) or perCraft == math.huge then return false end
        targets[id] = perCraft * crafts
    end
    for id, target in pairs(targets) do plan.reagents[id].target = target end
    plan.crafts = crafts
    self.recipeCraftCounts = self.recipeCraftCounts or {}
    self.recipeCraftCounts[recipeID] = crafts
    return true
end

-- Replace one recipe plan only after every alternative has an explicit selection.
function Addon:TrackAllRecipeIngredients(recipeID, snapshot, crafts, choices)
    crafts = ns.RecipeCraftCount(crafts)
    if not crafts or type(recipeID) ~= "number" or type(snapshot) ~= "table" or type(snapshot.slots) ~= "table" then return false end
    local targets = {}
    for index, row in ipairs(ns.RecipeMaterialRows(snapshot, crafts)) do
        local id = row.itemID
        if not id then
            local chosen = choices and choices[index]
            for _, candidate in ipairs(row.itemIDs) do if candidate == chosen then id = chosen; break end end
        end
        if not id or type(row.quantity) ~= "number" or row.quantity <= 0 or row.quantity ~= math.floor(row.quantity) or row.quantity == math.huge then return false end
        targets[id] = targets[id] or {target = 0}
        targets[id].target = targets[id].target + row.quantity
    end
    if not next(targets) then return false end
    self.db.profile.recipeWatchlists = self.db.profile.recipeWatchlists or {}
    self.db.profile.recipeWatchlists[recipeID] = {crafts = crafts, reagents = targets}
    self.recipeCraftCounts = self.recipeCraftCounts or {}
    self.recipeCraftCounts[recipeID] = crafts
    return true
end

-- An explicit row selection replaces its tracked alternatives, preserving other requirements.
function Addon:ReplaceTrackedRecipeVariant(recipeID, row, selected)
    local plan = self:GetRecipeWatchlist(recipeID)
    if not plan then return end
    local valid, tracked = false, false
    for _, id in ipairs(row.itemIDs) do
        if id == selected then valid = true end
        if plan.reagents[id] then tracked = true end
    end
    if not valid or not tracked then return end
    for _, id in ipairs(row.itemIDs) do plan.reagents[id] = nil end
    plan.reagents[selected] = {target = row.quantity}
end
