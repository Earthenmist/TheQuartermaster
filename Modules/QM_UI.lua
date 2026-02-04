--[[
    The Quartermaster - UI Module
    Modern, clean UI design
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster
local L = ns.L

-- Import shared UI components from SharedWidgets
local COLORS = ns.UI_COLORS
local QUALITY_COLORS = ns.UI_QUALITY_COLORS
local GetQualityHex = ns.UI_GetQualityHex
local CreateCard = ns.UI_CreateCard
-- Money formatting helper (lazy-resolved to avoid load-order issues and respects Discretion Mode)
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
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local GetItemTypeName = ns.UI_GetItemTypeName
local GetItemClassID = ns.UI_GetItemClassID
local GetTypeIcon = ns.UI_GetTypeIcon
local AcquireItemRow = ns.UI_AcquireItemRow
local ReleaseItemRow = ns.UI_ReleaseItemRow
local AcquireStorageRow = ns.UI_AcquireStorageRow
local ReleaseStorageRow = ns.UI_ReleaseStorageRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren

-- Performance: Local function references
local format = string.format
local floor = math.floor
local date = date

-- Constants
local DEFAULT_WIDTH = 680
local DEFAULT_HEIGHT = 500
-- Minimum size must account for the widest tab content (Characters has multiple
-- columns and long names). We clamp both during resize *and* on load so a saved
-- too-small size can't break the layout.
local MIN_WIDTH = 1050
local MIN_HEIGHT = 620
local ROW_HEIGHT = 26

local mainFrame = nil
local goldTransferFrame = nil
local currentTab = "stats" -- Default to Characters tab
local currentItemsSubTab = "warband" -- Default to Warband Bank
local expandedGroups = {} -- Persisted expand/collapse state for item groups

-- Search text state (exposed to namespace for sub-modules to access directly)
ns.itemsSearchText = ""
ns.storageSearchText = ""
ns.currencySearchText = ""
ns.reputationSearchText = ""

-- Namespace exports for state management (used by sub-modules)
ns.UI_GetItemsSubTab = function() return currentItemsSubTab end
ns.UI_SetItemsSubTab = function(val)
    currentItemsSubTab = val
    -- Only sync the WoW BankFrame tab when switching to bank-backed views
    -- (Inventory is view-only and should not force bank tab sync.)
    if TheQuartermaster and TheQuartermaster.SyncBankTab and TheQuartermaster.bankIsOpen then
        if val == "personal" or val == "warband" or val == "guild" then
            TheQuartermaster:SyncBankTab()
        end
    end
end
ns.UI_GetItemsSearchText = function() return ns.itemsSearchText end
ns.UI_GetStorageSearchText = function() return ns.storageSearchText end
ns.UI_GetCurrencySearchText = function() return ns.currencySearchText end
ns.UI_GetReputationSearchText = function() return ns.reputationSearchText end
ns.UI_GetExpandedGroups = function() return expandedGroups end

--============================================================================
-- MAIN FUNCTIONS
--============================================================================
function TheQuartermaster:ToggleMainWindow()
    if mainFrame and mainFrame:IsShown() then
        mainFrame:Hide()
    else
        self:ShowMainWindow()
    end
end

-- Manual open via /wn show or minimap click -> Opens Characters tab
function TheQuartermaster:ShowMainWindow()
    if not mainFrame then
        mainFrame = self:CreateMainWindow()
    end
    
    -- Manual open defaults to Characters tab
    mainFrame.currentTab = "stats"
    
    self:PopulateContent()
    mainFrame:Show()
end

-- Bank open -> Opens Items tab with correct sub-tab based on NPC type
function TheQuartermaster:ShowMainWindowWithItems(bankType)
    if not mainFrame then
        mainFrame = self:CreateMainWindow()
    end
    
    -- CRITICAL: Match addon's sub-tab to Blizzard's current tab (don't force it!)
    -- Blizzard already chose the correct tab when bank opened
    local subTab = (bankType == "warband") and "warband" or "personal"
    
    -- IMPORTANT: Use direct assignment to avoid triggering SyncBankTab
    -- We're matching Blizzard's choice, not forcing it
    currentItemsSubTab = subTab
    
    -- Bank open defaults to Items tab
    mainFrame.currentTab = "items"
    
    self:PopulateContent()
    mainFrame:Show()
    
    -- NO SyncBankTab here! We're following Blizzard's lead, not forcing our choice.
    -- SyncBankTab only runs when USER manually switches tabs inside the addon.
end

function TheQuartermaster:HideMainWindow()
    if mainFrame then
        mainFrame:Hide()
    end
end

--============================================================================
-- CREATE MAIN WINDOW
--============================================================================
function TheQuartermaster:CreateMainWindow()
    local savedWidth = self.db and self.db.profile.windowWidth or DEFAULT_WIDTH
    local savedHeight = self.db and self.db.profile.windowHeight or DEFAULT_HEIGHT
    -- Clamp saved size so an older/smaller value can't render the UI unusable.
    if type(savedWidth) ~= "number" then savedWidth = DEFAULT_WIDTH end
    if type(savedHeight) ~= "number" then savedHeight = DEFAULT_HEIGHT end
    if savedWidth < MIN_WIDTH then savedWidth = MIN_WIDTH end
    if savedHeight < MIN_HEIGHT then savedHeight = MIN_HEIGHT end
    
    -- Main frame
    local f = CreateFrame("Frame", "TheQuartermasterFrame", UIParent, "BackdropTemplate")
    f:SetSize(savedWidth, savedHeight)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, 1200, 900)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")  -- DIALOG is above HIGH, ensures we're above BankFrame
    f:SetFrameLevel(100)         -- Extra high level for safety
    f:SetClampedToScreen(true)

    -- Enforce minimum size even if some client versions don't fully respect
    -- resize bounds while sizing (or if other code sets the size directly).
    f:SetScript("OnSizeChanged", function(frame)
        local w, h = frame:GetSize()
        if w < MIN_WIDTH or h < MIN_HEIGHT then
            frame:SetSize(math.max(w, MIN_WIDTH), math.max(h, MIN_HEIGHT))
        end
    end)
    
    -- Modern backdrop
    f:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 2,
    })
    f:SetBackdropColor(unpack(COLORS.bg))
    f:SetBackdropBorderColor(unpack(COLORS.border))
    
    -- Resize handle
    local resizeBtn = CreateFrame("Button", nil, f)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeBtn:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    resizeBtn:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        if TheQuartermaster.db and TheQuartermaster.db.profile then
            -- Persist clamped values so the window never reloads too small.
            TheQuartermaster.db.profile.windowWidth = math.max(f:GetWidth(), MIN_WIDTH)
            TheQuartermaster.db.profile.windowHeight = math.max(f:GetHeight(), MIN_HEIGHT)
        end
        TheQuartermaster:PopulateContent()
    end)
    
    -- ===== HEADER BAR =====
    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetHeight(40)
    header:SetPoint("TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", -2, -2)
    header:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
    })
    header:SetBackdropColor(unpack(COLORS.accentDark))
    f.header = header  -- Store reference for color updates

    -- Icon
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("LEFT", 15, 0)
    icon:SetTexture("Interface\\AddOns\\TheQuartermaster\\Media\\icon")

    -- Title
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText(L["CFFFFFFFFTHE_QUARTERMASTER_R"])  -- Always white
    title:SetTextColor(1, 1, 1)  -- Force white color
    f.title = title  -- Store reference (but don't change color)
    
    -- Status badge removed: bank/warband are view-only now, so LIVE/CACHED status is no longer meaningful.
    f.statusBadge = nil
    f.statusText = nil
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(30, 30)
    closeBtn:SetPoint("RIGHT", -8, 0)
    closeBtn:SetNormalTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Discretion Mode (privacy) toggle - header top-right
    local discretionCB = CreateFrame("CheckButton", nil, header, "UICheckButtonTemplate")
    discretionCB:SetSize(22, 22)
    discretionCB:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
    discretionCB:SetChecked(TheQuartermaster.db and TheQuartermaster.db.profile and TheQuartermaster.db.profile.discretionMode)

    -- Remove Blizzard template label text (we use our own label)
    local cbText = discretionCB.Text or discretionCB.text or (discretionCB.GetName and _G[discretionCB:GetName() .. "Text"])
    if cbText and cbText.SetText then
        cbText:SetText("")
    end

    local discretionLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    discretionLabel:SetText(L["DISCRETION_MODE"])
	-- Text colour must remain readable against dynamic (class-colour) headers.
	-- We auto-pick a light/dark colour based on the header's current theme colour.
	local function ApplyDiscretionLabelColor()
		local colors = ns.UI_COLORS
		local br, bg, bb = 0.20, 0.20, 0.20
		if colors and colors.accentDark then
			br, bg, bb = colors.accentDark[1] or br, colors.accentDark[2] or bg, colors.accentDark[3] or bb
		end
		-- perceived brightness (YIQ)
		local brightness = (br * 299 + bg * 587 + bb * 114) / 1000
		if brightness > 0.6 then
			discretionLabel:SetTextColor(0.1, 0.1, 0.1, 0.95)
		else
			discretionLabel:SetTextColor(1, 1, 1, 0.95)
		end
	end
	ApplyDiscretionLabelColor()
    discretionLabel:SetPoint("RIGHT", discretionCB, "LEFT", -6, 0)

	-- Store references so the shared colour refresh can update the label when themes change
	f.discretionLabel = discretionLabel
	f.ApplyDiscretionLabelColor = ApplyDiscretionLabelColor

    discretionCB:SetScript("OnClick", function(self)
        if TheQuartermaster.db and TheQuartermaster.db.profile then
            TheQuartermaster.db.profile.discretionMode = self:GetChecked() and true or false
        end
        TheQuartermaster:PopulateContent()
    end)
    discretionCB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["DISCRETION_MODE"])
        GameTooltip:AddLine("When enabled, all gold amounts are hidden across the addon.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    discretionCB:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    tinsert(UISpecialFrames, "TheQuartermasterFrame")
    
    -- ===== NAV SIDEBAR =====
    -- Sidebar navigation (distinct from Warband Nexus' top-tab layout)
    local nav = CreateFrame("Frame", nil, f, "BackdropTemplate")
    nav:SetWidth(160)
    nav:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 8, -8)
    nav:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 45)
    nav:SetBackdrop({
        bgFile = "Interface\BUTTONS\WHITE8X8",
        edgeFile = "Interface\BUTTONS\WHITE8X8",
        edgeSize = 1,
    })
    nav:SetBackdropColor(0.06, 0.06, 0.07, 1)
    nav:SetBackdropBorderColor(unpack(COLORS.border))
    f.nav = nav
    f.currentTab = "stats" -- Start with Characters tab
    f.tabButtons = {}
    
    -- Tab styling function
    local function CreateTabButton(parent, text, key, yOffset)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(144, 32)
        btn:SetPoint("TOPLEFT", 8, -yOffset)
        btn.key = key

        -- Rounded background using backdrop with rounded edge texture
        btn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            tile = false,
            tileSize = 16,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        btn:SetBackdropColor(0.12, 0.12, 0.15, 1)
        -- Use theme border color
        local borderColor = COLORS.border
        btn:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)
        
        -- Glow overlay for active/hover states (dynamic color)
        local glow = btn:CreateTexture(nil, "ARTWORK")
        glow:SetPoint("TOPLEFT", 3, -3)
        glow:SetPoint("BOTTOMRIGHT", -3, 3)
        local glowColor = COLORS.accent
        glow:SetColorTexture(glowColor[1], glowColor[2], glowColor[3], 0.15)
        glow:SetAlpha(0)
        btn.glow = glow
        
        -- Active indicator bar (bottom, rounded) (dynamic color)
        local activeBar = btn:CreateTexture(nil, "OVERLAY")
        activeBar:SetHeight(3)
        activeBar:SetPoint("BOTTOMLEFT", 8, 4)
        activeBar:SetPoint("BOTTOMRIGHT", -8, 4)
        local accentColor = COLORS.accent
        activeBar:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
        activeBar:SetAlpha(0)
        btn.activeBar = activeBar

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("CENTER", 0, 1)
        label:SetText(text)
        label:SetFont(label:GetFont(), 12, "")
        btn.label = label

        btn:SetScript("OnEnter", function(self)
            if self.active then return end
            local hoverColor = COLORS.tabHover
            local borderColor = COLORS.accent
            self:SetBackdropColor(hoverColor[1], hoverColor[2], hoverColor[3], 1)
            self:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)
            glow:SetAlpha(0.3)
        end)
        btn:SetScript("OnLeave", function(self)
            if self.active then return end
            self:SetBackdropColor(0.12, 0.12, 0.15, 1)
            self:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
            glow:SetAlpha(0)
        end)
        btn:SetScript("OnClick", function(self)
            f.currentTab = self.key
            TheQuartermaster:PopulateContent()
        end)

        return btn
    end
    
    -- Create tabs with equal spacing (105px width + 5px gap = 110px spacing)
    local tabSpacing = 36
        f.tabButtons["stats"] = CreateTabButton(nav, "Dashboard", "stats", 10)
