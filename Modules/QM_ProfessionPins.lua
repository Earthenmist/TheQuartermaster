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
    if not recipeID or not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeSchematic then
        return {}
    end

    local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    if not schematic or not schematic.reagentSlotSchematics then
        return {}
    end

    local out = {}
    local function add(itemID, qty)
        itemID = tonumber(itemID)
        qty = tonumber(qty) or 0
        if not itemID or itemID <= 0 or qty <= 0 then return end
        out[itemID] = (out[itemID] or 0) + qty
    end

    -- Some recipes include "Spark" reagents (e.g. Spark of Omens) in the *required* section.
    -- For Quartermaster's watchlist workflow we explicitly skip these.
    local function IsSparkItem(itemID)
        itemID = tonumber(itemID)
        if not itemID or itemID <= 0 then return false end

        local name
        if C_Item and C_Item.GetItemNameByID then
            name = C_Item.GetItemNameByID(itemID)
        end
        if not name then
            name = GetItemInfo(itemID)
        end
        if type(name) ~= "string" then
            return false
        end

        -- Whole word match for "Spark" to avoid false positives like "Sparkling".
        return name:match("%f[%a]Spark%f[%A]") ~= nil
    end




    -- Prefer the classic reagent API when available (it typically returns ONLY required reagents,
    -- excluding Optional/Finishing reagent slots). This also avoids edge cases in schematic slot typing.
    if _G.C_TradeSkillUI and _G.C_TradeSkillUI.GetRecipeNumReagents then
        local ok, num = pcall(_G.C_TradeSkillUI.GetRecipeNumReagents, recipeID)
        if ok and type(num) == "number" and num > 0 then
            for i = 1, num do
                local qty
                if _G.C_TradeSkillUI.GetRecipeReagentInfo then
                    local ok2, _name, _tex, reagentCount = pcall(_G.C_TradeSkillUI.GetRecipeReagentInfo, recipeID, i)
                    if ok2 then
                        qty = reagentCount
                    end
                end

                local itemID
                if _G.C_TradeSkillUI.GetRecipeReagentItemLink then
                    local ok3, link = pcall(_G.C_TradeSkillUI.GetRecipeReagentItemLink, recipeID, i)
                    if ok3 and link then
                        itemID = GetItemInfoInstant(link)
                    end
                end

                qty = tonumber(qty) or 0
                if itemID and qty > 0 then
                    if not IsSparkItem(itemID) then
                        add(itemID, qty)
                    else
                        dprint("Skipping Spark reagent itemID="..tostring(itemID))
                    end
                end
            end

            if next(out) ~= nil then
                return out
            end
        end
    end

-- Filter out optional & finishing reagent slots. We only want the *required/basic* reagents.
local function IsBasicReagentSlot(slot)
    if not slot or type(slot) ~= "table" then return false end

    -- Preferred: slotType enum (retail)
    local st = slot.slotType
    if st and _G.Enum and _G.Enum.TradeskillSlotType then
        local t = _G.Enum.TradeskillSlotType

        -- Explicit exclusions
        if t.OptionalReagent and st == t.OptionalReagent then return false end
        if t.ModifiedReagent and st == t.ModifiedReagent then return false end
        if t.FinishingReagent and st == t.FinishingReagent then return false end
        if t.EnhancingReagent and st == t.EnhancingReagent then return false end

        -- Explicit inclusions
        if t.Reagent and st == t.Reagent then return true end
        if t.BasicReagent and st == t.BasicReagent then return true end

        -- Common pattern: 1 = required/basic, >1 = optional/finishing
        if type(st) == "number" then
            return st == 1
        end
    end

    -- Alternate: crafting reagent type enum
    local rt = slot.reagentType or slot.craftingReagentType
    if rt and _G.Enum and _G.Enum.CraftingReagentType then
        local r = _G.Enum.CraftingReagentType
        if r.Optional and rt == r.Optional then return false end
        if r.Finishing and rt == r.Finishing then return false end
        if r.Basic and rt == r.Basic then return true end
    end

    -- Flag-based fallbacks (varies by build)
    if slot.isOptionalReagent or slot.isModifyingReagent or slot.isFinishingReagent then
        return false
    end
    if slot.isRequiredReagent ~= nil then
        return slot.isRequiredReagent and true or false
    end

    -- Text heuristics (last resort)
    local label = (slot.slotText or slot.slotName or slot.name or ""):lower()
    if label:find("optional", 1, true) then return false end
    if label:find("finishing", 1, true) then return false end

    -- Default: be conservative (treat as non-basic)
    return false
