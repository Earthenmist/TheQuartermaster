--[[
    The Quartermaster - Information Dialog
    Displays addon information, features, and usage instructions
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

--[[
    Show Information Dialog
    Displays addon information, features, and usage instructions
]]
function TheQuartermaster:ShowInfoDialog()
    -- Get theme colors
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
    headerBg:SetColorTexture(COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1)
    
    -- Logo
    local logo = dialog:CreateTexture(nil, "ARTWORK")
    logo:SetSize(32, 32)
    logo:SetPoint("LEFT", dialog, "TOPLEFT", 15, -25)
    logo:SetTexture("Interface\\AddOns\\TheQuartermaster\\Media\\icon")
    
    -- Title (centered)
    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("CENTER", dialog, "TOP", 0, -25)
    title:SetText("|cffffffffThe Quartermaster|r")
    
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
    
    AddText("Welcome to The Quartermaster!", "GameFontNormalHuge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8, true)
    AddText("Your comprehensive addon for managing Warband features, banks, currencies, reputations, and more.", "GameFontNormal", {0.8, 0.8, 0.8}, 15)
    
    AddDivider()
    
    -- Characters Tab
    AddText("Characters Tab", "GameFontNormalLarge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Displays all characters you have logged into with a summary of their gold, levels, class colors, professions, and last played dates. Gold is automatically summed across all characters.", "GameFontNormal", {0.9, 0.9, 0.9}, 15)
    
    -- Items Tab
    AddText("Items Tab", "GameFontNormalLarge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Updates automatically whenever you open your bank (including Warband Bank). This addon is view-only: it caches your items so you can browse and search them later. Use the search bar to find items across all Warband and character banks.", "GameFontNormal", {0.9, 0.9, 0.9}, 15)
    
    -- Storage Tab
    AddText("Storage Tab", "GameFontNormalLarge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Aggregates all items from characters, Warband Bank, and Guild Bank. Search your entire inventory in one convenient location.", "GameFontNormal", {0.9, 0.9, 0.9}, 15)
    
    -- PvE Tab
    AddText("PvE Tab", "GameFontNormalLarge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Track Great Vault progress, rewards, Mythic+ keystones, and raid lockouts across all your characters.", "GameFontNormal", {0.9, 0.9, 0.9}, 15)
    
    -- Reputations Tab
    AddText("Reputations Tab", "GameFontNormalLarge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Two viewing modes:\n• Filtered: Smart filtering organized by 'Account-Wide' and 'Character-Specific' categories, displaying the highest progress across your account.\n• All Characters: Displays the standard Blizzard UI view for each character individually.\n\nNote: While active, you cannot collapse reputation headers in the default character panel.", "GameFontNormal", {0.9, 0.9, 0.9}, 15)
    
    -- Currency Tab
    AddText("Currency Tab", "GameFontNormalLarge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Two filtering modes:\n• Filtered: Organizes and categorizes all currencies by expansion.\n• Non-Filtered: Matches the default Blizzard UI layout.\n• Hide Quantity 0: Automatically hides currencies with zero quantity.", "GameFontNormal", {0.9, 0.9, 0.9}, 15)
    
    -- Statistics Tab
    AddText("Statistics Tab", "GameFontNormalLarge", {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}, 8)
    AddText("Displays achievement points, mount collections, battle pets, toys, and bag/bank slot usage for all characters.", "GameFontNormal", {0.9, 0.9, 0.9}, 15)
    
    AddDivider()
    
    -- Footer
    AddText("Thank you for your support!", "GameFontNormalLarge", {0.2, 0.8, 0.2}, 8)
    AddText("If you encounter any bugs or have suggestions, please leave a comment on CurseForge. Your feedback helps make The Quartermaster better!", "GameFontNormal", {0.8, 0.8, 0.8}, 5)
    
    -- Update scroll child height
    scrollChild:SetHeight(yOffset)
    
    -- OK Button (bottom center)
    local okBtn = CreateFrame("Button", nil, dialog, "GameMenuButtonTemplate")
    okBtn:SetSize(100, 30)
    okBtn:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 15)
    okBtn:SetText("OK")
    okBtn:SetNormalFontObject("GameFontNormal")
    okBtn:SetHighlightFontObject("GameFontHighlight")
    okBtn:SetScript("OnClick", function() dialog:Hide() end)
    
    dialog:Show()
end

