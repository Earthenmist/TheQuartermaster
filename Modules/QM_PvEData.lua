-- Time-aware read views preserve collected history without presenting it as current.
local _, ns = ...
local Addon = ns.TheQuartermaster
local function NumberFromAPI(fn)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    if type(value) == "number" and value >= 0 then return value end
end
local function Copy(source)
    local result = {}
    for k, v in pairs(source or {}) do result[k] = v end
    return result
end
function Addon:GetPvENow()
    return NumberFromAPI(GetServerTime) or time()
end
function Addon:GetWeeklyResetSeconds()
    return NumberFromAPI(C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset)
end
function Addon:GetPvESeason()
    return NumberFromAPI(C_MythicPlus and C_MythicPlus.GetCurrentSeason)
end
function Addon:GetPvEView(source)
    local view = Copy(source)
    local now = self:GetPvENow()
    local season = self:GetPvESeason()
    if source then
        if source.seasonID and season and source.seasonID ~= season then
            view.periodState = "season_changed"
        elseif source.weeklyResetAt and now >= source.weeklyResetAt then
            view.periodState = "previous_week"
        elseif not source.weeklyResetAt or not source.seasonID or not season then
            view.periodState = "unknown"
        end
    end
    if view.periodState then
        view.hasUnclaimedRewards = nil
        view.mythicPlus = Copy(view.mythicPlus)
        view.mythicPlus.keystone = nil
    end
    view.lockouts = {}
    for _, lockout in ipairs(source and source.lockouts or {}) do
        local expiry = lockout.expiresAt
        -- Only the PvE snapshot's own capture time can anchor legacy durations.
        local captured = source.capturedAt or source.lastScan
        if not expiry and captured and type(lockout.reset) == "number" then
            expiry = captured + lockout.reset
        end
        if not expiry or expiry > now then
            local entry = Copy(lockout)
            entry.expiresAt = expiry
            entry.remaining = expiry and math.max(0, expiry - now) or nil
            view.lockouts[#view.lockouts + 1] = entry
        end
    end
    return view
end
