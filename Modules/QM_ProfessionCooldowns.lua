local _, ns = ...
local Addon, W = ns.TheQuartermaster, ns.Wealth

function ns.ReadRecipeCooldown(id, detail, old)
    local values = W.Read(C_TradeSkillUI and C_TradeSkillUI.GetRecipeCooldown, id)
    if not values then return old end
    local remaining, daily, charges, cap = unpack(values)
    if remaining ~= nil and (not W.Number(remaining) or remaining < 0) then return old end
    if daily ~= nil and type(daily) ~= "boolean" then return old end
    if charges ~= nil and (not W.Number(charges) or charges < 0 or charges % 1 ~= 0) then return old end
    if cap ~= nil and (not W.Number(cap) or cap < 0 or cap % 1 ~= 0) then return old end
    if cap and cap > 0 and (not charges or charges > cap) then return old end
    -- Nil means no current cooldown, not evidence that an ordinary recipe has a cooldown.
    if not old and not (remaining and remaining > 0) and not (cap and cap > 0) then return nil end
    return {name=detail.name, expansion=detail.expansion, checked=time(),
        expires=remaining and remaining > 0 and time()+remaining or nil,
        daily=daily==true, charges=charges, maxCharges=cap}
end

function ns.RecipeCooldownState(row, now)
    if not row or not W.Public(row) or not W.Number(row.checked) or now < row.checked
        or now-row.checked > 7*86400 then return "stale" end
    if row.expires and (not W.Number(row.expires) or row.expires < row.checked) then return "stale" end
    if row.charges and row.charges > 0 then return now-row.checked <= 300 and "ready" or "estimated" end
    if row.expires and row.expires > now then return "cooling", math.ceil(row.expires-now) end
    return now-row.checked <= 300 and not row.expires and "ready" or "estimated"
end

function Addon:GetProfessionCooldownRows()
    local rows, counts = {}, {ready=0,estimated=0,cooling=0,stale=0}
    for key, char in pairs(self.db.global.characters or {}) do
        for professionID, snapshot in pairs(char.professionCooldowns or {}) do
            if snapshot.version == 1 then
                for recipeID, row in pairs(snapshot.rows or {}) do
                    local state, remaining = ns.RecipeCooldownState(row, time())
                    rows[#rows+1]={character=key,professionID=professionID,profession=snapshot.professionName,
                        recipeID=recipeID,data=row,state=state,remaining=remaining}
                    counts[state]=counts[state]+1
                end
            end
        end
    end
    local order={ready=1,estimated=2,cooling=3,stale=4}
    table.sort(rows,function(a,b)
        if a.state~=b.state then return order[a.state]<order[b.state] end
        if a.remaining~=b.remaining then return (a.remaining or 0)<(b.remaining or 0) end
        if a.character~=b.character then return a.character<b.character end
        return a.recipeID<b.recipeID
    end)
    return rows, counts
end
