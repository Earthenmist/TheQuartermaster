local _, ns = ...
local L = ns.L
local columns = {{0.28, 0.22, "PVE_COMPARE_KEY"}, {0.50, 0.10, "PVE_COMPARE_RATING"},
    {0.60, 0.12, "PVE_COMPARE_VAULT"}, {0.72, 0.10, "PVE_COMPARE_RAIDS"}, {0.82, 0.18, "PVE_COMPARE_DATA"}}

function ns.UI_PvECompactSummary(source, view)
    local result = {key = "—", rating = "—", vault = "—", raids = "—"}
    if not source then result.state = "missing"
    elseif view.scanState == "stale" or view.scanState == "unavailable" then result.state = "unavailable"
    elseif view.periodState then result.state = "historical"
    else result.state = "cached" end
    if result.state ~= "cached" then return result end
    local mythic = view.mythicPlus or {}
    if mythic.keystone and mythic.keystone.level then
        result.key = "+" .. mythic.keystone.level .. " " .. (mythic.keystone.name or "")
    end
    if mythic.overallScore ~= nil then result.rating = tostring(mythic.overallScore) end
    local done, total = 0, 0
    for _, slot in ipairs(view.greatVault or {}) do
        if type(slot.threshold) == "number" and slot.threshold > 0 and type(slot.progress) == "number" then
            total = total + 1
            if slot.progress >= slot.threshold then done = done + 1 end
        end
    end
    if total > 0 then result.vault = done .. " / " .. total end
    if source.lockouts then
        local count, uncertain = 0, false
        for _, lockout in ipairs(view.lockouts or {}) do
            if lockout.isRaid then
                if lockout.expiresAt then count = count + 1 else uncertain = true end
            end
        end
        if not uncertain then result.raids = tostring(count) end
    end
    return result
end

local function Cell(parent, value, x, y, width, color)
    local text = ns.UI_RenderFontString(parent, nil, "OVERLAY", "QuartermasterFontSmall")
    text:SetPoint("TOPLEFT", x, -y)
    text:SetWidth(math.max(1, width))
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetTextColor(unpack(color or ns.UI_COLORS.textNormal))
    text:SetText(value)
    return text
end

function ns.UI_DrawPvEComparisonControls(parent, y, compact, onToggle, headingsOnly)
    local width = parent:GetWidth() - 20
    if not headingsOnly then
    local button = ns.UI_RenderFrame("Button", nil, parent, "BackdropTemplate")
    button:SetPoint("TOPLEFT", 10, -y)
    button:SetSize(170, 28)
    button:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    button:SetBackdropColor(unpack(ns.UI_COLORS.bgLight))
    button:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
    Cell(button, L[compact and "PVE_COMPARE_DETAILS" or "PVE_COMPARE_COMPACT"], 10, 7, 150)
    button:SetScript("OnClick", onToggle)
    Cell(parent, L["PVE_COMPARE_HINT"], 192, y + 8, width - 182, ns.UI_COLORS.textDim)
    y = y + 40
    end
    if compact then
        Cell(parent, L["PVE_COMPARE_CHARACTER"], 68, y, width * 0.28 - 58, ns.UI_COLORS.textDim)
        for _, column in ipairs(columns) do Cell(parent, L[column[3]], 10 + width * column[1], y, width * column[2] - 8, ns.UI_COLORS.textDim) end
        y = y + 26
    end
    return y
end

function ns.UI_DrawPvECompactCells(header, width, char, source, view)
    local summary = ns.UI_PvECompactSummary(source, view)
    local values = {summary.key, summary.rating, summary.vault, summary.raids, L["PVE_COMPARE_STATE_" .. summary.state]}
    for index, column in ipairs(columns) do
        Cell(header, values[index], width * column[1], 14, width * column[2] - 8,
            index == 5 and summary.state ~= "cached" and ns.UI_COLORS.warning or ns.UI_COLORS.textNormal)
    end
    local enter, leave = header:GetScript("OnEnter"), header:GetScript("OnLeave")
    header:SetScript("OnEnter", function(self)
        if enter then enter(self) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine((char.name or "") .. "-" .. (char.realm or ""))
        GameTooltip:AddLine(L["PVE_COMPARE_STATE_" .. summary.state], 1, 0.8, 0.4)
        if view.periodState then GameTooltip:AddLine(L["PVE_PERIOD_" .. view.periodState], 1, 0.8, 0.4, true) end
        if summary.state == "unavailable" then GameTooltip:AddLine(L["PVE_SCAN_RETAINED"], 1, 0.8, 0.4, true) end
        local stamp = source and (source.capturedAt or source.lastScan)
        if stamp then GameTooltip:AddLine(L["COVERAGE_COLLECTED"] .. date("%d %b %Y %H:%M", stamp), 0.7, 0.7, 0.7) end
        if summary.state == "cached" then GameTooltip:AddLine(L["PVE_COMPARE_KEY"] .. ": " .. summary.key) end
        GameTooltip:AddLine(L["PVE_COMPARE_EXPLANATION"], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function(self) if leave then leave(self) end; GameTooltip:Hide() end)
end
