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
local DEBUG_PINS = false -- set true for temporary debugging
local function dprint(msg) if DEBUG_PINS then print("|cff00ff88[QM]|r "..msg) end end

local function GetSelectedRecipeID()
    if C_TradeSkillUI and C_TradeSkillUI.GetSelectedRecipeID then
        local id = C_TradeSkillUI.GetSelectedRecipeID()
        if id and id > 0 then return id end
    end
    -- Fallbacks for different builds
    local pf = _G.ProfessionsFrame
    if pf and pf.CraftingPage then
        local page = pf.CraftingPage

        -- Most reliable: the schematic form exposes a getter
        if page.SchematicForm then
            local form = page.SchematicForm
            if type(form.GetRecipeID) == "function" then
                local rid = form:GetRecipeID()
                if rid and rid > 0 then return rid end
            end

            -- Older/variant fields
            if form.recipeID and form.recipeID > 0 then return form.recipeID end
            if form.currentRecipeID and form.currentRecipeID > 0 then return form.currentRecipeID end

            -- Some builds store the recipe on the transaction
            if form.transaction and type(form.transaction.GetRecipeID) == "function" then
                local rid = form.transaction:GetRecipeID()
                if rid and rid > 0 then return rid end
            end
        end

        -- Recipe list fallbacks
        if page.RecipeList then
            local rl = page.RecipeList
            if type(rl.GetSelectedRecipeID) == "function" then
                local rid = rl:GetSelectedRecipeID()
                if rid and rid > 0 then return rid end
            end
            if rl.selectedRecipeID and rl.selectedRecipeID > 0 then return rl.selectedRecipeID end
        end
    end
    return nil
end

