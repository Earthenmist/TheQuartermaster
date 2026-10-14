--[[
    The Quartermaster - Shared UI Widgets & Helpers
    Common UI components and utility functions used across all tabs
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

--============================================================================
-- COLOR CONSTANTS
--============================================================================

-- Compatibility exports use the same fixed palette as the shell.
local CalculateThemeColors = ns.Theme.GetColors
local GetThemeColors = ns.Theme.GetColors
local GetColors = ns.Theme.GetColors

-- Create initial COLORS table
local COLORS = GetColors()

-- Refresh COLORS table from database
local function RefreshColors()
    if TheQuartermaster.db.profile.debugMode then
        print("=== RefreshColors CALLED ===")
    end
    
    -- Immediate update
    local newColors = GetColors()
    for k, v in pairs(newColors) do
        COLORS[k] = v
    end
    -- Also update the namespace reference
    ns.UI_COLORS = COLORS
    
    if TheQuartermaster.db.profile.debugMode then
        print(string.format("New accent color: R=%.2f, G=%.2f, B=%.2f", COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]))
    end
    
    -- Update main frame border and header if it exists
    if TheQuartermaster and TheQuartermaster.UI and TheQuartermaster.UI.mainFrame then
        local f = TheQuartermaster.UI.mainFrame
        local accentColor = COLORS.accent
        local borderColor = COLORS.border
        
        -- Calculate hex color inline
        local accentHex = string.format("%02x%02x%02x", accentColor[1] * 255, accentColor[2] * 255, accentColor[3] * 255)
        
        if TheQuartermaster.db.profile.debugMode then
            print(string.format("Accent hex: %s", accentHex))
            print(string.format("mainFrame exists: %s", tostring(f ~= nil)))
        end
        
        -- Note: Title stays white (not theme-colored)
        
        -- Update main frame border using COLORS.border
        if f.SetBackdropBorderColor then
            f:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        end
        
        -- Update header background
        if f.header and f.header.SetBackdropColor then
            f.header:SetBackdropColor(COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], COLORS.accentDark[4] or 1)
        end

	    -- Keep the Discretion Mode label readable against dynamic header colours
	    if f.ApplyDiscretionLabelColor then
	        pcall(f.ApplyDiscretionLabelColor)
	    elseif f.discretionLabel and f.discretionLabel.SetTextColor then
	        -- Fallback: inline auto-contrast if older frames don't have the helper
	        local br, bg, bb = COLORS.accentDark[1] or 0.2, COLORS.accentDark[2] or 0.2, COLORS.accentDark[3] or 0.2
	        local brightness = (br * 299 + bg * 587 + bb * 114) / 1000
	        if brightness > 0.6 then
	            f.discretionLabel:SetTextColor(0.1, 0.1, 0.1, 0.95)
	        else
	            f.discretionLabel:SetTextColor(1, 1, 1, 0.95)
	        end
	    end
        
        -- Update content area border
        if f.content and f.content.SetBackdropBorderColor then
            f.content:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        end
        
        -- Update footer buttons (Scan, Sort, Classic Bank)
        if f.scanBtn and f.scanBtn.SetBackdropBorderColor then
            f.scanBtn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.5)
        end
        if f.sortBtn and f.sortBtn.SetBackdropBorderColor then
            f.sortBtn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.5)
        end
        if f.classicBtn and f.classicBtn.SetBackdropBorderColor then
            f.classicBtn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.5)
        end
        
        -- Update main tab buttons (activeBar highlight)
        if f.tabButtons then
            local accentColor = COLORS.accent
            local tabActiveColor = COLORS.tabActive
            local tabInactiveColor = COLORS.tabInactive
            local tabHoverColor = COLORS.tabHover
            
            for tabKey, btn in pairs(f.tabButtons) do
                local isActive = f.currentTab == tabKey
                
                -- Update background color
                if isActive then
                    btn:SetBackdropColor(tabActiveColor[1], tabActiveColor[2], tabActiveColor[3], 1)
                    btn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
                else
                    btn:SetBackdropColor(tabInactiveColor[1], tabInactiveColor[2], tabInactiveColor[3], 1)
                    btn:SetBackdropBorderColor(tabInactiveColor[1] * 1.5, tabInactiveColor[2] * 1.5, tabInactiveColor[3] * 1.5, 0.5)
                end
                
                -- Update activeBar (bottom highlight line)
                if btn.activeBar then
                    btn.activeBar:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
                end
                
                -- Update glow
                if btn.glow then
                    btn.glow:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], isActive and 0.25 or 0.15)
                end
            end
        end
        
        -- Update search bar borders
        if f.persistentSearchBoxes then
            for _, searchBox in pairs(f.persistentSearchBoxes) do
                if searchBox and searchBox.searchFrame then
                    local borderColor = COLORS.accent
                    searchBox.searchFrame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.5)
                end
            end
        end
        
        -- Refresh content to update dynamic elements (without infinite loop)
        if f:IsShown() and TheQuartermaster.RefreshUI then
            if TheQuartermaster.db.profile.debugMode then
                print("Calling RefreshUI to update content")
            end
            TheQuartermaster:RefreshUI()
        end
        
        if TheQuartermaster.db.profile.debugMode then
            print("=== RefreshColors COMPLETE ===")
        end
    else
        if TheQuartermaster.db.profile.debugMode then
            print("ERROR: mainFrame not found!")
            print(string.format("TheQuartermaster exists: %s", tostring(TheQuartermaster ~= nil)))
            print(string.format("TheQuartermaster.UI exists: %s", tostring(TheQuartermaster and TheQuartermaster.UI ~= nil)))
        end
    end
end

-- Quality colors (hex)
local QUALITY_COLORS = {
    [0] = "9d9d9d", -- Poor (Gray)
    [1] = "ffffff", -- Common (White)
    [2] = "1eff00", -- Uncommon (Green)
    [3] = "0070dd", -- Rare (Blue)
    [4] = "a335ee", -- Epic (Purple)
    [5] = "ff8000", -- Legendary (Orange)
    [6] = "e6cc80", -- Artifact (Gold)
    [7] = "00ccff", -- Heirloom (Cyan)
}

-- Export to namespace
ns.UI_COLORS = COLORS
ns.UI_QUALITY_COLORS = QUALITY_COLORS

