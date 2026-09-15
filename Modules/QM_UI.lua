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
local DEFAULT_WIDTH = 1200
local DEFAULT_HEIGHT = 680
-- Minimum size must account for the widest tab content (Characters has multiple
-- columns and long names). We clamp both during resize *and* on load so a saved
-- too-small size can't break the layout.
local MIN_WIDTH = 1200
local MIN_HEIGHT = 680
local ROW_HEIGHT = 26
local DEFAULT_SCALE = 1.0
local MIN_SCALE = 0.70
local MAX_SCALE = 1.15


local mainFrame = nil
local goldTransferFrame = nil
local currentTab = "stats" -- Default to Characters tab
local currentItemsSubTab = "inventory" -- Default to Inventory
local expandedGroups = {} -- Persisted expand/collapse state for item groups

-- ------------------------------------------------------------
-- Search focus preservation
-- Many panels rebuild their content frequently (filters, pin changes, refresh timers).
-- Without explicitly restoring keyboard focus, EditBoxes can lose focus while typing.
-- ------------------------------------------------------------
function TheQuartermaster:CaptureSearchFocus()
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() or nil
    if not focus or not focus.GetObjectType then
        self._qmSearchFocus = nil
        return
    end

    if focus:GetObjectType() ~= "EditBox" then
        self._qmSearchFocus = nil
        return
    end

    local cursor = 0
    if focus.GetCursorPosition then
        cursor = focus:GetCursorPosition() or 0
    end

    self._qmSearchFocus = {
        editBox = focus,
        cursor = cursor,
    }
end

function TheQuartermaster:RestoreSearchFocus()
    local info = self._qmSearchFocus
    if not info or not info.editBox then return end

    local eb = info.editBox
    if not eb.IsShown or not eb:IsShown() then return end
    if eb.SetFocus then
        eb:SetFocus()
        if eb.SetCursorPosition then
            eb:SetCursorPosition(info.cursor or 0)
        end
    end
end

-- Search text state (exposed to namespace for sub-modules to access directly)
ns.itemsSearchText = ""
ns.storageSearchText = ""
ns.currencySearchText = ""
ns.reputationSearchText = ""
ns.globalSearchText = ""
ns.globalSearchMode = "all"
ns.globalSearchIncludeGuild = nil

-- Namespace exports for state management (used by sub-modules)
ns.UI_GetItemsSubTab = function() return currentItemsSubTab end
ns.UI_ResetItemsPresentation = function()
    for key in pairs(expandedGroups) do expandedGroups[key] = nil end
    local profile = TheQuartermaster.db and TheQuartermaster.db.profile
    if profile then
        for _, key in ipairs({"inventoryViewMode", "personalBankViewMode", "warbandBankViewMode", "guildBankViewMode"}) do
            profile[key] = "list"
        end
    end
end
ns.UI_SetItemsSubTab = function(val)
    ns.UI_ResetItemsPresentation()
    currentItemsSubTab = val
    -- Only sync the WoW BankFrame tab when switching to bank-backed views
    -- (Inventory is view-only and should not force bank tab sync.)
    if TheQuartermaster and TheQuartermaster.SyncBankTab and TheQuartermaster.bankIsOpen then
        if val == "personal" or val == "warband" or val == "guild" then
            TheQuartermaster:SyncBankTab()
        end
    end

    -- If the guild bank view is selected while the GuildBankFrame is open,
    -- trigger a scan so the cache populates even when auto-scan is disabled.
    if val == "guild" and TheQuartermaster and TheQuartermaster.guildBankIsOpen and TheQuartermaster.ScanGuildBank then
        -- Delay slightly so tab data has time to populate.
        C_Timer.After(0.2, function()
            if TheQuartermaster and TheQuartermaster.guildBankIsOpen and TheQuartermaster.ScanGuildBank then
                TheQuartermaster:ScanGuildBank()
            end
        end)
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