local function GetRequiredReagents(recipeID)
    if not recipeID or not C_TradeSkillUI then
        return {}
    end

    local out = {}

    local function add(itemID, qty)
        itemID = tonumber(itemID)
        qty = tonumber(qty) or 0
        if not itemID or itemID <= 0 or qty <= 0 then return end
        out[itemID] = (out[itemID] or 0) + qty
    end

    local function isSparkItem(itemID, hintText)
        if hintText and tostring(hintText):lower():find("spark", 1, true) then
            return true
        end
        if itemID and _G.GetItemInfo then
            local name = _G.GetItemInfo(itemID)
            if type(name) == "string" and name:lower():find("spark", 1, true) then
                return true
            end
        end
        return false
    end

    -- Build an exclusion set from the schematic for Optional + Finishing slots (and Spark-labelled slots),
    -- so we can safely filter the reagent list API even when it includes these.
    local excluded = {}
    local schematic = C_TradeSkillUI.GetRecipeSchematic and C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    if schematic and schematic.reagentSlotSchematics then
        local slotEnum = _G.Enum and _G.Enum.TradeskillSlotType
        local OPTIONAL = slotEnum and slotEnum.OptionalReagent
        local FINISHING = slotEnum and slotEnum.FinishingReagent

        for _, slot in ipairs(schematic.reagentSlotSchematics) do
            local slotType = slot.slotType
            local slotText = slot.slotText or slot.slotName or slot.name
            local lower = slotText and tostring(slotText):lower() or ""

            local isOptional = slot.isOptionalReagent or (OPTIONAL and slotType == OPTIONAL) or lower:find("optional", 1, true)
            local isFinishing = slot.isFinishingReagent or (FINISHING and slotType == FINISHING) or lower:find("finishing", 1, true)

            if isOptional or isFinishing or lower:find("spark", 1, true) then
                if slot.reagents then
                    for _, r in ipairs(slot.reagents) do
                        local itemID = r.itemID or r.itemId
                        if itemID then excluded[tonumber(itemID)] = true end
                    end
                elseif slot.reagent and (slot.reagent.itemID or slot.reagent.itemId) then
                    local itemID = slot.reagent.itemID or slot.reagent.itemId
                    excluded[tonumber(itemID)] = true
                end
            end
        end
    end

    -- Prefer Blizzard's reagent list API (this is generally the "Reagents" section),
    -- but we filter using the schematic exclusion set to guarantee Optional/Finishing are not pinned.
    if C_TradeSkillUI.GetRecipeNumReagents and C_TradeSkillUI.GetRecipeReagentInfo then
        local okNum, num = pcall(C_TradeSkillUI.GetRecipeNumReagents, recipeID)
        if okNum and type(num) == "number" and num > 0 then
            for i = 1, num do
                local okInfo, name, _, reagentCount = pcall(C_TradeSkillUI.GetRecipeReagentInfo, recipeID, i)
                reagentCount = tonumber(reagentCount) or 0
                if okInfo and reagentCount > 0 then
                    local itemID
                    if C_TradeSkillUI.GetRecipeReagentItemLink then
                        local okLink, link = pcall(C_TradeSkillUI.GetRecipeReagentItemLink, recipeID, i)
                        if okLink and link then
                            itemID = _G.GetItemInfoInstant and _G.GetItemInfoInstant(link)
                        end
                    end
                    if (not itemID or itemID <= 0) and C_TradeSkillUI.GetRecipeReagentItemID then
                        local okID, rid = pcall(C_TradeSkillUI.GetRecipeReagentItemID, recipeID, i)
                        if okID and rid then itemID = rid end
                    end

                    itemID = tonumber(itemID)
                    if itemID and itemID > 0 then
                        if not excluded[itemID] and not isSparkItem(itemID, name) then
                            add(itemID, reagentCount)
                        end
                    end
                end
            end
        end
    end

    -- If the reagent list API produced nothing (or isn't available), fall back to schematic required-only slots.
    if not next(out) and schematic and schematic.reagentSlotSchematics then
        local slotEnum = _G.Enum and _G.Enum.TradeskillSlotType
        local OPTIONAL = slotEnum and slotEnum.OptionalReagent
        local FINISHING = slotEnum and slotEnum.FinishingReagent

        for _, slot in ipairs(schematic.reagentSlotSchematics) do
            local slotType = slot.slotType
            local slotText = slot.slotText or slot.slotName or slot.name
            local lower = slotText and tostring(slotText):lower() or ""

            local isOptional = slot.isOptionalReagent or (OPTIONAL and slotType == OPTIONAL) or lower:find("optional", 1, true)
            local isFinishing = slot.isFinishingReagent or (FINISHING and slotType == FINISHING) or lower:find("finishing", 1, true)

            if not isOptional and not isFinishing and not lower:find("spark", 1, true) then
                local required = slot.quantityRequired or slot.quantityRequiredPerCraft or slot.requiredQuantity or slot.quantity or slot.reagentCount or 0
                required = tonumber(required) or 0
                if required > 0 then
                    local itemID
                    if slot.reagents and slot.reagents[1] then
                        itemID = slot.reagents[1].itemID or slot.reagents[1].itemId
                    elseif slot.reagent then
                        itemID = slot.reagent.itemID or slot.reagent.itemId
                    end
                    itemID = tonumber(itemID)
                    if itemID and itemID > 0 and not isSparkItem(itemID, slotText) then
                        add(itemID, required)
                    end
                end
            end
        end
    end

    return out
end

local function HasAnyRequiredReagents(recipeID)
    local reagents = GetRequiredReagents(recipeID)
    return reagents and next(reagents) ~= nil
end

local function GetCurrentProfessionTitle()
	local pf = _G.ProfessionsFrame
	if not pf then return nil end

	-- Prefer the API when available (more reliable than title widgets).
	if _G.C_TradeSkillUI and _G.C_TradeSkillUI.GetTradeSkillLine then
		local ok, lineName = pcall(_G.C_TradeSkillUI.GetTradeSkillLine)
		if ok and type(lineName) == "string" and lineName ~= "" then
			return lineName
		end
	end

	if pf.GetTitleText then
		local t = pf:GetTitleText()
		if type(t) == "string" and t ~= "" then return t end
	end
	if pf.TitleText and pf.TitleText.GetText then
		local t = pf.TitleText:GetText()
		if type(t) == "string" and t ~= "" then return t end
	end

	-- Some pages don't expose TitleText; try crafting page header/title widgets.
	if pf.CraftingPage then
		local cp = pf.CraftingPage
		if cp.SchematicForm then
			local sf = cp.SchematicForm
			if sf.Title and sf.Title.GetText then
				local t = sf.Title:GetText()
				if type(t) == "string" and t ~= "" then return t end
			end
		end
		if cp.Header and cp.Header.Title and cp.Header.Title.GetText then
			local t = cp.Header.Title:GetText()
			if type(t) == "string" and t ~= "" then return t end
		end
	end

	-- Final fallback: some builds expose a name directly.
	if type(pf.professionName) == "string" and pf.professionName ~= "" then
		return pf.professionName
	end
	return nil
end

local function IsBlockedProfession()
    local title = GetCurrentProfessionTitle()

    -- Fallback to tradeskill line name if the frame title isn't available (some pages don't use TitleText)
    local lineName
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillLine then
        local n = C_TradeSkillUI.GetTradeSkillLine()
        if type(n) == "string" and n ~= "" then
            lineName = n
        end
    end

    local haystack = ((title or "") .. " " .. (lineName or "")):lower()

    -- Gathering professions & Archaeology: no "reagents required" concept in the recipe UI
    if haystack:find("fishing", 1, true) then return true end
    if haystack:find("mining", 1, true) then return true end
    if haystack:find("herbalism", 1, true) then return true end
    if haystack:find("skinning", 1, true) then return true end
    if haystack:find("archaeology", 1, true) then return true end

    return false