f.tabButtons["chars"] = CreateTabButton(nav, "Characters", "chars", 10 + tabSpacing * 1)
    f.tabButtons["exp"] = CreateTabButton(nav, "Experience", "exp", 10 + tabSpacing * 2)
    f.tabButtons["guild"] = CreateTabButton(nav, "Guilds", "guild", 10 + tabSpacing * 3)
    f.tabButtons["items"] = CreateTabButton(nav, "Items", "items", 10 + tabSpacing * 4)
    f.tabButtons["storage"] = CreateTabButton(nav, "Storage", "storage", 10 + tabSpacing * 5)
    f.tabButtons["pve"] = CreateTabButton(nav, "PvE", "pve", 10 + tabSpacing * 6)
    f.tabButtons["reputations"] = CreateTabButton(nav, "Reputations", "reputations", 10 + tabSpacing * 7)
    f.tabButtons["currency"] = CreateTabButton(nav, "Currency", "currency", 10 + tabSpacing * 8)
-- Sidebar actions (Information + Settings) - match nav button style, anchored to bottom
local infoNav = CreateTabButton(nav, L["INFORMATION"] or "Information", "info_action", 10) -- yOffset ignored after re-anchor
local settingsNav = CreateTabButton(nav, L["SETTINGS"] or "Settings", "settings_action", 10) -- yOffset ignored after re-anchor
-- Re-anchor to bottom-left of sidebar (footer area)
infoNav:ClearAllPoints()
settingsNav:ClearAllPoints()
settingsNav:SetPoint("BOTTOMLEFT", nav, "BOTTOMLEFT", 10, 10)
settingsNav:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", -10, 10)
infoNav:SetPoint("BOTTOMLEFT", settingsNav, "TOPLEFT", 0, 8)
infoNav:SetPoint("BOTTOMRIGHT", settingsNav, "TOPRIGHT", 0, 8)
infoNav:SetScript("OnClick", function()
    if TheQuartermaster and TheQuartermaster.ShowInfoDialog then
        TheQuartermaster:ShowInfoDialog()
    end
end)
settingsNav:SetScript("OnClick", function()
    if TheQuartermaster and TheQuartermaster.OpenOptions then
        TheQuartermaster:OpenOptions()
    end
end)

    -- Function to update tab colors dynamically
    f.UpdateTabColors = function()
        local freshColors = ns.UI_COLORS
        for _, btn in pairs(f.tabButtons) do
            if btn.glow then
                btn.glow:SetColorTexture(freshColors.accent[1], freshColors.accent[2], freshColors.accent[3], 0.15)
            end
            if btn.activeBar then
                btn.activeBar:SetColorTexture(freshColors.accent[1], freshColors.accent[2], freshColors.accent[3], 1)
            end
            -- Update border color
            local borderColor = freshColors.border
            btn:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)
            
            if btn.active then
                local activeColor = freshColors.tabActive
                btn:SetBackdropColor(activeColor[1], activeColor[2], activeColor[3], 1)
            end
        end
    end
    
    -- NOTE: Information + Settings buttons are part of the left navigation rail.
    
    -- ===== CONTENT AREA =====
    local content = CreateFrame("Frame", nil, f, "BackdropTemplate")
    content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 12, 0)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 45)
    content:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    content:SetBackdropColor(0.04, 0.04, 0.05, 1)
    content:SetBackdropBorderColor(unpack(COLORS.border))
    f.content = content
    
    -- ===== PERSISTENT SEARCH AREA (for Items & Storage tabs) =====
    -- This area is NEVER cleared/refreshed, only shown/hidden
    local searchArea = CreateFrame("Frame", nil, content)
    searchArea:SetHeight(48) -- Search box (32px) + padding (8+8)
    searchArea:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    searchArea:SetPoint("TOPRIGHT", content, "TOPRIGHT", -24, 0) -- Account for scroll bar
    searchArea:Hide() -- Hidden by default
    f.searchArea = searchArea
    
    -- Scroll frame (dynamically positioned based on whether searchArea is visible)
    local scroll = CreateFrame("ScrollFrame", "TheQuartermasterScroll", content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0) -- Will be adjusted
    scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -24, 4)
    f.scroll = scroll
    
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(1) -- Temporary, will be updated
    scrollChild:SetHeight(1)
    scroll:SetScrollChild(scrollChild)
    f.scrollChild = scrollChild
    
    -- Update scrollChild width when scroll frame is resized
    scroll:SetScript("OnSizeChanged", function(self, width, height)
        if scrollChild then
            scrollChild:SetWidth(width)
        end
    end)
    
    -- ===== FOOTER =====
    local footer = CreateFrame("Frame", nil, f)
    footer:SetHeight(35)
    footer:SetPoint("BOTTOMLEFT", 8, 5)
    footer:SetPoint("BOTTOMRIGHT", -8, 5)
    
    local footerText = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footerText:SetPoint("LEFT", 5, 0)
    footerText:SetTextColor(unpack(COLORS.textDim))
    f.footerText = footerText
    
    -- Action buttons (right side)
    -- Note: Button states are updated in UpdateButtonStates()
    
    local classicBtn = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate, BackdropTemplate")
    classicBtn:SetSize(90, 24)
    classicBtn:SetPoint("RIGHT", -10, 0)
    classicBtn:SetText(L["CLASSIC_BANK"])
    -- Theme this footer button to match the Quartermaster UI
    do
        -- Remove Blizzard button textures so our backdrop is the visual
        local nt = classicBtn:GetNormalTexture(); if nt then nt:SetAlpha(0) end
        local pt = classicBtn:GetPushedTexture(); if pt then pt:SetAlpha(0) end
        local ht = classicBtn:GetHighlightTexture(); if ht then ht:SetAlpha(0) end
        local dt = classicBtn:GetDisabledTexture(); if dt then dt:SetAlpha(0) end

        classicBtn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })
        classicBtn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
        classicBtn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)
        if classicBtn.GetFontString and classicBtn:GetFontString() then
            classicBtn:GetFontString():SetTextColor(1, 1, 1, 0.95)
        end
    end

        -- (Information + Settings moved to the sidebar navigation)

