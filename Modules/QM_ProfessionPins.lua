--[[
    The Quartermaster - Profession Recipe Pins

    Adds a small "Pin Reagents" button to the Professions recipe page.

    Clicking the button:
      - Reads the currently selected recipe schematic
      - Extracts required (basic) reagents and their quantities
      - Prompts for number of crafts
      - Adds each reagent to the Watchlist (Reagents) and increments desired targets
]]

local ADDON_NAME, ns = ...
local QM = ns and ns.TheQuartermaster
if not QM then return end

local function GetSelectedRecipeID()
    if C_TradeSkillUI and C_TradeSkillUI.GetSelectedRecipeID then
        local id = C_TradeSkillUI.GetSelectedRecipeID()
        if id and id > 0 then return id end
    end
    -- Fallbacks for different builds
    local pf = _G.ProfessionsFrame
    if pf and pf.CraftingPage and pf.CraftingPage.SchematicForm then
        local form = pf.CraftingPage.SchematicForm
        if form.recipeID and form.recipeID > 0 then return form.recipeID end
        if form.currentRecipeID and form.currentRecipeID > 0 then return form.currentRecipeID end
    end
    return nil
end

local function GetRequiredReagents(recipeID)
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then return {} end

    local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    if not schematic or not schematic.reagentSlotSchematics then return {} end

    local BASIC = (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 0
    local out = {}

    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        -- Only include required/basic reagents; optional/finishing reagents are excluded.
        if (slot.reagentType == nil) or (slot.reagentType == BASIC) then
            local qty = slot.quantityRequired or slot.quantity or slot.requiredQuantity or 0
            local reagents = slot.reagents or {}

            -- If multiple reagent choices exist, we don't know which one the player will use.
            -- We only auto-pin when there is a single, explicit itemID.
            if qty and qty > 0 and #reagents == 1 and reagents[1] and reagents[1].itemID then
                local itemID = tonumber(reagents[1].itemID)
                if itemID then
                    out[itemID] = (out[itemID] or 0) + qty
                end
            end
        end
    end

    return out
end

local function EnsurePopup()
    if StaticPopupDialogs["QM_PIN_RECIPE_REAGENTS"] then return end

    StaticPopupDialogs["QM_PIN_RECIPE_REAGENTS"] = {
        text = "Pin required reagents\n\nHow many crafts?",
        button1 = OKAY,
        button2 = CANCEL,
        hasEditBox = true,
        maxLetters = 6,
        whileDead = true,
        hideOnEscape = true,
        OnShow = function(selfPopup)
            selfPopup.editBox:SetText("1")
            selfPopup.editBox:HighlightText()
        end,
        OnAccept = function(selfPopup, data)
            local crafts = tonumber(selfPopup.editBox:GetText() or "") or 1
            crafts = math.max(1, math.floor(crafts + 0.5))

            if not data or not data.reagents then return end
            for itemID, qty in pairs(data.reagents) do
                QM:ToggleWatchlistReagent(itemID)
                QM:AddWatchlistReagentTarget(itemID, qty * crafts)
            end
        end,
        EditBoxOnEnterPressed = function(selfPopup)
            local parentPopup = selfPopup:GetParent()
            if parentPopup and parentPopup.button1 and parentPopup.button1:IsEnabled() then
                parentPopup.button1:Click()
            end
        end,
    }
end

local function CreatePinButton(parent)
    local btn = CreateFrame("Button", "QM_ProfessionsPinReagentsButton", parent, "BackdropTemplate")
    btn:SetSize(120, 22)
    btn:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
    btn:SetBackdropColor(0, 0, 0, 0.25)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText("Pin Reagents")

    btn:SetScript("OnEnter", function(selfBtn)
        selfBtn:SetBackdropColor(0, 0, 0, 0.35)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Pin required reagents to Watchlist", 1,1,1)
        GameTooltip:AddLine("Adds required quantities to desired amounts.", 0.8,0.8,0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(selfBtn)
        selfBtn:SetBackdropColor(0, 0, 0, 0.25)
        GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function()
        local recipeID = GetSelectedRecipeID()
        if not recipeID then return end

        local reagents = GetRequiredReagents(recipeID)
        local any = false
        for _ in pairs(reagents) do any = true break end
        if not any then
            UIErrorsFrame:AddMessage("Quartermaster: No explicit required reagents to pin for this recipe.", 1, 0.2, 0.2)
            return
        end

        EnsurePopup()
        StaticPopup_Show("QM_PIN_RECIPE_REAGENTS", nil, nil, { reagents = reagents })
    end)

    return btn
end

local function TryAttachButton()
    local pf = _G.ProfessionsFrame
    if not (pf and pf.CraftingPage) then return end

    local form = pf.CraftingPage.SchematicForm
    if not form then return end

    if pf._qmPinReagentsButton then
        return
    end

    -- Try to find a stable anchor near the schematic.
    local anchor = form
    if form.reagentsContainer then
        anchor = form.reagentsContainer
    elseif form.Details and form.Details.Reagents then
        anchor = form.Details.Reagents
    end

    local btn = CreatePinButton(pf)
    pf._qmPinReagentsButton = btn

    btn:ClearAllPoints()
    btn:SetPoint("LEFT", anchor, "LEFT", 10, 70)
end

-- Lightweight event driver
local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("TRADE_SKILL_SHOW")
driver:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
driver:SetScript("OnEvent", function()
    C_Timer.After(0.2, TryAttachButton)
end)
