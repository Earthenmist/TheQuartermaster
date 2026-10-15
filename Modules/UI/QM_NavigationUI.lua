local _, ns = ...
local L = ns.L

-- Session-only open paths: one sibling per depth, with descendants reset on toggles.
function ns.UI_ProgressionAccordion(page, refresh)
    ns.progressionOpenPaths = ns.progressionOpenPaths or {}
    local path = ns.progressionOpenPaths[page] or {}
    ns.progressionOpenPaths[page] = path
    local depths = {}
    local function IsExpanded(key, _, depth)
        depth = depth or 3
        depths[key] = depth
        return path[depth] == key
    end
    local function Toggle(key, open)
        local depth = depths[key]
        if not depth then return end
        for index in pairs(path) do if index >= depth then path[index] = nil end end
        path[depth] = open and key or nil
        refresh()
    end
    return IsExpanded, Toggle
end

ns.NavigationGroups = {
    {id = "stats", label = "NAV_DASHBOARD", pages = {{"stats", "NAV_DASHBOARD"}}},
    {id = "chars", label = "NAV_CHARACTERS", pages = {{"chars", "NAV_OVERVIEW"}, {"exp", "NAV_EXPERIENCE"}, {"guild", "NAV_GUILDS"}, {"equip", "NAV_EQUIPMENT"}, {"setup", "NAV_SETUP"}}},
    {id = "storage", label = "NAV_STORAGE", pages = {{"storage", "NAV_ALL_STORAGE"}, {"items", "NAV_BAGS_BANKS"}, {"auctions", "AU_TITLE"}}},
    {id = "professions", label = "NAV_PROFESSIONS", pages = {{"recipes", "NAV_RECIPES"}, {"materials", "NAV_MATERIALS"}, {"profequip", "NAV_PROF_GEAR"}, {"concentration", "PC_TITLE"}, {"cooldowns", "CD_TITLE"}, {"knowledge", "KP_TITLE"}}},
    {id = "progression", label = "NAV_PROGRESSION", pages = {{"pve", "NAV_PVE"}, {"reputations", "NAV_REPUTATIONS"}, {"currency", "NAV_CURRENCIES"}, {"quests", "QL_TITLE"}, {"achievements", "AC_TITLE"}}},
    {id = "totals", label = "NAV_ACCOUNT", pages = {{"totals", "NAV_ACCOUNT"}}},
    {id = "wealth", label = "WL_TITLE", pages = {{"wealth", "WL_TITLE"}}},
    {id = "search", label = "NAV_SEARCH", pages = {{"search", "NAV_SEARCH"}}},
    {id = "watchlist", label = "NAV_WATCHLIST", pages = {{"watchlist", "NAV_WATCHLIST"}}},
}
function ns.UI_GetNavigationGroup(page)
    for _, group in ipairs(ns.NavigationGroups) do
        for _, entry in ipairs(group.pages) do if entry[1] == page then return group end end
    end
end