classicBtn:SetScript("OnClick", function()
        if TheQuartermaster.bankIsOpen then
            -- Enter Classic Bank mode for this session
            TheQuartermaster.classicModeThisSession = true
            
            -- Restore Blizzard bank UI
            TheQuartermaster:RestoreDefaultBankFrame()
            
            -- Hide The Quartermaster window
            TheQuartermaster:HideMainWindow()
            
            -- Show temporary message
            TheQuartermaster:Print("|cff00ccffClassic Bank Mode|r - Using Blizzard UI this session. Use /reload to return to The Quartermaster.")
            
            -- Open bags
            if OpenAllBags then
                OpenAllBags()
            end
        else
            TheQuartermaster:Print("|cffff6600You must be near a banker.|r")
        end
    end)

    classicBtn:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(COLORS.tabHover[1], COLORS.tabHover[2], COLORS.tabHover[3], 1)
            self:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Classic Bank", 1, 1, 1)
        GameTooltip:AddLine("Open the default WoW bank interface", 0.7, 0.7, 0.7)
        if not TheQuartermaster.bankIsOpen then
            GameTooltip:AddLine("|cffff6600Requires bank access|r", 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    classicBtn:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
            self:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)
        end
        GameTooltip:Hide()
    end)
    f.classicBtn = classicBtn
    
    -- Scan and Sort buttons removed - no longer needed
    -- Scan is automatic (autoScan setting), Sort is automatic (items auto-sorted alphabetically)
    
    -- Store reference in TheQuartermaster for cross-module access
    if not TheQuartermaster.UI then
        TheQuartermaster.UI = {}
    end
    TheQuartermaster.UI.mainFrame = f
    
    f:Hide()
    return f