--============================================================================
-- LAYOUT CONSTANTS (Unified spacing across all tabs)
--============================================================================

local UI_LAYOUT = {
    ROW_HEIGHT = 26,
    ROW_SPACING = 28,      -- Space between item/currency rows
    HEADER_SPACING = 38,   -- Space after headers (character, expansion, category)
    SECTION_SPACING = 15,  -- Space between major sections (character headers) - reduced from 25
    -- Indent constants for hierarchical content
    CHAR_INDENT = 20,      -- Indent for content under character header
    EXPANSION_INDENT = 20, -- Additional indent for expansion content
    CATEGORY_INDENT = 20,  -- Additional indent for category content
}

-- Export to namespace
ns.UI_LAYOUT = UI_LAYOUT

--============================================================================
-- FRAME POOLING SYSTEM (Performance Optimization)
--============================================================================
-- Reuse frames instead of creating new ones on every refresh
-- This dramatically reduces memory churn and GC pressure

local ItemRowPool = {}
local StorageRowPool = {}
local CurrencyRowPool = {}

-- Get a currency row from pool or create new
local function AcquireCurrencyRow(parent, width, rowHeight)
    local row = table.remove(CurrencyRowPool)
    if row then row._qmInRowPool = nil end
    
    if not row then
        -- Create new button with all children
        row = CreateFrame("Button", nil, parent, "BackdropTemplate")
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        -- Background
        row:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
        })
        
        -- Icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 15, 0)
        
        -- Name text
        row.nameText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
        row.nameText:SetPoint("LEFT", 43, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        
        -- Amount text
        row.amountText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
        row.amountText:SetPoint("RIGHT", -10, 0)
        row.amountText:SetWidth(150)
        row.amountText:SetJustifyH("RIGHT")
        
        row.isPooled = true
        row.rowType = "currency"  -- Mark as CurrencyRow
    end
    
    -- CRITICAL: Always set parent when acquiring from pool
    row:SetParent(parent)
    row:SetSize(width, rowHeight or 26)
    row:SetFrameLevel(parent:GetFrameLevel() + 1)  -- Ensure proper z-order
    row:Show()
    return row
end

-- Return currency row to pool
local function ReleaseCurrencyRow(row)
    if not row or not row.isPooled or row._qmInRowPool then return end
    row._qmInRowPool = true
    
    row:Hide()
    row:ClearAllPoints()
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row:SetScript("OnClick", nil)
    
    -- Reset icon
    if row.icon then
        row.icon:SetTexture(nil)
        row.icon:SetAlpha(1)
    end
    
    -- Reset texts
    if row.nameText then
        row.nameText:SetText("")
        row.nameText:SetTextColor(1, 1, 1)
    end
    
    if row.amountText then
        row.amountText:SetText("")
        row.amountText:SetTextColor(1, 1, 1)
    end
    
    -- Reset background
    row:SetBackdropColor(0, 0, 0, 0)
    
    table.insert(CurrencyRowPool, row)
end

-- Get an item row from pool or create new
local function AcquireItemRow(parent, width, rowHeight)
    local row = table.remove(ItemRowPool)
    if row then row._qmInRowPool = nil end
    
    if not row then
        -- Create new button with all children
        row = CreateFrame("Button", nil, parent)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        -- Background texture
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        
        -- Quantity text (left)
        row.qtyText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
        row.qtyText:SetPoint("LEFT", 15, 0)
        row.qtyText:SetWidth(45)
        row.qtyText:SetJustifyH("RIGHT")
        
        -- Icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 70, 0)
        
        -- Name text
        row.nameText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
        row.nameText:SetPoint("LEFT", 98, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        
        -- Item level text (optional)
        row.ilvlText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
        row.ilvlText:SetPoint("RIGHT", -78, 0)
        row.ilvlText:SetWidth(50)
        row.ilvlText:SetJustifyH("RIGHT")

        -- Location text
        row.locationText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
        row.locationText:SetPoint("RIGHT", -10, 0)
        row.locationText:SetWidth(60)
        row.locationText:SetJustifyH("RIGHT")

        row.isPooled = true
        row.rowType = "item"  -- Mark as ItemRow
    end

    row:SetParent(parent)
    row:SetSize(width, rowHeight)
    row:SetFrameLevel(parent:GetFrameLevel() + 1)  -- Ensure proper z-order

    -- Reset pooled values so other tabs don't inherit stale data
    if row.ilvlText then row.ilvlText:SetText("") end
    row:Show()
    return row
end

-- Return item row to pool
local function ReleaseItemRow(row)
    if not row or not row.isPooled or row._qmInRowPool then return end
    row._qmInRowPool = true
    
    row:Hide()
    row:ClearAllPoints()
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    
    table.insert(ItemRowPool, row)
end

-- Get storage row from pool (updated to match Items tab style)
local function AcquireStorageRow(parent, width, rowHeight)
    local row = table.remove(StorageRowPool)
    if row then row._qmInRowPool = nil end
    
    if not row then
        -- Create new button with all children (Button for hover effects)
        row = CreateFrame("Button", nil, parent)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        -- Background texture
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(0.05, 0.05, 0.07, 1)
        
        -- Quantity text (left)
        row.qtyText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
        row.qtyText:SetPoint("LEFT", 15, 0)
        row.qtyText:SetWidth(45)
        row.qtyText:SetJustifyH("RIGHT")
        
        -- Icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 70, 0)
        
        -- Name text
        row.nameText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
        row.nameText:SetPoint("LEFT", 98, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        
        -- Location text
        row.locationText = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
        row.locationText:SetPoint("RIGHT", -10, 0)
        row.locationText:SetWidth(60)
        row.locationText:SetJustifyH("RIGHT")
        
        row.isPooled = true
        row.rowType = "storage"  -- Mark as StorageRow
    end
    
    row:SetParent(parent)
    row:SetSize(width, rowHeight or 26)
    row:SetFrameLevel(parent:GetFrameLevel() + 1)  -- Ensure proper z-order
    row:Show()
    return row
end

-- Return storage row to pool
local function ReleaseStorageRow(row)
    if not row or not row.isPooled or row._qmInRowPool then return end
    row._qmInRowPool = true
    
    row:Hide()
    row:ClearAllPoints()
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row:SetScript("OnClick", nil)
    
    table.insert(StorageRowPool, row)
end

-- Release all pooled children of a frame (and hide non-pooled ones)
local function ReleaseAllPooledChildren(parent)
    for _, child in pairs({parent:GetChildren()}) do
        if child.isPooled and child.rowType then
            -- Use rowType to determine which pool to release to
            if child.rowType == "item" then
                ReleaseItemRow(child)
            elseif child.rowType == "storage" then
                ReleaseStorageRow(child)
            elseif child.rowType == "currency" then
                ReleaseCurrencyRow(child)
            end
        else
            -- Non-pooled frame (like headers) - just hide and clear
            -- Use pcall to safely handle frames that don't support scripts
            pcall(function()
                child:Hide()
                child:ClearAllPoints()
            end)
            
            -- Only set scripts if the frame type supports it (Button, Frame, etc.)
            if child.SetScript and child.GetScript then
                pcall(function()
                    child:SetScript("OnClick", nil)
                    child:SetScript("OnEnter", nil)
                    child:SetScript("OnLeave", nil)
                end)
            end
        end
    end
end

--============================================================================
-- UI HELPER FUNCTIONS
--============================================================================

-- Get quality color as hex string
local function GetQualityHex(quality)
    return QUALITY_COLORS[quality] or "ffffff"
end

-- Get accent color as hex string
local function GetAccentHexColor()
    local c = COLORS.accent
    return string.format("%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

-- Create a card frame (common UI element)
local function CreateCard(parent, height)
    local card = ns.UI_RenderFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetHeight(height or 100)
    card:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 2,
    })
    card:SetBackdropColor(unpack(COLORS.bgCard))
    -- Use theme accent color for title card borders
    card:SetBackdropBorderColor(unpack(COLORS.border))
    return card
