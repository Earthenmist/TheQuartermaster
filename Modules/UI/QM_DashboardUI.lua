local _, ns = ...
local Addon, L = ns.TheQuartermaster, ns.L

-- Read-only summaries use the same period validation as the detailed PvE view.
function ns.UI_GetDashboardRows(addon)
    local rows, gold, refresh, incomplete = {}, 0, 0, 0
    local current = addon:GetCharacterKey()
    for key, char in pairs(addon.db.global.characters or {}) do
        local view = addon:GetPvEView(char.pve)
        local known = char.pve and not view.periodState and view.scanState ~= "stale"
            and view.scanState ~= "unavailable" and type(view.greatVault) == "table" and #view.greatVault > 0
        local done, total = 0, 0
        if known then
            for _, slot in ipairs(view.greatVault) do
                if type(slot.threshold) == "number" and slot.threshold > 0 and type(slot.progress) == "number" then
                    total = total + 1
                    if slot.progress >= slot.threshold then done = done + 1 end
                end
            end
            known = total > 0
        end
        if not known then refresh = refresh + 1
        elseif done < total then incomplete = incomplete + 1 end
        rows[#rows + 1] = {key = key, char = char, current = key == current,
            favorite = addon:IsFavoriteCharacter(key), known = known, done = done, total = total}
        gold = gold + (tonumber(char.gold) or 0)
    end
    rows = ns.SortCharacterRows(addon.db, rows, function(row) return row.key end)
    gold = gold + (tonumber((addon.db.global.warbandBank or {}).gold) or 0)
    return rows, gold, refresh, incomplete
end

local function Text(parent, value, x, y, width, font, color)
    local text = ns.UI_RenderFontString(parent, nil, "OVERLAY", font or "QuartermasterFontBody")
    text:SetPoint("TOPLEFT", x, -y)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    text:SetTextColor(unpack(color or ns.UI_COLORS.textNormal))
    text:SetText(value)
    return text
end

local function Button(parent, label, x, y, width, callback)
    local button = ns.UI_RenderFrame("Button", nil, parent, "BackdropTemplate")
    button:SetPoint("TOPLEFT", x, -y)
    button:SetSize(width, 28)
    button:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    button:SetBackdropColor(unpack(ns.UI_COLORS.bgLight))
    button:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
    local labelText = Text(button, label, 8, 7, width - 16, "QuartermasterFontSmall")
    labelText:SetWordWrap(false)
    button:SetScript("OnClick", callback)
    button:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(ns.UI_COLORS.accent)) end)
    button:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(ns.UI_COLORS.border)) end)
    return button
end

function Addon:OpenDashboardDestination(key)
    local frame = self.UI and self.UI.mainFrame
    if not frame then return end
    frame.currentTab = key
    if frame.scroll then frame.scroll:SetVerticalScroll(0) end
    self:PopulateContent()
    if key == "search" then
        local box = frame.persistentSearchBoxes and frame.persistentSearchBoxes.global
        if box and box.editBox then box.editBox:SetFocus() end
    end
end

