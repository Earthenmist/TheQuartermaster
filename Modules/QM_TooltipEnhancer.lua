--[[
    The Quartermaster - Tooltip Enhancer Module
    Adds item location information to GameTooltip
    
    Features:
    - Shows Warband Bank quantity and locations
    - Shows Personal Bank quantities per character
    - Click hint to locate item
    - Cached for performance
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

-- Cache for tooltip data (avoid scanning on every hover)
local tooltipCache = {}
local CACHE_DURATION = 2 -- seconds

-- ============================================================================
-- TOOLTIP SCANNING
-- ============================================================================

--[[
    Scan for item locations across all banks
    @param itemID number - Item ID to search for
    @return table - Location data
]]
local function ScanItemLocations(itemID)
    if not itemID or itemID == 0 then
        return nil
    end

    -- Check cache first
    local now = time()
    if tooltipCache[itemID] and (now - tooltipCache[itemID].timestamp) < CACHE_DURATION then
        return tooltipCache[itemID].data
    end

    local data = {
        warband = 0,
        characters = {}, -- [charKey] = { name, realm, classFile, bags, bank, total }
    }

    -- Warband Bank
    if TheQuartermaster.db and TheQuartermaster.db.global
        and TheQuartermaster.db.global.warbandBank
        and TheQuartermaster.db.global.warbandBank.items
    then
        for _, bagData in pairs(TheQuartermaster.db.global.warbandBank.items) do
            for _, item in pairs(bagData) do
                if item and item.itemID == itemID then
                    data.warband = data.warband + (item.stackCount or 1)
                end
            end
        end
    end

    -- Character inventories + personal banks (all characters)
    if TheQuartermaster.db and TheQuartermaster.db.global and TheQuartermaster.db.global.characters then
        for charKey, charData in pairs(TheQuartermaster.db.global.characters) do
            if type(charData) == "table" then
                local name = charData.name or (charKey:match("^([^-]+)")) or charKey
                local realm = charData.realm or (charKey:match("^[^-]+%-(.+)$")) or ""
                local classFile = charData.classFile or charData.class -- prefer classFile like "PALADIN"

                local bags = 0
                local bank = 0

                -- Inventory (bags)
                if charData.inventory and charData.inventory.items then
                    for _, bagData in pairs(charData.inventory.items) do
                        for _, item in pairs(bagData) do
                            if item and item.itemID == itemID then
                                bags = bags + (item.stackCount or 1)
                            end
                        end
                    end
                end

                -- Personal Bank
                if charData.personalBank then
                    for _, bagData in pairs(charData.personalBank) do
                        for _, item in pairs(bagData) do
                            if item and item.itemID == itemID then
                                bank = bank + (item.stackCount or 1)
                            end
                        end
                    end
                end

                if bags > 0 or bank > 0 then
                    data.characters[charKey] = {
                        name = name,
                        realm = realm,
                        classFile = classFile,
                        bags = bags,
                        bank = bank,
                        total = bags + bank,
                    }
                end
            end
        end
    end

    -- Cache result
    tooltipCache[itemID] = {
        data = data,
        timestamp = now,
    }

    return data
end

--[[
    Clear tooltip cache
    Called when bank data changes
]]
function TheQuartermaster:ClearTooltipCache()
    tooltipCache = {}
end

-- ============================================================================
-- TOOLTIP HOOK
-- ============================================================================

--[[
    Add item location info to tooltip
    @param tooltip frame - Tooltip frame
    @param itemLink string - Item link
]]
local function AddItemLocationInfo(tooltip, itemLink)
    if not tooltip or not itemLink then
        return
    end

    -- Check if addon is enabled and tooltip enhancement is enabled
    if not TheQuartermaster.db or not TheQuartermaster.db.profile.enabled then
        return
    end

    if not TheQuartermaster.db.profile.tooltipEnhancement then
        return
    end

    local function ColorizeName(name, classFile)
        if RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile] then
            local c = RAID_CLASS_COLORS[classFile]
            return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name)
        end
        return name
    end

    -- Extract item ID from link
    local itemID = tonumber(itemLink:match("item:(%d+)"))
    if not itemID then
        return
    end

    -- Scan for locations
    local locations = ScanItemLocations(itemID)
    if not locations then
        return
    end

    local charList = {}
    if locations.characters then
        for _, info in pairs(locations.characters) do
            local total = (info.bags or 0) + (info.bank or 0)
            if total > 0 then
                table.insert(charList, {
                    name = info.name,
                    realm = info.realm,
                    classFile = info.classFile,
                    bags = info.bags or 0,
                    bank = info.bank or 0,
                    total = total,
                })
            end
        end
    end

    local hasAny = (#charList > 0) or ((locations.warband or 0) > 0)
    if not hasAny then
        return
    end

    -- Sort by total desc, then name
    table.sort(charList, function(a, b)
        if (a.total or 0) == (b.total or 0) then
            return (a.name or "") < (b.name or "")
        end
        return (a.total or 0) > (b.total or 0)
    end)

    tooltip:AddLine(" ")

    local totalOwned = locations.warband or 0
    for _, info in ipairs(charList) do
        local realmText = (info.realm and info.realm ~= "") and (" (" .. info.realm .. ")") or ""
        local left = ColorizeName((info.name or "Unknown") .. realmText, info.classFile)

        local breakdown = {}
        if info.bags and info.bags > 0 then
            table.insert(breakdown, "Bags: " .. info.bags)
        end
        if info.bank and info.bank > 0 then
            table.insert(breakdown, "Bank: " .. info.bank)
        end

        local right = tostring(info.total or 0)
        if #breakdown > 0 then
            right = right .. " (" .. table.concat(breakdown, ", ") .. ")"
        end

        tooltip:AddDoubleLine(left, right, 0.75, 0.75, 0.75, 1, 1, 1)
        totalOwned = totalOwned + (info.total or 0)
    end

    if (locations.warband or 0) > 0 then
        tooltip:AddDoubleLine("Warband Bank", tostring(locations.warband), 0.75, 0.75, 0.75, 1, 1, 1)
    end

    tooltip:AddLine("|cff999999-------------------------------|r")
    tooltip:AddLine("Total owned: " .. totalOwned, 1, 1, 1)
end

local function OnTooltipSetItem(tooltip)
    if not tooltip then return end
    
    -- Safety check: Ensure tooltip has GetItem method (some tooltips don't)
    if not tooltip.GetItem then return end
    
    -- Get item link
    local _, itemLink = tooltip:GetItem()
    if not itemLink then return end
    
    -- Add our info
    AddItemLocationInfo(tooltip, itemLink)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

--[[
    Initialize tooltip hooks
    Called during OnEnable
    
    TWW (11.x+): Uses TooltipDataProcessor API
    Legacy (10.x-): Uses OnTooltipSetItem hook
]]
function TheQuartermaster:InitializeTooltipEnhancer()
    -- TWW (11.x+): Use new TooltipDataProcessor API
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        -- Register for item tooltips
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            OnTooltipSetItem(tooltip)
        end)
    else
        -- Legacy (pre-11.x): Use OnTooltipSetItem hook
        -- Hook GameTooltip
        if GameTooltip and GameTooltip.HookScript then
            pcall(function()
                GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
            end)
        end
        
        -- Hook ItemRefTooltip (for chat links)
        if ItemRefTooltip and ItemRefTooltip.HookScript then
            pcall(function()
                ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
            end)
        end
        
        -- Hook shopping tooltips (comparison)
        if ShoppingTooltip1 and ShoppingTooltip1.HookScript then
            pcall(function()
                ShoppingTooltip1:HookScript("OnTooltipSetItem", OnTooltipSetItem)
            end)
        end
        if ShoppingTooltip2 and ShoppingTooltip2.HookScript then
            pcall(function()
                ShoppingTooltip2:HookScript("OnTooltipSetItem", OnTooltipSetItem)
            end)
        end
    end
end

-- ============================================================================
-- SHIFT+CLICK HANDLER (SAFE IMPLEMENTATION)
-- ============================================================================

--[[
    Handle Shift+Click on items to search in addon
    SAFE: Hooks chat frame hyperlinks instead of protected SetItemRef
]]
local function HandleChatHyperlinkEnter(chatFrame, link, text)
    -- Only handle if Shift is down
    if not IsShiftKeyDown() then
        return
    end
    
    -- Only handle item links
    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID then
        return
    end
    
    -- Safety: Don't do anything in combat
    if InCombatLockdown() then
        return
    end
    
    -- Get item name (async-safe)
    local itemName = C_Item.GetItemNameByID(itemID)
    if not itemName then
        -- Fallback: try GetItemInfo
        itemName = GetItemInfo(itemID)
        if not itemName then
            return
        end
    end
    
    -- Open addon and search for item
    if TheQuartermaster.ShowMainWindow then
        TheQuartermaster:ShowMainWindow()
    end
    
    -- Switch to Items tab and search
    if TheQuartermaster.mainFrame then
        TheQuartermaster.mainFrame.currentTab = "items"
        if ns.itemsSearchText ~= nil then
            ns.itemsSearchText = itemName:lower()
        end
        if TheQuartermaster.PopulateContent then
            TheQuartermaster:PopulateContent()
        end
        
        TheQuartermaster:Print(string.format("Searching for: %s", itemName))
    end
end

--[[
    Hook chat frame hyperlink handlers (SAFE approach)
    Called during OnEnable
]]
function TheQuartermaster:InitializeTooltipClickHandler()
    -- Removed: we no longer auto-open/search the addon when Shift is held over
    -- item hyperlinks (previously used for the old "Show click hint" option).
    return
end

-- ============================================================================
-- AUTO CACHE INVALIDATION
-- ============================================================================

-- Clear tooltip cache when bank data changes
-- This is called from Core.lua after bank scans
function TheQuartermaster:InvalidateTooltipCache()
    tooltipCache = {}
end
