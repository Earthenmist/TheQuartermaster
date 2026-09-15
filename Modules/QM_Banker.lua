--[[
    The Quartermaster - Banker Module
    Handles gold and item deposit operations
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster
local L = ns.L

-- Money formatting helper (respects Discretion Mode and avoids load-order issues)
local function FormatMoney(amount)
    local addon = ns and ns.TheQuartermaster
    if addon and addon.db and addon.db.profile and addon.db.profile.discretionMode then
        return "|cff9aa0a6Hidden|r"
    end

    local fn = ns and ns.UI_FormatGold
    if type(fn) == "function" then
        return fn(amount)
    end
    if type(GetCoinTextureString) == "function" then
        return GetCoinTextureString(tonumber(amount) or 0)
    end
    return tostring(tonumber(amount) or 0)
end

function TheQuartermaster:GetWarbandBankMoney()
    if C_Bank and C_Bank.FetchDepositedMoney then
        return C_Bank.FetchDepositedMoney(Enum.BankType.Account) or 0
    end
    return 0
end

-- Guild bank gold is cached during Guild Bank scans. This is display-only and is
-- NOT included in any overall totals.
function TheQuartermaster:GetCachedGuildBankMoney()
    if not IsInGuild() then return 0 end

    local guildName = GetGuildInfo("player")
    if not guildName then return 0 end

    local gb = self.db and self.db.global and self.db.global.guildBank
    local g = gb and gb[guildName]
    return (g and g.money) or 0
end

