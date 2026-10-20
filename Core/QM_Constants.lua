--[[
    The Quartermaster - Constants
    Centralized constants and shared tables used across modules.
]]

local ADDON_NAME, ns = ...

-- Feature Flags
ns.ENABLE_GUILD_BANK = true -- Enable Guild Bank (view-only) caching & Items tab

-- Personal travel tools do not benefit from cross-character ownership tooltips.
ns.TOOLTIP_QUANTITY_EXCLUSIONS = {
    [6948] = true, -- Hearthstone
    [110560] = true, -- Garrison Hearthstone
    [140192] = true, -- Dalaran Hearthstone
    [141605] = true, -- Flight Master's Whistle
}

-- Warband tab count (Account Bank tabs)
ns.WARBAND_TAB_COUNT = 5

-- Warband Bank Bag IDs (13-17, NOT 12!)
ns.WARBAND_BAGS = {
    Enum.BagIndex.AccountBankTab_1 or 13,
    Enum.BagIndex.AccountBankTab_2 or 14,
    Enum.BagIndex.AccountBankTab_3 or 15,
    Enum.BagIndex.AccountBankTab_4 or 16,
    Enum.BagIndex.AccountBankTab_5 or 17,
}

-- Personal Bank Bag IDs
local personalBankBags = {}

-- Bank bag slots (6-11 in TWW, bag 12 is Warband now!)
for i = 1, (NUM_BANKBAGSLOTS or 7) do
    local bagEnum = Enum.BagIndex["BankBag_" .. i]
    if bagEnum then
        -- Skip bag 12 - it's now Warband's first tab in TWW!
        if bagEnum ~= 12 and bagEnum ~= Enum.BagIndex.AccountBankTab_1 then
            table.insert(personalBankBags, bagEnum)
        end
    end
end

-- Fallback: if enums didn't work, use numeric IDs (6-11, NOT 12!)
-- Note: We intentionally do NOT include the main bank container (-1) here.
-- TheQuartermaster is view-only and already displays bank bag tabs correctly; including -1
-- can produce an empty "Bank" tab on some clients.
if #personalBankBags == 0 then
    personalBankBags = { 6, 7, 8, 9, 10, 11 }
end

ns.PERSONAL_BANK_BAGS = personalBankBags

-- Item Categories for grouping
ns.ITEM_CATEGORIES = {
    WEAPON = 1,
    ARMOR = 2,
    CONSUMABLE = 3,
    TRADEGOODS = 4, -- Materials
    RECIPE = 5,
    GEM = 6,
    MISCELLANEOUS = 7,
    QUEST = 8,
    CONTAINER = 9,
    OTHER = 10,
}
-- Inventory (player bags)
-- Bag IDs: 0=Backpack, 1-4=equipped bags, 5=Reagent bag (if present)
ns.INVENTORY_BAGS = { 0, 1, 2, 3, 4, 5 }

ns.INVENTORY_BAG_LABELS = {
    [0]  = "Backpack",
    [1]  = "Bag 1",
    [2]  = "Bag 2",
    [3]  = "Bag 3",
    [4]  = "Bag 4",
    [5]  = "Reagent",
}


-- Expansion menus use release order; cached profession regions share that order.
local expansionAliases = {
    [0]={"Classic","Vanilla","Eastern Kingdoms","Kalimdor"},
    [1]={"The Burning Crusade","Burning Crusade","Outland"},
    [2]={"Wrath of the Lich King","Northrend"},
    [3]={"Cataclysm"}, [4]={"Mists of Pandaria","Pandaria"},
    [5]={"Warlords of Draenor","Draenor"}, [6]={"Legion","Broken Isles"},
    [7]={"Battle for Azeroth","Kul Tiras","Kul Tiran","Zandalar","Zandalari"},
    [8]={"Shadowlands"}, [9]={"Dragonflight","Dragon Isles"},
    [10]={"The War Within","TWW","Khaz Algar","Algari"}, [11]={"Midnight"},
}
local expansionRanks={}
for rank,names in pairs(expansionAliases) do for _,name in ipairs(names) do expansionRanks[name:lower()]=rank end end
function ns.ExpansionReleaseRank(name)
    if type(name)~="string" then return -1 end
    -- Client-localized expansion labels also support newly introduced expansions.
    for rank=0,30 do if _G["EXPANSION_NAME"..rank]==name then return rank end end
    return expansionRanks[name:lower()] or -1
end
function ns.ExpansionNewestFirst(a,b)
    local ar,br=ns.ExpansionReleaseRank(a),ns.ExpansionReleaseRank(b)
    if ar~=br then return ar>br end
    return a<b
end