end

-- Format money with consistent Gold/Silver/Copper display.
-- NOTE: WoW's base unit is copper. The user-facing label sometimes says "bronze" in modern UI,
-- but the underlying unit remains copper.
local function FormatGold(copper)
    -- Discretion mode: hide all gold amounts everywhere this formatter is used.
    local addon = ns.TheQuartermaster
    if addon and addon.db and addon.db.profile and addon.db.profile.discretionMode then
        return "|cff9aa0a6Hidden|r"
    end

    local total = tonumber(copper) or 0
    if total < 0 then total = 0 end

    local gold = math.floor(total / 10000)
    local silver = math.floor((total % 10000) / 100)
    local copperAmt = total % 100

    local goldStr
    if type(BreakUpLargeNumbers) == "function" then
        goldStr = BreakUpLargeNumbers(gold)
    else
        goldStr = tostring(gold)
    end

    -- Always show all units for consistency.
    return string.format(
        "%s|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t %02d|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t %02d|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t",
        goldStr,
        silver,
        copperAmt
    )
end

--============================================================================
-- CHARACTER DISPLAY HELPERS
--============================================================================

-- Returns a consistent "Name-Realm" label where:
--  - Name is class-colored (if classFile provided)
--  - Realm is gray
--
-- Accepts either:
--   FormatCharacterNameRealm(name, realm, classFile)
--   FormatCharacterNameRealm(name, realm, {r=,g=,b=})
local function FormatCharacterNameRealm(name, realm, class)
    local n = name or "Unknown"
    local rlm = realm or "Unknown"

    local color
    if type(class) == "table" then
        color = class
    elseif type(class) == "string" and RAID_CLASS_COLORS then
        color = RAID_CLASS_COLORS[class]
    end
    if not color then
        color = { r = 1, g = 1, b = 1 }
    end

    return string.format("|cff%02x%02x%02x%s|r|cff808080-%s|r",
        (color.r or 1) * 255,
        (color.g or 1) * 255,
        (color.b or 1) * 255,
        n,
        rlm)
end

-- Create collapsible header; opt-in render owners reuse its frame and regions.
local function CreateCollapsibleHeader(parent, text, key, isExpanded, onToggle, iconTexture)
    -- Other screens keep their existing allocation path.
    local header = ns.UI_RenderFrame("Button", nil, parent, "BackdropTemplate")
    header:SetSize(parent:GetWidth() - 20, 32)
    header:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 2,
    })
    header:SetBackdropColor(unpack(COLORS.bgCard))
    local headerBorder = COLORS.border
    header:SetBackdropBorderColor(headerBorder[1], headerBorder[2], headerBorder[3], 0.5)
    
    -- Expand/Collapse icon (texture-based)
    local expandIcon = ns.UI_RenderTexture(header, nil, "ARTWORK")
    expandIcon:SetSize(16, 16)
    expandIcon:SetPoint("LEFT", 12, 0)
    
    -- Use WoW's built-in plus/minus button textures
    if isExpanded then
        expandIcon:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
    else
        expandIcon:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
    end
    -- Dynamic theme color tint
    local iconTint = COLORS.accent
    expandIcon:SetVertexColor(iconTint[1] * 1.5, iconTint[2] * 1.5, iconTint[3] * 1.5)
    
    local textAnchor = expandIcon
    local textOffset = 8
    
    -- Optional icon
    local categoryIcon = nil
    if iconTexture then
        categoryIcon = ns.UI_RenderTexture(header, nil, "ARTWORK")
        categoryIcon:SetSize(28, 28)  -- Bigger icon size (same as favorite star in rows)
        categoryIcon:SetPoint("LEFT", expandIcon, "RIGHT", 8, 0)
        categoryIcon:SetTexture(iconTexture)
        textAnchor = categoryIcon
        textOffset = 8
    end
    
    -- Header text
    local headerText = ns.UI_RenderFontString(header, nil, "OVERLAY", "QuartermasterFontBody")
    headerText:SetPoint("LEFT", textAnchor, "RIGHT", textOffset, 0)
    headerText:SetText(text)
    headerText:SetTextColor(0.8, 0.8, 0.8)
    
    -- Click handler
    header:SetScript("OnClick", function()
        isExpanded = not isExpanded
        -- Update icon texture
        if isExpanded then
            expandIcon:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
        else
            expandIcon:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
        end
        onToggle(isExpanded)
    end)
    
    -- Hover effect
    header:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(COLORS.bgLight))
    end)
    
    header:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(COLORS.bgCard))
    end)
    
    return header, expandIcon, categoryIcon