function TheQuartermaster:ApplyWindowScale(scale)
    if not mainFrame then return end

    local value = tonumber(scale) or DEFAULT_SCALE
    if value < MIN_SCALE then value = MIN_SCALE end
    if value > MAX_SCALE then value = MAX_SCALE end

    mainFrame:SetScale(value)

    if self.db and self.db.profile then
        self.db.profile.uiScale = value
    end

    if mainFrame.scaleValueText then
        mainFrame.scaleValueText:SetText(string.format("%.0f%%", value * 100))
    end
    if mainFrame.scaleSlider and math.abs((mainFrame.scaleSlider:GetValue() or value) - value) > 0.0001 then
        mainFrame.scaleSlider:SetValue(value)
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
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
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

    local savedScale = self.db and self.db.profile and self.db.profile.uiScale or DEFAULT_SCALE
    if type(savedScale) ~= "number" then savedScale = DEFAULT_SCALE end
    if savedScale < MIN_SCALE then savedScale = MIN_SCALE end
    if savedScale > MAX_SCALE then savedScale = MAX_SCALE end
    f:SetScale(savedScale)

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

    -- Title
    local title = header:CreateFontString(nil, "OVERLAY", "QuartermasterFontHeading")
    title:SetPoint("LEFT", 30, 0)
    local titleAccent = header:CreateTexture(nil, "ARTWORK")
    titleAccent:SetSize(6, 6)
    titleAccent:SetPoint("RIGHT", title, "LEFT", -10, 0)
    titleAccent:SetColorTexture(unpack(COLORS.accent))
    title:SetText(L["CFFFFFFFFTHE_QUARTERMASTER_R"])  -- Always white
    title:SetFontObject("QuartermasterFontTitle")
    title:SetTextColor(unpack(COLORS.textNormal))
    f.title = title  -- Store reference (but don't change color)
    
    -- Status badge removed: bank/warband are view-only now, so LIVE/CACHED status is no longer meaningful.
    f.statusBadge = nil
    f.statusText = nil
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(30, 30)
    closeBtn:SetPoint("RIGHT", -8, 0)
    local closeGlyph = closeBtn:CreateFontString(nil, "OVERLAY", "QuartermasterFontClose")
    closeGlyph:SetPoint("CENTER")
    closeGlyph:SetText("×")
    closeBtn:SetScript("OnEnter", function() closeGlyph:SetTextColor(unpack(COLORS.red)) end)
    closeBtn:SetScript("OnLeave", function() closeGlyph:SetTextColor(unpack(COLORS.textNormal)) end)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Discretion Mode (privacy) toggle - header top-right
    local discretionCB = CreateFrame("CheckButton", nil, header, "BackdropTemplate")
    discretionCB:SetSize(18, 18)
    discretionCB:SetPoint("RIGHT", closeBtn, "LEFT", -18, 0)
    discretionCB:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    discretionCB:SetBackdropColor(unpack(COLORS.bgCard))
    discretionCB:SetBackdropBorderColor(unpack(COLORS.border))
    local discretionMark = discretionCB:CreateTexture(nil, "ARTWORK")
    discretionMark:SetPoint("TOPLEFT", 4, -4)
    discretionMark:SetPoint("BOTTOMRIGHT", -4, 4)
    discretionMark:SetColorTexture(unpack(COLORS.accent))
    discretionCB:SetCheckedTexture(discretionMark)
    discretionCB:SetChecked(TheQuartermaster.db and TheQuartermaster.db.profile and TheQuartermaster.db.profile.discretionMode)

    local discretionLabel = header:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
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
		local tr, tg, tb = 1, 1, 1
		if brightness > 0.6 then
			tr, tg, tb = 0.1, 0.1, 0.1
		end
		discretionLabel:SetTextColor(tr, tg, tb, 0.95)
		if f and f.scaleLabel then
			f.scaleLabel:SetTextColor(unpack(COLORS.textDim))
		end
		if f and f.scaleValueText then
			f.scaleValueText:SetTextColor(unpack(COLORS.textNormal))
		end
	end
	ApplyDiscretionLabelColor()
    discretionLabel:SetPoint("RIGHT", discretionCB, "LEFT", -6, 0)

    -- Window scale slider
    local scaleSlider = CreateFrame("Slider", nil, f)
    scaleSlider:SetSize(140, 18)
    scaleSlider:SetOrientation("HORIZONTAL")
    scaleSlider:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -75, 13)
    local scaleRail = scaleSlider:CreateTexture(nil, "BACKGROUND")
    scaleRail:SetHeight(4)
    scaleRail:SetPoint("LEFT")
    scaleRail:SetPoint("RIGHT")
    scaleRail:SetColorTexture(unpack(COLORS.border))
    local scaleThumb = scaleSlider:CreateTexture(nil, "ARTWORK")
    scaleThumb:SetSize(10, 16)
    scaleThumb:SetColorTexture(unpack(COLORS.accent))
    scaleSlider:SetThumbTexture(scaleThumb)
    scaleSlider:SetMinMaxValues(MIN_SCALE, MAX_SCALE)
    scaleSlider:SetValueStep(0.05)
    scaleSlider:SetObeyStepOnDrag(true)
    scaleSlider:SetValue(savedScale)

    local scaleLabel = f:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
    scaleLabel:SetPoint("RIGHT", scaleSlider, "LEFT", -8, 0)
    scaleLabel:SetText(L.MAIN_SCALE)
    scaleLabel:SetTextColor(unpack(COLORS.textDim))

    local scaleValueText = f:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
    scaleValueText:SetPoint("LEFT", scaleSlider, "RIGHT", 10, 0)
    scaleValueText:SetText(string.format("%.0f%%", savedScale * 100))
    scaleValueText:SetTextColor(unpack(COLORS.textNormal))

    local function NormalizeScaleValue(value)
        local stepped = math.floor((value / 0.05) + 0.5) * 0.05
        if stepped < MIN_SCALE then stepped = MIN_SCALE end
        if stepped > MAX_SCALE then stepped = MAX_SCALE end
        return stepped
    end

    local function UpdateScalePreview(value)
        local stepped = NormalizeScaleValue(value)
        if math.abs((scaleSlider:GetValue() or stepped) - stepped) > 0.0001 then
            scaleSlider:SetValue(stepped)
            return nil
        end
        if scaleValueText then
            scaleValueText:SetText(string.format("%.0f%%", stepped * 100))
        end
        scaleSlider.pendingScaleValue = stepped
        return stepped
    end

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        UpdateScalePreview(value)
    end)

    scaleSlider:SetScript("OnMouseUp", function(self)
        local stepped = self.pendingScaleValue or NormalizeScaleValue(self:GetValue())
        TheQuartermaster:ApplyWindowScale(stepped)
    end)
    scaleSlider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.CFG_WINDOW_SCALE)
        GameTooltip:AddLine(L.CFG_WINDOW_SCALE_DESC, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    scaleSlider:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.scaleSlider = scaleSlider
    f.scaleValueText = scaleValueText

	-- Store references so the shared colour refresh can update the label when themes change
	f.discretionLabel = discretionLabel
	f.scaleLabel = scaleLabel
	f.scaleValueText = scaleValueText
	f.ApplyDiscretionLabelColor = ApplyDiscretionLabelColor

    discretionCB:SetScript("OnClick", function(self)
        if TheQuartermaster.db and TheQuartermaster.db.profile then
            TheQuartermaster.db.profile.discretionMode = self:GetChecked() and true or false
        end
        TheQuartermaster:PopulateContent()
    end)
    discretionCB:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(COLORS.accent))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["DISCRETION_MODE"])
        GameTooltip:AddLine(L.MAIN_DISCRETION_HELP, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    discretionCB:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(COLORS.border))
        GameTooltip:Hide()
    end)
    
    tinsert(UISpecialFrames, "TheQuartermasterFrame")
    
    -- ===== NAV SIDEBAR =====
    -- Sidebar navigation (distinct from other addons' top-tab layout)
    local nav = CreateFrame("Frame", nil, f, "BackdropTemplate")
    nav:SetWidth(ns.Theme.layout.sidebarWidth)
    nav:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 8, -8)
    nav:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 45)
    nav:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8"})
    nav:SetBackdropColor(unpack(COLORS.bgCard))
    f.nav = nav
    f.currentTab = "stats" -- Start with Characters tab
    f.tabButtons = {}
    
    -- Selected navigation uses a left marker; hover only raises the surface.
    local function CreateTabButton(parent, text, key, yOffset)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetHeight(ns.Theme.layout.navHeight)
        btn:SetPoint("TOPLEFT", 0, -yOffset)
        btn:SetPoint("TOPRIGHT", 0, -yOffset)
        btn.key = key
        btn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
        btn:SetBackdropColor(unpack(COLORS.tabInactive))
        local activeBar = btn:CreateTexture(nil, "OVERLAY")
        activeBar:SetWidth(2)
        activeBar:SetPoint("TOPLEFT")
        activeBar:SetPoint("BOTTOMLEFT")
        activeBar:SetColorTexture(unpack(COLORS.accent))
        activeBar:SetAlpha(0)
        btn.activeBar = activeBar
        local label = btn:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
        label:SetPoint("LEFT", 12, 0)
        label:SetPoint("RIGHT", -8, 0)
        label:SetJustifyH("LEFT")
        label:SetText(text)
        label:SetTextColor(unpack(COLORS.textNormal))
        btn.label = label
        btn:SetScript("OnEnter", function(self)
            if not self.active then self:SetBackdropColor(unpack(COLORS.tabHover)) end
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(unpack(self.active and COLORS.tabActive or COLORS.tabInactive))
        end)
        btn:SetScript("OnClick", function(self)
            f.currentTab = self.key
            TheQuartermaster:PopulateContent()
        end)
        return btn
    end

    ns.UI_CreateGroupedNavigation(f, CreateTabButton)

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

