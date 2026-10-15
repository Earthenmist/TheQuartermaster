local _, ns = ...
local Addon, L, W = ns.TheQuartermaster, ns.L, ns.Wealth
local C = {}; ns.Comparison=C
function C.Domain(page)
    if page=="currency" or page=="reputations" then return page end
    if page=="recipes" or page=="materials" or page=="profequip" or page=="concentration" or page=="cooldowns" or page=="knowledge" then return "professions" end
end
function C.Settings(addon,domain)
    local profile=addon.db.profile
    profile.comparison=profile.comparison or {}
    profile.comparison[domain]=profile.comparison[domain] or {}
    return profile.comparison[domain]
end
local function Stamp(v) return W.Number(v) and v>0 and v<=time() and v or nil end
local function Cell(text,checked,current,cap,target)
    return {text=text,checked=Stamp(checked),current=current,cap=cap,target=target}
end
local function Number(v) return W.Number(v) and tostring(v) or L.CMP_MISSING end
local function Amount(v,cap) return Number(v)..(W.Number(cap) and cap>0 and " / "..Number(cap) or "") end
function C.Build(addon,domain,settings)
    local result={characters={},rows={},expansions={},professions={}}
    local selected={}
    for key,char in ns.OrderedCharacterPairs(addon.db) do
        if not settings.characters or settings.characters[key] then
            result.characters[#result.characters+1]={key=key,name=char.name or key,class=char.classFile or char.class}
            selected[key]=true
        end
    end
    local map={}
    local function Row(id,name,expansion,shared)
        expansion=expansion or L.CMP_OTHER
        result.expansions[expansion]=true
        local row=map[id]
        if not row then row={id=id,name=name,expansion=expansion,cells={},shared=shared};map[id]=row end
        if shared then row.shared=true end
        return row
    end
    if domain~="professions" then
        for _,character in ipairs(result.characters) do
            local char=addon.db.global.characters[character.key]
            local records=domain=="currency" and char.currencies or char.reputations
            for id,v in pairs(records or {}) do
                if type(v)=="table" and W.Public(v) then
                    local metadata=domain=="reputations" and (addon.db.global.factionMetadata or {})[id] or v
                    if metadata and not v.isHidden and (not metadata.isHeader or metadata.isHeaderWithRep) then
                        local expansion=domain=="currency" and v.expansion or metadata.parentHeaders and metadata.parentHeaders[1]
                        local row=Row(id,metadata.name or tostring(id),expansion,v.isAccountWide==true)
                        local cell
                        if domain=="currency" then
                            local heldCap=v.useTotalEarnedForMaxQty==false and v.maxQuantity or nil
                            cell=Cell(Amount(v.quantity,heldCap),v.checked,v.quantity,heldCap)
                            if v.useTotalEarnedForMaxQty==true then cell.note=L.CMP_EARNED..": "..Amount(v.totalEarned,v.maxQuantity) end
                            if v.maxWeeklyQuantity and v.maxWeeklyQuantity>0 then cell.note=(cell.note and cell.note.."\n" or "")..L.CMP_WEEKLY..": "..Amount(v.quantityEarnedThisWeek,v.maxWeeklyQuantity) end
                        else
                            local text=v.renownLevel and string.format(L.CMP_RENOWN,v.renownLevel) or v.rankName or _G["FACTION_STANDING_LABEL"..tostring(v.standingID)] or L.CMP_MISSING
                            cell=Cell(text,v.lastUpdated,v.paragonThreshold and v.paragonValue or v.currentValue,v.paragonThreshold or v.maxValue)
                            cell.note=Amount(cell.current,cell.cap)
                        end
                        row.cells[character.key]=cell
                    end
                end
            end
        end
    else
        -- Knowledge profiles provide expansion-specific skill identity; concentration and cooldowns retain their own dates.
        for _,p in ipairs(ns.KnowledgeData.professions) do result.professions[p.name]=true;result.expansions[p.expansion]=true end
        local profession=settings.profession
        if not profession then local names={};for name in pairs(result.professions) do names[#names+1]=name end;table.sort(names);profession=names[1] end
        result.profession=profession
        for _,p in ipairs(ns.KnowledgeData.professions) do
            if p.name==profession then
                local measures={{"skill",L.CMP_SKILL},{"concentration",L.PC_TITLE},{"unspent",L.KP_UNSPENT},{"spent",L.KP_SPENT},{"cooldowns",L.CD_TITLE}}
                for _,measure in ipairs(measures) do
                    local kind,label=unpack(measure)
                    local row=Row(p.skill..":"..kind,label,p.expansion)
                    for _,character in ipairs(result.characters) do
                        local char=addon.db.global.characters[character.key]
                        local snapshot=(char.professionKnowledge or {})[p.skill]
                        if snapshot and snapshot.version~=1 then snapshot=nil end
                        local summary=snapshot and snapshot.summary
                        local target=kind=="concentration" and "concentration" or kind=="cooldowns" and "cooldowns" or "knowledge"
                        local cell=Cell(L.CMP_MISSING,nil,nil,nil,target);cell.profile=p
                        if kind=="skill" and snapshot then cell.text=Number(snapshot.skillLevel);cell.checked=Stamp(snapshot.checked)
                        elseif kind=="unspent" and summary then cell.text=Number(summary.unspent);cell.checked=Stamp(summary.checked)
                        elseif kind=="spent" and summary then cell.text=Amount(summary.spent,summary.capacity);cell.checked=Stamp(summary.checked);cell.current=summary.spent;cell.cap=summary.capacity
                        elseif kind=="concentration" then
                            local count=0
                            for _,pool in pairs(char.professionConcentration or {}) do
                                if pool.skillLines and pool.skillLines[p.skill] then
                                    local estimate=ns.ConcentrationEstimate(pool,time())
                                    if estimate then count=count+1;cell.text=(estimate.estimated and "~" or "")..Amount(estimate.amount,estimate.cap);cell.checked=Stamp(pool.checked);cell.current=estimate.amount;cell.cap=estimate.cap end
                                end
                            end
                            if count>1 then cell.text=L.CMP_MULTIPLE;cell.current=nil;cell.cap=nil end
                        elseif kind=="cooldowns" then
                            local cache=(char.professionCooldowns or {})[p.root]
                            if cache and cache.version==1 then
                                local counts={ready=0,estimated=0,cooling=0,stale=0};local found=false
                                for _,cooldown in pairs(cache.rows or {}) do
                                    local expansion=p.expansion=="TWW" and L.KP_TWW or p.expansion
                                    if cooldown.expansion==expansion then
                                        local state=ns.RecipeCooldownState(cooldown,time());counts[state]=counts[state]+1;found=true
                                    end
                                end
                                if found then cell.text=counts.stale>0 and counts.ready+counts.cooling+counts.estimated==0 and L.KP_STATE_stale or (counts.estimated>0 and "~" or "")..string.format(L.CMP_COOLDOWNS,counts.ready+counts.estimated,counts.cooling);cell.note=string.format(L.CMP_ESTIMATES,counts.estimated,counts.stale);cell.checked=Stamp(cache.checked) end
                            end
                        end
                        if cell.text==L.CMP_MISSING then cell.target=nil end
                        row.cells[character.key]=cell
                    end
                end
            end
        end
    end
    local query=(settings.query or ""):lower()
    for _,row in pairs(map) do
        if (not settings.expansion or settings.expansion==row.expansion) and (query=="" or row.name:lower():find(query,1,true)) then
            if row.shared then
                for _,character in ipairs(result.characters) do
                    local cell=row.cells[character.key]
                    if cell and (not row.sharedCell or (cell.checked or 0)>(row.sharedCell.checked or 0)) then row.sharedCell=cell;row.observedOn=character.key end
                end
            end
            result.rows[#result.rows+1]=row
        end
    end
    table.sort(result.rows,function(a,b) if a.shared~=b.shared then return a.shared==true end;if a.expansion~=b.expansion then return a.expansion<b.expansion end;if a.name~=b.name then return a.name<b.name end;return tostring(a.id)<tostring(b.id) end)
    return result
end
function Addon:OpenComparisonDetail(key,cell)
    local p=cell.profile;if not p then return end
    local settings=C.Settings(self,"professions");settings.enabled=false
    if cell.target=="knowledge" then self.knowledgeFilters={character=key,profession=p.name,expansion=p.expansion}
    elseif cell.target=="concentration" then self.concentrationFilters={character=key,profession=p.root,expansion=p.expansion=="TWW" and L.KP_TWW or p.expansion}
    else self.cooldownFilters={character=key,profession=p.name} end
    self.UI.mainFrame.currentTab=cell.target;if self.UI.mainFrame.scroll then self.UI.mainFrame.scroll:SetVerticalScroll(0) end;self:RefreshUI()
end