end

--============================================================================
-- POPULATE CONTENT
--============================================================================
function TheQuartermaster:PopulateContent()
    if not mainFrame then return end
    
    local scrollChild = mainFrame.scrollChild
    if not scrollChild then return end
    
    scrollChild:SetWidth(mainFrame.scroll:GetWidth() - 5)
    
    -- PERFORMANCE: Only clear/hide children, don't SetParent(nil)
    for _, child in pairs({scrollChild:GetChildren()}) do
        child:Hide()
    end
    for _, region in pairs({scrollChild:GetRegions()}) do
        region:Hide()
    end
    
    -- Update status
    self:UpdateStatus()
    
    -- Update tabs with modern active state (rounded style) - Dynamic colors
    local freshColors = ns.UI_COLORS
    for key, btn in pairs(mainFrame.tabButtons) do
        if key == mainFrame.currentTab then
            btn.active = true
            local activeColor = freshColors.tabActive
            local accentColor = freshColors.accent
            btn:SetBackdropColor(activeColor[1], activeColor[2], activeColor[3], 1)
            btn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
            btn.label:SetTextColor(1, 1, 1)
            btn.label:SetFont(btn.label:GetFont(), 12, "OUTLINE")
            if btn.glow then
                btn.glow:SetAlpha(0.25)  -- Show glow for active
            end
            if btn.activeBar then
                btn.activeBar:SetAlpha(1)  -- Show active indicator
            end
        else
            btn.active = false
            btn:SetBackdropColor(0.12, 0.12, 0.15, 1)
            btn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
            btn.label:SetTextColor(0.7, 0.7, 0.7)
            btn.label:SetFont(btn.label:GetFont(), 12, "")
            if btn.glow then
                btn.glow:SetAlpha(0)  -- Hide glow
            end
            if btn.activeBar then
                btn.activeBar:SetAlpha(0)  -- Hide active indicator
            end
        end
    end
    
    -- Show/hide searchArea and create persistent search boxes
    local isSearchTab = (mainFrame.currentTab == "items" or mainFrame.currentTab == "storage" or mainFrame.currentTab == "currency" or mainFrame.currentTab == "reputations")
    
    if mainFrame.searchArea then
        if isSearchTab then
            mainFrame.searchArea:Show()
            
            -- Reposition scroll below searchArea
            mainFrame.scroll:ClearAllPoints()
            mainFrame.scroll:SetPoint("TOPLEFT", mainFrame.searchArea, "BOTTOMLEFT", 0, 0)
            mainFrame.scroll:SetPoint("BOTTOMRIGHT", mainFrame.content, "BOTTOMRIGHT", -24, 4)
            
            -- Create persistent search boxes (only once)
            if not mainFrame.persistentSearchBoxes then
                mainFrame.persistentSearchBoxes = {}
                
                local CreateSearchBox = ns.UI_CreateSearchBox
                
                -- Items search box (responsive width)
                local itemsSearch, itemsClear = CreateSearchBox(
                    mainFrame.searchArea,
                    10,  -- Dummy width, will be set with anchors
                    "Search items...",
                    function(searchText)
                        ns.itemsSearchText = searchText
                        self:PopulateContent()
                    end,
                    0.4
                )
                itemsSearch:ClearAllPoints()
                itemsSearch:SetPoint("TOPLEFT", 10, -8)
                itemsSearch:SetPoint("TOPRIGHT", -10, -8)  -- Responsive
                itemsSearch:Hide()
                mainFrame.persistentSearchBoxes.items = itemsSearch
                
                -- Storage search box (responsive width)
                local storageSearch, storageClear = CreateSearchBox(
                    mainFrame.searchArea,
                    10,  -- Dummy width, will be set with anchors
                    "Search storage...",
                    function(searchText)
                        ns.storageSearchText = searchText
                        self:PopulateContent()
                    end,
                    0.4
                )
                storageSearch:ClearAllPoints()
                storageSearch:SetPoint("TOPLEFT", 10, -8)
                storageSearch:SetPoint("TOPRIGHT", -10, -8)  -- Responsive
                storageSearch:Hide()
                mainFrame.persistentSearchBoxes.storage = storageSearch
                
                -- Currency search box (responsive width)
                local currencySearch, currencyClear = CreateSearchBox(
                    mainFrame.searchArea,
                    10,  -- Dummy width, will be set with anchors
                    "Search currencies...",
                    function(searchText)
                        ns.currencySearchText = searchText
                        self:PopulateContent()
                    end,
                    0.4
                )
                currencySearch:ClearAllPoints()
                currencySearch:SetPoint("TOPLEFT", 10, -8)
                currencySearch:SetPoint("TOPRIGHT", -10, -8)  -- Responsive
                currencySearch:Hide()
                mainFrame.persistentSearchBoxes.currency = currencySearch
                
                -- Reputation search box (responsive width)
                local reputationSearch, reputationClear = CreateSearchBox(
                    mainFrame.searchArea,
                    10,  -- Dummy width, will be set with anchors
                    "Search reputations...",
                    function(searchText)
                        ns.reputationSearchText = searchText
                        self:PopulateContent()
                    end,
                    0.4
                )
                reputationSearch:ClearAllPoints()
                reputationSearch:SetPoint("TOPLEFT", 10, -8)
                reputationSearch:SetPoint("TOPRIGHT", -10, -8)  -- Responsive
                reputationSearch:Hide()
                mainFrame.persistentSearchBoxes.reputations = reputationSearch
            end
            
            -- Show appropriate search box
            if mainFrame.currentTab == "items" then
                mainFrame.persistentSearchBoxes.items:Show()
                mainFrame.persistentSearchBoxes.storage:Hide()
                mainFrame.persistentSearchBoxes.currency:Hide()
                mainFrame.persistentSearchBoxes.reputations:Hide()
            elseif mainFrame.currentTab == "storage" then
                mainFrame.persistentSearchBoxes.items:Hide()
                mainFrame.persistentSearchBoxes.storage:Show()
                mainFrame.persistentSearchBoxes.currency:Hide()
                mainFrame.persistentSearchBoxes.reputations:Hide()
            elseif mainFrame.currentTab == "currency" then
                mainFrame.persistentSearchBoxes.items:Hide()
                mainFrame.persistentSearchBoxes.storage:Hide()
                mainFrame.persistentSearchBoxes.currency:Show()
                mainFrame.persistentSearchBoxes.reputations:Hide()
            else -- reputations
                mainFrame.persistentSearchBoxes.items:Hide()
                mainFrame.persistentSearchBoxes.storage:Hide()
                mainFrame.persistentSearchBoxes.currency:Hide()
                mainFrame.persistentSearchBoxes.reputations:Show()
            end
        else
            mainFrame.searchArea:Hide()
            
            -- Reposition scroll at top
            mainFrame.scroll:ClearAllPoints()
            mainFrame.scroll:SetPoint("TOPLEFT", mainFrame.content, "TOPLEFT", 0, 0)
            mainFrame.scroll:SetPoint("BOTTOMRIGHT", mainFrame.content, "BOTTOMRIGHT", -24, 4)
            
            -- Hide all search boxes
            if mainFrame.persistentSearchBoxes then
                mainFrame.persistentSearchBoxes.items:Hide()
                mainFrame.persistentSearchBoxes.storage:Hide()
                mainFrame.persistentSearchBoxes.currency:Hide()
                mainFrame.persistentSearchBoxes.reputations:Hide()
            end
        end
    end
    
    -- Draw based on current tab (search boxes are now in persistent searchArea!)
    local height
    if mainFrame.currentTab == "chars" then
        height = self:DrawCharacterList(scrollChild)
    elseif mainFrame.currentTab == "exp" then
        height = self:DrawExperienceList(scrollChild)
    elseif mainFrame.currentTab == "guild" then
        height = self:DrawGuildSummaryList(scrollChild)
    elseif mainFrame.currentTab == "currency" then
        height = self:DrawCurrencyTab(scrollChild)
    elseif mainFrame.currentTab == "items" then
        height = self:DrawItemList(scrollChild)
    elseif mainFrame.currentTab == "storage" then
        height = self:DrawStorageTab(scrollChild)
    elseif mainFrame.currentTab == "pve" then
        height = self:DrawPvEProgress(scrollChild)
    elseif mainFrame.currentTab == "reputations" then
        height = self:DrawReputationTab(scrollChild)
    elseif mainFrame.currentTab == "stats" then
        height = self:DrawStatistics(scrollChild)
    else
        height = self:DrawCharacterList(scrollChild)
    end
    
    scrollChild:SetHeight(math.max(height, mainFrame.scroll:GetHeight()))

    -- Ensure the scroll position is always within valid bounds.
    -- Occasionally the vertical scroll can end up outside the valid range when content height changes
    -- (e.g., switching views/tabs quickly or expanding/collapsing sections), which can produce large blank areas.
    if mainFrame.scroll then
        local scroll = mainFrame.scroll
        if scroll.UpdateScrollChildRect then
            scroll:UpdateScrollChildRect()
        end
        local maxScroll = math.max(0, (scrollChild:GetHeight() or 0) - (scroll:GetHeight() or 0))
        local curScroll = scroll:GetVerticalScroll() or 0
        if curScroll < 0 then
            scroll:SetVerticalScroll(0)
        elseif curScroll > maxScroll then
            scroll:SetVerticalScroll(maxScroll)
        end
    end
    self:UpdateFooter()