function ns.UI_CreateGroupedNavigation(frame, createButton)
    frame.groupLastPage = {}
    frame:HookScript("OnHide", function()
        ns.storageOpenPath = nil
        ns.progressionOpenPaths = nil
        frame.lastNavigationPage = nil
    end)
    for index, group in ipairs(ns.NavigationGroups) do
        local y = 10 + (index - 1) * ns.Theme.layout.navHeight + (index >= 8 and 20 or 0)
        local button = createButton(frame.nav, L[group.label], group.id, y)
        frame.tabButtons[group.id] = button
        button:SetScript("OnClick", function()
            ns.TheQuartermaster:OpenDashboardDestination(frame.groupLastPage[group.id] or group.pages[1][1])
        end)
    end
    local separator = frame.nav:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", 10, -(10 + 7 * ns.Theme.layout.navHeight + 6))
    separator:SetPoint("TOPRIGHT", -10, -(10 + 7 * ns.Theme.layout.navHeight + 6))
    separator:SetHeight(1)
    separator:SetColorTexture(unpack(ns.UI_COLORS.border))

    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame.nav, "TOPRIGHT", 12, 0)
    bar:SetPoint("TOPRIGHT", frame.header, "BOTTOMRIGHT", -6, -8)
    bar:SetHeight(32)
    bar.buttons = {}
    local maxPages = 1
    for _, group in ipairs(ns.NavigationGroups) do maxPages = math.max(maxPages, #group.pages) end
    for index = 1, maxPages do
        local button = CreateFrame("Button", nil, bar, "BackdropTemplate")
        button:SetHeight(30)
        button:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        button.label = button:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
        button.label:SetPoint("LEFT", 10, 0)
        button.label:SetPoint("RIGHT", -10, 0)
        button.label:SetJustifyH("CENTER")
        button.label:SetWordWrap(false)
        button:SetScript("OnClick", function(self) ns.TheQuartermaster:OpenDashboardDestination(self.page) end)
        button:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(ns.UI_COLORS.accent)) end)
        button:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(self.active and ns.UI_COLORS.accent or ns.UI_COLORS.border)) end)
        bar.buttons[index] = button
    end
    local summary = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    summary:SetPoint("TOPLEFT", frame.nav, "TOPRIGHT", 12, 0)
    summary:SetPoint("TOPRIGHT", frame.header, "BOTTOMRIGHT", -6, -8)
    summary:SetHeight(70)
    summary:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    summary:SetBackdropColor(unpack(ns.UI_COLORS.bgCard)); summary:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
    local portrait = summary:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(40, 40); portrait:SetPoint("LEFT", 15, 0)
    if SetPortraitTexture then pcall(SetPortraitTexture, portrait, "player") end
    local title = summary:CreateFontString(nil, "OVERLAY", "QuartermasterFontHeading")
    title:SetPoint("LEFT", portrait, "RIGHT", 12, 8); title:SetText(L.CHAR_TITLE)
    summary.title = title
    summary.icon = portrait
    summary.count = summary:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
    summary.count:SetPoint("LEFT", portrait, "RIGHT", 12, -12)
    summary.dragHint = summary:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
    summary.dragHint:SetPoint("BOTTOMLEFT", 200, 8)
    summary.dragHint:SetPoint("BOTTOMRIGHT", -16, 8)
    summary.dragHint:SetHeight(28)
    summary.dragHint:SetJustifyH("RIGHT")
    summary.dragHint:SetJustifyV("BOTTOM")
    summary.dragHint:SetWordWrap(true)
    summary.dragHint:SetText(L.CHAR_DRAG_HINT)
    local action = CreateFrame("Button", nil, summary, "BackdropTemplate")
    action:SetPoint("RIGHT", -16, 0); action:SetSize(160, 28)
    action:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    action.label = action:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
    action.label:SetPoint("CENTER")
    action.label:SetTextColor(unpack(ns.UI_COLORS.textNormal))
    action:SetScript("OnClick", function()
        local addon = ns.TheQuartermaster
        local profile = addon.db.profile
        if frame.currentTab == "reputations" then
            profile.reputationViewMode = profile.reputationViewMode == "filtered" and "all" or "filtered"
        elseif frame.currentTab == "currency" then
            profile.currencyShowZero = profile.currencyShowZero == false
        else return end
        addon:RefreshUI()
    end)
    action:SetScript("OnEnter", function(button)
        button:SetBackdropColor(unpack(ns.UI_COLORS.bgLight))
        GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
        GameTooltip:SetText(button.label:GetText(), 1, 1, 1)
        GameTooltip:AddLine(L[frame.currentTab == "reputations" and "REP_VIEW_HELP" or "CURRENCY_ZERO_HELP"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    action:SetScript("OnLeave", function(button)
        button:SetBackdropColor(unpack(ns.UI_COLORS.bgCard)); GameTooltip:Hide()
    end)
    local compare=CreateFrame("Button",nil,summary,"BackdropTemplate")
    compare:SetSize(185,28)
    compare:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    compare:SetBackdropColor(unpack(ns.UI_COLORS.bgCard));compare:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
    compare.label=compare:CreateFontString(nil,"OVERLAY","QuartermasterFontSmall");compare.label:SetPoint("CENTER")
    compare:SetScript("OnClick",function(b)
        local domain=ns.Comparison and ns.Comparison.Domain(frame.currentTab);if not domain then return end
        ns.UI_RecipeMenu(b,function(_,menu)
            menu:CreateButton(L.CMP_CURRENT,function() ns.Comparison.Settings(ns.TheQuartermaster,domain).enabled=false;if frame.scroll then frame.scroll:SetVerticalScroll(0) end;ns.TheQuartermaster:RefreshUI() end)
            menu:CreateButton(L.CMP_VIEW,function() ns.Comparison.Settings(ns.TheQuartermaster,domain).enabled=true;if frame.scroll then frame.scroll:SetVerticalScroll(0) end;ns.TheQuartermaster:RefreshUI() end)
        end)
    end)
    summary.compare=compare;compare:Hide()
    summary.action = action
    action:Hide()
    frame.characterOverviewHeader = summary
    summary:Hide()
    frame.groupNavigation = bar
    local function Layout()
        local count = bar.count or 1
        local width = math.max(1, (bar:GetWidth() - (count - 1) * 8) / count)
        for index, button in ipairs(bar.buttons) do
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", (index - 1) * (width + 8), 0)
            button:SetWidth(width)
        end
    end
    bar.Layout = Layout
    bar:SetScript("OnSizeChanged", Layout)
end

function ns.UI_UpdateGroupedNavigation(frame)
    if frame.currentTab == "storage" and frame.lastNavigationPage ~= "storage" then ns.storageOpenPath = nil end
    if frame.currentTab == "items" and frame.lastNavigationPage ~= "items" and ns.UI_ResetItemsPresentation then ns.UI_ResetItemsPresentation() end
    if (frame.currentTab == "reputations" or frame.currentTab == "currency") and frame.lastNavigationPage ~= frame.currentTab then
        ns.progressionOpenPaths = ns.progressionOpenPaths or {}
        ns.progressionOpenPaths[frame.currentTab] = nil
    end
    frame.lastNavigationPage = frame.currentTab
    local group = ns.UI_GetNavigationGroup(frame.currentTab)
    local bar = frame.groupNavigation
    if not bar then return end
    if group then frame.groupLastPage[group.id] = frame.currentTab end
    for key, button in pairs(frame.tabButtons) do
        button.active = group and key == group.id or false
        button:SetBackdropColor(unpack(button.active and ns.UI_COLORS.tabActive or ns.UI_COLORS.tabInactive))
        button.label:SetTextColor(unpack(ns.UI_COLORS.textNormal))
        button.activeBar:SetAlpha(button.active and 1 or 0)
    end
    local show = group and #group.pages > 1
    local summary = frame.characterOverviewHeader
    local action = summary.action
    if frame.currentTab == "reputations" or frame.currentTab == "currency" then
        local profile = ns.TheQuartermaster.db.profile
        local filtered = frame.currentTab == "reputations" and profile.reputationViewMode == "filtered"
        action.label:SetText(frame.currentTab == "reputations" and (filtered and L.VIEW_FILTERED or L.VIEW_ALL_CHARACTERS)
            or (profile.currencyShowZero == false and L.CURRENCY_SHOW_ZERO or L.CURRENCY_HIDE_ZERO))
        action:SetWidth(frame.currentTab == "reputations" and 160 or 100)
        action:SetBackdropColor(unpack(ns.UI_COLORS.bgCard))
        action:SetBackdropBorderColor(unpack(filtered and ns.UI_COLORS.accent or ns.UI_COLORS.border))
        action:Show()
    else action:Hide() end
    local domain=ns.Comparison and ns.Comparison.Domain(frame.currentTab)
    if domain then
        local enabled=ns.Comparison.Settings(ns.TheQuartermaster,domain).enabled
        local compare=summary.compare;compare:ClearAllPoints()
        compare:SetPoint("RIGHT",summary,"RIGHT",(not enabled and (frame.currentTab=="currency" or frame.currentTab=="reputations")) and -190 or -16,0)
        compare.label:SetText((enabled and L.CMP_VIEW or L.CMP_CURRENT).."  v");compare:Show()
        if enabled then action:Hide() end
    else summary.compare:Hide() end
    local comparing=domain and ns.Comparison.Settings(ns.TheQuartermaster,domain).enabled
    local characterGroup = group and group.id == "chars"
    local storageGroup = group and group.id == "storage"
    local professionGroup = group and group.id == "professions"
    local weeklyPage = frame.currentTab == "pve"
    local hasHeader = frame.currentTab == "stats" or characterGroup or storageGroup or professionGroup or (group and group.id == "progression") or frame.currentTab == "totals" or frame.currentTab == "search" or frame.currentTab == "wealth"
    if frame.currentTab == "chars" or frame.currentTab == "equip" then
        summary.dragHint:SetText(frame.currentTab == "equip" and L.EQ_LEGEND or L.CHAR_DRAG_HINT)
        summary.dragHint:Show()
    elseif weeklyPage then
        summary.dragHint:Show()
    else
        summary.dragHint:Hide()
    end
    bar:ClearAllPoints()
    if hasHeader then
        summary.title:SetText(frame.currentTab == "exp" and L.NAV_EXPERIENCE or frame.currentTab == "guild" and L.GUILD_SUMMARY_TITLE or frame.currentTab == "equip" and L.NAV_EQUIPMENT or L.CHAR_TITLE)
        local count = 0
        for _ in pairs(ns.TheQuartermaster.db.global.characters or {}) do count = count + 1 end
        if frame.currentTab == "stats" then
            summary.title:SetText(L.DASH_TITLE)
            summary.count:SetText(L.DASH_HOME_DESC)
            summary.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        elseif frame.currentTab == "search" then
            summary.title:SetText(L.SEARCH_HEADER_TITLE)
            summary.count:SetText(L.SEARCH_HEADER_DESC)
            summary.icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
        elseif frame.currentTab == "wealth" then
            summary.title:SetText(L.WL_TITLE)
            summary.count:SetText(L.WL_SUBTITLE)
            summary.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
        elseif frame.currentTab == "totals" then
            summary.title:SetText(L.NAV_ACCOUNT)
            summary.count:SetText(L.COLLECTION_PROGRESS_GOLD_AND_STORAGE_OVERVIEW)
            summary.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        elseif weeklyPage then
            summary.title:SetText(L.WEEKLY_TITLE)
            summary.count:SetText(L.WEEKLY_SUBTITLE)
            summary.icon:SetTexture("Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster")
        elseif frame.currentTab == "achievements" then
            summary.title:SetText(L.AC_TITLE)
            summary.count:SetText(L.AC_SUBTITLE)
            summary.icon:SetTexture(236507)
        elseif frame.currentTab == "quests" then
            summary.title:SetText(L.QL_TITLE)
            summary.count:SetText(L.QL_SUBTITLE)
            summary.icon:SetTexture(134269)
        elseif frame.currentTab == "reputations" or frame.currentTab == "currency" then
            local reputation = frame.currentTab == "reputations"
            summary.title:SetText(reputation and L.REPUTATION_TRACKER_TITLE or L.CURRENCY_TRACKER_TITLE)
            summary.count:SetText(reputation and L.TRACK_ALL_ACTIVE_REPUTATIONS_AND_RENOWN_IN_BLIZZARDS_ORDER or L.TRACK_ALL_CURRENCIES_ACROSS_YOUR_CHARACTERS)
            summary.icon:SetTexture(reputation and "Interface\\Icons\\Achievement_Reputation_01" or "Interface\\Icons\\achievement_garrison_alliance_pve")
        elseif professionGroup then
            local page = frame.currentTab
            summary.title:SetText(comparing and L.CMP_PROF_TITLE or page == "knowledge" and L.KP_TITLE or page == "cooldowns" and L.CD_TITLE or page == "concentration" and L.PC_TITLE or page == "recipes" and L.NAV_RECIPES or page == "materials" and L.NAV_MATERIALS or L.PROF_EQUIPMENT_TITLE)
            summary.count:SetText(comparing and L.CMP_PROF_SUBTITLE or page == "knowledge" and L.KP_SUBTITLE or page == "cooldowns" and L.CD_SUBTITLE or page == "concentration" and L.PC_SUBTITLE or page == "recipes" and L.RECIPES_HEADER_DESC or page == "materials" and L.MATERIALS_HEADER_DESC or string.format(L.PROF_EQUIPMENT_DESC, count))
            summary.icon:SetTexture(page == "recipes" and "Interface\\Icons\\INV_Scroll_03" or page == "materials" and "Interface\\Icons\\inv_misc_herb_19" or "Interface\\Icons\\inv_10_blacksmithing_consumable_repairhammer_color1")
            if page == "concentration" or page == "cooldowns" then summary.icon:SetTexture(136243) end
            if page == "knowledge" then summary.icon:SetTexture(134917) end
        elseif frame.currentTab == "auctions" then
            summary.title:SetText(L.AU_TITLE)
            summary.count:SetText(L.AU_SUBTITLE)
            summary.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
        elseif storageGroup then
            local source = ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() or "inventory"
            local titles = {inventory = L.INVENTORY, personal = L.PERSONAL_BANK, warband = L.WARBAND_BANK, guild = L.GUILD_BANK}
            local descriptions = {inventory = L.STORAGE_INVENTORY_DESC, personal = L.STORAGE_PERSONAL_DESC, warband = L.STORAGE_WARBAND_DESC, guild = L.STORAGE_GUILD_DESC}
            local allStorage = frame.currentTab == "storage"
            summary.title:SetText(allStorage and L.STORAGE_BROWSER_TITLE or (titles[source] or L.NAV_BAGS_BANKS))
            summary.count:SetText(allStorage and L.BROWSE_ALL_ITEMS_ORGANIZED_BY_TYPE or (descriptions[source] or L.STORAGE_INVENTORY_DESC))
            summary.icon:SetTexture(allStorage and "Interface\\Icons\\INV_Misc_Bag_36" or "Interface\\Icons\\achievement_guildperk_mobilebanking")
        elseif frame.currentTab == "equip" then
            summary.icon:SetTexture("Interface\\Icons\\INV_Chest_Cloth_17")
            summary.count:SetText(L.EQUIPMENT_DESC)
        else
            if SetPortraitTexture then pcall(SetPortraitTexture, summary.icon, "player") end
            summary.count:SetText(string.format(L.CHAR_COUNT, count))
        end
        summary:Show()
        bar:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -8)
        bar:SetPoint("TOPRIGHT", summary, "BOTTOMRIGHT", 0, -8)
    else
        summary:Hide()
        bar:SetPoint("TOPLEFT", frame.nav, "TOPRIGHT", 12, 0)
        bar:SetPoint("TOPRIGHT", frame.header, "BOTTOMRIGHT", -6, -8)
    end
    frame.content:ClearAllPoints()
    frame.content:SetPoint("TOPLEFT", frame.nav, "TOPRIGHT", 12, hasHeader and (show and -118 or -78) or (show and -40 or 0))
    frame.content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 45)
    for index, button in ipairs(bar.buttons) do
        local entry = show and group.pages[index]
        if entry then
            button.page = entry[1]
            button.active = entry[1] == frame.currentTab
            button.label:SetText(L[entry[2]])
            button.label:SetTextColor(unpack(button.active and ns.UI_COLORS.accent or ns.UI_COLORS.textNormal))
            button:SetBackdropColor(unpack(ns.UI_COLORS.bgCard))
            button:SetBackdropBorderColor(unpack(button.active and ns.UI_COLORS.accent or ns.UI_COLORS.border))
            button:Show()
        else button.page = nil; button:Hide() end
    end
    if show then bar.count = #group.pages; bar:Show(); bar.Layout() else bar:Hide() end
end