end

-- Get item type name from class ID
local function GetItemTypeName(classID)
    local typeName = GetItemClassInfo(classID)
    return typeName or "Other"
end

-- Get item class ID from item ID
local function GetItemClassID(itemID)
    if not itemID then return 15 end -- Miscellaneous
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    return classID or 15
end

-- Get icon texture for item type
local function GetTypeIcon(classID)
    local icons = {
        [0] = "Interface\\Icons\\INV_Potion_51",          -- Consumable (Potion)
        [1] = "Interface\\Icons\\INV_Box_02",             -- Container
        [2] = "Interface\\Icons\\INV_Sword_27",           -- Weapon
        [3] = "Interface\\Icons\\INV_Misc_Gem_01",        -- Gem
        [4] = "Interface\\Icons\\INV_Chest_Cloth_07",     -- Armor
        [5] = "Interface\\Icons\\INV_Enchant_DustArcane", -- Reagent
        [6] = "Interface\\Icons\\INV_Ammo_Arrow_02",      -- Projectile
        [7] = "Interface\\Icons\\Trade_Engineering",      -- Trade Goods
        [8] = "Interface\\Icons\\INV_Misc_EnchantedScroll", -- Item Enhancement
        [9] = "Interface\\Icons\\INV_Scroll_04",          -- Recipe
        [12] = "Interface\\Icons\\INV_Misc_Key_03",       -- Quest (Key icon)
        [15] = "Interface\\Icons\\INV_Misc_Gear_01",      -- Miscellaneous
        [16] = "Interface\\Icons\\INV_Inscription_Tradeskill01", -- Glyph
        [17] = "Interface\\Icons\\PetJournalPortrait",    -- Battlepet
        [18] = "Interface\\Icons\\WoW_Token01",           -- WoW Token
    }
    return icons[classID] or "Interface\\Icons\\INV_Misc_Gear_01"
end

--============================================================================
-- SORTABLE TABLE HEADER (Reusable for any table with sorting)
--============================================================================

--[[
    Creates a sortable table header with clickable columns
    
    @param parent - Parent frame
    @param columns - Array of column definitions:
        {
            {key="name", label="CHARACTER", align="LEFT", offset=12},
            {key="level", label="LEVEL", align="LEFT", offset=200},
            {key="gold", label="GOLD", align="RIGHT", offset=-120},
            {key="lastSeen", label="LAST SEEN", align="RIGHT", offset=-20}
        }
    @param width - Total header width
    @param onSortChanged - Callback: function(sortKey, isAscending)
    @param defaultSortKey - Initial sort column (optional)
    @param defaultAscending - Initial sort direction (optional, default true)
    
    @return header frame, getCurrentSort function
]]
local function CreateSortableTableHeader(parent, columns, width, onSortChanged, defaultSortKey, defaultAscending)
    -- State
    local currentSortKey = defaultSortKey or (columns[1] and columns[1].key)
    local isAscending = (defaultAscending ~= false) -- Default true

    -- Create header frame with backdrop (like collapsible headers)
    local header = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    header:SetSize(width, 28)
    header:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 2,
    })
    header:SetBackdropColor(unpack(COLORS.bgCard))  -- Darker background
    header:SetBackdropBorderColor(unpack(COLORS.border))
    
    -- Column buttons
    local columnButtons = {}
    
    for i, col in ipairs(columns) do
        -- Create clickable button (no backdrop = no box!)
        local btn = CreateFrame("Button", nil, header)
        btn:SetSize(col.width or 100, 28)
        
        if col.align == "LEFT" then
            btn:SetPoint("LEFT", col.offset or 0, 0)
        elseif col.align == "RIGHT" then
            btn:SetPoint("RIGHT", col.offset or 0, 0)
        else
            btn:SetPoint("CENTER", col.offset or 0, 0)
        end
        
        -- Label text (position based on alignment)
        btn.label = btn:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")  -- Normal size font
        if col.align == "LEFT" then
            btn.label:SetPoint("LEFT", 5, 0)  -- Small padding
            btn.label:SetJustifyH("LEFT")
        elseif col.align == "RIGHT" then
            btn.label:SetPoint("RIGHT", -17, 0) -- Space for arrow on right
            btn.label:SetJustifyH("RIGHT")
        else
            btn.label:SetPoint("CENTER", -6, 0)
            btn.label:SetJustifyH("CENTER")
        end
        btn.label:SetText(col.label)
        btn.label:SetTextColor(0.8, 0.8, 0.8)  -- Brighter text
        
        -- Sort arrow (^ ascending, v descending, - sortable)
        btn.arrow = btn:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody") -- Bigger font!
        if col.align == "RIGHT" then
            btn.arrow:SetPoint("RIGHT", 0, 0)
        else
            btn.arrow:SetPoint("LEFT", btn.label, "RIGHT", 4, 0)
        end
        btn.arrow:SetText("◆") -- Default: sortable indicator
        btn.arrow:SetTextColor(0.4, 0.4, 0.4, 0.6) -- Dim gray
        
        -- Update arrow visibility
        local function UpdateArrow()
            if currentSortKey == col.key then
                btn.arrow:SetText(isAscending and "▲" or "▼")
                btn.arrow:SetTextColor(unpack(COLORS.accent))
                btn.label:SetTextColor(1, 1, 1) -- Highlight active column
            else
                btn.arrow:SetText("◆") -- Sortable hint (diamond)
                btn.arrow:SetTextColor(0.4, 0.4, 0.4, 0.6) -- Dim
                btn.label:SetTextColor(0.8, 0.8, 0.8)
            end
        end
        
        UpdateArrow()
        
        -- Hover effect
        btn:SetScript("OnEnter", function(self)
            if currentSortKey ~= col.key then
                self.label:SetTextColor(1, 1, 1)
            end
        end)
        
        btn:SetScript("OnLeave", function(self)
            if currentSortKey ~= col.key then
                self.label:SetTextColor(0.8, 0.8, 0.8)
            end
        end)
        
        -- Click handler
        btn:SetScript("OnClick", function()
            if currentSortKey == col.key then
                -- Same column - toggle direction
                isAscending = not isAscending
            else
                -- New column - default to ascending
                currentSortKey = col.key
                isAscending = true
            end
            
            -- Update all arrows
            for _, otherBtn in pairs(columnButtons) do
                if otherBtn.updateArrow then
                    otherBtn.updateArrow()
                end
            end
            
            -- Notify parent
            if onSortChanged then
                onSortChanged(currentSortKey, isAscending)
            end
        end)
        
        btn.updateArrow = UpdateArrow
        columnButtons[i] = btn
    end
    
    -- Function to get current sort state
    local function GetCurrentSort()
        return currentSortKey, isAscending
    end
    
    return header, GetCurrentSort