end

--============================================================================
-- UPDATE STATUS
--============================================================================
function TheQuartermaster:UpdateStatus()
    if not mainFrame then return end

    -- Status badge removed: bank/warband are view-only now, so LIVE/CACHED status is no longer meaningful.
    -- Keep button state updates (Classic Bank visibility, etc.).
    self:UpdateButtonStates()
end

--============================================================================
-- UPDATE BUTTON STATES
--============================================================================
function TheQuartermaster:UpdateButtonStates()
    if not mainFrame then return end
    
    local bankOpen = self.bankIsOpen
    
    -- Footer buttons (Scan and Sort removed - not needed)
    
    if mainFrame.classicBtn then
        -- Only show Classic Bank button if bank module is enabled
        if self.db.profile.bankModuleEnabled then
            mainFrame.classicBtn:Show()
            mainFrame.classicBtn:SetEnabled(true)
            mainFrame.classicBtn:SetAlpha(1)
        else
            -- Hide when bank module disabled (user is using another addon)
            mainFrame.classicBtn:Hide()
        end
    end

    -- Keep footer icon placement correct when Classic Bank visibility changes
    if mainFrame.UpdateFooterIconLayout then
        mainFrame.UpdateFooterIconLayout()
    end
end

--============================================================================
-- UPDATE FOOTER
--============================================================================
function TheQuartermaster:UpdateFooter()
    if not mainFrame or not mainFrame.footerText then return end
    
    local stats = self:GetBankStatistics()
    local wbCount = stats.warband and stats.warband.itemCount or 0
    local pbCount = stats.personal and stats.personal.itemCount or 0
    local totalCount = wbCount + pbCount
    
    
    -- Update "Up-to-Date" status indicator (next to Scan button)
    if mainFrame.scanStatus then
        local wbScan = stats.warband and stats.warband.lastScan or 0
        local pbScan = stats.personal and stats.personal.lastScan or 0
        local lastScan = math.max(wbScan, pbScan)
        
        -- Check if recently scanned (within 60 seconds while bank is open)
        local isUpToDate = self.bankIsOpen and lastScan > 0 and (time() - lastScan < 60)
        if isUpToDate then
            mainFrame.scanStatus:SetText(L["CFF00FF00UP_TO_DATE_R"])
        elseif lastScan > 0 then
            local scanText = date("%m/%d %H:%M", lastScan)
            mainFrame.scanStatus:SetText("|cffaaaaaa" .. scanText .. "|r")
        else
            mainFrame.scanStatus:SetText(L["CFFFF6600NEVER_SCANNED_R"])
        end
    end
