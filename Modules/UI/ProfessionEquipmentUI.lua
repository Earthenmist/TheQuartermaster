--[[
    The Quartermaster - Profession Equipment Tab
    Shows cached profession equipment/tools/accessories per character.
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

local CreateCard = ns.UI_CreateCard

local function GetCOLORS()
    return ns.UI_COLORS or { accent = {0.40, 0.20, 0.58} }
end

local PROFESSION_SLOT_ORDER = {
    { key = 20, label = "Profession Slot 20" },
    { key = 21, label = "Profession Slot 21" },
    { key = 22, label = "Profession Slot 22" },
    { key = 23, label = "Profession Slot 23" },
    { key = 24, label = "Profession Slot 24" },
    { key = 25, label = "Profession Slot 25" },
    { key = 26, label = "Profession Slot 26" },
    { key = 27, label = "Profession Slot 27" },
    { key = 28, label = "Profession Slot 28" },
    --[[
    { key = 29, label = "Profession Slot 29" },
    { key = 30, label = "Profession Slot 30" },
    ]]
}

local function GetLinkRGB(itemLink)
    if type(itemLink) ~= "string" then return nil end
    local hex = itemLink:match("|c(%x%x%x%x%x%x%x%x)")
    if not hex then return nil end
    local rr = tonumber(hex:sub(3, 4), 16)
    local gg = tonumber(hex:sub(5, 6), 16)
    local bb = tonumber(hex:sub(7, 8), 16)
    if not rr or not gg or not bb then return nil end
    return rr / 255, gg / 255, bb / 255
end

local function AttachItemTooltip(btn, itemLink, fallbackText)
    if not btn then return end
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if itemLink then
            GameTooltip:SetHyperlink(itemLink)
        else
            GameTooltip:SetText(fallbackText or "Profession Equipment", 1, 1, 1)
            GameTooltip:AddLine("No profession equipment cached for this slot. Log into the character once after equipping profession gear.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function HasProfessionEquipment(char)
    if not char or not char.professionEquipment then return false end
    for _, item in pairs(char.professionEquipment) do
        if item and (item.itemID or item.itemLink or item.iconFileID) then
            return true
        end
    end
    return false
end

function TheQuartermaster:DrawProfessionEquipmentList(parent)
    local yOffset = 8
    local characters = self.GetCachedCharacters and self:GetCachedCharacters() or self:GetAllCharacters()
    characters = characters or {}

    table.sort(characters, function(a, b)
        local an = ((a.name or "") .. (a.realm or "")):lower()
        local bn = ((b.name or "") .. (b.realm or "")):lower()
        return an < bn
    end)

    -- ===== TITLE CARD =====
    -- Match the large title card used by the main Equipment tab.
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)

    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\inv_10_blacksmithing_consumable_repairhammer_color1")

    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Profession Equipment|r")

    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText(string.format("Shows each character's profession tools and accessories (%d characters, cached per character).", #characters))

    yOffset = yOffset + 75

    local rowH = 42
    local favW = 28
    local nameW = 190
    local cellW = 42

    for i, char in ipairs(characters) do
        local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        row:SetHeight(rowH)
        row:SetPoint("TOPLEFT", 10, -yOffset)
        row:SetPoint("TOPRIGHT", -10, -yOffset)
        row:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
        if (i % 2) == 0 then
            row:SetBackdropColor(0.06, 0.06, 0.07, 1)
        else
            row:SetBackdropColor(0.045, 0.045, 0.055, 1)
        end

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", 12, 0)
        label:SetWidth(nameW)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetMaxLines(1)

        local baseName = char.name or "?"
        local realm = (char.realm and char.realm ~= "") and char.realm or nil
        local displayName = baseName
        local classColor = (char.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.classFile]) or nil
        if classColor then
            displayName = string.format("|cff%02x%02x%02x%s|r", classColor.r * 255, classColor.g * 255, classColor.b * 255, baseName)
        end
        if realm then
            displayName = displayName .. string.format("|cff666666-%s|r", realm)
        end
        label:SetText(displayName)

        local equipment = char.professionEquipment or {}
        local cx = 12 + nameW + favW
        for _, slot in ipairs(PROFESSION_SLOT_ORDER) do
            local item = equipment[slot.key]
            local cell = CreateFrame("Button", nil, row, "BackdropTemplate")
            cell:SetSize(cellW - 2, rowH - 6)
            cell:SetPoint("LEFT", row, "LEFT", cx, 0)
            cell:SetBackdrop({
                bgFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false,
                edgeSize = 10,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            cell:SetBackdropColor(0.10, 0.10, 0.12, 0.35)
            cell:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.25)

            local iconTex = cell:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(30, 30)
            iconTex:SetPoint("CENTER")

            if item and (item.iconFileID or item.itemID or item.itemLink) then
                iconTex:SetTexture(item.iconFileID or "Interface\\Icons\\INV_Misc_QuestionMark")
                local r, g, b = GetLinkRGB(item.itemLink)
                if r then
                    cell:SetBackdropBorderColor(r, g, b, 1)
                end
                AttachItemTooltip(cell, item.itemLink, item.name or slot.label)
            else
                iconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                iconTex:SetDesaturated(true)
                iconTex:SetAlpha(0.25)
                AttachItemTooltip(cell, nil, slot.label)
            end

            cx = cx + cellW
        end

        if not HasProfessionEquipment(char) then
            local empty = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            empty:SetPoint("LEFT", row, "LEFT", cx + 8, 0)
            empty:SetTextColor(0.5, 0.5, 0.5)
            empty:SetText("No profession equipment cached")
        end

        yOffset = yOffset + rowH + 2
    end

    return yOffset + 10
end