end

    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        if IsBasicReagentSlot(slot) then
            -- IMPORTANT: only treat slots as "required" if the schematic provides an explicit required quantity.
            -- Optional/finishing slots sometimes carry generic fields (e.g. slot.quantity) that can be non-zero
            -- even though they're not truly required reagents.
            local required = slot.quantityRequired or slot.quantityRequiredPerCraft or slot.requiredQuantity or 0
            required = tonumber(required) or 0

            if required > 0 then
                -- The slot can expose the reagent item in a few different ways across builds.
                -- Prefer a direct itemID, otherwise derive from an itemLink if present.
                local itemID

                -- Some builds expose a single reagent as slot.reagent (table) or slot.reagents[1]
                if slot.reagent and type(slot.reagent) == "table" then
                    itemID = slot.reagent.itemID or (slot.reagent.item and slot.reagent.item.itemID)
                end

            if not itemID and slot.reagents and type(slot.reagents) == "table" and #slot.reagents > 0 then
                -- Prefer the first entry; qualities map to same base itemID for most mats
                local r = slot.reagents[1]
                if type(r) == "table" then
                    itemID = r.itemID or (r.item and r.item.itemID) or (r.reagent and r.reagent.itemID)
                    if not itemID and r.itemLink then
                        itemID = GetItemInfoInstant(r.itemLink)
                    end
                end
            end

            if not itemID and slot.itemID then
                itemID = slot.itemID
            end

            if not itemID and slot.itemLink then
                itemID = GetItemInfoInstant(slot.itemLink)
            end

            if itemID then
                if not IsSparkItem(itemID) then
                    add(itemID, required)
                else
                    dprint("Skipping Spark reagent itemID="..tostring(itemID))
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
        maxLetters = 4,
        OnShow = function(selfPopup, data)
            if selfPopup.editBox then
                selfPopup.editBox:SetNumeric(true)
                selfPopup.editBox:SetAutoFocus(true)
                selfPopup.editBox:SetText("1")
                selfPopup.editBox:HighlightText()
            end
        end,
        EditBoxOnEnterPressed = function(editBox)
            local popup = editBox and editBox:GetParent()
            if popup and popup.data then
                local n = tonumber(editBox:GetText())
                if n and n > 0 then popup.data._qmCrafts = math.floor(n) end
            end
            if popup and popup.button1 and popup.button1.Click then
                popup.button1:Click()
            end
        end,
        EditBoxOnEscapePressed = function(editBox)
            local popup = editBox and editBox:GetParent()
            if popup then popup:Hide() end
        end,
        OnAccept = function(selfPopup, data)
            data = data or selfPopup.data
            if not data then return end


	        local reagents = data.reagents
	        if not reagents or #reagents == 0 then return end

	        -- Apply: +requiredQty to Watchlist reagent targets (and ensure they are pinned)
	        -- IMPORTANT: Never "toggle" here. A recipe can reference the same item multiple times (quality/optional slots)
	        -- and a toggle would cancel itself out. We aggregate and use ensure+targetDelta.
	        local crafts = 1
            -- Read planned crafts from popup edit box (defaults to 1)
            do
                local edit = (selfPopup and (selfPopup.editBox or (_G[selfPopup.GetName and (selfPopup:GetName() .. "EditBox") or nil] )))
                if edit and edit.GetText then
                    local n = tonumber(edit:GetText())
                    if n and n > 0 then crafts = math.floor(n) end
                elseif data and type(data._qmCrafts) == "number" and data._qmCrafts > 0 then
                    crafts = math.floor(data._qmCrafts)
                end
            end


            crafts = math.floor(crafts)
            if crafts < 1 then crafts = 1 end

            local totals = {}
            for _, r in ipairs(reagents) do
	            local itemID = r.itemID
	            local qty = tonumber(r.quantity) or 0
	            if itemID and qty > 0 then
	                totals[itemID] = (totals[itemID] or 0) + (qty * crafts)
	            end
	        end
	        for itemID, qty in pairs(totals) do
	            -- Use the addon instance captured from ... (QM), not a global.
	            -- In The Quartermaster, the object is stored on the namespace, so a global
	            -- 'TheQuartermaster' may not exist.
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