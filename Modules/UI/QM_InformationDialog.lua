--[[
    The Quartermaster - Information Dialog
    Displays addon information, features, and usage instructions
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

--[[
    Show Information Dialog
    Displays addon information, features, and usage instructions
]]
function TheQuartermaster:ShowInfoDialog()
    -- Get theme colors
    if ns.UI_RefreshColors then pcall(ns.UI_RefreshColors) end
    local COLORS = ns.UI_COLORS
    
    -- Create dialog frame (or reuse if exists)
    if self.infoDialog then
        self.infoDialog:Show()
        return
    end
    
    local dialog = CreateFrame("Frame", "TheQuartermasterInfoDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(500, 600)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(1000)
    dialog:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 16,
        edgeSize = 1,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    dialog:SetBackdropColor(unpack(COLORS.bg))
    dialog:SetBackdropBorderColor(unpack(COLORS.border))
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    self.infoDialog = dialog
    -- ===== HEADER BAR (match main frame styling in QM_UI.lua) =====
    local header = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
    header:SetHeight(40)
    header:SetPoint("TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", -4, -4)
    header:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
    })

    local hdr = (COLORS and COLORS.accentDark) or (COLORS and COLORS.accent) or {0.60, 0.10, 0.10}
    header:SetBackdropColor(hdr[1], hdr[2], hdr[3], 1)

    -- Icon (same as main frame header)
    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(24, 24)
    logo:SetPoint("LEFT", 15, 0)
    logo:SetTexture("Interface\\AddOns\\TheQuartermaster\\Media\\icon")

    -- Title (always white)
    local title = header:CreateFontString(nil, "OVERLAY", "QuartermasterFontHeading")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetJustifyH("LEFT")
    title:SetText((L and L["CFFFFFFFFTHE_QUARTERMASTER_R"]) or "The Quartermaster")
    title:SetTextColor(1, 1, 1, 1)

    -- Close button (match main frame)
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(30, 30)
    closeBtn:SetPoint("RIGHT", -8, 0)
    local closeGlyph = closeBtn:CreateFontString(nil, "OVERLAY", "QuartermasterFontClose")
    closeGlyph:SetPoint("CENTER"); closeGlyph:SetText("×")
    closeGlyph:SetTextColor(unpack(COLORS.textNormal))
    closeBtn:SetScript("OnEnter", function() closeGlyph:SetTextColor(unpack(COLORS.red)) end)
    closeBtn:SetScript("OnLeave", function() closeGlyph:SetTextColor(unpack(COLORS.textNormal)) end)
    closeBtn:SetScript("OnClick", function() dialog:Hide() end)

    -- Scroll Frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -30, 50)
    ns.UI_ThemeScrollBar(scrollFrame)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(450, 1) -- Height will be calculated
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Content
    local yOffset = 0
    local function AddText(text, fontObject, color, spacing, centered)
        local fs = scrollChild:CreateFontString(nil, "OVERLAY", fontObject or "QuartermasterFontBody")
        fs:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
        fs:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -yOffset)
        fs:SetJustifyH(centered and "CENTER" or "LEFT")
        fs:SetWordWrap(true)
        if color then
            fs:SetTextColor(color[1], color[2], color[3])
        end
        fs:SetText(text)
        yOffset = yOffset + fs:GetStringHeight() + (spacing or 12)
        return fs
    end
    
    AddText(L.INFO_WELCOME, "QuartermasterFontTitle", COLORS.textNormal, 8, true)

    -- Version line (safe metadata lookup)
    local addonVersion = "Unknown"
    if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
        addonVersion = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or addonVersion
    elseif type(GetAddOnMetadata) == "function" then
        addonVersion = GetAddOnMetadata(ADDON_NAME, "Version") or addonVersion
    end
    AddText(string.format(L.INFO_VERSION, tostring(addonVersion)), "QuartermasterFontSmall", {0.75, 0.75, 0.75}, 10)

    AddText(L.INFO_INTRO, "QuartermasterFontBody", COLORS.textNormal, 16)
    local sections = {
        {L.INFO_COLLECTION_TITLE, L.INFO_COLLECTION_BODY},
        {L.NAV_DASHBOARD, L.INFO_DASHBOARD_BODY},
        {L.NAV_CHARACTERS, L.INFO_CHARACTERS_BODY},
        {L.NAV_STORAGE, L.INFO_STORAGE_BODY},
        {L.NAV_PROFESSIONS, L.INFO_PROFESSIONS_BODY},
        {L.NAV_PROGRESSION, L.INFO_PROGRESSION_BODY},
        {L.NAV_ACCOUNT, L.INFO_TOTALS_BODY},
        {L.WL_TITLE, L.INFO_WEALTH_BODY},
        {L.AU_TITLE, L.AU_GUIDE .. " " .. L.AU_NOT_STOCK},
        {L.SEARCH_HEADER_TITLE, L.INFO_SEARCH_BODY},
        {L.NAV_WATCHLIST, L.INFO_WATCHLIST_BODY},
        {L.INFO_MAIL_TITLE, L.CFG_MAIL_REMINDERS},
        {L.INFO_DATA_TITLE, L.INFO_DATA_BODY},
        {L.INFO_HELP_TITLE, L.INFO_HELP_BODY},
    }
    for _, section in ipairs(sections) do
        AddText(section[1], "QuartermasterFontHeading", COLORS.accent, 8)
        AddText(section[2], "QuartermasterFontBody", COLORS.textNormal, 18)
    end

    -- Update scroll child height
    scrollChild:SetHeight(yOffset)
    
    -- OK Button (bottom center) - match Items "Slot View" themed action button
local okBtn = CreateFrame("Button", nil, dialog, "BackdropTemplate")
okBtn:SetSize(96, 24)
okBtn:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 15)

okBtn.text = okBtn:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
okBtn.text:SetPoint("CENTER")
okBtn.text:SetTextColor(1, 1, 1, 0.95)
okBtn.text:SetText(L.INFO_OK)

okBtn:SetBackdrop({
    bgFile = "Interface\\BUTTONS\\WHITE8X8",
    edgeFile = "Interface\\BUTTONS\\WHITE8X8",
    edgeSize = 2,
})
okBtn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
okBtn:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)

okBtn:SetScript("OnEnter", function(btn)
    btn:SetBackdropColor(COLORS.tabHover[1], COLORS.tabHover[2], COLORS.tabHover[3], 1)
    btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
end)

okBtn:SetScript("OnLeave", function(btn)
    btn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
    btn:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)
end)

okBtn:SetScript("OnClick", function() dialog:Hide() end)

    dialog:Show()
end
