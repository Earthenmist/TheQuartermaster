
--[[
    The Quartermaster - Global Search UI
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

-- Context menu utility (works on modern + classic dropdown APIs)
local QM_OpenRowMenu_DROPDOWN
local function QM_OpenRowMenu(menu, anchor)
    if not menu or #menu == 0 then return end

    -- Modern menu API
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(anchor or UIParent, function(_, rootDescription)
            for _, entry in ipairs(menu) do
                rootDescription:CreateButton(entry.text, entry.func)
            end
        end)
        return
    end

    -- Legacy dropdown API fallback
    if not QM_OpenRowMenu_DROPDOWN then
        QM_OpenRowMenu_DROPDOWN = CreateFrame("Frame", "QM_SearchContextMenuDrop", UIParent, "UIDropDownMenuTemplate")
    end

    if UIDropDownMenu_Initialize and ToggleDropDownMenu and UIDropDownMenu_CreateInfo then
        UIDropDownMenu_Initialize(QM_OpenRowMenu_DROPDOWN, function(self, level)
            local info = UIDropDownMenu_CreateInfo()
            for _, entry in ipairs(menu) do
                info.text = entry.text
                info.func = entry.func
                info.notCheckable = true
                UIDropDownMenu_AddButton(info, level)
            end
        end, "MENU")
        ToggleDropDownMenu(1, nil, QM_OpenRowMenu_DROPDOWN, "cursor", 0, 0)
    end
end

local function QM_CopyItemLinkToChat(itemLink)
    if not itemLink then return end
    if ChatFrame_OpenChat then
        ChatFrame_OpenChat(itemLink)
    else
        local editBox = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
        if editBox then
            editBox:Insert(itemLink)
        end
    end
end

local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard

local function ItemPages(addon, parent, y, page, pages)
    if pages <= 1 then return y end
    for i, entry in ipairs({{ns.L.RB_PREVIOUS, -1}, {ns.L.RB_NEXT, 1}}) do
        local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
        button:SetSize(100, 24); button:SetPoint("TOPLEFT", 10 + (i - 1) * 260, -y)
        button:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        button:SetBackdropColor(unpack(COLORS.bgCard)); button:SetBackdropBorderColor(unpack(COLORS.border))
        local label = button:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
        label:SetPoint("CENTER"); label:SetText(entry[1])
        local target = page + entry[2]
        button:SetEnabled(target >= 1 and target <= pages)
        button:SetScript("OnClick", function()
            ns.globalSearchItemPage = target
            if addon.UI and addon.UI.mainFrame then addon.UI.mainFrame.scroll:SetVerticalScroll(0) end
            addon:PopulateContent()
        end)
    end
    local label = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
    label:SetPoint("TOPLEFT", 130, -y - 6); label:SetText(string.format(ns.L.RB_PAGE, page, pages))
    return y + 32
end

local function DrawEmptyState(parent, text, yOffset)
    local msg = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    msg:SetPoint("TOPLEFT", 20, -yOffset)
    msg:SetTextColor(0.7, 0.7, 0.7)
    msg:SetText(text)
    return yOffset + 30
end

local function CreateRow(parent, y, width, height)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(width, height)
    row:SetPoint("TOPLEFT", 10, -y)
    row:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 2,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    row:SetBackdropColor(unpack(COLORS.bgCard))
    row:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 8, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetTextColor(1, 1, 1)

    row.meta = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
    row.meta:SetPoint("RIGHT", -60, 0)
    row.meta:SetJustifyH("RIGHT")
    row.meta:SetTextColor(0.8, 0.8, 0.8)

    row.count = row:CreateFontString(nil, "OVERLAY", "QuartermasterFontBody")
    row.count:SetPoint("RIGHT", -12, 0)
    row.count:SetJustifyH("RIGHT")
    row.count:SetTextColor(1, 1, 1)

    
row.pin = CreateFrame("Button", nil, row, "BackdropTemplate")
row.pin:SetSize(22, 22)
row.pin:SetPoint("RIGHT", row.meta, "LEFT", -8, 0)
row.pin:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
row.pin:SetBackdropColor(0, 0, 0, 0.20)

row.pin.icon = row.pin:CreateTexture(nil, "ARTWORK")
row.pin.icon:SetAllPoints()
-- Favorite star icon (texture avoids missing-font glyphs)
row.pin.icon:SetTexture("Interface\\Common\\FavoritesIcon")
row.pin.icon:SetAlpha(0.9)

    row.pin:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        local text = btn.isPinned and "Unpin from Watchlist" or "Pin to Watchlist"
        GameTooltip:AddLine(text, 1, 1, 1)
        GameTooltip:AddLine("Click to toggle.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    row.pin:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    row.pin.icon:SetVertexColor(1, 1, 1)

    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.5)
        GameTooltip:Hide()
    end)

    
row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
row:SetScript("OnMouseUp", function(selfRow, btn)
    if btn == "RightButton" then
        if selfRow.kind == "item" and selfRow.itemID then
            QM_SearchUI_ContextMenu(TheQuartermaster, "item", selfRow.itemID, selfRow)
        elseif selfRow.kind == "currency" and selfRow.currencyID then
            QM_SearchUI_ContextMenu(TheQuartermaster, "currency", selfRow.currencyID, selfRow)
        end
    end
end)

return row
end


-- Context menu helper (right-click rows)
local function QM_SearchUI_ContextMenu(self, kind, id, anchor)
    if not kind or not id then return end
    local menu = {}
    if kind == "item" then
            local pinned = self:IsWatchlistedItem(id)
            table.insert(menu, {
                text = pinned and "Unpin from Watchlist" or "Pin to Watchlist",
                func = function() self:ToggleWatchlistItem(id) end,
            })
            table.insert(menu, {
                text = "Copy Item Link",
                func = function()
                    local _, link = GetItemInfo(id)
                    QM_CopyItemLinkToChat(link)
                end,
            })
        elseif kind == "currency" then
        local pinned = self:IsWatchlistedCurrency(id)
        table.insert(menu, {
            text = pinned and "Unpin from Watchlist" or "Pin to Watchlist",
            func = function() self:ToggleWatchlistCurrency(id) end,
        })
    end
    if #menu > 0 then
        QM_OpenRowMenu(menu, anchor or UIParent)
    end
end

local function DrawItemFilters(addon, parent, width, y, settings)
    local L = ns.L
    local function Button(label, x, top, w, callback)
        local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
        b:SetPoint("TOPLEFT", x, -top); b:SetSize(w, 28)
        b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
        b:SetBackdropColor(unpack(COLORS.bgCard)); b:SetBackdropBorderColor(unpack(COLORS.border))
        local text=b:CreateFontString(nil,"OVERLAY","QuartermasterFontSmall")
        text:SetPoint("LEFT",8,0); text:SetWidth(w-16); text:SetJustifyH("LEFT"); text:SetWordWrap(false); text:SetText(label)
        b:SetScript("OnClick",callback)
        b:SetScript("OnEnter",function() b:SetBackdropBorderColor(unpack(COLORS.accent)) end)
        b:SetScript("OnLeave",function() b:SetBackdropBorderColor(unpack(COLORS.border)) end)
        return b
    end
    local function Refresh() ns.globalSearchItemPage=1; addon:PopulateContent() end
    local active=ns.SearchFilters.Active(settings)
    Button((settings.expanded and "- " or "+ ")..L.SF_TITLE..(active and " *" or ""),10,y,200,function()
        settings.expanded=not settings.expanded; Refresh()
    end)
    Button(L.SF_RESET,218,y,150,function()
        local expanded=settings.expanded
        for key in pairs(settings) do settings[key]=nil end
        settings.expanded=expanded; Refresh()
    end)
    y=y+36
    if not settings.expanded then return y end
    local third=(width-16)/3
    local function Dropdown(field, all, choices, x)
        local label=all
        for _,entry in ipairs(choices) do if entry[1]==settings[field] then label=entry[2] end end
        Button(label.."  v",x,y,third,function(b)
            ns.UI_RecipeMenu(b,function(_,menu)
                menu:CreateButton(all,function() settings[field]=nil; Refresh() end)
                for _,entry in ipairs(choices) do
                    menu:CreateButton(entry[2],function() settings[field]=entry[1]; Refresh() end)
                end
            end)
        end)
    end
    local slots={}
    for _,key in ipairs({"HEAD","NECK","SHOULDER","BODY","CHEST","WAIST","LEGS","FEET","WRIST","HAND","FINGER","TRINKET","CLOAK","WEAPON","2HWEAPON","WEAPONMAINHAND","WEAPONOFFHAND","SHIELD","HOLDABLE","RANGED","RANGEDRIGHT","THROWN","RELIC","TABARD","BAG","PROFESSION_TOOL","PROFESSION_GEAR"}) do
        local token="INVTYPE_"..key
        if _G[token] then slots[#slots+1]={token,_G[token]} end
    end
    Dropdown("slot",L.SF_ALL_SLOTS,slots,10)
    local qualities={}
    for i=0,8 do if _G["ITEM_QUALITY"..i.."_DESC"] then qualities[#qualities+1]={i,_G["ITEM_QUALITY"..i.."_DESC"]} end end
    Dropdown("quality",L.SF_ALL_QUALITIES,qualities,18+third)
    local expansions={}
    for i=30,0,-1 do if _G["EXPANSION_NAME"..i] then expansions[#expansions+1]={i,_G["EXPANSION_NAME"..i]} end end
    Dropdown("expansion",L.PD_ALL_EXPANSIONS,expansions,26+third*2)
    y=y+42
    local editors={}
    local function Range(label, low, high, x)
        local text=parent:CreateFontString(nil,"OVERLAY","QuartermasterFontSmall")
        text:SetPoint("TOPLEFT",x,-y); text:SetText(label)
        for i,key in ipairs({low,high}) do
            local box=CreateFrame("EditBox",nil,parent,"BackdropTemplate")
            box:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
            box:SetBackdropColor(unpack(COLORS.bgCard));box:SetBackdropBorderColor(unpack(COLORS.border))
            box:SetFontObject("QuartermasterFontSmall");box:SetTextInsets(6,6,0,0)
            box:SetSize(math.max(50,(third-26)/2),24); box:SetPoint("TOPLEFT",x+6+(i-1)*(third/2),-y-20)
            box:SetAutoFocus(false); box:SetNumeric(true); box:SetMaxLetters(5)
            box:SetText(settings[key] and tostring(settings[key]) or "")
            editors[key]=box
            box:SetScript("OnEscapePressed",function(b) b:ClearFocus() end)
        end
    end
    Range(L.SF_ITEM_LEVEL,"minItemLevel","maxItemLevel",10)
    Range(L.SF_REQUIRED_LEVEL,"minRequiredLevel","maxRequiredLevel",18+third)
    local function Apply()
        for key,box in pairs(editors) do settings[key]=tonumber(box:GetText()); box:ClearFocus() end
        for _,pair in ipairs({{"minItemLevel","maxItemLevel"},{"minRequiredLevel","maxRequiredLevel"}}) do
            local a,b=settings[pair[1]],settings[pair[2]]
            if a and b and a>b then settings[pair[1]],settings[pair[2]]=b,a end
        end
        Refresh()
    end
    for _,box in pairs(editors) do box:SetScript("OnEnterPressed",Apply) end
    Button(L.SF_APPLY,26+third*2,y+18,third,Apply)
    y=y+58
    local hint=parent:CreateFontString(nil,"OVERLAY","QuartermasterFontSmall")
    hint:SetPoint("TOPLEFT",10,-y);hint:SetWidth(width);hint:SetJustifyH("LEFT");hint:SetWordWrap(true)
    hint:SetText(L.SF_HINT);hint:SetTextColor(unpack(COLORS.textDim))
    return y+hint:GetStringHeight()+12
end

function TheQuartermaster:DrawGlobalSearch(parent)

local yOffset = 8
local width = parent:GetWidth() - 20

-- Controls card (extra padding)
local controls = CreateCard(parent, 64)
controls:SetWidth(width)
controls:SetPoint("TOPLEFT", 10, -yOffset)

local wl = self.db and self.db.profile and self.db.profile.watchlist
if not wl then wl = { includeGuildBank = true } end

local mode = ns.globalSearchMode or "all"
local includeGuild = ns.globalSearchIncludeGuild
if includeGuild == nil then includeGuild = wl.includeGuildBank ~= false end

local function Skin(button)
    button:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    button:SetBackdropColor(unpack(COLORS.bgCard)); button:SetBackdropBorderColor(unpack(COLORS.border))
    button:SetScript("OnEnter",function(b) b:SetBackdropBorderColor(unpack(COLORS.accent)) end)
    button:SetScript("OnLeave",function(b) b:SetBackdropBorderColor(unpack(COLORS.border)) end)
end
local choices={{"all",ns.L.SEARCH_MODE_ALL},{"items",ns.L.SEARCH_MODE_ITEMS},{"reagents",ns.L.SEARCH_MODE_REAGENTS},{"currency",ns.L.CURRENCY}}
local drop=CreateFrame("Button",nil,controls,"BackdropTemplate")
drop:SetSize(180,28); drop:SetPoint("LEFT",16,0); Skin(drop)
local label=drop:CreateFontString(nil,"OVERLAY","QuartermasterFontSmall")
label:SetPoint("LEFT",10,0); label:SetText(ns.L.SEARCH_MODE_ALL); label:SetTextColor(unpack(COLORS.textNormal))
local arrow=drop:CreateTexture(nil,"ARTWORK")
arrow:SetSize(12,12); arrow:SetPoint("RIGHT",-6,0)
arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up"); arrow:SetVertexColor(unpack(COLORS.accent))
local menu=CreateFrame("Frame",nil,drop,"BackdropTemplate")
menu:SetSize(180,#choices*26+8); menu:SetPoint("TOPLEFT",drop,"BOTTOMLEFT",0,-2)
menu:SetFrameStrata("DIALOG"); Skin(menu)
for index,choice in ipairs(choices) do
    if choice[1]==mode then label:SetText(choice[2]) end
    local option=CreateFrame("Button",nil,menu,"BackdropTemplate")
    option:SetSize(172,26); option:SetPoint("TOPLEFT",4,-4-(index-1)*26); Skin(option)
    local text=option:CreateFontString(nil,"OVERLAY","QuartermasterFontSmall")
    text:SetPoint("LEFT",8,0); text:SetText(choice[2]); text:SetTextColor(unpack(choice[1]==mode and COLORS.accent or COLORS.textNormal))
    option:SetScript("OnClick",function() menu:Hide(); ns.globalSearchMode=choice[1]; self:PopulateContent() end)
end
menu:Hide()
drop:SetScript("OnClick",function() if menu:IsShown() then menu:Hide() else menu:Show() end end)
controls.modeDrop=drop
local cb=CreateFrame("CheckButton",nil,controls,"BackdropTemplate")
cb:SetSize(18,18); cb:SetPoint("LEFT",drop,"RIGHT",28,0); Skin(cb)
local mark=cb:CreateTexture(nil,"ARTWORK")
mark:SetPoint("TOPLEFT",4,-4); mark:SetPoint("BOTTOMRIGHT",-4,4)
mark:SetColorTexture(unpack(COLORS.accent)); cb:SetCheckedTexture(mark); cb:SetChecked(includeGuild)
local text=cb:CreateFontString(nil,"OVERLAY","QuartermasterFontSmall")
text:SetPoint("LEFT",cb,"RIGHT",8,0); text:SetText(ns.L.SEARCH_INCLUDE_GUILD); text:SetTextColor(unpack(COLORS.textNormal))
cb:SetScript("OnClick",function(button)
    ns.globalSearchIncludeGuild=button:GetChecked() and true or false
    if self.db.profile.watchlist then self.db.profile.watchlist.includeGuildBank=ns.globalSearchIncludeGuild end
    self:PopulateContent()
end)
controls.guildCheck=cb

yOffset = yOffset + 74
local profile=self.db.profile
profile.searchFilters=type(profile.searchFilters)=="table" and profile.searchFilters or {}
local filters=profile.searchFilters
if mode ~= "currency" then yOffset=DrawItemFilters(self,parent,width,yOffset,filters) end
local mailNote = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontSmall")
mailNote:SetPoint("TOPLEFT", 10, -yOffset)
mailNote:SetWidth(width); mailNote:SetJustifyH("LEFT"); mailNote:SetWordWrap(true)
mailNote:SetText(ns.L.MAIL_ATTACHMENT_NOTE)
yOffset = yOffset + mailNote:GetStringHeight() + 12

local searchText = ns.globalSearchText or ""

    if searchText:match("^%s*$") and (mode == "currency" or not ns.SearchFilters.Active(filters)) then
        return DrawEmptyState(parent, ns.L.SF_EMPTY, yOffset)
    end

    local results = self:PerformGlobalSearch(searchText, mode, includeGuild, filters)
    local pageKey = searchText .. "\031" .. mode .. tostring(includeGuild) .. ns.SearchFilters.Key(filters)
    if ns.globalSearchPageKey ~= pageKey then ns.globalSearchItemPage = 1; ns.globalSearchPageKey = pageKey end

    if results.unknownItems and results.unknownItems > 0 then
        local note=parent:CreateFontString(nil,"OVERLAY","QuartermasterFontSmall")
        note:SetPoint("TOPLEFT",10,-yOffset);note:SetWidth(width);note:SetJustifyH("LEFT");note:SetWordWrap(true)
        note:SetText(string.format(ns.L.SF_UNKNOWN,results.unknownItems));note:SetTextColor(unpack(COLORS.textDim))
        yOffset=yOffset+note:GetStringHeight()+12
    end
    -- Items results
    if mode == "all" or mode == "items" or mode == "reagents" then
        local items = results.items or {}
        local title = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontHeading")
        title:SetPoint("TOPLEFT", 10, -yOffset)
        title:SetText(mode == "reagents" and "Reagents" or "Items")
        title:SetTextColor(1, 1, 1)
        yOffset = yOffset + 26

        if #items == 0 then
            yOffset = DrawEmptyState(parent, "No item matches found.", yOffset)
        else
            local rowH = 30
            local pages = math.max(1, math.ceil(#items / 60))
            local page = math.max(1, math.min(ns.globalSearchItemPage or 1, pages))
            ns.globalSearchItemPage = page
            yOffset = ItemPages(self, parent, yOffset, page, pages)
            for i=(page - 1) * 60 + 1, math.min(#items, page * 60) do
                local r = items[i]
                local item = r.item
                local row = CreateRow(parent, yOffset, width, rowH)
                row.icon:SetTexture(item and item.iconFileID or 134400)
                row.name:SetText(item and item.name or ("Item " .. tostring(item and item.itemID or "")))
                row.meta:SetText((r.location or "") .. (r.locationDetail and (" • " .. r.locationDetail) or ""))
                row.count:SetText(tostring(item and (item.stackCount or item.count or 1) or 1))

                local itemID = item and item.itemID
                row.kind = (mode == "reagents") and "reagent" or "item"
                row.itemID = itemID
                row.currencyID = nil
                local pinned = itemID and ((mode == "reagents") and self:IsWatchlistedReagent(itemID) or self:IsWatchlistedItem(itemID))
                if pinned then
                    row.pin.icon:SetVertexColor(1, 0.2, 0.2) -- red when pinned
                else
                    row.pin.icon:SetVertexColor(1, 0.82, 0) -- yellow when not pinned
                end

				row.pin:SetScript("OnClick", function()
					if not itemID then return end
					if mode == "reagents" then
						self:ToggleWatchlistReagent(itemID)
						local nowPinned = self:IsWatchlistedReagent(itemID)
						row.pin.icon:SetVertexColor(nowPinned and 1 or 1, nowPinned and 0.2 or 0.82, nowPinned and 0.2 or 0, 1)
					else
						self:ToggleWatchlistItem(itemID)
						local nowPinned = self:IsWatchlistedItem(itemID)
						row.pin.icon:SetVertexColor(nowPinned and 1 or 1, nowPinned and 0.2 or 0.82, nowPinned and 0.2 or 0, 1)
					end
				end)

                row:SetScript("OnEnter", function(selfRow)
                    selfRow:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
                    if item and item.itemLink then
                        GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink(item.itemLink)
                        if r.auction then TheQuartermaster:AuctionTooltip(r.auction) end
                        if r.mailExpiresAt then
                            GameTooltip:AddLine(r.locationDetail, 0.3, 0.8, 0.8, true)
                            GameTooltip:AddLine(string.format(ns.L.MAIL_ATTACHMENT_EXPIRY,
                                TheQuartermaster:FormatMailTimeLeft(r.mailExpiresAt - time())), 1, 0.7, 0.3, true)
                            GameTooltip:AddDoubleLine(ns.L.MAIL_LAST_SCANNED, date("%Y-%m-%d %H:%M", r.mailLastScan))
                        end
                        GameTooltip:Show()
                    end
                end)

                yOffset = yOffset + rowH + 6
            end
            yOffset = ItemPages(self, parent, yOffset, page, pages)
        end
        yOffset = yOffset + 10
    end

    -- Currency results
    if mode == "currency" or (mode == "all" and not ns.SearchFilters.Active(filters)) then
        local cur = results.currencies or {}
        local title = parent:CreateFontString(nil, "OVERLAY", "QuartermasterFontHeading")
        title:SetPoint("TOPLEFT", 10, -yOffset)
        title:SetText("Currency")
        title:SetTextColor(1, 1, 1)
        yOffset = yOffset + 26

        if #cur == 0 then
            yOffset = DrawEmptyState(parent, "No currency matches found.", yOffset)
        else
            local rowH = 30
            for i=1, math.min(#cur, 60) do
                local r = cur[i]
                local currencyID = r.currencyID
                local c = r.currency or {}
                local row = CreateRow(parent, yOffset, width, rowH)
                row.kind = "item"
                row.itemID = itemID
                row.currencyID = nil

                row.icon:SetTexture(c.iconFileID or c.icon or 134400)
                row.name:SetText(c.name or ("Currency " .. tostring(currencyID)))
                row.meta:SetText((r.character or "Unknown") .. (r.realm and (" • " .. r.realm) or ""))
                row.count:SetText(tostring(c.quantity or c.count or 0))

                local pinned = currencyID and self:IsWatchlistedCurrency(currencyID)
                if pinned then
                    row.pin.icon:SetVertexColor(1, 0.2, 0.2) -- red when pinned
                else
                    row.pin.icon:SetVertexColor(1, 0.82, 0) -- yellow when not pinned
                end

				row.pin:SetScript("OnClick", function()
					if not currencyID then return end
					self:ToggleWatchlistCurrency(currencyID)
					local nowPinned = self:IsWatchlistedCurrency(currencyID)
					if nowPinned then
						row.pin.icon:SetVertexColor(1, 0.2, 0.2)
					else
						row.pin.icon:SetVertexColor(1, 0.82, 0)
					end
				end)

                row:SetScript("OnEnter", function(selfRow)
                    selfRow:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
                    if currencyID and GameTooltip and GameTooltip.SetCurrencyByID then
                        GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
                        GameTooltip:SetCurrencyByID(currencyID)
                        GameTooltip:Show()
                    end
                end)

                yOffset = yOffset + rowH + 6
            end
        end
        yOffset = yOffset + 10
    end

        parent:SetHeight(yOffset + 20)
        return yOffset
end
