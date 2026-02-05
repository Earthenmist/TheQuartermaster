--[[
    The Quartermaster - Constants
    Centralized constants and shared tables used across modules.
]]

local ADDON_NAME, ns = ...

-- Feature Flags
ns.ENABLE_GUILD_BANK = true -- Enable Guild Bank (view-only) caching & Items tab

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