-- Addon identity sits in the open sidebar space above its utility actions.
local sidebarLogo = nav:CreateTexture(nil, "ARTWORK")
sidebarLogo:SetSize(112, 112)
sidebarLogo:SetAlpha(0.5)
-- Additive blending makes the icon's black matte disappear into the sidebar.
sidebarLogo:SetBlendMode("ADD")
sidebarLogo:SetPoint("BOTTOM", infoNav, "TOP", 0, 24)
sidebarLogo:SetTexture("Interface\\AddOns\\TheQuartermaster\\Media\\icon")

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
        edgeSize = 2,
    })
    content:SetBackdropColor(unpack(COLORS.bg))
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
    ns.UI_ThemeScrollBar(scroll)
    
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
    
    local footerText = footer:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
    footerText:SetPoint("LEFT", 5, 0)
    footerText:SetTextColor(unpack(COLORS.textDim))
    f.footerText = footerText
    ns.UI_CreateDataCoverage(f, footer)
    
    -- Action buttons (right side)
    -- Note: Button states are updated in UpdateButtonStates()
    
    local classicBtn = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate, BackdropTemplate")
    classicBtn:SetSize(90, 24)
    classicBtn:SetPoint("RIGHT", scaleLabel, "LEFT", -16, 0)
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
            edgeSize = 2,
        })
        classicBtn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
        classicBtn:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)
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
            self:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)
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
    
    ns.UI_UpdateGroupedNavigation(mainFrame)

    -- Show/hide searchArea and create persistent search boxes
    local isSearchTab = (mainFrame.currentTab == "items" or mainFrame.currentTab == "materials" or mainFrame.currentTab == "recipes" or mainFrame.currentTab == "storage" or mainFrame.currentTab == "currency" or mainFrame.currentTab == "reputations" or mainFrame.currentTab == "search")
    
    if ns.Comparison.Domain(mainFrame.currentTab)=="professions" and ns.Comparison.Settings(self,"professions").enabled then isSearchTab=false end
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
                        self:RefreshUI()
                    end,
                    0.4
                )
                itemsSearch:ClearAllPoints()
                itemsSearch:SetPoint("TOPLEFT", 10, -8)
                itemsSearch:SetPoint("TOPRIGHT", -10, -8)  -- Responsive
                itemsSearch:Hide()
                mainFrame.persistentSearchBoxes.items = itemsSearch

                -- Materials search box (responsive width)
                local materialsSearch, materialsClear = CreateSearchBox(
                    mainFrame.searchArea,
                    10,
                    "Search materials...",
                    function(searchText)
                        ns.materialsSearchText = searchText
                        self:RefreshUI()
                    end,
                    0.4
                )
                materialsSearch:ClearAllPoints()
                materialsSearch:SetPoint("TOPLEFT", 10, -8)
                materialsSearch:SetPoint("TOPRIGHT", -10, -8)
                materialsSearch:Hide()
                mainFrame.persistentSearchBoxes.materials = materialsSearch

                -- Recipes search box
                local recipesSearch, recipesClear = CreateSearchBox(
                    mainFrame.searchArea,
                    10,
                    "Search recipes...",
                    function(searchText)
                        ns.recipesSearchText = searchText or ""
                        self:RefreshUI()
                    end,
                    0.4
                )
                recipesSearch:ClearAllPoints()
                recipesSearch:SetPoint("TOPLEFT", 10, -8)
                recipesSearch:SetPoint("TOPRIGHT", -10, -8)
                recipesSearch:Hide()
                mainFrame.persistentSearchBoxes.recipes = recipesSearch

                
                -- Storage search box (responsive width)
                local storageSearch, storageClear = CreateSearchBox(
                    mainFrame.searchArea,
                    10,  -- Dummy width, will be set with anchors
                    "Search storage...",
                    function(searchText)
                        ns.storageSearchText = searchText
                        self:RefreshUI()
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
                        self:RefreshUI()
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
                        self:RefreshUI()
                    end,
                    0.4
                )
                reputationSearch:ClearAllPoints()
                reputationSearch:SetPoint("TOPLEFT", 10, -8)
                reputationSearch:SetPoint("TOPRIGHT", -10, -8)  -- Responsive
                reputationSearch:Hide()
                mainFrame.persistentSearchBoxes.reputations = reputationSearch