end

--============================================================================
-- DRAW EMPTY STATE (Shared by Items and Storage tabs)
--============================================================================

local function DrawEmptyState(addon, parent, startY, isSearch, searchText, emptyHintText)
    -- Validate parent frame
    if not parent or not parent.CreateTexture then
        return startY or 0
    end
    
    local yOffset = startY + 50
    
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(48, 48)
    icon:SetPoint("TOP", 0, -yOffset)
    icon:SetTexture(isSearch and "Interface\\Icons\\INV_Misc_Spyglass_02" or "Interface\\Icons\\INV_Misc_Bag_10_Blue")
    icon:SetDesaturated(true)
    icon:SetAlpha(0.4)
    yOffset = yOffset + 60
    
    local title = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontHeading")
    title:SetPoint("TOP", 0, -yOffset)
    yOffset = yOffset + 30
    
    local desc = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    desc:SetPoint("TOP", 0, -yOffset)
    desc:SetTextColor(0.5, 0.5, 0.5)
    local displayText = searchText or ""
    if isSearch then
        desc:SetText("No items match '" .. displayText .. "'")
    else
        -- Optional caller-provided hint (Items tab uses this to distinguish Warband/Guild/Personal etc.)
        desc:SetText(emptyHintText or "Open the relevant bank to scan items")
    end
    
    return yOffset + 50
end

--============================================================================
-- SEARCH BOX (Reusable component for Items and Storage tabs)
--============================================================================

--[[
    Creates a search box with icon, placeholder, and throttled callback
    
    @param parent - Parent frame
    @param width - Search box width
    @param placeholder - Placeholder text (e.g., "Search items...")
    @param onTextChanged - Callback function(searchText) - called after throttle
    @param throttleDelay - Delay in seconds before callback (default 0.3)
    @param initialValue - Initial text value (optional, for restoring state)
    
    @return searchContainer frame, clearFunction
]]
local function CreateSearchBox(parent, width, placeholder, onTextChanged, throttleDelay, initialValue)
    local delay = throttleDelay or 0.3
    local throttleTimer = nil
    local initialText = initialValue or ""
    
    -- Container frame
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 32)
    
    -- Background frame with border (dynamic colors)
    local searchFrame = CreateFrame("Frame", nil, container, "BackdropTemplate")
    container.searchFrame = searchFrame  -- Store reference for color updates
    searchFrame:SetAllPoints()
    searchFrame:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 2,
    })
    searchFrame:SetBackdropColor(unpack(COLORS.bgCard))
    local borderColor = COLORS.accent
    searchFrame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.5)
    
    -- Search icon
    local searchIcon = searchFrame:CreateTexture(nil, "ARTWORK")
    searchIcon:SetSize(16, 16)
    searchIcon:SetPoint("LEFT", 10, 0)
    searchIcon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
    searchIcon:SetAlpha(0.5)

    -- Clear button (appears when text is present)
    -- Styled to match other themed action buttons (e.g., List View toggle)
    local clearBtn = CreateFrame("Button", nil, searchFrame, "BackdropTemplate")
    clearBtn:SetSize(52, 24)
    clearBtn:SetPoint("RIGHT", -6, 0)
    clearBtn:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 2,
    })
    clearBtn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
    clearBtn:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)

    clearBtn.text = clearBtn:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
    clearBtn.text:SetPoint("CENTER", 0, 0)
    clearBtn.text:SetTextColor(1, 1, 1, 0.95)
    clearBtn.text:SetText("Clear")

    clearBtn:SetScript("OnEnter", function(btn)
        if btn.SetBackdropColor then
            btn:SetBackdropColor(COLORS.tabHover[1], COLORS.tabHover[2], COLORS.tabHover[3], 1)
            btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
        end
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:AddLine("Clear Search", 1, 0.82, 0)
        GameTooltip:AddLine("Clear the current search filter.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)

    clearBtn:SetScript("OnLeave", function(btn)
        if btn.SetBackdropColor then
            btn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
            btn:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)
        end
        GameTooltip:Hide()
    end)
    
    -- EditBox
    local searchBox = CreateFrame("EditBox", nil, searchFrame)
    container.editBox = searchBox
    searchBox:SetPoint("LEFT", searchIcon, "RIGHT", 8, 0)
    searchBox:SetPoint("RIGHT", clearBtn, "LEFT", -6, 0)
    searchBox:SetHeight(20)
    searchBox:SetFontObject("QuartermasterFontBody")
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(50)
    
    -- Set initial value if provided
    if initialText and initialText ~= "" then
        searchBox:SetText(initialText)
    end
    
    -- Placeholder text
    local placeholderText = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    placeholderText:SetPoint("LEFT", 0, 0)
    placeholderText:SetText(placeholder or "Search...")
    placeholderText:SetTextColor(0.5, 0.5, 0.5)
    
    -- Show/hide placeholder based on initial text
    if initialText and initialText ~= "" then
        placeholderText:Hide()
        clearBtn:Show()
    else
        placeholderText:Show()
        clearBtn:Hide()
    end
    
    -- OnTextChanged handler with throttle
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        
        local text = self:GetText()
        local newSearchText = ""
        
        if text and text ~= "" then
            placeholderText:Hide()
            clearBtn:Show()
            newSearchText = text:lower()
        else
            placeholderText:Show()
            clearBtn:Hide()
            newSearchText = ""
        end
        
        -- Cancel previous throttle
        if throttleTimer then
            throttleTimer:Cancel()
        end
        
        -- Throttle callback - refresh after delay (live search)
        throttleTimer = C_Timer.NewTimer(delay, function()
            if onTextChanged then
                -- Request focus restoration after the UI refreshes.
                if TheQuartermaster and TheQuartermaster.UI then
                    -- Keep focus sticky for a short grace period so background refreshes
                    -- (bags/events) don't steal focus while the user is typing.
                    TheQuartermaster.UI._restoreSearchFocus = true
                    TheQuartermaster.UI._restoreSearchFocusUntil = (GetTime() or 0) + 1.5
                end
                onTextChanged(newSearchText)
            end
            throttleTimer = nil
        end)
    end)

    -- Expose the most recently created search box so the UI can restore focus after refresh.
    if TheQuartermaster and TheQuartermaster.UI then
        TheQuartermaster.UI.activeSearchBox = searchBox
    end
    
    -- Escape to clear
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    
    -- Enter to defocus
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    
    -- Focus border highlight (dynamic colors)
    searchBox:SetScript("OnEditFocusGained", function(self)
        local accentColor = COLORS.accent
        searchFrame:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
        -- Track the most recently focused search box so refreshes can restore focus reliably.
        if TheQuartermaster and TheQuartermaster.UI then
            TheQuartermaster.UI.activeSearchBox = self
        end
    end)
    
    searchBox:SetScript("OnEditFocusLost", function(self)
        local accentColor = COLORS.accent
        searchFrame:SetBackdropBorderColor(unpack(COLORS.border))
    end)
    
    -- Clear function
    local function ClearSearch()
        searchBox:SetText("")
        placeholderText:Show()
        clearBtn:Hide()
    end

    -- Clear button handler (immediate clear + immediate callback)
    clearBtn:SetScript("OnClick", function()
        local hadFocus = searchBox:HasFocus()
        if throttleTimer then
            throttleTimer:Cancel()
            throttleTimer = nil
        end
        searchBox:SetText("")
        placeholderText:Show()
        clearBtn:Hide()

        if onTextChanged then
            -- Keep focus sticky after the UI refreshes.
            if TheQuartermaster and TheQuartermaster.UI then
                TheQuartermaster.UI._restoreSearchFocus = hadFocus
                TheQuartermaster.UI._restoreSearchFocusUntil = (GetTime() or 0) + 1.5
                TheQuartermaster.UI.activeSearchBox = searchBox
            end
            onTextChanged("")
        end

        if hadFocus then
            searchBox:SetFocus()
        end
    end)
    
    return container, ClearSearch
