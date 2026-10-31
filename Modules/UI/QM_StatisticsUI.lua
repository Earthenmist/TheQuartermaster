local _, ns = ...
local Addon, L = ns.TheQuartermaster, ns.L

local function Played(seconds)
    if not seconds or seconds <= 0 then return "--" end
    return string.format("%dd %02dh %02dm %02ds", math.floor(seconds/86400), math.floor(seconds%86400/3600), math.floor(seconds%3600/60), seconds%60)
end
local function Text(parent, value, x, y, width, font, colour)
    local label = ns.UI_RenderFontString(parent, nil, "OVERLAY", font or "QuartermasterFontBody")
    label:SetPoint("TOPLEFT", x, -y); label:SetWidth(math.max(1,width)); label:SetJustifyH("LEFT")
    label:SetWordWrap(false); label:SetText(tostring(value)); label:SetTextColor(unpack(colour or ns.UI_COLORS.textNormal))
    return label
end
local function CharacterName(char)
    if not char then return "--" end
    if ns.UI_FormatCharacterNameRealm then return ns.UI_FormatCharacterNameRealm(char.name, char.realm, char.classFile or char.class) end
    return (char.name or "--")..(char.realm and "-"..char.realm or "")
end
local function Card(parent, entry, x, y, width)
    local colours = ns.UI_COLORS
    local card = ns.UI_RenderFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetPoint("TOPLEFT", x, -y); card:SetSize(width, 98)
    card:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    card:SetBackdropColor(unpack(colours.bgCard)); card:SetBackdropBorderColor(unpack(colours.border))
    local icon = ns.UI_RenderTexture(card,nil,"ARTWORK")
    icon:SetPoint("TOPLEFT",12,-16); icon:SetSize(28,28); icon:SetTexture(entry.icon)
    Text(card,entry.label,50,12,width-62,"QuartermasterFontSmall",colours.textDim)
    Text(card,entry.value,50,31,width-62,entry.compact and "QuartermasterFontBody" or "QuartermasterFontTitle",entry.colour or colours.textNormal)
    Text(card,entry.note or L.AT_CACHED_CHARACTERS,12,65,width-24,"QuartermasterFontSmall",colours.textDim)
    if entry.total and entry.total>0 and entry.current then
        local track=ns.UI_RenderTexture(card,nil,"BACKGROUND")
        track:SetPoint("BOTTOMLEFT",12,8); track:SetSize(width-24,3); track:SetColorTexture(unpack(colours.border))
        if entry.current>0 then
            local fill=ns.UI_RenderTexture(card,nil,"ARTWORK")
            fill:SetPoint("BOTTOMLEFT",12,8); fill:SetSize((width-24)*math.min(1,entry.current/entry.total),3)
            fill:SetColorTexture(unpack(colours.accent))
        end
    end
    card:EnableMouse(true)
    card:SetScript("OnEnter",function(frame)
        GameTooltip:SetOwner(frame,"ANCHOR_RIGHT"); GameTooltip:SetText(entry.label,1,0.82,0)
        GameTooltip:AddLine(tostring(entry.value),1,1,1,true)
        GameTooltip:AddLine(entry.help or entry.note or L.AT_CACHED_CHARACTERS,0.8,0.8,0.8,true)
        if entry.capturedAt then GameTooltip:AddLine(L.ES_CHECKED..date("%d %b %H:%M",entry.capturedAt),0.6,0.6,0.6) end
        if entry.totalCapturedAt then GameTooltip:AddLine(string.format(L.AT_TOTAL_CHECKED,date("%d %b %H:%M",entry.totalCapturedAt)),0.6,0.6,0.6,true) end
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave",function() GameTooltip:Hide() end)
end

function Addon:DrawAccountStatistics(parent)
    if self.RequestAccountCollections then self:RequestAccountCollections() end
    local width, y = parent:GetWidth()-20, 10
    local colours, unknown = ns.UI_COLORS, L.AT_UNKNOWN
    local function Row(title,entries)
        Text(parent,title,10,y,width,"QuartermasterFontHeading",colours.accent); y=y+26
        local columns=math.min(#entries,width<740 and 2 or 3)
        local cardWidth=(width-(columns-1)*10)/columns
        for index,entry in ipairs(entries) do
            Card(parent,entry,10+((index-1)%columns)*(cardWidth+10),y+math.floor((index-1)/columns)*108,cardWidth)
        end
        y=y+math.ceil(#entries/columns)*108+10
    end
    local chars=self.db.global.characters or {}
    local count,gold,played,highest,most=0,0,0,nil,nil
    local guildCounts,guildLabels,guilded,unguilded={},{},0,0
    for _,char in pairs(chars) do
        count=count+1; gold=gold+(tonumber(char.gold) or 0); played=played+(tonumber(char.playedTime) or 0)
        if tonumber(char.ilvlEquipped or char.ilvlAvg) and (not highest or tonumber(char.ilvlEquipped or char.ilvlAvg)>(tonumber(highest.ilvlEquipped or highest.ilvlAvg) or 0)) then highest=char end
        if tonumber(char.playedTime) and (not most or char.playedTime>(most.playedTime or 0)) then most=char end
        local guild=char.guildName or (type(char.guild)=="table" and char.guild.name)
        if type(guild)=="string" and guild~="" then
            guilded=guilded+1
            local key=char.guildKey or ("unknown:"..tostring(char.name).."-"..tostring(char.realm))
            guildCounts[key]=(guildCounts[key] or 0)+1
            guildLabels[key]=guild.." - "..(char.guildRealm or L.GUILD_REALM_UNKNOWN)
        else unguilded=unguilded+1 end
    end
    local best
    for key,n in pairs(guildCounts) do if not best or n>guildCounts[best] or (n==guildCounts[best] and key<best) then best=key end end
    local wbGold=tonumber((self.db.global.warbandBank or {}).gold)
    local totalGold=ns.UI_FormatGold(gold+(wbGold or 0))
    local bankGold=wbGold and ns.UI_FormatGold(wbGold) or unknown
    Row(L.AT_ACCOUNT,{
        {label=L.ACHIEVEMENT_POINTS,value=GetTotalAchievementPoints() or unknown,icon="Interface\\Icons\\Achievement_General_StayClassy",note=L.AT_ACCOUNT_WIDE,colour=colours.accent},
        {label=L.TOTAL_GOLD,value=totalGold,icon="Interface\\Icons\\INV_Misc_Coin_01",note=wbGold and L.AT_GOLD_SCOPE or L.AT_GOLD_PARTIAL,compact=true},
        {label=L.WARBAND_GOLD,value=bankGold,icon="Interface\\Icons\\INV_Misc_Bag_36",note=L.AT_BANK_GOLD_SCOPE,compact=true},
    })
    local collections=self.accountCollections or {}
    local entries={}
    for _,def in ipairs({{"mounts",L.MOUNTS_COLLECTED,"Ability_Mount_RidingHorse"},{"pets",L.AT_PET_SPECIES,"INV_Box_PetCarrier_01"},{"toys",L.TOYS,"INV_Misc_Toy_10"}}) do
        local data=collections[def[1]]
        local value=data and tostring(data.owned) or unknown
        if data and data.total then value=value.." / "..data.total end
        entries[#entries+1]={label=def[2],value=value,icon="Interface\\Icons\\"..def[3],current=data and data.owned,total=data and data.total,
            note=data and (data.total and L.AT_JOURNAL_TOTAL or L.AT_TOTAL_UNVERIFIED) or L.AT_WAITING_JOURNAL,
            help=data and L[data.scope] or L.AT_COLLECTION_UNAVAILABLE,capturedAt=data and data.capturedAt,totalCapturedAt=data and data.totalCapturedAt,colour=colours.accent}
    end
    Row(L.AT_COLLECTIONS,entries)
    local maxLevel,rested=ns.GetExperienceSummary(chars)
    Row(L.NAV_CHARACTERS,{
        {label=L.TOTAL_CHARACTERS,value=count,icon="Interface\\Icons\\INV_Misc_GroupLooking"},
        {label=L.MAX_LEVEL,value=maxLevel,icon="Interface\\Icons\\Achievement_Level_90"},
        {label=L.FULLY_RESTED,value=rested,icon="Interface\\Icons\\Spell_Nature_Sleep"},
    })
    Row(L.AT_PLAY_AND_GEAR,{
        {label=L.TOTAL_PLAYED_TIME,value=Played(played),icon="Interface\\Icons\\INV_Misc_PocketWatch_01",compact=true},
        {label=L.HIGHEST_ITEM_LEVEL,value=CharacterName(highest),note=highest and string.format("iLvl %.1f",highest.ilvlEquipped or highest.ilvlAvg) or unknown,help=L.AT_CACHED_CHARACTERS,icon="Interface\\Icons\\ui_mission_itemupgrade",compact=true},
        {label=L.MOST_PLAYED_CHARACTER,value=CharacterName(most),note=most and Played(most.playedTime) or unknown,help=L.AT_CACHED_CHARACTERS,icon="Interface\\Icons\\Achievement_General_StayClassy",compact=true},
    })
    local stats=self:GetBankStatistics() or {}
    entries={}
    for _,def in ipairs({{"warband",L.WARBAND_BANK,L.AT_WARBAND_STORAGE},{"personal",L.PERSONAL_BANK,L.AT_CURRENT_STORAGE},{"inventory",L.INVENTORY,L.AT_CURRENT_STORAGE}}) do
        local data=stats[def[1]] or {}
        local total,used=tonumber(data.totalSlots),tonumber(data.usedSlots)
        local valid=total and total>0 and used and used>=0 and used<=total
        entries[#entries+1]={label=def[2],value=valid and (used.." / "..total) or unknown,
            note=valid and string.format(L.AT_STORAGE_NOTE,def[1]=="warband" and L.AT_ACCOUNT_WIDE or L.AT_CURRENT_CHARACTER,total-used) or L.AT_STORAGE_UNKNOWN,
            help=def[3],current=valid and used,total=valid and total,icon="Interface\\Icons\\INV_Misc_Bag_36"}
    end
    Row(L.AT_STORAGE,entries)
    Row(L.NAV_GUILDS,{
        {label=L.MOST_POPULAR_GUILD,value=best and guildLabels[best] or "--",icon="Interface\\Icons\\Achievement_guildperk_honorablemention",compact=true},
        {label=L.CHARACTERS_IN_A_GUILD,value=guilded,icon="Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"},
        {label=L.CHARACTERS_UNGUILDED,value=unguilded,icon="Interface\\Icons\\Ability_Rogue_Disguise"},
    })
    return y
end