function Addon:DrawStatistics(parent)
    self.dashboardPool = self.dashboardPool or ns.UI_NewRenderPool(parent)
    local pool = self.dashboardPool
    local root = pool:Begin(parent:GetWidth())
    local width = parent:GetWidth() - 24
    if self.UI and self.UI.mainFrame and self.UI.mainFrame.currentTab == "totals" then
        local height = self:DrawAccountStatistics(root)
        root:SetFrameLevel(parent:GetFrameLevel() + 1)
        return pool:Finish(height)
    end
    root:SetFrameLevel(parent:GetFrameLevel() + 1)
    local rows, gold, refresh, incomplete = ns.UI_GetDashboardRows(self)
    local colors = ns.UI_COLORS
    Button(root, L.DASH_SEARCH, 12, 12, width - 188, function() self:OpenDashboardDestination("search") end)
    Button(root, L.DASH_OPEN_PVE, width - 168, 12, 180, function() self:OpenDashboardDestination("pve") end)

    local unlocked = 0
    for _, entry in ipairs(rows) do
        if entry.known and entry.done > 0 then unlocked = unlocked + 1 end
    end
    local statWidth = (width - 16) / 3
    local values = {
        {L.DASH_CHARACTERS, tostring(#rows), L.DASH_SAVED, "chars", "Interface\\Icons\\Achievement_Character_Human_Male"},
        {L.DASH_UNLOCKED, tostring(unlocked), L.DASH_UNLOCKED_SCOPE, "pve", "Interface\\Icons\\INV_Misc_TreasureChest04b"},
        {L.DASH_GOLD, ns.UI_FormatGold(gold), L.DASH_GOLD_SCOPE, "totals", "Interface\\Icons\\INV_Misc_Coin_01"},
    }
    for i, value in ipairs(values) do
        local card = Button(root, "", 12 + (i - 1) * (statWidth + 8), 52, statWidth,
            function() self:OpenDashboardDestination(value[4]) end)
        card:SetHeight(100)
        card:SetBackdropColor(unpack(colors.bgCard))
        local icon = ns.UI_RenderTexture(card, nil, "ARTWORK")
        icon:SetSize(28, 28)
        icon:SetPoint("TOPLEFT", 14, -16)
        icon:SetTexture(value[5])
        Text(card, value[1], 52, 14, statWidth - 64, "QuartermasterFontSmall", colors.textDim)
        Text(card, value[2], 52, 34, statWidth - 64, "QuartermasterFontTitle", colors.accent):SetWordWrap(false)
        Text(card, value[3], 14, 72, statWidth - 28, "QuartermasterFontSmall", colors.textDim)
    end
    local split = width >= 820
    local rosterWidth = split and width - 308 or width
    Text(root, L.DASH_YOUR_CHARACTERS, 12, 180, rosterWidth - 160, "QuartermasterFontHeading")
    Button(root, self.dashboardFavoritesOnly and L.DASH_SHOW_ALL or L.DASH_FAVORITES,
        12 + rosterWidth - 150, 172, 150, function()
            self.dashboardFavoritesOnly = not self.dashboardFavoritesOnly
            self:PopulateContent()
        end)
    local columns = {0, rosterWidth * 0.44, rosterWidth * 0.55, rosterWidth * 0.69}
    for i, name in ipairs({L.DASH_CHARACTER, L.DASH_LEVEL, L.DASH_ILVL, L.DASH_WEEKLY}) do
        Text(root, name, 20 + columns[i], 215, (i == 1 and columns[2] - 12 or i == 4 and rosterWidth * 0.31 - 16 or 60), "QuartermasterFontSmall", colors.textDim)
    end
    self.dashboardExpanded = self.dashboardExpanded or {}
    local y, shown, matching = 239, 0, 0
    for _, entry in ipairs(rows) do
        if not self.dashboardFavoritesOnly or entry.favorite then matching = matching + 1 end
    end
    for _, entry in ipairs(rows) do
        if shown < 6 and (not self.dashboardFavoritesOnly or entry.favorite) then
            shown = shown + 1
            local expanded = self.dashboardExpanded[entry.key]
            local height = expanded and 110 or 62
            local row = ns.UI_RenderFrame("Button", nil, root, "BackdropTemplate")
            row:SetPoint("TOPLEFT", 12, -y)
            row:SetSize(rosterWidth, height)
            row:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
            row:SetBackdropColor(unpack(shown % 2 == 0 and ns.UI_COLORS.bgCard or ns.UI_COLORS.bg))
            local class = RAID_CLASS_COLORS[entry.char.classFile or ""]
            local color = class and {class.r, class.g, class.b, 1} or ns.UI_COLORS.textNormal
            local name = (expanded and "− " or "+ ") .. (entry.char.name or entry.key)
            Text(row, name, 8, 12, columns[2] - 32, "QuartermasterFontHeading", color):SetWordWrap(false)
            if entry.favorite then
                local star = ns.UI_RenderTexture(row, nil, "ARTWORK")
                star:SetSize(10, 10)
                star:SetPoint("TOPLEFT", columns[2] - 20, -14)
                star:SetTexture("Interface\\COMMON\\ReputationStar")
            end
            Text(row, tostring(entry.char.level or "—"), 8 + columns[2], 12, 50)
            local ilvl = entry.char.ilvlEquipped or entry.char.ilvlAvg
            Text(row, ilvl and string.format("%.1f", ilvl) or "—", 8 + columns[3], 12, 65)
            Text(row, entry.known and string.format(L["DASH_VAULT_SLOTS"], entry.done, entry.total) or L["DASH_REFRESH"],
                8 + columns[4], 12, rosterWidth - columns[4] - 16, "QuartermasterFontSmall", entry.known and colors.textNormal or colors.textDim)
            Text(row, entry.char.realm or "", 24, 36, columns[2] - 32, "QuartermasterFontSmall", colors.textDim):SetWordWrap(false)
            if entry.current then
                Text(row, L.DASH_ONLINE, 8 + columns[2], 36, columns[4] - columns[2] - 8, "QuartermasterFontSmall", colors.accent)
            end
            if entry.known then
                local railWidth = rosterWidth - columns[4] - 20
                local rail = ns.UI_RenderTexture(row, nil, "ARTWORK")
                rail:SetPoint("TOPLEFT", 8 + columns[4], -40)
                rail:SetSize(railWidth, 3)
                rail:SetTexture("Interface\\Buttons\\WHITE8X8")
                rail:SetVertexColor(unpack(colors.border))
                if entry.done > 0 then
                    local fill = ns.UI_RenderTexture(row, nil, "OVERLAY")
                    fill:SetPoint("TOPLEFT", 8 + columns[4], -40)
                    fill:SetSize(railWidth * entry.done / entry.total, 3)
                    fill:SetTexture("Interface\\Buttons\\WHITE8X8")
                    fill:SetVertexColor(unpack(colors.accent))
                end
            end
            if expanded then
                local stamp = entry.char.pve and (entry.char.pve.capturedAt or entry.char.pve.lastScan)
                local detail = (entry.char.realm or "") .. " · " .. (entry.current and L["DASH_ONLINE"] or L["DASH_OFFLINE"])
                if stamp and stamp > 0 then detail = detail .. " · " .. L["COVERAGE_COLLECTED"] .. date("%d %b %H:%M", stamp) end
                Text(row, detail, 12, 64, rosterWidth - 24, "QuartermasterFontSmall", ns.UI_COLORS.textDim)
                Text(row, entry.known and L["DASH_EXPAND_HINT"] or L["DASH_UNKNOWN_HINT"], 12, 84, rosterWidth - 24, "QuartermasterFontSmall", ns.UI_COLORS.textDim)
            end
            local key = entry.key
            row:SetScript("OnClick", function()
                self.dashboardExpanded[key] = not self.dashboardExpanded[key]
                self:PopulateContent()
            end)
            y = y + height + 4
        end
    end
    if shown == 0 then Text(root, L["DASH_NO_CHARACTERS"], 20, y, rosterWidth - 16); y = y + 42 end
    Text(root, string.format(L.DASH_PREVIEW_COUNT, shown, matching), 20, y + 4, rosterWidth - 16, "QuartermasterFontSmall", colors.textDim)
    Button(root, L.DASH_OPEN_CHARACTERS, 12, y + 26, rosterWidth, function() self:OpenDashboardDestination("chars") end)

    local asideX, asideY, asideWidth = split and 12 + rosterWidth + 16 or 12, split and 172 or y + 76, split and 292 or width
    local function Panel(title, offset, height)
        local panel = ns.UI_CreateCard(root, height)
        panel:SetPoint("TOPLEFT", asideX, -(asideY + offset))
        panel:SetWidth(asideWidth)
        Text(panel, title, 14, 14, asideWidth - 28, "QuartermasterFontHeading", colors.accent)
        return panel
    end
    local nextPanel = Panel(L.DASH_WEEKLY_FOCUS, 0, 222)
    Text(nextPanel, string.format(L.DASH_INCOMPLETE, incomplete), 14, 44, asideWidth - 28)
    Button(nextPanel, L.DASH_OPEN_PVE, 14, 90, asideWidth - 28, function() self:OpenDashboardDestination("pve") end)
    Text(nextPanel, string.format(L.DASH_UNVERIFIED, refresh), 14, 134, asideWidth - 28, "QuartermasterFontSmall", colors.textDim)
    Button(nextPanel, L.DASH_REVIEW_DATA, 14, 178, asideWidth - 28, function() self:OpenDashboardDestination("setup") end)

    local watchPanel = Panel(L.DASH_WATCHLIST, 234, 142)
    local count = 0
    local watchlist = self.db.profile.watchlist or {}
    for _, domain in ipairs({"items", "reagents", "currencies"}) do
        for _ in pairs(watchlist[domain] or {}) do count = count + 1 end
    end
    Text(watchPanel, count > 0 and string.format(L.DASH_PINNED, count) or L.DASH_EMPTY_WATCHLIST,
        14, 44, asideWidth - 28, "QuartermasterFontSmall", colors.textDim)
    Button(watchPanel, L.DASH_OPEN_WATCHLIST, 14, 98, asideWidth - 28, function() self:OpenDashboardDestination("watchlist") end)

    local linksPanel = Panel(L.DASH_QUICK_LINKS, 388, 126)
    local shortcutWidth = (asideWidth - 36) / 2
    for i, link in ipairs({{"storage", L.NAV_STORAGE}, {"recipes", L.NAV_RECIPES}, {"equip", L.NAV_EQUIPMENT}, {"totals", L.NAV_ACCOUNT}}) do
        Button(linksPanel, link[2], 14 + ((i - 1) % 2) * (shortcutWidth + 8), 44 + math.floor((i - 1) / 2) * 36,
            shortcutWidth, function() self:OpenDashboardDestination(link[1]) end)
    end
    local cooldownPanel=Panel(L.CD_TITLE,526,112)
    local _, cooldowns=self:GetProfessionCooldownRows()
    Text(cooldownPanel,string.format(L.CD_DASH,cooldowns.ready,cooldowns.estimated),14,42,asideWidth-28,"QuartermasterFontSmall",colors.textDim)
    Button(cooldownPanel,L.CD_TITLE,14,72,asideWidth-28,function() self:OpenDashboardDestination("cooldowns") end)
    return pool:Finish(math.max(y + 66, asideY + 650))
end