end

--============================================================================
-- SEARCH TEXT GETTERS
--============================================================================

local function GetCurrencySearchText()
    return (ns.currencySearchText or ""):lower()
end

--============================================================================
-- CURRENCY TRANSFER POPUP
--============================================================================

--[[
    Create a currency transfer popup dialog
    @param currencyData table - Currency information
    @param currentCharacterKey string - Current character key
    @param onConfirm function - Callback(targetCharKey, amount)
    @return frame - Popup frame
]]
local function CreateCurrencyTransferPopup(currencyData, currentCharacterKey, onConfirm)
    -- Create backdrop overlay
    local overlay = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")  -- Highest strata
    overlay:SetFrameLevel(1000)
    overlay:SetAllPoints()
    overlay:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
    })
    overlay:SetBackdropColor(0, 0, 0, 0.7)
    overlay:EnableMouse(true)
    overlay:SetScript("OnMouseDown", function(self)
        self:Hide()
    end)
    
    -- Create popup frame
    local popup = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    popup:SetSize(400, 380)  -- Increased height for instructions
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(overlay:GetFrameLevel() + 10)
    popup:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 2,
    })
    popup:SetBackdropColor(unpack(COLORS.bgCard))
    local popupBorder = COLORS.border
    popup:SetBackdropBorderColor(popupBorder[1], popupBorder[2], popupBorder[3], 1)
    popup:EnableMouse(true)
    
    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY", "QuartermasterFontHeading")
    title:SetPoint("TOP", 0, -15)
    title:SetText(L["CFF6A0DADTRANSFER_CURRENCY_R"])
    
    -- Get TheQuartermaster and current character info
    local TheQuartermaster = ns.TheQuartermaster
    local currentPlayerName = UnitName("player")
    local currentRealm = GetRealmName()
    
    -- From Character (current/online)
    local fromText = popup:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
    fromText:SetPoint("TOP", 0, -38)
    fromText:SetText(string.format("|cff888888From:|r |cff00ff00%s|r |cff888888(Online)|r", currentPlayerName))
    
    -- Currency Icon
    local icon = popup:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOP", 0, -65)
    if currencyData.iconFileID then
        icon:SetTexture(currencyData.iconFileID)
    end
    
    -- Currency Name
    local nameText = popup:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    nameText:SetPoint("TOP", 0, -105)
    nameText:SetText(currencyData.name or "Unknown Currency")
    nameText:SetTextColor(1, 0.82, 0)
    
    -- Available Amount
    local availableText = popup:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
    availableText:SetPoint("TOP", 0, -125)
    availableText:SetText(string.format("|cff888888Available:|r |cffffffff%d|r", currencyData.quantity or 0))
    
    -- Amount Input Label
    local amountLabel = popup:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    amountLabel:SetPoint("TOPLEFT", 30, -155)
    amountLabel:SetText(L["AMOUNT"])
    
    -- Amount Input Box
    local amountBox = CreateFrame("EditBox", nil, popup, "BackdropTemplate")
    amountBox:SetSize(100, 28)
    amountBox:SetPoint("LEFT", amountLabel, "RIGHT", 10, 0)
    amountBox:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 2,
    })
    amountBox:SetBackdropColor(unpack(COLORS.bg))
    amountBox:SetBackdropBorderColor(unpack(COLORS.border))
    amountBox:SetFontObject("QuartermasterFontBody")
    amountBox:SetTextInsets(8, 8, 0, 0)
    amountBox:SetAutoFocus(false)
    amountBox:SetNumeric(true)
    amountBox:SetMaxLetters(10)
    amountBox:SetText("1")
    
    -- Max Button
    local maxBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    maxBtn:SetSize(45, 24)
    maxBtn:SetPoint("LEFT", amountBox, "RIGHT", 5, 0)
    maxBtn:SetText(L["MAX"])
    maxBtn:SetScript("OnClick", function()
        amountBox:SetText(tostring(currencyData.quantity or 0))
    end)
    
    -- Confirm Button (create early so it can be referenced)
    local confirmBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    confirmBtn:SetSize(120, 28)
    confirmBtn:SetPoint("BOTTOMRIGHT", -20, 15)
    confirmBtn:SetText(L["OPEN_GUIDE"])  -- Changed text
    confirmBtn:Disable() -- Initially disabled until character selected
    
    -- Cancel Button
    local cancelBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 28)
    cancelBtn:SetPoint("RIGHT", confirmBtn, "LEFT", -5, 0)
    cancelBtn:SetText(L["CANCEL"])
    cancelBtn:SetScript("OnClick", function()
        overlay:Hide()
    end)
    
    -- Info note at bottom
    local infoNote = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    infoNote:SetPoint("BOTTOM", 0, 50)
    infoNote:SetWidth(360)
    infoNote:SetText(L["CFF00FF00_R_CURRENCY_WINDOW_WILL_BE_OPENED_AUTOMATICALLY_N_C"])
    infoNote:SetJustifyH("CENTER")
    infoNote:SetWordWrap(true)
    
    -- Target Character Label
    local targetLabel = popup:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    targetLabel:SetPoint("TOPLEFT", 30, -195)
    targetLabel:SetText(L["TO_CHARACTER"])
    
    -- Get TheQuartermaster addon reference
    local TheQuartermaster = ns.TheQuartermaster
    
    -- Build character list (exclude current character)
    local characterList = {}
    if TheQuartermaster and TheQuartermaster.db and TheQuartermaster.db.global.characters then
        for charKey, charData in pairs(TheQuartermaster.db.global.characters) do
            if charKey ~= currentCharacterKey and charData.name then
                table.insert(characterList, {
                    key = charKey,
                    name = charData.name,
                    realm = charData.realm or "",
                    class = charData.class or "UNKNOWN",
                    level = charData.level or 0,
                })
            end
        end
        
        -- Sort by name
        characterList = ns.SortCharacterRows(TheQuartermaster.db, characterList)
    end
    
    -- Selected character
    local selectedTargetKey = nil
    local selectedCharData = nil
    
    -- Character selection dropdown container
    local charDropdown = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    charDropdown:SetSize(320, 28)
    charDropdown:SetPoint("TOPLEFT", 30, -215)
    charDropdown:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 2,
    })
    charDropdown:SetBackdropColor(unpack(COLORS.bg))
    charDropdown:SetBackdropBorderColor(unpack(COLORS.border))
    charDropdown:EnableMouse(true)
    
    local charText = charDropdown:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    charText:SetPoint("LEFT", 10, 0)
    charText:SetText(L["CFF888888SELECT_CHARACTER_R"])
    charText:SetJustifyH("LEFT")
    
    -- Dropdown arrow icon
    local arrowIcon = charDropdown:CreateTexture(nil, "ARTWORK")
    arrowIcon:SetSize(16, 16)
    arrowIcon:SetPoint("RIGHT", -5, 0)
    arrowIcon:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    
    -- Character list frame (dropdown menu)
    local charListFrame = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    charListFrame:SetSize(320, math.min(#characterList * 28 + 4, 200))  -- Max 200px height
    charListFrame:SetPoint("TOPLEFT", charDropdown, "BOTTOMLEFT", 0, -2)
    charListFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    charListFrame:SetFrameLevel(popup:GetFrameLevel() + 20)
    charListFrame:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 2,
    })
    charListFrame:SetBackdropColor(unpack(COLORS.bgCard))
    local listBorder = COLORS.border
    charListFrame:SetBackdropBorderColor(listBorder[1], listBorder[2], listBorder[3], 1)
    charListFrame:Hide()  -- Initially hidden
    
    -- Scroll frame for character list (if many characters)
    local scrollFrame = CreateFrame("ScrollFrame", nil, charListFrame)
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -2, 2)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetSize(316, #characterList * 28)
    
    -- Create character buttons
    for i, charData in ipairs(characterList) do
        local charBtn = CreateFrame("Button", nil, scrollChild, "BackdropTemplate")
        charBtn:SetSize(316, 26)
        charBtn:SetPoint("TOPLEFT", 0, -(i-1) * 28)
        charBtn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
        })
        charBtn:SetBackdropColor(0, 0, 0, 0)
        
        -- Class color
        local classColor = RAID_CLASS_COLORS[charData.class] or {r=1, g=1, b=1}
        
        local btnText = charBtn:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
        btnText:SetPoint("LEFT", 8, 0)
        btnText:SetText(string.format("|c%s%s|r |cff888888(%d - %s)|r", 
            string.format("%02x%02x%02x%02x", 255, classColor.r*255, classColor.g*255, classColor.b*255),
            charData.name,
            charData.level,
            charData.realm
        ))
        btnText:SetJustifyH("LEFT")
        
        charBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(unpack(COLORS.bgLight))
        end)
        charBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0, 0, 0, 0)
        end)
        charBtn:SetScript("OnClick", function(self)
            selectedTargetKey = charData.key
            selectedCharData = charData
            charText:SetText(string.format("|c%s%s|r", 
                string.format("%02x%02x%02x%02x", 255, classColor.r*255, classColor.g*255, classColor.b*255),
                charData.name
            ))
            charListFrame:Hide()
            confirmBtn:Enable()  -- Enable confirm button
        end)
    end
    
    -- Toggle dropdown
    charDropdown:SetScript("OnMouseDown", function(self)
        if charListFrame:IsShown() then
            charListFrame:Hide()
        else
            charListFrame:Show()
        end
    end)
    
    -- Set confirm button click handler (now that we have all variables)
    confirmBtn:SetScript("OnClick", function()
        local amount = tonumber(amountBox:GetText()) or 0
        if amount > 0 and amount <= (currencyData.quantity or 0) and selectedTargetKey and selectedCharData then
            -- STEP 1: Open Currency Frame (SAFE - No Taint)
            -- TWW (11.x) uses different frame name
            if not CharacterFrame or not CharacterFrame:IsShown() then
                ToggleCharacter("PaperDollFrame")
            end
            
            -- Switch to currency tab
            C_Timer.After(0.1, function()
                if CharacterFrame and CharacterFrame:IsShown() then
                    -- Click the Token (Currency) tab
                    if CharacterFrameTab4 then
                        CharacterFrameTab4:Click()
                    end
                end
            end)
            
            -- STEP 2: Try to expand currency categories (SAFE)
            C_Timer.After(0.3, function()
                -- Expand all currency categories so user can see target currency
                for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
                    local info = C_CurrencyInfo.GetCurrencyListInfo(i)
                    if info and info.isHeader and not info.isHeaderExpanded then
                        C_CurrencyInfo.ExpandCurrencyList(i, true)
                    end
                end
            end)
            
            -- STEP 3: Show instructions in chat
            local TheQuartermaster = ns.TheQuartermaster
            if TheQuartermaster then
                TheQuartermaster:Print("|cff00ff00=== Currency Transfer Instructions ===|r")
                TheQuartermaster:Print(string.format("|cffffaa00Currency:|r %s", currencyData.name))
                TheQuartermaster:Print(string.format("|cffffaa00Amount:|r %d", amount))
                TheQuartermaster:Print(string.format("|cffffaa00From:|r %s |cff888888(current character)|r", currentPlayerName))
                TheQuartermaster:Print(string.format("|cffffaa00To:|r |cff00ff00%s|r", selectedCharData.name))
                TheQuartermaster:Print(" ")
                TheQuartermaster:Print("|cff00aaffNext steps:|r")
                TheQuartermaster:Print("|cff00ff001.|r Find |cffffffff" .. currencyData.name .. "|r in the Currency window")
                TheQuartermaster:Print("|cff00ff002.|r |cffff8800Right-click|r on it")
                TheQuartermaster:Print("|cff00ff003.|r Select |cffffffff'Transfer to Warband'|r")
                TheQuartermaster:Print("|cff00ff004.|r Choose |cff00ff00" .. selectedCharData.name .. "|r")
                TheQuartermaster:Print("|cff00ff005.|r Enter amount: |cffffffff" .. amount .. "|r")
                TheQuartermaster:Print(" ")
                TheQuartermaster:Print("|cff00ff00✓|r Currency window is now open!")
                TheQuartermaster:Print("|cff888888(Blizzard security prevents automatic transfer)|r")
            end
            
            overlay:Hide()
        end
    end)
    
    -- Store reference for cleanup
    overlay.popup = popup
    
    -- Show overlay
    overlay:Show()
    
    return overlay
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

