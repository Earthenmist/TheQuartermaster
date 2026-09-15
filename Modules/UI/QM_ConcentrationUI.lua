local _, ns = ...
local Addon, L = ns.TheQuartermaster, ns.L
local function Text(parent, value, x, y, width, color, small)
    local label = ns.UI_RenderFontString(parent, nil, "OVERLAY", small and "QuartermasterFontSmall" or "QuartermasterFontBody")
    label:SetPoint("TOPLEFT", x, -y); label:SetWidth(math.max(1, width)); label:SetJustifyH("LEFT")
    label:SetText(value); label:SetTextColor(unpack(color or ns.UI_COLORS.textNormal))
    return label
end
local function Card(parent, x, y, width, height)
    local frame = ns.UI_RenderFrame("Button", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", x, -y); frame:SetSize(width, height)
    frame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    frame:SetBackdropColor(unpack(ns.UI_COLORS.bgCard)); frame:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
    return frame
end
local function Names(values)
    local result = {}; for name in pairs(values or {}) do result[#result + 1] = name end
    table.sort(result); return result
end
local function Dropdown(parent, label, x, y, width, choices, select)
    local button = Card(parent, x, y, width, 28)
    Text(button, label .. "  v", 10, 7, width - 20, nil, true):SetWordWrap(false)
    button:SetScript("OnClick", function(b)
        ns.UI_RecipeMenu(b, function(_, menu)
            for _, choice in ipairs(choices) do menu:CreateButton(choice.label, function() select(choice.id) end) end
        end)
    end)
    button:SetScript("OnEnter", function(b) b:SetBackdropBorderColor(unpack(ns.UI_COLORS.accent)) end)
    button:SetScript("OnLeave", function(b) b:SetBackdropBorderColor(unpack(ns.UI_COLORS.border)) end)
end
function Addon:DrawConcentration(parent)
    if self.recipeDropdown then self.recipeDropdown:Hide() end
    if not self._concentrationViewTimer and C_Timer and C_Timer.After then
        self._concentrationViewTimer = true
        C_Timer.After(60, function()
            self._concentrationViewTimer = nil
            local main = self.UI and self.UI.mainFrame
            if self._professionDepthEnabled and main and main:IsShown() and main.currentTab == "concentration" then self:RefreshUI() end
        end)
    end
    self.concentrationPool = self.concentrationPool or ns.UI_NewRenderPool(parent)
    local width = parent:GetWidth() - 20
    local root = self.concentrationPool:Begin(parent:GetWidth())
    if not self.concentrationFilters then
        local expansion = GetExpansionLevel and GetExpansionLevel()
        self.concentrationFilters = {expansion = ns.Wealth.Number(expansion) and _G["EXPANSION_NAME" .. expansion] or nil}
    end
    local state = self.concentrationFilters
    local rows, chars, professions, expansions = {}, {}, {}, {}
    for key, char in pairs(self.db.global.characters or {}) do
        for id, pool in pairs(char.professionConcentration or {}) do
            local estimate = ns.ConcentrationEstimate(pool, time())
            if estimate then
                chars[key] = true; professions[pool.professionID] = pool.professionName
                for name in pairs(pool.expansions or {}) do expansions[name] = true end
                rows[#rows + 1] = {key = key, id = id, pool = pool, estimate = estimate}
            end
        end
    end
    local charChoices, profChoices, expChoices = {{label = L.RB_ALL_CRAFTERS}}, {{label = L.RB_ALL_PROFESSIONS}}, {{label = L.PD_ALL_EXPANSIONS}}
    for _, name in ipairs(Names(chars)) do charChoices[#charChoices + 1] = {id = name, label = name} end
    for id, name in pairs(professions) do profChoices[#profChoices + 1] = {id = id, label = name} end
    table.sort(profChoices, function(a, b) if a.id == b.id then return false elseif not a.id then return true elseif not b.id then return false end return a.label < b.label end)
    local expansionNames=Names(expansions);table.sort(expansionNames,ns.ExpansionNewestFirst)
    for _, name in ipairs(expansionNames) do expChoices[#expChoices + 1] = {id = name, label = name} end
    local quarter = (width - 24) / 4
    local function Set(field, value) state[field] = value; state.page = 1; self:RefreshUI() end
    Dropdown(root, state.expansion or L.PD_ALL_EXPANSIONS, 10, 10, quarter, expChoices, function(v) Set("expansion", v) end)
    Dropdown(root, professions[state.profession] or L.RB_ALL_PROFESSIONS, 18 + quarter, 10, quarter, profChoices, function(v) Set("profession", v) end)
    Dropdown(root, state.character or L.RB_ALL_CRAFTERS, 26 + quarter * 2, 10, quarter, charChoices, function(v) Set("character", v) end)
    Dropdown(root, L["PC_FILTER_" .. (state.status or "all")], 34 + quarter * 3, 10, quarter,
        {{label = L.PC_FILTER_all}, {id = "near", label = L.PC_FILTER_near}, {id = "full", label = L.PC_FILTER_full}}, function(v) Set("status", v) end)
    local guide = Text(root, L.PC_GUIDE, 10, 50, width, ns.UI_COLORS.textDim, true)
    local y = 50 + math.max(42, guide:GetStringHeight() + 14)
    if not self.db.profile.trackProfessionRecipes then
        Text(root, L.RB_DISABLED, 10, y, width); return self.concentrationPool:Finish(y + 65)
    end
    local filtered, full, near, total = {}, 0, 0, 0
    for _, row in ipairs(rows) do
        local pool, estimate = row.pool, row.estimate
        if (not state.character or state.character == row.key) and (not state.profession or state.profession == pool.professionID)
            and (not state.expansion or pool.expansions[state.expansion]) then
            total = total + 1
            local reliable = estimate.rateKnown or not estimate.estimated
            local isFull = reliable and estimate.amount >= estimate.cap
            local isNear = reliable and estimate.amount / estimate.cap >= 0.8
            if isFull then full = full + 1 end
            if isNear then near = near + 1 end
            if not state.status or state.status == "full" and isFull or state.status == "near" and isNear then filtered[#filtered + 1] = row end
        end
    end
    local third = (width - 16) / 3
    for index, summary in ipairs({{L.PC_POOLS, total}, {L.PC_NEAR, near}, {L.PC_FULL, full}}) do
        local card = Card(root, 10 + (index - 1) * (third + 8), y, third, 65)
        Text(card, summary[1], 12, 10, third - 24, ns.UI_COLORS.textDim, true)
        Text(card, tostring(summary[2]), 12, 34, third - 24, ns.UI_COLORS.accent)
    end
    y = y + 78
    local note = Text(root, L.PC_ESTIMATE_NOTE, 10, y, width, ns.UI_COLORS.textDim, true)
    y = y + math.max(36, note:GetStringHeight() + 12)
    table.sort(filtered, function(a, b)
        local ar, br = a.estimate.amount / a.estimate.cap, b.estimate.amount / b.estimate.cap
        if ar ~= br then return ar > br end
        if a.key ~= b.key then return a.key < b.key end
        return a.id < b.id
    end)
    local pages = math.max(1, math.ceil(#filtered / 20))
    state.page = math.min(state.page or 1, pages)
    for index = (state.page - 1) * 20 + 1, math.min(#filtered, state.page * 20) do
        local row = filtered[index]
        local pool, estimate = row.pool, row.estimate
        local card = Card(root, 10, y, width, 92)
        local icon = ns.UI_RenderTexture(card, nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 12, -14); icon:SetSize(30, 30); icon:SetTexture(pool.icon or 136243)
        Text(card, row.key, 52, 12, width * 0.43 - 58):SetWordWrap(false)
        Text(card, pool.professionName, 52, 34, width * 0.43 - 58, ns.UI_COLORS.accent, true)
        Text(card, table.concat(Names(pool.expansions), " / "), 12, 64, width * 0.45 - 24, ns.UI_COLORS.textDim, true)
        local amount = string.format(L.PC_AMOUNT, estimate.amount, estimate.cap)
        if estimate.estimated then amount = (estimate.rateKnown and L.PC_ESTIMATED or L.PC_CACHED) .. amount end
        Text(card, amount, width * 0.46, 12, width * 0.31, ns.UI_COLORS.accent)
        local recharge = L.PC_RATE_UNKNOWN
        if estimate.remaining then
            if estimate.remaining == 0 then recharge = L.PC_FULL
            else recharge = string.format(L.PC_FULL_IN, math.floor(estimate.remaining / 3600), math.ceil(estimate.remaining % 3600 / 60)) end
        end
        Text(card, recharge, width * 0.78, 12, width * 0.21, nil, true)
        local barWidth = width * 0.52
        local track = ns.UI_RenderTexture(card, nil, "ARTWORK")
        track:SetPoint("TOPLEFT", width * 0.46, -44); track:SetSize(barWidth, 5); track:SetColorTexture(unpack(ns.UI_COLORS.border))
        if estimate.amount > 0 then
            local fill = ns.UI_RenderTexture(card, nil, "OVERLAY")
            fill:SetPoint("TOPLEFT", width * 0.46, -44); fill:SetSize(barWidth * math.min(1, estimate.amount / estimate.cap), 5); fill:SetColorTexture(unpack(ns.UI_COLORS.accent))
        end
        Text(card, L.PC_CHECKED .. date("%d %b %H:%M", pool.checked), width * 0.46, 64, width * 0.52, ns.UI_COLORS.textDim, true)
        card:SetScript("OnEnter", function(b)
            b:SetBackdropBorderColor(unpack(ns.UI_COLORS.accent))
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT"); GameTooltip:SetText(row.key .. " - " .. pool.professionName)
            GameTooltip:AddLine(amount, 1, 1, 1)
            GameTooltip:AddLine(L.PC_TOOLTIP, 0.8, 0.8, 0.8, true)
            if pool.rate then GameTooltip:AddLine(string.format(L.PC_RATE, pool.rate * 3600), 0.3, 0.85, 0.8) end
            if #Names(pool.expansions) > 1 then GameTooltip:AddLine(L.PC_SHARED, 1, 0.8, 0.3, true) end
            GameTooltip:Show()
        end)
        card:SetScript("OnLeave", function(b) b:SetBackdropBorderColor(unpack(ns.UI_COLORS.border)); GameTooltip:Hide() end)
        y = y + 100
    end
    if #filtered == 0 then Text(root, L.PC_EMPTY, 10, y, width); y = y + 66 end
    if pages > 1 then
        local previous = Card(root, 10, y, 110, 28)
        Text(previous, L.RB_PREVIOUS, 10, 7, 90, nil, true)
        previous:SetScript("OnClick", function() state.page = math.max(1, state.page - 1); self:RefreshUI() end)
        Text(root, string.format(L.RB_PAGE, state.page, pages), 130, y + 7, width - 250, nil, true)
        local nextPage = Card(root, width - 100, y, 110, 28)
        Text(nextPage, L.RB_NEXT, 10, 7, 90, nil, true)
        nextPage:SetScript("OnClick", function() state.page = math.min(pages, state.page + 1); self:RefreshUI() end)
        y = y + 40
    end
    return self.concentrationPool:Finish(y + 10)
end
