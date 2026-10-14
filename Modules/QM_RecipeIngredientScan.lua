-- One bounded, owner-scoped ingredient pass per verified recipe list/open context.
local _, ns = ...
local Addon = ns.TheQuartermaster
local BATCH_SIZE = 5

local function Context(addon)
    if not (addon.db and addon.db.profile and addon.db.profile.trackProfessionRecipes)
        or (InCombatLockdown and InCombatLockdown()) then return nil end
    local ok, context = pcall(ns.GetOwnedRecipeContext, addon)
    if ok then return context end
end
local function Entry(addon, context)
    local char = addon.db and addon.db.global and addon.db.global.characters[context.key]
    return char and char.professionRecipes and char.professionRecipes[context.id]
end
local function Notify(addon, job, redraw)
    addon.recipeIngredientScanStatus = {state = job.state, name = job.entry.professionName or tostring(job.context.id),
        checked = job.checked, total = #job.ids, refreshed = job.refreshed, cached = job.cached or 0}
    if addon.UpdateRecipeIngredientScanUI then addon:UpdateRecipeIngredientScanUI(redraw) end
end
function Addon:StopRecipeIngredientScan()
    local job = self.recipeIngredientJob
    self.recipeIngredientJob = nil
    if job then
        if job.timer then job.timer:Cancel(); job.timer = nil end
        job.state = "interrupted"
        Notify(self, job, true)
    end
end
function Addon:OnRecipeProfessionClosed()
    self:StopRecipeIngredientScan()
    self.recipeIngredientLastPass = nil
    self._qmRecipeRetryPending = nil
    self._qmRecipeScanContext = nil
end

function Addon:StartRecipeIngredientScan(expected)
    local context = Context(self)
    if not ns.SameRecipeContext(context, expected) then self:StopRecipeIngredientScan(); return end
    local entry = Entry(self, context)
    if not entry or not entry.ownerVerified or type(entry.recipes) ~= "table" or #entry.recipes == 0 then return end
    local existing = self.recipeIngredientJob or self.recipeIngredientLastPass
    if existing and ns.SameRecipeContext(existing.context, context) and existing.entry == entry
        and existing.ids == entry.recipes then return end
    self:StopRecipeIngredientScan()
    if not (C_Timer and C_Timer.NewTimer) then return end
    local job = {context = context, entry = entry, ids = entry.recipes, index = 1,
        failures = {}, checked = 0, refreshed = 0, state = "running"}
    self.recipeIngredientJob = job
    Notify(self, job, true)
    local function Valid()
        return self.recipeIngredientJob == job and ns.SameRecipeContext(Context(self), job.context)
            and Entry(self, job.context) == job.entry and job.entry.recipes == job.ids
    end
    local function Step()
        job.timer = nil
        if self.recipeIngredientJob ~= job then return end
        if not Valid() then self:StopRecipeIngredientScan(); return end
        local started = debugprofilestop and debugprofilestop()
        for _ = 1, BATCH_SIZE do
            local list = job.retrying and job.failures or job.ids
            local id = list[job.index]
            if not id then
                if not job.retrying and #job.failures > 0 then
                    job.retrying, job.index, job.state = true, 1, "retrying"
                    break
                end
                job.cached = 0
                for _, recipeID in ipairs(job.ids) do
                    local snapshot = entry.ingredients and entry.ingredients[recipeID]
                    if snapshot and snapshot.version == 1 then job.cached = job.cached + 1 end
                end
                job.state = "complete"
                self.recipeIngredientJob = nil
                self.recipeIngredientLastPass = {context = job.context, entry = entry, ids = job.ids}
                Notify(self, job, true)
                return
            end
            -- Revalidate before and after every recipe; the collector repeats its own guards.
            if not Valid() then self:StopRecipeIngredientScan(); return end
            local ok = self:CollectRecipeIngredients(id)
            if not Valid() then self:StopRecipeIngredientScan(); return end
            if ok then job.refreshed = job.refreshed + 1
            elseif not job.retrying then job.failures[#job.failures + 1] = id end
            if not job.retrying then job.checked = job.checked + 1 end
            job.index = job.index + 1
            if started and debugprofilestop() - started >= 5 then break end
        end
        Notify(self, job, false)
        job.timer = C_Timer.NewTimer(0.05, Step)
    end
    job.timer = C_Timer.NewTimer(0.05, Step)
end
