--[[
    The Quartermaster - Recipes UI (Option A)

    Provides an interactive screen to search cached profession recipes across your characters.
    Notes:
      - Recipes are cached only when you log into that character and open the profession window.
      - We store known recipeIDs per character (compact arrays) and recipe names globally.
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster
local L = ns.L

local DrawEmptyState = ns.UI_DrawEmptyState
local COLORS = ns.UI_COLORS

-- Keep Cooking, but ignore recipe caching display for Fishing/Archaeology.
-- These IDs correspond to C_TradeSkillUI.GetBaseProfessionInfo().professionID
local IGNORED_PROFESSION_IDS = {
    [356] = true, -- Fishing
    [794] = true, -- Archaeology
}

local function GetCachedRecipeStore(db)
    return db and db.global and db.global.characters
end

local function CollectScanSummary(db)
    local chars = GetCachedRecipeStore(db)
    if type(chars) ~= "table" then return {} end

    local out = {}
    for charKey, charData in pairs(chars) do
        local profStore = charData and charData.professionRecipes
        if type(profStore) == "table" then
            for profID, entry in pairs(profStore) do
	                if not IGNORED_PROFESSION_IDS[tonumber(profID)] then
	                    if entry and (type(entry.professionName) == "string") then
	                        out[#out + 1] = {
	                            charKey = charKey,
	                            professionName = entry.professionName,
	                            lastScan = entry.lastScan or 0,
	                            recipeCount = (entry.recipes and #entry.recipes) or 0,
	                        }
	                    end
	                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.charKey ~= b.charKey then return a.charKey < b.charKey end
        return (a.professionName or "") < (b.professionName or "")
    end)

    return out
end

-- Group the per-profession summary into one line per character.
local function GroupScanSummary(summary)
    if type(summary) ~= "table" or #summary == 0 then return {} end

    local byChar = {}
    local order = {}

    for i = 1, #summary do
        local s = summary[i]
        if s and s.charKey then
            local t = byChar[s.charKey]
            if not t then
                t = { charKey = s.charKey, lastScan = 0, professions = {} }
                byChar[s.charKey] = t
                order[#order + 1] = s.charKey
            end
            t.professions[#t.professions + 1] = {
                name = s.professionName or "?",
                count = s.recipeCount or 0,
                lastScan = s.lastScan or 0,
            }
            if (s.lastScan or 0) > (t.lastScan or 0) then
                t.lastScan = s.lastScan or 0
            end
        end
    end

    table.sort(order)

    local out = {}
    for i = 1, #order do
        local key = order[i]
        local t = byChar[key]
        if t then
            table.sort(t.professions, function(a, b)
                return (a.name or "") < (b.name or "")
            end)

            local parts = {}
            for p = 1, #t.professions do
                local pr = t.professions[p]
                parts[#parts + 1] = string.format("%s (%d)", pr.name, pr.count or 0)
            end

            out[#out + 1] = {
                charKey = t.charKey,
                professionsText = table.concat(parts, ", "),
                lastScan = t.lastScan or 0,
            }
        end
    end

    return out
end

local function FormatShortTime(ts)
    if not ts or ts <= 0 then return "Never" end
    local delta = time() - ts
    if delta < 60 then return "Just now" end
    if delta < 3600 then return string.format("%dm ago", math.floor(delta / 60)) end
    if delta < 86400 then return string.format("%dh ago", math.floor(delta / 3600)) end
    return date("%Y-%m-%d", ts)
end

local function CreateHeader(parent, y)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, -y)
    title:SetText("Recipes")
    title:SetTextColor(1, 1, 1)

    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    desc:SetWidth(parent:GetWidth() - 30)
    desc:SetJustifyH("LEFT")
    desc:SetTextColor(0.75, 0.75, 0.75)
    desc:SetText("Search recipes you've scanned on your characters. To scan: enable tracking in settings, log onto a crafter, and open their profession window.")

    return y + 44
end

local function CreateResetButtons(self, parent, y)
    -- Themed action button to match other QM header controls (e.g. Items "List View").
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(120, 24)
    btn:SetPoint("TOPRIGHT", -10, -10)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetTextColor(1, 1, 1, 0.95)
    btn.text:SetText("Reset My Cache")

    btn:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
    btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)
    btn:SetScript("OnClick", function()
        if self and self.ClearProfessionRecipeCache then
            local cleared = self:ClearProfessionRecipeCache(nil)
            if cleared then
                self:Print("|cff00ff00Cleared recipe cache for current character.|r")
            else
                self:Print("|cff888888No recipe cache found for current character.|r")
            end
            if self.RefreshUI then self:RefreshUI() end
        end
    end)
    btn:SetScript("OnEnter", function(b)
        if b.SetBackdropColor then
            b:SetBackdropColor(COLORS.tabHover[1], COLORS.tabHover[2], COLORS.tabHover[3], 1)
            b:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
        end
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetText("Clears cached recipes for the currently logged-in character.\nUse /tq recipes resetall to clear everything.", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(b)
        if b and b.SetBackdropColor then
            b:SetBackdropColor(COLORS.tabInactive[1], COLORS.tabInactive[2], COLORS.tabInactive[3], 1)
            b:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.65)
        end
        GameTooltip:Hide()
    end)
    return y
end

local function CreateRow(parent, y, width)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(width, 40)
    row:SetPoint("TOPLEFT", 10, -y)
    row:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    row:SetBackdropColor(0.10, 0.10, 0.12, 1)
    row:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", 10, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetTextColor(1, 1, 1)

    row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.meta:SetPoint("RIGHT", -10, 0)
    row.meta:SetJustifyH("RIGHT")
    row.meta:SetTextColor(0.8, 0.8, 0.8)

    row:EnableMouse(true)

    return row
end

function TheQuartermaster:DrawRecipesTab(parent)
    local y = 10
    local width = (parent:GetWidth() or 700) - 20

    if not self.db or not self.db.profile then
        return DrawEmptyState(self, parent, y, false, nil, "Database not ready.")
    end

    y = CreateHeader(parent, y)
    CreateResetButtons(self, parent, y)

    if not self.db.profile.trackProfessionRecipes then
        y = y + 6
        y = DrawEmptyState(self, parent, y, false, nil, "Recipe tracking is disabled. Enable it in Settings → Display.")
        return y + 10
    end

    -- Summary block
    local summary = GroupScanSummary(CollectScanSummary(self.db))
    if #summary == 0 then
        y = y + 6
        y = DrawEmptyState(self, parent, y, false, nil, "No recipes cached yet. Log onto a crafter and open their profession window to scan.")
        return y + 10
    end

    local sumTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sumTitle:SetPoint("TOPLEFT", 10, -y)
    sumTitle:SetText("Scanned professions")
    sumTitle:SetTextColor(1, 1, 1)
    y = y + 22

    -- Scrollable list so we never hide tracked characters behind a "…and N more" line.
    do
        local lineH = 16
        local contentH = math.max(1, #summary) * lineH
        local maxH = 140
        local visibleH = math.min(contentH, maxH)

        local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 10, -y)
        scroll:SetSize(width, visibleH)

        -- Nudge the scrollbar slightly left so it doesn't hug the panel edge.
        if scroll.ScrollBar then
            scroll.ScrollBar:ClearAllPoints()
            scroll.ScrollBar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -6, -16)
            scroll.ScrollBar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -6, 16)
        end

        local child = CreateFrame("Frame", nil, scroll)
        child:SetSize(width - 34, contentH)
        scroll:SetScrollChild(child)

        for i = 1, #summary do
            local s = summary[i]
            local line = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            line:SetPoint("TOPLEFT", 4, -((i - 1) * lineH))
            line:SetJustifyH("LEFT")
            line:SetTextColor(0.75, 0.75, 0.75)
            line:SetText(string.format("• %s — %s — %s", s.charKey, s.professionsText or "", FormatShortTime(s.lastScan)))
        end

        y = y + visibleH + 10
    end

    local q = tostring(ns.recipesSearchText or "")
    q = q:gsub("^%s+", ""):gsub("%s+$", "")

    if q == "" then
        y = DrawEmptyState(self, parent, y, false, nil, "Type in the search box above to find recipes (e.g. \"ring\", \"setting\", \"filigree\").")
        return y + 10
    end

    local results = self:FindRecipeCraftersByName(q)
    if #results == 0 then
        y = DrawEmptyState(self, parent, y, true, q, nil)
        return y + 10
    end

    local hdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", 10, -y)
    hdr:SetText(string.format("Matches (%d)", #results))
    hdr:SetTextColor(1, 1, 1)
    y = y + 22

    local maxRows = 200
    local shown = 0

    for i = 1, #results do
        local r = results[i]
        local name = r.name or ("Recipe #" .. tostring(r.recipeID))
        local crafters = r.crafters or {}

        local row = CreateRow(parent, y, width)
        row.name:SetText(name)
        row.meta:SetText(table.concat(crafters, ", "))

        -- Tooltip: prefer the crafted item if we have an output itemID cached, otherwise show recipe text.
        row:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            if r.itemID then
                GameTooltip:SetItemByID(r.itemID)
            else
                GameTooltip:SetText(name, 1, 1, 1)
            end
            if #crafters > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Crafters:", 1, 0.82, 0)
                GameTooltip:AddLine(table.concat(crafters, ", "), 0.8, 0.8, 0.8, true)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        y = y + 44
        shown = shown + 1
        if shown >= maxRows then
            local cap = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cap:SetPoint("TOPLEFT", 10, -y)
            cap:SetTextColor(0.7, 0.7, 0.7)
            cap:SetText("Result list truncated. Refine your search to see more.")
            y = y + 20
            break
        end
    end

    return y + 10
end