ns.UI_GetQualityHex = GetQualityHex
ns.UI_GetAccentHexColor = GetAccentHexColor
ns.UI_CreateCard = CreateCard
ns.UI_FormatGold = FormatGold
ns.UI_FormatCharacterNameRealm = FormatCharacterNameRealm
ns.UI_CreateCollapsibleHeader = CreateCollapsibleHeader
ns.UI_GetItemTypeName = GetItemTypeName
ns.UI_GetItemClassID = GetItemClassID
ns.UI_GetTypeIcon = GetTypeIcon
ns.UI_CreateSortableTableHeader = CreateSortableTableHeader
ns.UI_DrawEmptyState = DrawEmptyState
ns.UI_CreateSearchBox = CreateSearchBox
ns.UI_GetCurrencySearchText = GetCurrencySearchText
ns.UI_RefreshColors = RefreshColors
ns.UI_CalculateThemeColors = CalculateThemeColors

-- Frame pooling exports
ns.UI_AcquireItemRow = AcquireItemRow
ns.UI_ReleaseItemRow = ReleaseItemRow
ns.UI_AcquireStorageRow = AcquireStorageRow
ns.UI_ReleaseStorageRow = ReleaseStorageRow
ns.UI_AcquireCurrencyRow = AcquireCurrencyRow
ns.UI_ReleaseCurrencyRow = ReleaseCurrencyRow
ns.UI_ReleaseAllPooledChildren = ReleaseAllPooledChildren

