-- Browse verified character recipe caches without performing profession scans.
local _, ns = ...
local Addon, L = ns.TheQuartermaster, ns.L
local PAGE_SIZE = 20

function ns.UI_RecipeCatalog(db, professionID)
    local professions, crafters, byProfession, unverified = {}, {}, {}, 0
    for key, char in pairs(db.global.characters or {}) do
        local skills = {}
        local entries = {}
        for id, entry in pairs(char.professionRecipes or {}) do entries[id] = entry end
        for id, snapshot in pairs(char.professionRecipeDetails or {}) do
            if snapshot.version == 1 and (not entries[id] or not entries[id].ownerVerified) then
                local recipes = {}
                for rid, row in pairs(snapshot.rows) do if row.learned then recipes[#recipes + 1] = rid end end
                entries[id] = {ownerVerified = true, professionName = snapshot.professionName, recipes = recipes, lastScan = snapshot.checked}
            end
        end
        for id, entry in pairs(entries) do
            id = tonumber(id)
            if ns.IsTrackedRecipeProfession(id) then
                if entry.ownerVerified then
                    if not byProfession[id] then
                        byProfession[id] = {id = id, name = entry.professionName or tostring(id)}
                        professions[#professions + 1] = byProfession[id]
                    end
                    if not professionID or professionID == id then
                        local seen, count = {}, 0
                        for _, recipeID in ipairs(entry.recipes or {}) do
                            if not seen[recipeID] then seen[recipeID], count = true, count + 1 end
                        end
                        skills[#skills + 1] = {name = byProfession[id].name, count = count, lastScan = entry.lastScan}
                    end
                else
                    unverified = unverified + 1
                end
            end
        end
        if #skills > 0 then
            table.sort(skills, function(a, b) return a.name < b.name end)
            crafters[#crafters + 1] = {id = key, name = key, skills = skills}
        end
    end
    local function Sort(a, b)
        if a.name == b.name then return a.id < b.id end
        return a.name < b.name
    end
    table.sort(professions, Sort)
    crafters = ns.SortCharacterRows(db, crafters, function(row) return row.id end)
    return professions, crafters, unverified
end

local function Text(parent, value, x, y, width, font)
    local text = ns.UI_RenderFontString(parent, nil, "OVERLAY", font or "QuartermasterFontBody")
    text:SetPoint("TOPLEFT", x, -y)
    text:SetWidth(math.max(1, width))
    text:SetJustifyH("LEFT")
    text:SetTextColor(unpack(ns.UI_COLORS.textNormal))
    text:SetText(value)
    return text
end

local function Button(parent, value, x, y, width, callback, selected)
    local colors = ns.UI_COLORS
    local button = ns.UI_RenderFrame("Button", nil, parent, "BackdropTemplate")
    button:SetPoint("TOPLEFT", x, -y)
    button:SetSize(width, 28)
    button:SetEnabled(true)
    button:SetAlpha(1)
    button:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    button:SetBackdropColor(unpack(colors.bgCard))
    button:SetBackdropBorderColor(unpack(selected and colors.accent or colors.border))
    button.recipeLabel = Text(button, value, 10, 7, width - 20, "QuartermasterFontSmall")
    button.recipeLabel:SetWordWrap(false)
    button:SetScript("OnClick", callback)
    button:SetScript("OnEnter", function(b)
        b:SetBackdropBorderColor(unpack(colors.accent))

    end)
    button:SetScript("OnLeave", function(b)
        b:SetBackdropBorderColor(unpack(selected and colors.accent or colors.border))
        GameTooltip:Hide()
    end)
    return button
end

local BindItemLabel

-- One reusable popup for all recipe filters and ingredient choices.
local function RecipeMenu(anchor, build)
    GameTooltip:Hide()
    local popup = Addon.recipeDropdown
    if popup and popup:IsShown() and popup.anchor == anchor then popup:Hide(); return end
    if not popup then
        popup = CreateFrame("Frame", "QuartermasterRecipeDropdown", UIParent, "BackdropTemplate")
        Addon.recipeDropdown = popup
        popup:SetFrameStrata("DIALOG")
        popup:SetClampedToScreen(true)
        popup:EnableMouse(true)
        popup.rows = {}
        if UISpecialFrames then table.insert(UISpecialFrames, "QuartermasterRecipeDropdown") end
        popup:SetScript("OnUpdate", function(p)
            if not p.anchor or not p.anchor:IsShown() then p:Hide(); return end
            local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
            if down and not p.mouseDown and not p:IsMouseOver() and not p.anchor:IsMouseOver() then p:Hide() end
            p.mouseDown = down
        end)
    end
    popup.anchor = anchor
    -- The main window is raised within DIALOG; a UIParent child otherwise sits behind it.
    popup:SetFrameStrata(anchor:GetFrameStrata())
    popup:SetFrameLevel(anchor:GetFrameLevel() + 10)
    popup:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    local choices = {}
    build(anchor, {CreateButton = function(_, label, callback, itemID)
        choices[#choices + 1] = {label = label, callback = callback, itemID = itemID}
    end})
    local width, pageSize = anchor:GetWidth(), 12
    local function Draw(page)
        for _, row in ipairs(popup.rows) do row.recipeChoice = nil; row:Hide() end
        local visible = {}
        for index = (page - 1) * pageSize + 1, math.min(#choices, page * pageSize) do
            visible[#visible + 1] = choices[index]
        end
        if page > 1 then visible[#visible + 1] = {label = L.RB_PREVIOUS, callback = function() Draw(page - 1) end, paging = true} end
        if page * pageSize < #choices then visible[#visible + 1] = {label = L.RB_NEXT, callback = function() Draw(page + 1) end, paging = true} end
        popup:SetSize(width, math.max(28, #visible * 28))
        for index, choice in ipairs(visible) do
            local row = popup.rows[index]
            if not row then
                row = CreateFrame("Button", nil, popup, "BackdropTemplate")
                popup.rows[index] = row
                row:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
                row.label = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
                row.label:SetPoint("LEFT", 8, 0)
                row.label:SetJustifyH("LEFT"); row.label:SetWordWrap(false)
            end
            row:SetFrameLevel(popup:GetFrameLevel() + 1)
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(index - 1) * 28)
            row:SetSize(width, 28); row.label:SetWidth(width - 16)
            row.recipeChoice = choice
            row.label:SetText(choice.itemID and ns.UI_IngredientVariantLabel(choice.itemID, true) or choice.label)
            row.label:SetTextColor(unpack(ns.UI_COLORS.textNormal))
            if choice.itemID then
                BindItemLabel(row.label, choice.itemID, function(itemID)
                    return ns.UI_IngredientVariantLabel(itemID, true)
                end, function()
                    return popup:IsShown() and popup.anchor == anchor and anchor:IsShown()
                        and row.recipeChoice == choice and row:IsShown()
                end)
            end
            row:SetBackdropColor(unpack(ns.UI_COLORS.bgCard))
            row:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
            row:SetScript("OnEnter", function(b) b:SetBackdropBorderColor(unpack(ns.UI_COLORS.accent)) end)
            row:SetScript("OnLeave", function(b) b:SetBackdropBorderColor(unpack(ns.UI_COLORS.border)) end)
            row:SetScript("OnClick", function()
                if not choice.paging then popup:Hide() end
                choice.callback()
            end)
            row:Show()
        end
    end
    Draw(1)
    popup.mouseDown = true
    popup:Show()
end

ns.UI_RecipeMenu = RecipeMenu

local function IngredientName(id)
    local name = GetItemInfo and GetItemInfo(id)
    if (issecretvalue and issecretvalue(name)) or type(name) ~= "string" then
        return string.format(L.RI_ITEM, id)
    end
    return name
end

-- Update only labels when uncached item metadata arrives; do not rebuild active editors.
local itemLabels = {}
BindItemLabel = function(label, id, formatter, isCurrent)
    local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    local ok, name = pcall(getInfo, id)
    if ok and not (issecretvalue and issecretvalue(name)) and type(name) == "string" then return end
    if not ns.recipeItemDataListener then
        local listener = CreateFrame("Frame")
        ns.recipeItemDataListener = listener
        listener:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        listener:RegisterEvent("ITEM_DATA_LOAD_RESULT")
        listener:SetScript("OnEvent", function(_, _, itemID, success)
            if (issecretvalue and (issecretvalue(itemID) or issecretvalue(success)))
                or type(itemID) ~= "number" or success ~= true then return end
            local bindings = itemLabels[itemID]
            if not bindings then return end
            local frame = Addon.UI and Addon.UI.mainFrame
            if frame and (not frame:IsShown() or frame.currentTab ~= "recipes") then
                itemLabels = {}; return
            end
            local loaded, itemName = pcall(getInfo, itemID)
            if not loaded or (issecretvalue and issecretvalue(itemName)) or type(itemName) ~= "string" then return end
            itemLabels[itemID] = nil
            for _, binding in ipairs(bindings) do
                if binding.label:IsShown() and (not binding.isCurrent or binding.isCurrent()) then
                    binding.label:SetText(binding.formatter(itemID))
                end
            end
        end)
    end
    local first = not itemLabels[id]
    itemLabels[id] = itemLabels[id] or {}
    itemLabels[id][#itemLabels[id] + 1] = {label = label, formatter = formatter, isCurrent = isCurrent}
    if first and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end

-- Item IDs keep same-name alternatives distinguishable when quality data is absent.
function ns.UI_IngredientVariantLabel(id, short)
    local quality
    local api = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
    if api then
        local ok, value = pcall(api, id)
        if ok and not (issecretvalue and issecretvalue(value)) and type(value) == "number"
            and value > 0 and value <= 10 and value == math.floor(value) then quality = value end
    end
    local name = IngredientName(id)
    local expansion
    local itemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    if quality and itemInfo then
        local ok, value = pcall(function() return select(15, itemInfo(id)) end)
        if ok and not (issecretvalue and issecretvalue(value)) and type(value) == "number" then
            expansion = value
        end
    end
    -- Use the reagent's expansion, independently of the current recipe filter.
    local label
    if expansion == 11 then -- Midnight: two quality tiers.
        label = ({L.RI_SILVER, L.RI_GOLD})[quality]
    elseif expansion == 9 or expansion == 10 then -- Dragonflight / The War Within.
        label = ({L.RI_BRONZE, L.RI_SILVER, L.RI_GOLD})[quality]
    end
    if short and label then return label end
    if label then return string.format(L.RI_VARIANT_NAMED, name, label, id) end
    if quality then return string.format(L.RI_VARIANT_QUALITY, name, quality, id) end
    return string.format(L.RI_VARIANT_ID, name, id)
end

local function DrawMaterialOption(addon, parent, id, quantity, y, width, alternative, recipeID, crafts)
    local name = alternative and ns.UI_IngredientVariantLabel(id) or IngredientName(id)
    local total = addon:CountItemTotals(id, addon:WatchlistIncludesGuildBank())
    local tracked = addon:IsRecipeIngredientTracked(recipeID, id)
    local line = Text(parent, name, 20, y, width - 220)
    BindItemLabel(line, id, IngredientName)
    local nameHeight = math.max(18, line:GetStringHeight())
    local counts = Text(parent, string.format(L.RI_COUNTS, quantity, total, math.max(0, quantity - total)), 20, y + nameHeight + 4, width - 220, "QuartermasterFontSmall")
    local button = Button(parent, tracked and L.RI_TRACKED or (alternative and L.RI_TRACK_VARIANT or L.RI_TRACK), width - 180, y, 190, function()
        addon:ToggleRecipeIngredient(recipeID, id, quantity, crafts)
    end, tracked)
    button:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(id)
        GameTooltip:Show()
    end)
    return y + math.max(50, nameHeight + counts:GetStringHeight() + 16)
end

local function DrawCraftQuantity(addon, parent, recipeID, snapshot, y, width, refresh)
    addon.recipeCraftCounts = addon.recipeCraftCounts or {}
    local count = addon:GetRecipeWatchlistCrafts(recipeID)
    -- One persistent editor, outside the render pool; input commits only on Apply/Enter.
    local edit = addon.recipeCraftEditor
    if not edit then
        edit = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
        addon.recipeCraftEditor = edit
        edit:SetAutoFocus(false)
        edit:SetNumeric(true)
        edit:SetMaxLetters(5)
        edit:SetFontObject("QuartermasterFontBody")
        edit:SetTextInsets(8, 8, 0, 0)
        edit:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        edit:SetBackdropColor(unpack(ns.UI_COLORS.bgCard))
        edit:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
        edit:SetTextColor(unpack(ns.UI_COLORS.textNormal))
        edit:SetScript("OnHide", function(b) b:ClearFocus() end)
    end
    Text(parent, L.RQ_CRAFTS, 20, y + 7, 120)
    edit:ClearAllPoints()
    edit:SetPoint("TOPLEFT", 145, -y)
    edit:SetSize(90, 28)
    edit:SetText(tostring(count))
    edit:Show()
    local function Apply()
        local value = ns.RecipeCraftCount(edit:GetText())
        if not value then
            addon.recipeCraftError = recipeID
        else
            addon.recipeCraftError = nil
            addon.recipeCraftCounts[recipeID] = value
            addon:UpdateRecipeIngredientTargets(recipeID, snapshot, value)
        end
        edit:ClearFocus()
        refresh()
    end
    edit:SetScript("OnEnterPressed", Apply)
    edit:SetScript("OnEscapePressed", function(b) b:SetText(tostring(count)); b:ClearFocus() end)
    Button(parent, L.RQ_APPLY, 245, y, 110, Apply)
    return y + 36, count
end

local function IngredientChoices(addon, recipeID, snapshot)
    local state = addon.recipeIngredientChoices
    if not state or state.recipeID ~= recipeID or state.snapshot ~= snapshot then
        state = {recipeID = recipeID, snapshot = snapshot, choices = {}}
        addon.recipeIngredientChoices = state
    end
    for index, row in ipairs(ns.RecipeMaterialRows(snapshot, 1)) do
        if not row.itemID and not state.choices[index] then
            local selected, count = nil, 0
            for _, id in ipairs(row.itemIDs) do
                if addon:IsRecipeIngredientTracked(recipeID, id) then selected, count = id, count + 1 end
            end
            if count == 1 then state.choices[index] = selected end
        end
    end
    return state
end


local function DrawMaterialChoices(addon, parent, recipeID, row, state, index, crafts, y, width, refresh)
    local id = state.choices[index]
    local dropdownLabel = id and ns.UI_IngredientVariantLabel(id, true) or L.RI_SELECT_QUALITY
    -- The menu retains names and IDs for alternatives that are not quality tiers.
    local dropdownWidth = math.min(330, width * 0.36)
    local nameLabel = Text(parent, IngredientName(id or row.itemIDs[1]), 20, y, width - dropdownWidth - 240)
    nameLabel:SetWordWrap(false)
    BindItemLabel(nameLabel, id or row.itemIDs[1], IngredientName)
    local total = id and addon:CountItemTotals(id, addon:WatchlistIncludesGuildBank())
    local counts = id and string.format(L.RI_COUNTS, row.quantity, total, math.max(0, row.quantity - total))
        or string.format(L.RI_SELECT_COUNTS, row.quantity)
    Text(parent, counts, 20, y + 32, width - 220, "QuartermasterFontSmall")
    local dropdown = Button(parent, dropdownLabel .. "  v", width - 200 - dropdownWidth, y, dropdownWidth, function(button)
        RecipeMenu(button, function(_, menu)
            for _, candidate in ipairs(row.itemIDs) do
                menu:CreateButton(ns.UI_IngredientVariantLabel(candidate, true), function()
                    addon:ReplaceTrackedRecipeVariant(recipeID, row, candidate)
                    state.choices[index] = candidate
                    refresh()
                end, candidate)
            end
        end)
    end)
    if id then BindItemLabel(dropdown.recipeLabel, id, function(itemID)
        return ns.UI_IngredientVariantLabel(itemID, true) .. "  v"
    end) end
    local tracked = id and addon:IsRecipeIngredientTracked(recipeID, id)
    local button = Button(parent, tracked and L.RI_TRACKED or L.RI_TRACK, width - 180, y, 190, function()
        if id then addon:ToggleRecipeIngredient(recipeID, id, row.quantity, crafts) end
    end, tracked)
    button:SetEnabled(id ~= nil)
    button:SetAlpha(id and 1 or 0.4)
    return y + 64
end

local function DrawIngredients(addon, parent, result, y, width, refresh)
    local snapshot, owner = addon:GetRecipeIngredients(result.recipeID, result.crafters)
    local function RefreshIngredients()
        addon.recipeIngredientFailure = not addon:CollectRecipeIngredients(result.recipeID) and result.recipeID or nil
        refresh()
    end
    if not snapshot then
        Button(parent, L.RI_COLLECT, 20, y, 210, RefreshIngredients)
        local hint = Text(parent, addon.recipeIngredientFailure == result.recipeID and L.RI_FAILED or L.RI_HINT,
            20, y + 36, width - 20, "QuartermasterFontSmall")
        return y + 36 + math.max(32, hint:GetStringHeight() + 12)
    end
    local toolbarY, crafts = y
    y, crafts = DrawCraftQuantity(addon, parent, result.recipeID, snapshot, y, width, refresh)
    local state = IngredientChoices(addon, result.recipeID, snapshot)
    local actionsY = width < 780 and y or toolbarY
    Button(parent, L.RA_TRACK_ALL, width < 780 and 20 or 365, actionsY, 200, function()
        state.incomplete = not addon:TrackAllRecipeIngredients(result.recipeID, snapshot, crafts, state.choices)
        refresh()
    end)
    local expanded = addon.recipeIngredientDetails == result.recipeID
    Button(parent, L.RI_DETAILS, width - 180, actionsY, 190, function()
        addon.recipeIngredientDetails = not expanded and result.recipeID or nil
        refresh()
    end, expanded)
    if width < 780 then y = y + 36 end
    local errorText = addon.recipeCraftError == result.recipeID and L.RQ_INVALID
        or (state.incomplete and L.RI_SELECT_MISSING)
        or (addon.recipeIngredientFailure == result.recipeID and L.RI_FAILED)
    if errorText then
        local label = Text(parent, errorText, 20, y, width - 20, "QuartermasterFontSmall")
        y = y + math.max(30, label:GetStringHeight() + 12)
    end
    if expanded then
        Button(parent, L.RI_REFRESH, 20, y, 210, RefreshIngredients)
        y = y + 36
        local details = table.concat({table.concat(result.crafters, ", "),
            string.format(L.RQ_SOURCE, owner, date("%Y-%m-%d", snapshot.collectedAt), crafts),
            L.RI_READY, L.RQ_HINT, L.RI_SELECT_ALL, L.RI_SCOPE}, "\n\n")
        local label = Text(parent, details, 20, y, width - 20, "QuartermasterFontSmall")
        y = y + label:GetStringHeight() + 16
    end
    Text(parent, L.RI_REQUIRED, 20, y, width - 20)
    y = y + 28
    local choices = IngredientChoices(addon, result.recipeID, snapshot)
    for index, row in ipairs(ns.RecipeMaterialRows(snapshot, crafts)) do
        if row.itemID then
            y = DrawMaterialOption(addon, parent, row.itemID, row.quantity, y, width, false, result.recipeID, crafts)
        else
            y = DrawMaterialChoices(addon, parent, result.recipeID, row, choices, index, crafts, y, width, refresh)
        end
    end
    return y + 8
end

local function IngredientScanStatus(addon)
    local status = addon.recipeIngredientScanStatus
    if not status then return L.AI_IDLE end
    return string.format(L["AI_" .. status.state], status.name, status.checked, status.total, status.refreshed, status.cached)
end
function Addon:UpdateRecipeIngredientScanUI(redraw)
    local frame = self.UI and self.UI.mainFrame
    if not frame or not frame:IsShown() or frame.currentTab ~= "recipes" then return end
    if self.recipeIngredientProgressText then self.recipeIngredientProgressText:SetText(IngredientScanStatus(self)) end
    local editor = self.recipeCraftEditor
    if redraw and not (editor and editor.HasFocus and editor:HasFocus()) then self:RefreshUI() end
end

function Addon:DrawRecipesTab(parent)
    itemLabels = {}
    if self.recipeDropdown then self.recipeDropdown:Hide() end
    if self.recipeCraftEditor then self.recipeCraftEditor:Hide() end
    self.recipeBrowserPool = self.recipeBrowserPool or ns.UI_NewRenderPool(parent)
    local pool = self.recipeBrowserPool
    local width, y = parent:GetWidth() - 20, 10
    parent = pool:Begin(width)
    self.recipeBrowser = self.recipeBrowser or {page = 1, optionPage = 1}
    local state = self.recipeBrowser
    local function Refresh(reset)
        if reset then state.page, state.selected = 1, nil end
        self:RefreshUI()
    end
    self.recipeIngredientProgressText = nil
    if not self.db or not self.db.profile or not self.db.global then
        Text(parent, L.RB_DB_WAIT, 10, y, width)
        return pool:Finish(y + 50)
    end
    if not self.db.profile.trackProfessionRecipes then
        Text(parent, L.RB_DISABLED, 10, y, width)
        return pool:Finish(y + 60)
    end
    local professions, crafters, unverified = ns.UI_RecipeCatalog(self.db, state.professionID)
    local function Selected(list, id, fallback)
        for _, choice in ipairs(list) do if choice.id == id then return choice.name end end
        return fallback
    end
    if state.professionID and Selected(professions, state.professionID) == nil then
        state.professionID, state.charKey = nil, nil
        professions, crafters, unverified = ns.UI_RecipeCatalog(self.db)
    end
    if state.charKey and Selected(crafters, state.charKey) == nil then state.charKey = nil end
    local quarter = (width - 24) / 4
    Button(parent, string.format(L.RB_MODE_DROPDOWN, L["PD_MODE_" .. (state.mode or "all")]), 10, y, quarter, function(button)
        RecipeMenu(button, function(_, menu)
            for _, mode in ipairs({"all", "learned", "unlearned"}) do
                menu:CreateButton(L["PD_MODE_" .. mode], function() state.mode = mode; Refresh(true) end)
            end
        end)
    end)
    local function Filter(button, list, allLabel, profession)
        RecipeMenu(button, function(_, menu)
            local function Choose(id)
                if profession then state.professionID, state.charKey = id, nil else state.charKey = id end
                Refresh(true)
            end
            menu:CreateButton(allLabel, function() Choose(nil) end)
            for _, choice in ipairs(list) do
                menu:CreateButton(choice.name, function() Choose(choice.id) end)
            end
        end)
    end
    Button(parent, L.RB_PROFESSION .. Selected(professions, state.professionID, L.RB_ALL_PROFESSIONS), 18 + quarter, y, quarter, function(button)
        Filter(button, professions, L.RB_ALL_PROFESSIONS, true)
    end)
    Button(parent, L.RB_CRAFTER .. Selected(crafters, state.charKey, L.RB_ALL_CRAFTERS), 26 + 2 * quarter, y, quarter, function(button)
        Filter(button, crafters, L.RB_ALL_CRAFTERS, false)
    end)
    Button(parent, state.expansion or L.PD_ALL_EXPANSIONS, 34 + 3 * quarter, y, quarter, function(button)
        RecipeMenu(button, function(_, menu)
            menu:CreateButton(L.PD_ALL_EXPANSIONS, function() state.expansion = nil; Refresh(true) end)
            local found, names = {}, {}
            for key, char in pairs(self.db.global.characters or {}) do
                if not state.charKey or key == state.charKey then
                    for id, snapshot in pairs(char.professionRecipeDetails or {}) do
                        if snapshot.version == 1 and (not state.professionID or id == state.professionID) then
                            for _, row in pairs(snapshot.rows) do
                                if row.expansion ~= "" and not found[row.expansion] then found[row.expansion] = true; names[#names + 1] = row.expansion end
                            end
                        end
                    end
                end
            end
            table.sort(names,ns.ExpansionNewestFirst)
            for _, name in ipairs(names) do menu:CreateButton(name, function() state.expansion = name; Refresh(true) end) end
        end)
    end)
    y = y + 36
    local function Pager(page, pages, change)
        Button(parent, L.RB_PREVIOUS, 10, y, 90, function() change(math.max(1, page - 1)) end)
        Text(parent, string.format(L.RB_PAGE, page, pages), 110, y + 7, width - 210, "QuartermasterFontSmall")
        Button(parent, L.RB_NEXT, width - 80, y, 90, function() change(math.min(pages, page + 1)) end)
        y = y + 38
    end
    Button(parent, L.PD_REFRESH, 10, y, quarter, function() state.details = true; self:ScanProfessionDepth(); Refresh() end)
    Button(parent, string.format(state.showCrafters and L.RB_HIDE_CRAFTERS or L.RB_SHOW_CRAFTERS, #crafters), 18 + quarter, y, quarter, function()
        state.showCrafters = not state.showCrafters
        state.options = nil; Refresh()
    end, state.showCrafters)
    Button(parent, L.RB_CLEAR_FILTERS, 26 + 2 * quarter, y, quarter, function()
        state.professionID, state.charKey, state.options, state.crafterPage = nil, nil, nil, 1
        state.mode, state.expansion = nil, nil
        ns.recipesSearchText = ""
        local frame = self.UI and self.UI.mainFrame
        local box = frame and frame.persistentSearchBoxes and frame.persistentSearchBoxes.recipes
        if box and box.editBox then box.editBox:SetText("") end
        Refresh(true)
    end)
    Button(parent, unverified > 0 and string.format(L.RB_SCAN_DETAILS_OLD, unverified) or L.RB_SCAN_DETAILS,
        34 + 3 * quarter, y, quarter, function() state.details = not state.details; Refresh() end, state.details)
    y = y + 38
    if state.details then
        local function Detail(value)
            local line = Text(parent, value, 10, y, width, "QuartermasterFontSmall")
            y = y + math.max(24, line:GetStringHeight() + 10)
            return line
        end
        Detail(L.RECIPE_OWNER_GUIDANCE)
        Detail(L.PD_SCOPE)
        if self.recipeScanState then Detail(L["RS_" .. self.recipeScanState]) end
        self.recipeIngredientProgressText = Detail(IngredientScanStatus(self))
        if self.professionDepthState then
            local missing=self.professionDepthMissing
            if self.professionDepthState=="partial" and missing then
                Detail(string.format(L.PD_SCAN_partial,missing.count,missing.id))
            else Detail(L["PD_SCAN_" .. self.professionDepthState]) end
        end
        if unverified > 0 then Detail(string.format(L.RB_UNVERIFIED, unverified)) end
    end
    if state.showCrafters then
        local crafterPages = math.max(1, math.ceil(#crafters / 6))
        state.crafterPage = math.min(state.crafterPage or 1, crafterPages)
        for i = (state.crafterPage - 1) * 6 + 1, math.min(#crafters, state.crafterPage * 6) do
            local crafter, lines = crafters[i], {}
            for _, skill in ipairs(crafter.skills) do
                local stamp = type(skill.lastScan) == "number" and skill.lastScan > 0 and date("%Y-%m-%d", skill.lastScan) or L.RB_SCAN_UNKNOWN
                lines[#lines + 1] = string.format(L.RB_SKILL_SUMMARY, skill.name, skill.count, stamp)
            end
            local row = Button(parent, crafter.name, 10, y, width, function()
                state.charKey, state.showCrafters, state.options = crafter.id, false, nil
                Refresh(true)
            end, state.charKey == crafter.id)
            local summary = Text(row, table.concat(lines, "\n"), 10, 27, width - 20, "QuartermasterFontSmall")
            local height = math.max(48, summary:GetStringHeight() + 38)
            row:SetHeight(height)
            y = y + height + 6
        end
        if #crafters == 0 then Text(parent, L.RB_NO_CRAFTERS, 10, y, width); y = y + 40 end
        if crafterPages > 1 then Pager(state.crafterPage, crafterPages, function(page) state.crafterPage = page; Refresh() end) end
    end
    local query = ns.recipesSearchText or ""
    if state.query ~= query then state.query, state.page, state.selected = query, 1, nil end
    local results = self:FindProfessionRecipes(query, {professionID = state.professionID, charKey = state.charKey,
        mode = state.mode or "all", expansion = state.expansion})
    local pages = math.max(1, math.ceil(#results / PAGE_SIZE))
    state.page = math.min(state.page, pages)
    Text(parent, string.format(L.PD_RESULTS, #results), 10, y, width)
    y = y + 28
    local function ChangePage(page)
        state.page, state.selected = page, nil
        local frame = self.UI and self.UI.mainFrame
        if frame and frame.scroll then frame.scroll:SetVerticalScroll(0) end
        Refresh()
    end
    Pager(state.page, pages, ChangePage)
    if #results == 0 then Text(parent, L.RB_EMPTY, 10, y, width); y = y + 60 end
    for i = (state.page - 1) * PAGE_SIZE + 1, math.min(#results, state.page * PAGE_SIZE) do
        local result = results[i]
        local selected = state.selected == result.recipeID
        local row = Button(parent, (selected and "- " or "+ ") .. result.name, 10, y, width, function()
            state.selected = not selected and result.recipeID or nil; Refresh()
        end, selected)
        row:SetScript("OnEnter", function(b)
            b:SetBackdropBorderColor(unpack(ns.UI_COLORS.accent))
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            if result.itemID then GameTooltip:SetItemByID(result.itemID) else GameTooltip:SetText(result.name) end
            local source = state.charKey and result.learning[state.charKey]
            if not source then
                for _, key in ipairs(result.missing) do if result.learning[key] then source = result.learning[key]; break end end
            end
            if source then GameTooltip:AddLine(source, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        row:SetHeight(44)
        if #result.crafters == 0 then
            Text(row, L.PD_NO_CRAFTERS, 10, 26, width - 20, "QuartermasterFontEmphasis"):SetTextColor(unpack(ns.UI_COLORS.red))
        else
            Text(row, string.format(result.selectedLearned and L.RB_KNOWN_BY or L.PD_MISSING_BY, #result.crafters), 10, 27, width - 20, "QuartermasterFontSmall")
        end
        y = y + 50
        if selected then
            if result.missing and #result.missing > 0 then
                local lines, seen = {}, {}
                for _, key in ipairs(result.missing) do
                    if not state.charKey or key == state.charKey then
                        local source = result.learning[key] or L.PD_SOURCE_UNKNOWN
                        if not seen[source] then lines[#lines + 1] = source; seen[source] = true end
                    end
                end
                if #lines > 0 then
                    local instructions = Text(parent, L.PD_LEARN .. "\n" .. table.concat(lines, "\n\n"), 20, y, width - 20)
                    y = y + math.max(42, instructions:GetStringHeight() + 16)
                end
            end
            if #result.crafters > 0 then y = DrawIngredients(self, parent, result, y, width, Refresh) end
            local third = (width - 16) / 3
            if result.itemID then
                Button(parent, self:IsWatchlistedItem(result.itemID) and L.RB_UNPIN or L.RB_PIN, 10, y, third, function()
                    self:ToggleWatchlistItem(result.itemID)
                end)
            else Text(parent, L.RB_NO_OUTPUT, 10, y, third, "QuartermasterFontSmall") end
            Button(parent, L.RB_MATERIALS, 18 + third, y, third, function() self:OpenDashboardDestination("materials") end)
            Button(parent, L.RB_WATCHLIST, 26 + third * 2, y, third, function() self.recipeWatchlistScope = result.recipeID; self.watchlistReagentPage = 1; self:OpenDashboardDestination("watchlist") end)
            y = y + 44
        end
    end
    if pages > 1 then Pager(state.page, pages, ChangePage) end
    Button(parent, L.RB_RESET, 10, y + 10, 210, function() self:ClearProfessionRecipeCache(nil); Refresh(true) end)
    return pool:Finish(y + 54)
end
