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

    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        local required = slot.quantityRequired or slot.quantityRequiredPerCraft or slot.requiredQuantity or slot.quantity or slot.reagentCount or 0
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
                add(itemID, required)
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

local function UpdatePinButtonVisibility()
    local pf = ProfessionsFrame
    if not pf or not pf._qmPinBtn then return end

    local btn = pf._qmPinBtn
    if not pf.IsShown or not pf:IsShown() then
        btn:Hide()
        return
    end

    -- Only show on the Crafting page (Journal/other panes shouldn't get this).
    if not pf.CraftingPage or not pf.CraftingPage.IsShown or not pf.CraftingPage:IsShown() then
        btn:Hide()
        return
    end

    -- If Create/Forge controls aren't visible, we're not on a craftable recipe view.
    if not pf.CraftingPage.CreateAllButton or not pf.CraftingPage.CreateAllButton.IsShown or not pf.CraftingPage.CreateAllButton:IsShown() then
        btn:Hide()
        return
    end

    if IsBlockedProfession() then
        btn:Hide()
        return
    end

    local recipeID = GetSelectedRecipeID()
    if not recipeID then
        btn:Hide()
        return
    end

    -- Hide for recipes with no reagents.
    if not HasAnyRequiredReagents(recipeID) then
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
			local eb = selfPopup.editBox or selfPopup.EditBox
			if eb then
				eb:SetText("1")
				eb:HighlightText()
			end
        end,
        OnAccept = function(selfPopup, data)
			local eb = selfPopup.editBox or selfPopup.EditBox
			local crafts = tonumber((eb and eb:GetText() or "") or "") or 1
            crafts = math.max(1, math.floor(crafts + 0.5))

            print("|cffff5555[QM]|r Pin Reagents OnAccept. crafts=" .. tostring(crafts))
            if not data or not data.reagents then
                print("|cffff5555[QM]|r Pin Reagents OnAccept: missing data/reagents")
                return
            end
	            local wl = (TheQuartermaster and TheQuartermaster.db and TheQuartermaster.db.profile and TheQuartermaster.db.profile.watchlist) or nil
	            local reagentTbl = wl and wl.reagents or nil
	            if not reagentTbl then
	                print("|cffff5555[QM]|r Pin Reagents OnAccept: watchlist table missing")
	                return
	            end
	            for itemID, qty in pairs(data.reagents) do
	                local delta = (qty * crafts)
	                local existing = (reagentTbl[itemID] and reagentTbl[itemID].desired) or 0
	                local newDesired = math.max(0, existing) + math.max(0, delta)
	                print("|cffff5555[QM]|r  - itemID=" .. tostring(itemID) .. " qty=" .. tostring(qty) .. " crafts=" .. tostring(crafts) .. " add=" .. tostring(delta) .. " desired " .. tostring(existing) .. "->" .. tostring(newDesired))
	                QM:ToggleWatchlistReagent(itemID, true, newDesired)
	            end
	            -- If the Watchlist UI is open, refresh it immediately.
	            if TheQuartermaster and TheQuartermaster.UI and TheQuartermaster.UI.WatchlistUI and TheQuartermaster.UI.WatchlistUI.PopulateContent then
	                TheQuartermaster.UI.WatchlistUI:PopulateContent()
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
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetFrameStrata("DIALOG")
    btn:SetFrameLevel(1000)
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
        print("|cffff5555[QM]|r Pin Reagents clicked. recipeID=" .. tostring(recipeID))
        if not recipeID then
            print("|cffff5555[QM]|r Pin Reagents: no selected recipe ID (nothing to pin).")
            return
        end

        local reagents = GetRequiredReagents(recipeID)
        local count = 0
        for _ in pairs(reagents) do count = count + 1 end
        print("|cffff5555[QM]|r Pin Reagents: reagents found=" .. tostring(count))

        if count == 0 then
            UIErrorsFrame:AddMessage("Quartermaster: No explicit required reagents to pin for this recipe.", 1, 0.1, 0.1)
            return
        end

        local dialog = StaticPopup_Show("QM_PIN_RECIPE_REAGENTS")
        print("|cffff5555[QM]|r Pin Reagents: StaticPopup_Show returned=" .. tostring(dialog))
        if dialog then
            dialog.data = dialog.data or {}
            dialog.data.reagents = reagents
            dialog.data.recipeID = recipeID
        end
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
end

-- Lightweight event driver
local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("TRADE_SKILL_SHOW")
driver:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
driver:SetScript("OnEvent", function()
    C_Timer.After(0.2, function()
        TryAttachButton()

        -- Refresh visibility when the selected recipe changes.
        UpdatePinButtonVisibility()
        EnsurePinTicker()
    end)
end)