end

-- Return required reagents as an array of { itemID, quantity } for UI/popup usage.
local function GetReagentsForRecipe(recipeID)
    local map = GetRequiredReagents(recipeID)
    local out = {}
    if not map then return out end
    for itemID, qty in pairs(map) do
        table.insert(out, { itemID = itemID, quantity = qty })
    end
    table.sort(out, function(a,b) return (a.itemID or 0) < (b.itemID or 0) end)
    return out
end

local function UpdatePinButtonVisibility()
    local pf = ProfessionsFrame
    if not pf or not pf._qmPinReagentsButton then return end

    local btn = pf._qmPinReagentsButton
    if not pf.IsShown or not pf:IsShown() then
        btn:Hide()
        return
    end

    -- Blocked professions (gathering & Archaeology) should never show the button.
    -- Use our internal resolver (based on trade skill line/title) rather than any
    -- external helper that may not exist on some builds.
    if IsBlockedProfession() then
        dprint("VisCheck: blocked -> hide")
        btn:Hide()
        return
    end

    local recipeID = GetSelectedRecipeID()

    -- Avoid spamming chat: only print when the selected recipe changes.
    if pf._qmLastVisRecipeID ~= recipeID then
        pf._qmLastVisRecipeID = recipeID
        dprint("VisCheck: recipeID="..tostring(recipeID))
    end
    if not recipeID then
        btn:Hide()
        return
    end

    local reagents = GetReagentsForRecipe(recipeID)
    if pf._qmLastVisReagentCount ~= (reagents and #reagents or 0) then
        pf._qmLastVisReagentCount = (reagents and #reagents or 0)
        dprint("VisCheck: reagentCount="..tostring(pf._qmLastVisReagentCount))
    end
    if not reagents or #reagents == 0 then
        btn:Hide()
        return
    end

    btn:Show()
end

local function EnsurePinTicker()
    local pf = ProfessionsFrame
    if not pf or pf._qmPinTicker then return end

    pf._qmPinTicker = C_Timer.NewTicker(0.5, function()
        if not ProfessionsFrame or not ProfessionsFrame.IsShown or not ProfessionsFrame:IsShown() then
            if ProfessionsFrame and ProfessionsFrame._qmPinTicker then
                ProfessionsFrame._qmPinTicker:Cancel()
                ProfessionsFrame._qmPinTicker = nil
            end
            return
        end
        UpdatePinButtonVisibility()
    end)
end

local function EnsurePopup()
    -- StaticPopupDialogs lives in Blizzard_StaticPopup. If it's not loaded yet, load it.
    if not _G.StaticPopupDialogs then
        if _G.UIParentLoadAddOn then
            pcall(_G.UIParentLoadAddOn, "Blizzard_StaticPopup")
        end
    end

    local dialogs = _G.StaticPopupDialogs
    if not dialogs then return end
    if dialogs["QM_PIN_RECIPE_REAGENTS"] then return end

    dialogs["QM_PIN_RECIPE_REAGENTS"] = {
        text = [[Pin required reagents to Watchlist

How many crafts do you want to plan for?

Adds the recipe's required reagent quantities to your desired amounts.
If a reagent is already pinned, its desired amount will be increased.]],
        button1 = ACCEPT,
        button2 = CANCEL,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,

        hasEditBox = true,
        editBoxWidth = 80,
        maxLetters = 6,

        OnShow = function(selfPopup, data)
            -- Default to 1 craft and focus the edit box.
            if selfPopup.editBox then
                selfPopup.editBox:SetAutoFocus(true)
                selfPopup.editBox:SetNumeric(true)
                selfPopup.editBox:SetNumber(1)
                selfPopup.editBox:HighlightText()
                selfPopup.editBox:SetFocus()
            end
        end,

        EditBoxOnEnterPressed = function(editBox)
            -- In StaticPopup, this callback receives the editBox, not the popup.
            local popup = editBox and editBox:GetParent()
            if popup and popup.button1 and popup.button1.Click then
                popup.button1:Click()
            end
        end,

        OnAccept = function(selfPopup, data)
            data = data or selfPopup.data
            if not data then return end

            local crafts = 1
            if selfPopup and selfPopup.editBox and selfPopup.editBox.GetText then
                local n = tonumber(selfPopup.editBox:GetText())
                if n and n > 0 then crafts = math.floor(n) end
            end

            local reagents = data.reagents
            if not reagents or #reagents == 0 then return end

            -- Apply: +(requiredQty * crafts) to Watchlist reagent targets (and ensure they are pinned)
            -- IMPORTANT: Never "toggle" here. A recipe can reference the same item multiple times (quality/optional slots)
            -- and a toggle would cancel itself out. We aggregate and use ensure+targetDelta.
            local totals = {}
            for _, r in ipairs(reagents) do
                local itemID = r.itemID
                local qty = tonumber(r.quantity) or 0
                if itemID and qty > 0 then
                    totals[itemID] = (totals[itemID] or 0) + (qty * crafts)
                end
            end
            for itemID, qty in pairs(totals) do
                if QM and QM.ToggleWatchlistReagent then
                    QM:ToggleWatchlistReagent(itemID, { mode = "ensure", targetDelta = qty })
                end
            end
        end,
    }
end

local function CreatePinButton(parent)
    local btn = CreateFrame("Button", "QM_ProfessionsPinReagentsButton", parent, "BackdropTemplate")
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetFrameStrata("DIALOG")
    btn:SetFrameLevel(1000)
    btn:SetSize(120, 22)
    btn:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
    btn:SetBackdropColor(0, 0, 0, 0.25)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText("Pin Reagents")

    -- Start hidden; UpdatePinButtonVisibility() controls when it should be shown.
    btn:Hide()

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
    if not recipeID then
        QMPrint("Pin Reagents: no selected recipe (nothing to pin).")
        return
    end

    local reagents = GetReagentsForRecipe(recipeID)
    if not reagents or #reagents == 0 then
        QMPrint("Pin Reagents: recipe has no reagents (nothing to pin).")
        return
    end

    EnsurePopup()
    if not _G.StaticPopupDialogs or not _G.StaticPopupDialogs["QM_PIN_RECIPE_REAGENTS"] then
        QMPrint("Pin Reagents: popup not available (StaticPopupDialogs not ready).")
        return
    end

    StaticPopup_Show("QM_PIN_RECIPE_REAGENTS", nil, nil, { recipeID = recipeID, reagents = reagents })
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

    -- Parent to the CraftingPage so it stays on top of the schematic and doesn't get
    -- occluded by the reagent rows.
    local btn = CreatePinButton(pf.CraftingPage)
    pf._qmPinReagentsButton = btn

    btn:ClearAllPoints()

    -- Place it next to the Crafting action buttons so it never overlaps reagent icons.
    local createAll = pf.CraftingPage.CreateAllButton
    if createAll and createAll.GetObjectType and createAll:GetObjectType() == "Button" then
        -- Sit clearly to the left of Create All.
        btn:SetPoint("RIGHT", createAll, "LEFT", -12, 0)
    else
        btn:SetPoint("LEFT", anchor, "LEFT", 10, 70)
    end

    btn:SetFrameStrata("DIALOG")
    btn:SetFrameLevel((createAll and createAll.GetFrameLevel and createAll:GetFrameLevel() or btn:GetFrameLevel()) + 5)

    -- Initial/refresh visibility (and keep it updated while the frame is open).
    UpdatePinButtonVisibility()
    EnsurePinTicker()

    -- Extra hooks so the button shows/hides correctly when swapping professions/tabs.
    if not pf._qmPinHooksApplied then
        pf._qmPinHooksApplied = true

        -- Professions frame shown/hidden
        if pf.HookScript then
            pf:HookScript("OnShow", function()
                C_Timer.After(0, UpdatePinButtonVisibility)
            end)
        end

        -- Schematic form visibility & common refresh methods
        if form and form.HookScript then
            form:HookScript("OnShow", function() C_Timer.After(0, UpdatePinButtonVisibility) end)
            form:HookScript("OnHide", function() C_Timer.After(0, UpdatePinButtonVisibility) end)
        end

        local function SafeHook(obj, method)
            if not obj then return end
            local fn = obj[method]
            if type(fn) == "function" then
                hooksecurefunc(obj, method, function()
                    C_Timer.After(0, UpdatePinButtonVisibility)
                end)
            end
        end

        -- Methods vary by build; hook a few likely ones.
        SafeHook(pf, "SetProfession")
        SafeHook(pf, "SetProfessionInfo")
        SafeHook(pf.CraftingPage, "SetProfession")
        SafeHook(form, "SetRecipeID")
        SafeHook(form, "SetRecipe")
        SafeHook(form, "Refresh")
        SafeHook(form, "Update")
    end
end

-- Lightweight event driver
local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("TRADE_SKILL_SHOW")
driver:RegisterEvent("TRADE_SKILL_CLOSE")
driver:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
driver:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
    -- There is no reliable public event for "recipe selected" across all builds.
    -- Instead we poll selection/visibility state with a lightweight ticker (see EnsurePinTicker).

local attachTicker

local function StartAttachTicker()
    if attachTicker then return end
    attachTicker = C_Timer.NewTicker(1, function()
        -- Keep trying to attach while Professions is open or until attached.
        if not TryAttachButton() then
            -- no-op
        end
	    if ProfessionsFrame and ProfessionsFrame._qmPinReagentsButton then
	        UpdatePinButtonVisibility()
	    end
	    if ProfessionsFrame and ProfessionsFrame._qmPinReagentsButton and ProfessionsFrame:IsShown() then
            -- keep running
        end
    end)
end

driver:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        -- Register popup dialog as soon as StaticPopup is available.
        EnsurePopup()
        StartAttachTicker()
        return
    end

    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_Professions" or arg1 == "Blizzard_StaticPopup" then
            EnsurePopup()
            TryAttachButton()
            UpdatePinButtonVisibility()
        end
        return
    end

    -- Any profession UI churn: attempt attach + visibility refresh
    TryAttachButton()
    UpdatePinButtonVisibility()
end)