-- Skin only addon-owned legacy scroll frames; retain native slider/button scripts.
function ns.UI_ThemeScrollBar(scroll)
    local bar = scroll and scroll.ScrollBar
    if not bar or bar.qmThemed then return end
    bar.qmThemed = true
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(unpack(COLORS.bgCard))
    local rail = bar:CreateTexture(nil, "BORDER")
    rail:SetWidth(2)
    rail:SetPoint("TOP", bar, "TOP", 0, 0)
    rail:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    rail:SetColorTexture(unpack(COLORS.border))
    local thumb = bar:GetThumbTexture()
    if thumb then
        thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
        thumb:SetTexCoord(0, 1, 0, 1)
        thumb:SetVertexColor(unpack(COLORS.accent))
        thumb:SetSize(10, 24)
    end
    local function Arrow(button, direction)
        if not button then return end
        for _, state in ipairs({"Normal", "Pushed", "Disabled", "Highlight"}) do
            button["Set" .. state .. "Texture"](button, "Interface\\Buttons\\WHITE8X8")
            local texture = button["Get" .. state .. "Texture"](button)
            texture:SetTexCoord(0, 1, 0, 1)
            texture:ClearAllPoints()
            texture:SetAllPoints(button)
            local colour = state == "Highlight" and COLORS.accent or state == "Pushed" and COLORS.bgLight or COLORS.bgCard
            texture:SetVertexColor(colour[1], colour[2], colour[3], state == "Highlight" and 0.25 or 1)
        end
        -- Texture strokes remain legible even when the client font lacks arrow glyphs.
        local strokes = {}
        for index, side in ipairs({-1, 1}) do
            local stroke = button:CreateTexture(nil, "OVERLAY")
            stroke:SetSize(6, 2)
            stroke:SetPoint("CENTER", button, "CENTER", side * 2, 0)
            stroke:SetColorTexture(1, 1, 1, 1)
            stroke:SetRotation(-side * direction * math.pi / 4)
            strokes[index] = stroke
        end
        local function Update()
            local colour = button:IsEnabled() and COLORS.textNormal or COLORS.textDisabled
            for _, stroke in ipairs(strokes) do stroke:SetVertexColor(unpack(colour)) end
        end
        button:HookScript("OnEnable", Update)
        button:HookScript("OnDisable", Update)
        Update()
    end
    Arrow(bar.ScrollUpButton, 1)
    Arrow(bar.ScrollDownButton, -1)
end