end

--============================================================================
-- DRAW ITEM LIST
--============================================================================
-- Track which bank type is selected in Items tab
-- DEFAULT: Personal Bank (priority over Warband)
local currentItemsSubTab = "personal"  -- "personal" or "warband"

-- Setter for currentItemsSubTab (called from Core.lua)
function TheQuartermaster:SetItemsSubTab(subTab)
    if subTab == "warband" or subTab == "personal" or subTab == "guild" then
        currentItemsSubTab = subTab
    end
end

function TheQuartermaster:GetItemsSubTab()
    return currentItemsSubTab
end

-- Track expanded state for each category (persists across refreshes)
local expandedGroups = {} -- Used by ItemsUI for group expansion state

--============================================================================
-- TAB DRAWING FUNCTIONS (All moved to separate modules)
--============================================================================
-- DrawCharacterList moved to Modules/UI/QM_CharactersQM_UI.lua
-- DrawItemList moved to Modules/UI/QM_ItemsQM_UI.lua
-- DrawEmptyState moved to Modules/UI/QM_ItemsQM_UI.lua
-- DrawStorageTab moved to Modules/UI/QM_StorageQM_UI.lua
-- DrawPvEProgress moved to Modules/UI/QM_PvEQM_UI.lua
-- DrawStatistics moved to Modules/UI/QM_StatisticsQM_UI.lua


