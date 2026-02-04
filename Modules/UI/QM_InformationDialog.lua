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
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    dialog:SetBackdropColor(0.02, 0.02, 0.03, 1.0)
    dialog:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1.0)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    self.infoDialog = dialog
    
    -- Header background
    local headerBg = dialog:CreateTexture(nil, "BACKGROUND")
    headerBg:SetHeight(50)
    headerBg:SetPoint("TOPLEFT", 4, -4)
    headerBg:SetPoint("TOPRIGHT", -4, -4)
    local hdr = COLORS.accentDark or COLORS.accent or {0.60, 0.10, 0.10}
    headerBg:SetColorTexture(hdr[1], hdr[2], hdr[3], 1)
    
    -- Logo
    local logo = dialog:CreateTexture(nil, "ARTWORK")
    logo:SetSize(32, 32)
    logo:SetPoint("LEFT", dialog, "TOPLEFT", 15, -25)
    logo:SetTexture("Interface\\AddOns\\TheQuartermaster\\Media\\icon")
    
    -- Title (centered)
    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("CENTER", dialog, "TOP", 0, -25)
    title:SetText(L["CFFFFFFFFTHE_QUARTERMASTER_R"])
    
    -- X Close Button (top right)
    local closeBtn = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function() dialog:Hide() end)
    
    -- Scroll Frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", headerBg, "BOTTOMLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -30, 50)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(450, 1) -- Height will be calculated
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Content
    local yOffset = 0
    local function AddText(text, fontObject, color, spacing, centered)
        local fs = scrollChild:CreateFontString(nil, "OVERLAY", fontObject or "GameFontNormal")
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
    
    local function AddDivider()
        local line = scrollChild:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("LEFT", scrollChild, "LEFT", 0, -yOffset)
        line:SetPoint("RIGHT", scrollChild, "RIGHT", 0, -yOffset)
        line:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        yOffset = yOffset + 15
    end
    
        -- Welcome
    AddText("Welcome to The Quartermaster!", "GameFontNormalHuge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8, true)

    -- Version line (safe metadata lookup)
    local addonVersion = "Unknown"
    if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
        addonVersion = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or addonVersion
    elseif type(GetAddOnMetadata) == "function" then
        addonVersion = GetAddOnMetadata(ADDON_NAME, "Version") or addonVersion
    end
    AddText("Version: " .. tostring(addonVersion), "GameFontHighlightSmall", {0.75, 0.75, 0.75}, 10)

    AddText("A clean, account-wide overview of your characters, currencies, reputations, inventory storage, and progression — built for modern Warband play.", "GameFontNormal", {0.85, 0.85, 0.85}, 12)

    -- How data is collected
    AddText("How it works", "GameFontNormalLarge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("The Quartermaster is view-only. It builds your account database as you play:", "GameFontNormal", {0.9, 0.9, 0.9}, 6)
    AddText("• Log into characters at least once to capture their profile data.", "GameFontNormal", {0.9, 0.9, 0.9}, 6)
    AddText("• Open Inventory/Bank/Warband Bank/Guild Bank to cache item lists.", "GameFontNormal", {0.9, 0.9, 0.9}, 6)
    AddText("• Use search and filters to find items across all stored locations.", "GameFontNormal", {0.9, 0.9, 0.9}, 12)

    AddText("Tip: If something looks missing, visit that character and open the relevant window once (then /reload if needed).", "GameFontHighlightSmall", {0.75, 0.75, 0.75}, 14)

    -- Characters Tab
    AddText("Characters", "GameFontNormalLarge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("A roster view of every character you’ve logged into, including level, class, faction, professions, last played, and account-wide totals. Optional Discretion Mode can hide gold values.", "GameFontNormal", {0.9, 0.9, 0.9}, 15)

    -- Experience Tab
    AddText("Experience", "GameFontNormalLarge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Rested XP at a glance: total time played, how many characters are max level, how many are fully rested, and per-character rested status including time until fully rested.", "GameFontNormal", {0.9, 0.9, 0.9}, 15)

    -- Guilds Tab
    AddText("Guilds", "GameFontNormalLarge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("See guild membership across your roster: guild name, rank, and reputation — plus quick account-wide counts so you can spot which guild you’re most represented in.", "GameFontNormal", {0.9, 0.9, 0.9}, 15)

    -- Items Tab
    AddText("Items", "GameFontNormalLarge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Browse cached items by location (Inventory, Bank, Warband Bank, and Guild Bank). The list is searchable and designed to load fast even with large collections.", "GameFontNormal", {0.9, 0.9, 0.9}, 15)
    
    -- Storage Tab
    AddText("Storage", "GameFontNormalLarge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("A unified item view that aggregates everything you’ve cached across characters and banks. Use filters and search to quickly answer: “Where is that item?”", "GameFontNormal", {0.9, 0.9, 0.9}, 15)

    -- PvE Tab
    AddText("PvE", "GameFontNormalLarge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Track key progression details across your characters, including Mythic+ keystones, Great Vault status, and raid lockouts.", "GameFontNormal", {0.9, 0.9, 0.9}, 15)

    -- Reputations Tab
    AddText("Reputations", "GameFontNormalLarge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Choose between a smart, account-wide filtered view (highest progress) or a per-character view that mirrors Blizzard’s reputation panel.", "GameFontNormal", {0.9, 0.9, 0.9}, 15)

    -- Currency Tab
    AddText("Currency", "GameFontNormalLarge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("View currencies in a filtered expansion-organized layout or the default Blizzard ordering. Optional “Hide Quantity 0” keeps the list clean.", "GameFontNormal", {0.9, 0.9, 0.9}, 15)

    -- Statistics Tab
    AddText("Statistics", "GameFontNormalLarge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Account-wide collection stats such as achievement points, mounts, companions, toys, and storage usage.", "GameFontNormal", {0.9, 0.9, 0.9}, 15)
  
    -- Footer
    AddText("Thank you for your support!", "GameFontNormalLarge", {0.2, 0.8, 0.2}, 8)
    AddText("If you encounter any bugs or have suggestions, please leave a comment on CurseForge. Your feedback helps make The Quartermaster better!", "GameFontNormal", {0.8, 0.8, 0.8}, 5)
    
    -- Update scroll child height
    scrollChild:SetHeight(yOffset)
    
    -- OK Button (bottom center) - match Items "Slot View" themed action button
local okBtn = CreateFrame("Button", nil, dialog, "BackdropTemplate")
okBtn:SetSize(96, 24)
okBtn:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 15)

okBtn.text = okBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
okBtn.text:SetPoint("CENTER")
okBtn.text:SetTextColor(1, 1, 1, 0.95)
okBtn.text:SetText("OK")

okBtn:SetBackdrop({
    bgFile = "Interface\\BUTTONS\\WHITE8X8",
    edgeFile = "Interface\\BUTTONS\\WHITE8X8",
    edgeSize = 1,
})
okBtn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
okBtn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)

okBtn:SetScript("OnEnter", function(btn)
    btn:SetBackdropColor(COLORS.tabHover[1], COLORS.tabHover[2], COLORS.tabHover[3], 1)
    btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
end)

okBtn:SetScript("OnLeave", function(btn)
    btn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
    btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)
end)

okBtn:SetScript("OnClick", function() dialog:Hide() end)

    dialog:Show()
end
