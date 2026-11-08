local _, ns = ...
local L = ns.L

local function Coverage(frame)
    return ns.TheQuartermaster:GetDataCoverage(frame.currentTab,
        ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab())
end

function ns.UI_UpdateDataCoverage(frame)
    if not frame.dataCoverage then return end
    local counts = {}
    for _, group in ipairs(Coverage(frame)) do
        for state, count in pairs(group.counts) do counts[state] = (counts[state] or 0) + count end
    end
    local parts = {}
    for _, state in ipairs(ns.DataFreshness.states) do
        if counts[state] then parts[#parts + 1] = L["COVERAGE_STATE_" .. state] .. ": " .. counts[state] end
    end
    frame.dataCoverage.text:SetText(L["COVERAGE_TITLE"] .. " — " .. table.concat(parts, " / "))
end

function ns.UI_CreateDataCoverage(frame, footer)
    local bar = CreateFrame("Button", nil, footer)
    bar:SetPoint("LEFT", footer, "LEFT", 0, 0)
    -- Reserve the right side for scale, the optional bank button and resize handle.
    bar:SetPoint("RIGHT", footer, "RIGHT", -380, 0)
    bar:SetHeight(28)
    bar:EnableMouse(true)
    bar:SetScript("OnClick", function()
        GameTooltip:Hide()
        ns.TheQuartermaster:OpenDashboardDestination("setup")
    end)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
    bar.text:SetPoint("LEFT", 8, 0)
    bar.text:SetPoint("RIGHT", -8, 0)
    bar.text:SetJustifyH("LEFT")
    bar.text:SetWordWrap(false)
    bar:SetScript("OnEnter", function(self)
        ns.UI_UpdateDataCoverage(frame)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine(L["COVERAGE_TITLE"])
        GameTooltip:AddLine(L.SETUP_FOOTER_HINT, 0.2, 0.8, 0.75, true)
        GameTooltip:AddLine(L[frame.currentTab == "items" and "COVERAGE_ITEMS_SCOPE" or "COVERAGE_ACCOUNT_SCOPE"], 0.7, 0.7, 0.7, true)
        for _, group in ipairs(Coverage(frame)) do
            local parts = {}
            for _, state in ipairs(ns.DataFreshness.states) do
                if group.counts[state] then
                    parts[#parts + 1] = L["COVERAGE_STATE_" .. state] .. ": " .. group.counts[state]
                end
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["COVERAGE_SOURCE_" .. group.domain], 0.2, 0.8, 0.75)
            GameTooltip:AddLine(table.concat(parts, " / "), 0.9, 0.9, 0.9, true)
            if group.oldest then
                local range = date("%d %b %Y %H:%M", group.oldest)
                if group.newest ~= group.oldest then range = range .. " — " .. date("%d %b %Y %H:%M", group.newest) end
                GameTooltip:AddLine(L["COVERAGE_COLLECTED"] .. range, 0.7, 0.7, 0.7, true)
            end
            if group.empty > 0 then GameTooltip:AddLine(string.format(L["COVERAGE_EMPTY"], group.empty), 0.7, 0.7, 0.7, true) end
            if group.legacy then GameTooltip:AddLine(L["COVERAGE_LEGACY"], 1, 0.7, 0.3, true) end
            GameTooltip:AddLine(L["COVERAGE_HINT_" .. group.domain], 0.7, 0.7, 0.7, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["COVERAGE_EXPLANATION"], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    local function HideTooltip(self)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end
    bar:SetScript("OnLeave", HideTooltip)
    bar:SetScript("OnHide", HideTooltip)
    frame.dataCoverage = bar
end