--============================================================================
-- REFRESH
--============================================================================
--============================================================================
-- HELPER: SYNC WOW BANK TAB
-- Forces WoW's BankFrame to match our Addon's selected tab
-- This is CRITICAL for right-click item deposits to go to correct bank!
--============================================================================
function TheQuartermaster:SyncBankTab()
    -- Don't sync if bank module is disabled
    if not self.db.profile.bankModuleEnabled then
        return
    end
    
    -- Don't sync classic UI tabs if user chose to use another addon
    if self:IsUsingOtherBankAddon() then
        return
    end
    
    -- CRITICAL FIX: Use namespace getter instead of local variable
    local currentSubTab = ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() or "warband"
    
    -- Guild Bank handling (separate from Personal/Warband)
    if currentSubTab == "guild" then
        if not self.guildBankIsOpen then
            -- Silently skip if guild bank not open
            return
        end
        
        -- Guild Bank doesn't need tab syncing (we're not changing GuildBankFrame tabs)
        -- Guild Bank tabs are managed internally by WoW's GuildBankFrame
        -- We just display the data in our UI
        return
    end
    
    -- Personal/Warband Bank handling
    if not self.bankIsOpen then 
        -- Silently skip if bank not open (don't spam logs)
        return 
    end

    local status, err = pcall(function()
        if not BankFrame then 
            return 
        end
        
        -- TWW Tab System:
        -- characterBankTabID = 1 (Personal Bank)
        -- accountBankTabID = 2 (Warband Bank)
        -- Use BankFrame:SetTab(tabID) to switch
        
        local targetTabID
        if currentSubTab == "warband" then
            targetTabID = BankFrame.accountBankTabID or 2
        else
            targetTabID = BankFrame.characterBankTabID or 1
        end
        
        -- Primary method: Use SetTab function
        if BankFrame.SetTab then
            BankFrame:SetTab(targetTabID)
            return
        end
        
        -- Fallback: Try SelectDefaultTab
        if BankFrame.SelectDefaultTab then
            BankFrame:SelectDefaultTab(targetTabID)
            return
        end
        
        -- Fallback: Try GetTabButton and click it
        if BankFrame.GetTabButton then
            local tabButton = BankFrame:GetTabButton(targetTabID)
            if tabButton and tabButton.Click then
                tabButton:Click()
                return
            end
        end
    end)
    
    -- Silently handle errors
end

-- Debug function to dump BankFrame structure
function TheQuartermaster:DumpBankFrameInfo()
    self:Print("=== BankFrame Debug Info ===")
    
    if not BankFrame then
        self:Print("BankFrame is nil!")
        return
    end
    
    self:Print("BankFrame exists: " .. tostring(BankFrame:GetName()))
    self:Print("BankFrame:IsShown(): " .. tostring(BankFrame:IsShown()))
    
    -- Check for known properties
    local props = {"selectedTab", "activeTabIndex", "TabSystem", "Tabs", "AccountBankTab", "CharacterBankTab", "BankTab", "WarbandBankTab"}
    for _, prop in ipairs(props) do
        self:Print("  BankFrame." .. prop .. " = " .. tostring(BankFrame[prop]))
    end
    
    -- List children
    self:Print("Children:")
    for i, child in ipairs({BankFrame:GetChildren()}) do
        local name = child:GetName() or "(unnamed)"
        local objType = child:GetObjectType()
        local shown = child:IsShown() and "shown" or "hidden"
        self:Print("  " .. i .. ": " .. name .. " [" .. objType .. "] " .. shown)
    end
    
    -- Check global tab references
    self:Print("Global Tab References:")
    for i = 1, 5 do
        local tabName = "BankFrameTab" .. i
        local tab = _G[tabName]
        if tab then
            self:Print("  " .. tabName .. " exists, shown=" .. tostring(tab:IsShown()))
        else
            self:Print("  " .. tabName .. " = nil")
        end
    end
    
    self:Print("============================")
end

-- Throttled refresh to prevent spam
local lastRefreshTime = 0
local REFRESH_THROTTLE = 0.03 -- Ultra-fast refresh (30ms minimum between updates)

function TheQuartermaster:RefreshUI()
    -- Throttle rapid refresh calls
    local now = GetTime()
    if (now - lastRefreshTime) < REFRESH_THROTTLE then
        -- Schedule a delayed refresh instead
        if not self.pendingRefresh then
            self.pendingRefresh = true
            C_Timer.After(REFRESH_THROTTLE, function()
                self.pendingRefresh = false
                TheQuartermaster:RefreshUI()
            end)
        end
        return
    end
    lastRefreshTime = now
    
    if mainFrame and mainFrame:IsShown() then
        self:PopulateContent()
        self:SyncBankTab()
    end
end

function TheQuartermaster:RefreshMainWindow() self:RefreshUI() end
function TheQuartermaster:RefreshMainWindowContent() self:RefreshUI() end
function TheQuartermaster:ShowDepositQueueUI() self:Print("Coming soon!") end
function TheQuartermaster:RefreshDepositQueueUI() end


-- Re-bind sidebar action handlers (ensure clicks work after re-anchoring)
if infoNav then
    infoNav:SetScript("OnClick", function()
    if TheQuartermaster and TheQuartermaster.ShowInfoDialog then
        TheQuartermaster:ShowInfoDialog()
    end
end)
end

if settingsNav then
    settingsNav:SetScript("OnClick", function()
    if TheQuartermaster and TheQuartermaster.OpenOptions then
        TheQuartermaster:OpenOptions()
    end
end)
end
