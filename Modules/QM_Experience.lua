-- Shared read-only classification for Experience rows and account summaries.
local _, ns = ...
function ns.GetExperienceLevelCap()
    if type(GetMaxPlayerLevel) ~= "function" then return nil end
    local ok, cap = pcall(GetMaxPlayerLevel)
    if not ok or (issecretvalue and issecretvalue(cap)) then return nil end
    if type(cap) == "number" and cap > 0 then return cap end
end
function ns.IsCharacterMaxLevel(char, cap)
    if not char then return false end
    -- The current cap overrides stale negative flags and placeholder XP values.
    local level = tonumber(char.level) or 0
    if cap and level >= cap then return true end
    -- Keep explicit effective-cap observations when the client advertises a future cap.
    return char.isMaxLevel == true
end
function ns.GetExperienceSummary(characters)
    local cap, maxCount, restedCount = ns.GetExperienceLevelCap(), 0, 0
    for _, char in pairs(characters or {}) do
        if ns.IsCharacterMaxLevel(char, cap) then
            maxCount = maxCount + 1
        else
            local rested = tonumber(char.restXP or char.restXp or char.restedXP or char.restedXp)
            local maximum = tonumber(char.maxXP or char.maxXp or char.xpMax or char.xpmax)
            if maximum and maximum > 0 and rested and rested >= math.floor(maximum * 1.5 + 0.5) - 1 then
                restedCount = restedCount + 1
            end
        end
    end
    return maxCount, restedCount
end