-- Global Search box (for Search tab)
local globalSearch, globalClear = CreateSearchBox(
    mainFrame.searchArea,
    10,
    "Search items or currency...",
    function(searchText)
        ns.globalSearchText = searchText or ""
        self:RefreshUI()
    end,
    0.4
)
globalSearch:ClearAllPoints()
globalSearch:SetPoint("TOPLEFT", 10, -8)
globalSearch:SetPoint("TOPRIGHT", -10, -8)
globalSearch:Hide()
mainFrame.persistentSearchBoxes.global = globalSearch

            end
            
            -- Show appropriate search box
            if mainFrame._lastSearchTab ~= mainFrame.currentTab then
                -- (Always hide everything first, then show the relevant one)
                mainFrame.persistentSearchBoxes.items:Hide()
                if mainFrame.persistentSearchBoxes.materials then mainFrame.persistentSearchBoxes.materials:Hide() end
                if mainFrame.persistentSearchBoxes.recipes then mainFrame.persistentSearchBoxes.recipes:Hide() end
                mainFrame.persistentSearchBoxes.storage:Hide()
                mainFrame.persistentSearchBoxes.currency:Hide()
                mainFrame.persistentSearchBoxes.reputations:Hide()
                if mainFrame.persistentSearchBoxes.global then mainFrame.persistentSearchBoxes.global:Hide() end
    
                if mainFrame.currentTab == "items" then
                    mainFrame.persistentSearchBoxes.items:Show()
                elseif mainFrame.currentTab == "materials" then
                    if mainFrame.persistentSearchBoxes.materials then mainFrame.persistentSearchBoxes.materials:Show() end
                elseif mainFrame.currentTab == "recipes" then
                    if mainFrame.persistentSearchBoxes.recipes then mainFrame.persistentSearchBoxes.recipes:Show() end
                elseif mainFrame.currentTab == "storage" then
                    mainFrame.persistentSearchBoxes.storage:Show()
                elseif mainFrame.currentTab == "currency" then
                    mainFrame.persistentSearchBoxes.currency:Show()
                elseif mainFrame.currentTab == "search" then
                    if mainFrame.persistentSearchBoxes.global then mainFrame.persistentSearchBoxes.global:Show() end
                else -- reputations
                    mainFrame.persistentSearchBoxes.reputations:Show()
                end
                mainFrame._lastSearchTab = mainFrame.currentTab
            end
        else
            if mainFrame._lastSearchTab then
                for _, box in pairs(mainFrame.persistentSearchBoxes) do box:Hide() end
                mainFrame._lastSearchTab = nil
            end
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
                if mainFrame.persistentSearchBoxes.materials then mainFrame.persistentSearchBoxes.materials:Hide() end
                if mainFrame.persistentSearchBoxes.recipes then mainFrame.persistentSearchBoxes.recipes:Hide() end
                if mainFrame.persistentSearchBoxes.global then mainFrame.persistentSearchBoxes.global:Hide() end
            end
        end
    end
    
    -- Draw based on current tab (search boxes are now in persistent searchArea!)
    local height
    local comparisonDomain=ns.Comparison.Domain(mainFrame.currentTab)
    if comparisonDomain and ns.Comparison.Settings(self,comparisonDomain).enabled then
        height=self:DrawComparison(scrollChild,comparisonDomain)
    elseif mainFrame.currentTab == "chars" then
        height = self:DrawCharacterList(scrollChild)
    elseif mainFrame.currentTab == "setup" then
        height = self:DrawSetupChecklist(scrollChild)
    elseif mainFrame.currentTab == "exp" then
        height = self:DrawExperienceList(scrollChild)
    elseif mainFrame.currentTab == "equip" then
        height = self:DrawEquipmentList(scrollChild)
    elseif mainFrame.currentTab == "profequip" then
        if self.DrawProfessionEquipmentList then
            height = self:DrawProfessionEquipmentList(scrollChild)
        else
            height = 200
        end
    elseif mainFrame.currentTab == "achievements" then
        height = self:DrawAchievements(scrollChild)
    elseif mainFrame.currentTab == "quests" then
        height = self:DrawQuestLogs(scrollChild)
    elseif mainFrame.currentTab == "knowledge" then
        height = self:DrawKnowledge(scrollChild)
    elseif mainFrame.currentTab == "cooldowns" then
        height = self:DrawProfessionCooldowns(scrollChild)
    elseif mainFrame.currentTab == "concentration" then
        height = self:DrawConcentration(scrollChild)
    elseif mainFrame.currentTab == "guild" then
        height = self:DrawGuildSummaryList(scrollChild)
    elseif mainFrame.currentTab == "currency" then
        height = self:DrawCurrencyTab(scrollChild)
    elseif mainFrame.currentTab == "search" then
        height = self:DrawGlobalSearch(scrollChild)
    elseif mainFrame.currentTab == "watchlist" then
        height = self:DrawWatchlist(scrollChild)
    elseif mainFrame.currentTab == "items" then
        height = self:DrawItemList(scrollChild)
    elseif mainFrame.currentTab == "materials" then
        height = self:DrawMaterialsTab(scrollChild)
    elseif mainFrame.currentTab == "recipes" then
        if self.DrawRecipesTab then
            height = self:DrawRecipesTab(scrollChild)
        else
            height = 200
        end
    elseif mainFrame.currentTab == "storage" then
        height = self:DrawStorageTab(scrollChild)
    elseif mainFrame.currentTab == "pve" then
        height = self:DrawPvEProgress(scrollChild)
    elseif mainFrame.currentTab == "reputations" then
        height = self:DrawReputationTab(scrollChild)
    elseif mainFrame.currentTab == "wealth" then
        height = self:DrawWealth(scrollChild)
    elseif mainFrame.currentTab == "auctions" then
        height = self:DrawAuctions(scrollChild)
    elseif mainFrame.currentTab == "stats" or mainFrame.currentTab == "totals" then
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
    ns.UI_UpdateDataCoverage(mainFrame)
    
    local stats = self:GetBankStatistics()
    local wbCount = stats.warband and stats.warband.itemCount or 0
    local pbCount = stats.personal and stats.personal.itemCount or 0
    local totalCount = wbCount + pbCount
    
    
    -- Update "Up-to-Date" status indicator (next to Scan button)
    if mainFrame.scanStatus then
        local source = (ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab()) or "personal"
        local data = stats[source]
        local lastScan = data and data.lastScan or 0
        local unavailable = self.scanStatus and self.scanStatus[source] == "unavailable"
        local open = (source == "guild" and self.guildBankIsOpen)
            or (source == "warband" and self:IsWarbandBankOpen())
            or (source == "personal" and self.bankIsOpen)
        local isUpToDate = source ~= "guild" and not unavailable and open and lastScan > 0 and (time() - lastScan < 60)
        if unavailable then
            mainFrame.scanStatus:SetText(L["SCAN_UNAVAILABLE_RETAINED"])
        elseif isUpToDate then
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
	-- Preserve search focus through refreshes so typing doesn't fall through to the game.
	if self.CaptureSearchFocus then
		self:CaptureSearchFocus()
	end
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

        -- Focus restoration for search boxes: certain module refreshes rebuild frames and can drop focus.
        -- SharedWidgets sets TheQuartermaster.UI._restoreSearchFocus and activeSearchBox while typing.
	        local ui = self.UI
	        local nowTime = GetTime and GetTime() or nil
	        local focusSticky = false
	        if ui and nowTime and ui._restoreSearchFocusUntil and nowTime < ui._restoreSearchFocusUntil then
	            focusSticky = true
	        end
	        if ui and (ui._restoreSearchFocus or focusSticky) and ui.activeSearchBox and ui.activeSearchBox.IsShown and ui.activeSearchBox:IsShown() then
            local eb = self.UI.activeSearchBox
            -- Only restore if the user isn't currently focusing another edit box.
            local currentFocus = GetFocus()
            if not currentFocus or currentFocus == eb then
                eb:SetFocus()
                if eb.GetText then
                    local t = eb:GetText() or ""
                    if eb.SetCursorPosition then
                        eb:SetCursorPosition(#t)
                    end
                end
            end
	            ui._restoreSearchFocus = nil
	            if ui._restoreSearchFocusUntil and nowTime and nowTime >= ui._restoreSearchFocusUntil then
	                ui._restoreSearchFocusUntil = nil
	            end
        end
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
