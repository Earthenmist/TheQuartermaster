--[[
    The Quartermaster - PvE Progress Tab
    Display Great Vault, Mythic+ keystones, and Raid lockouts for all characters
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local FormatCharacterNameRealm = ns.UI_FormatCharacterNameRealm
local function GetCOLORS()
    return ns.UI_COLORS
end

-- Performance: Local function references
local format = string.format
local date = date

-- Expand/Collapse State Management
local expandedStates = {}

local function IsExpanded(key, defaultState)
    if expandedStates[key] == nil then
        expandedStates[key] = defaultState
    end
    return expandedStates[key]
end

local function ToggleExpand(key, newState)
    expandedStates[key] = newState
    TheQuartermaster:RefreshUI()
end

--============================================================================
-- DRAW PVE PROGRESS (Great Vault, Lockouts, M+)
--============================================================================

function TheQuartermaster:GetPvEResourceStats()
    return self.pveRenderPool and self.pveRenderPool:GetStats() or nil
end

function TheQuartermaster:DrawPvEProgress(parent)
    self.pveRenderPool = self.pveRenderPool or ns.UI_NewRenderPool(parent)
    local pool = self.pveRenderPool
    parent = pool:Begin(parent:GetWidth())
    local yOffset = 8 -- Top padding for breathing room
    local width = parent:GetWidth() - 20
    
    local characters = ns.SortCharacterRows(self.db, self:GetAllCharacters())

    -- Content visibility owns the timer; its text lives in the fixed page header.
    local titleCard = ns.UI_RenderFrame("Frame", nil, parent)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetSize(1, 1)
    local summary = self.UI and self.UI.mainFrame and self.UI.mainFrame.characterOverviewHeader
    local resetText = summary and summary.dragHint or ns.UI_RenderFontString(titleCard, nil, "OVERLAY", "QuartermasterFontSmall")
    if not summary then resetText:SetPoint("RIGHT", -8, 0) end
    local function GetWeeklyResetTime()
        return self:GetWeeklyResetSeconds()
    end

    local function FormatResetTime(seconds)
        if not seconds then return L["PVE_TIME_UNKNOWN"] end
        if seconds <= 0 then
            return L["PVE_RESET_DUE"]
        end
        
        local days = math.floor(seconds / 86400)
        local hours = math.floor((seconds % 86400) / 3600)
        local mins = math.floor((seconds % 3600) / 60)
        
        if days > 0 then
            return string.format("%d Days %d Hours", days, hours)
        elseif hours > 0 then
            return string.format("%d Hours %d Minutes", hours, mins)
        else
            return string.format("%d Minutes", mins)
        end
    end
    
    -- Update timer
    local secondsUntil = GetWeeklyResetTime()
    resetText:SetText("|cffaaaaaaWeekly Reset in:|r |cff4DE64D" .. FormatResetTime(secondsUntil) .. "|r")
    
    -- This card owns one timer, only while actually visible (including parent visibility).
    local function StartResetTicker(card)
        if card.resetTicker or not card:IsVisible() then return end
        resetText:SetText("|cffaaaaaaWeekly Reset in:|r |cff4DE64D" .. FormatResetTime(GetWeeklyResetTime()) .. "|r")
        card.resetTicker = C_Timer.NewTicker(60, function()
            resetText:SetText("|cffaaaaaaWeekly Reset in:|r |cff4DE64D" .. FormatResetTime(GetWeeklyResetTime()) .. "|r")
        end)
    end
    titleCard:SetScript("OnShow", StartResetTicker)
    titleCard:SetScript("OnHide", function(card)
        if card.resetTicker then card.resetTicker:Cancel(); card.resetTicker = nil end
    end)
    StartResetTicker(titleCard)

    yOffset, characters = ns.UI_DrawWeeklyControls(parent, yOffset, characters)

    -- ===== EMPTY STATE =====
    if #characters == 0 then
        local emptyIcon = ns.UI_RenderTexture(parent, nil, "ARTWORK")
        emptyIcon:SetSize(64, 64)
        emptyIcon:SetPoint("TOP", 0, -yOffset - 50)
        emptyIcon:SetTexture("Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster")
        emptyIcon:SetDesaturated(true)
        emptyIcon:SetAlpha(0.4)
        
        local emptyText = ns.UI_RenderFontString(parent, nil, "OVERLAY", "QuartermasterFontTitle")
        emptyText:SetPoint("TOP", 0, -yOffset - 130)
        emptyText:SetText(L["CFF666666NO_CHARACTERS_FOUND_R"])
        
        local emptyDesc = ns.UI_RenderFontString(parent, nil, "OVERLAY", "QuartermasterFontBody")
        emptyDesc:SetPoint("TOP", 0, -yOffset - 160)
        emptyDesc:SetTextColor(0.6, 0.6, 0.6)
        emptyDesc:SetText(L["LOG_IN_TO_ANY_CHARACTER_TO_START_TRACKING_PVE_PROGRESS"])
        
        local emptyHint = ns.UI_RenderFontString(parent, nil, "OVERLAY", "QuartermasterFontSmall")
        emptyHint:SetPoint("TOP", 0, -yOffset - 185)
        emptyHint:SetTextColor(0.5, 0.5, 0.5)
        emptyHint:SetText(L["GREAT_VAULT_MYTHIC_AND_RAID_LOCKOUTS_WILL_BE_DISPLAYED_HERE"])
        
        return pool:Finish(yOffset + 240)
    end
    
    -- Render the selected character directly below the selector.
    for i, char in ipairs(characters) do
        local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
        local pve = self:GetPvEView(char.pve)
        pve.mythicPlus = pve.mythicPlus or {}
        if pve.periodState then
            local notice = ns.UI_RenderFontString(parent, nil, "OVERLAY", "QuartermasterFontSmall")
            notice:SetPoint("TOPLEFT", 15, -yOffset)
            notice:SetText(L["PVE_PERIOD_" .. pve.periodState])
            notice:SetTextColor(unpack(ns.UI_COLORS.warning))
            yOffset = yOffset + 20
        end
        if (pve.scanState == "stale" or pve.scanState == "unavailable") then
            local notice = ns.UI_RenderFontString(parent, nil, "OVERLAY", "QuartermasterFontSmall")
            notice:SetPoint("TOPLEFT", 15, -yOffset)
            notice:SetText(L[pve.scanState == "stale" and "PVE_SCAN_RETAINED" or "PVE_SCAN_UNAVAILABLE"])
            notice:SetTextColor(1, 0.7, 0.3)
            yOffset = yOffset + 20
        end
        
        do
            local sectionTop = yOffset
            local cardContainer = ns.UI_RenderFrame("Frame", nil, parent)
            local totalWidth = parent:GetWidth() - 20
            local summaryWidth = math.floor(totalWidth * 0.38)
            local activityWidth = totalWidth - summaryWidth - 12
            local activityContainer = ns.UI_RenderFrame("Frame", nil, parent)
            activityContainer:SetPoint("TOPLEFT", 10, -yOffset)
            activityContainer:SetWidth(activityWidth)
            local activityHeight = ns.UI_DrawWeeklyActivities(activityContainer, 0, char)
            activityContainer:SetHeight(activityHeight)
            cardContainer:SetPoint("TOPLEFT", 10 + activityWidth + 12, -yOffset)
            cardContainer:SetWidth(summaryWidth)

            local card1Width = summaryWidth
            local card2Width = summaryWidth
            local card3Width = summaryWidth
            local cardHeight = 200  -- Reduced from 280 to 200
            local cardSpacing = 5
            
            -- === CARD 1: GREAT VAULT (30%) ===
            local vaultCard = CreateCard(cardContainer, cardHeight)
            vaultCard:SetPoint("TOPLEFT", 0, 0)
            vaultCard:SetWidth(card1Width - cardSpacing)


-- Great Vault header
local vaultTitle = ns.UI_RenderFontString(vaultCard, nil, "OVERLAY", "QuartermasterFontHeading")
vaultTitle:SetPoint("TOP", vaultCard, "TOP", 0, -15)
vaultTitle:SetJustifyH("CENTER")
vaultTitle:SetText(L["CFFFFCC00GREAT_VAULT_R"])
if pve.hasUnclaimedRewards then
    local waiting=ns.UI_RenderFontString(vaultCard,nil,"OVERLAY","QuartermasterFontSmall")
    waiting:SetPoint("TOP",0,-33); waiting:SetText(L.ES_VAULT_READY)
    waiting:SetTextColor(unpack(ns.UI_COLORS.accent))
end
            
            -- Helper function to get WoW icon textures for vault activity types
            local function GetVaultTypeIcon(typeName)
                local icons = {
                    ["Raid"] = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
                    ["M+"] = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
                    ["World"] = "Interface\\Icons\\INV_Misc_Map_01"
                }
                return icons[typeName] or "Interface\\Icons\\INV_Misc_QuestionMark"
            end

            local function Pluralize(count, singular, plural)
                if count == 1 then return singular end
                return plural or (singular .. "s")
            end

            local function ShowGreatVaultSlotTooltip(owner, slotIndex, vaultByType, defaultThresholds)
                if not owner or not slotIndex then return end
                GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                GameTooltip:SetText(string.format("Great Vault – Slot %d", slotIndex), 1, 0.82, 0)

                local function AddTypeLine(typeKey, displayName, descBuilder)
                    local activities = vaultByType and vaultByType[typeKey]
                    local activity = activities and activities[slotIndex]

                    local threshold = (activity and activity.threshold) or (defaultThresholds[typeKey] and defaultThresholds[typeKey][slotIndex]) or 0
                    local progress = (activity and activity.progress) or 0
                    local complete = (threshold > 0 and progress >= threshold)

                    if threshold and threshold > 0 then
                        local reqText = descBuilder(threshold)
                        local progText = string.format("%d/%d", progress, threshold)
                        GameTooltip:AddLine(displayName .. ": " .. reqText, 1, 1, 1)
                        if complete then
                            GameTooltip:AddLine("Status: Complete", 0.2, 1, 0.2)
                        else
                            GameTooltip:AddLine("Progress: " .. progText, 1, 0.82, 0)
                        end

                        local earned = activity and activity.level
                        if earned and earned ~= 0 then
                            local earnedText
                            if typeKey == "M+" then
                                earnedText = string.format("Earned at: +%d", earned)
                            else
                                earnedText = string.format("Earned at: %d", earned)
                            end
                            GameTooltip:AddLine(earnedText, 0.8, 0.8, 1)
                        end
                    else
                        GameTooltip:AddLine(displayName .. ": No data", 0.6, 0.6, 0.6)
                    end
                end

                AddTypeLine("Raid", "Raid", function(th) return string.format("Defeat %d raid %s", th, Pluralize(th, "boss")) end)
                AddTypeLine("M+", "Dungeons", function(th) return string.format("Complete %d %s", th, Pluralize(th, "dungeon")) end)
                AddTypeLine("World", "World", function(th) return string.format("Complete %d world %s", th, Pluralize(th, "activity", "activities")) end)

                GameTooltip:Show()
            end


            local function ShowGreatVaultActivityTooltip(owner, typeKey, slotIndex, activity, threshold, progress)
                if not owner or not typeKey or not slotIndex then return end
                GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()

                -- Best effort: try to use Blizzard's native Weekly Rewards tooltip if available
                if activity and GameTooltip.SetWeeklyRewardsActivity then
                    local ok = pcall(GameTooltip.SetWeeklyRewardsActivity, GameTooltip, activity.type, activity.index)
                    if ok then
                        GameTooltip:Show()
                        return
                    end
                end
                if activity and GameTooltip.SetWeeklyRewardActivity then
                    local ok = pcall(GameTooltip.SetWeeklyRewardActivity, GameTooltip, activity.type, activity.index)
                    if ok then
                        GameTooltip:Show()
                        return
                    end
                end

                -- Fallback: build a tooltip that matches Great Vault wording as closely as possible
                local headerType = typeKey
                if typeKey == "M+" then headerType = "Dungeons" end
                GameTooltip:SetText(string.format("%s – Slot %d", headerType, slotIndex), 1, 0.82, 0)
                if activity and activity.rewardItemLevel then GameTooltip:AddLine(string.format(L.ES_REWARD_LEVEL,activity.rewardItemLevel),0.4,0.85,0.8) end

                local th = tonumber(threshold) or 0
                local pr = tonumber(progress) or 0

                if th > 0 then
                    local line
                    if typeKey == "Raid" then
                        line = string.format("Defeat %d raid %s", th, Pluralize(th, "boss"))
                    elseif typeKey == "M+" then
                        line = string.format("Complete %d %s", th, Pluralize(th, "dungeon"))
                    elseif typeKey == "World" then
                        line = string.format("Complete %d world %s", th, Pluralize(th, "activity", "activities"))
                    else
                        line = string.format("Complete %d %s", th, Pluralize(th, "activity", "activities"))
                    end

                    GameTooltip:AddLine(line, 1, 1, 1)

                    local progText = string.format("%d/%d", pr, th)
                    if pr >= th then
                        GameTooltip:AddLine("Status: Complete", 0.2, 1, 0.2)
                    else
                        GameTooltip:AddLine("Progress: " .. progText, 1, 0.82, 0)
                    end

                    local earned = activity and tonumber(activity.level)
                    if earned and earned > 0 then
                        local earnedText
                        if typeKey == "M+" then
                            earnedText = string.format("Earned at: +%d", earned)
                        else
                            earnedText = string.format("Earned at: %d", earned)
                        end
                        GameTooltip:AddLine(earnedText, 0.8, 0.8, 1)
                    end
                else
                    GameTooltip:AddLine("No data available for this slot.", 0.6, 0.6, 0.6)
                end

                GameTooltip:Show()
            end

            
            local vaultY = 50  -- Start padding (header row removed)
        
        if pve.greatVault and #pve.greatVault > 0 then
            local vaultByType = {}
            for _, activity in ipairs(pve.greatVault) do
                local typeName = "Unknown"
                local typeNum = activity.type
                
                if Enum and Enum.WeeklyRewardChestThresholdType then
                        if typeNum == Enum.WeeklyRewardChestThresholdType.Raid then typeName = "Raid"
                        elseif typeNum == Enum.WeeklyRewardChestThresholdType.Activities then typeName = "M+"
                        elseif typeNum == Enum.WeeklyRewardChestThresholdType.RankedPvP then typeName = "PvP"
                        elseif typeNum == Enum.WeeklyRewardChestThresholdType.World then typeName = "World"
                    end
                else
                    if typeNum == 1 then typeName = "Raid"
                    elseif typeNum == 2 then typeName = "M+"
                    elseif typeNum == 3 then typeName = "PvP"
                    elseif typeNum == 4 then typeName = "World"
                    end
                end
                
                if not vaultByType[typeName] then vaultByType[typeName] = {} end
                table.insert(vaultByType[typeName], activity)
            end
            
            -- Column Layout Constants
            local cardWidth = card1Width - cardSpacing
            local typeColumnWidth = 70  -- Icon + label width
            local slotsAreaWidth = cardWidth - typeColumnWidth - 30  -- 30px for padding
            local slotWidth = slotsAreaWidth / 3  -- Three slots evenly distributed
            
            -- Default thresholds for each activity type (when no data exists)
            local defaultThresholds = {
                ["Raid"] = {2, 4, 6},
                ["M+"] = {1, 4, 8},
                ["World"] = {2, 4, 8},
                ["PvP"] = {3, 3, 3}
            }
            -- Header row removed (Slot / 1 / 2 / 3). We start rows closer to the top to avoid empty space.
            -- Calculate available space for rows
            local cardContentHeight = cardHeight - vaultY - 10  -- 10px bottom padding
            local numTypes = 3  -- Raid, M+, World (PvP removed)
            local rowHeight = math.floor(cardContentHeight / numTypes)
            -- Table Rows (3 TYPES - evenly distributed)
            local sortedTypes = {"Raid", "M+", "World"}
            local rowIndex = 0
            for _, typeName in ipairs(sortedTypes) do
                local activities = vaultByType[typeName]
                
                -- Create row frame container for better positioning
                local rowFrame = ns.UI_RenderFrame("Frame", nil, vaultCard)
                rowFrame:SetPoint("TOPLEFT", 10, -vaultY)
                rowFrame:SetPoint("TOPRIGHT", -10, -vaultY)
                rowFrame:SetHeight(rowHeight - 2)
                
                -- Row background (alternating colors)
                local rowBg = ns.UI_RenderTexture(rowFrame, nil, "BACKGROUND")
                rowBg:SetAllPoints()
                if rowIndex % 2 == 0 then
                    rowBg:SetColorTexture(0.1, 0.1, 0.12, 0.5)
                else
                    rowBg:SetColorTexture(0.08, 0.08, 0.1, 0.5)
                end
                
                -- Icon texture (left side)
                local iconTexture = ns.UI_RenderTexture(rowFrame, nil, "ARTWORK")
                iconTexture:SetSize(16, 16)
                iconTexture:SetPoint("LEFT", 5, 0)
                iconTexture:SetTexture(GetVaultTypeIcon(typeName))
                
                -- Type label (next to icon)
                local label = ns.UI_RenderFontString(rowFrame, nil, "OVERLAY", "QuartermasterFontBody")
                label:SetPoint("LEFT", 25, 0)  -- 5px offset + 16px icon + 4px padding
                label:SetText(string.format("|cffffffff%s|r", typeName))
                
                -- Create individual slot frames for proper alignment
                local thresholds = defaultThresholds[typeName] or {3, 3, 3}
                
                for slotIndex = 1, 3 do
                    -- Create slot container frame
                    local slotFrame = ns.UI_RenderFrame("Frame", nil, rowFrame)
                    local xOffset = typeColumnWidth + ((slotIndex - 1) * slotWidth)
                    slotFrame:SetSize(slotWidth, rowHeight - 2)
                    slotFrame:SetPoint("LEFT", rowFrame, "LEFT", xOffset, 0)
                    
                    -- Get activity data for this slot
                    local activity = activities and activities[slotIndex]
                    local threshold = (activity and activity.threshold) or thresholds[slotIndex] or 0
                    local progress = activity and activity.progress or 0
                    local isComplete = (threshold > 0 and progress >= threshold)
                    
slotFrame:EnableMouse(true)
                    slotFrame:SetScript("OnEnter", function(self)
                        ShowGreatVaultActivityTooltip(self, typeName, slotIndex, activity, threshold, progress)
                    end)
                    slotFrame:SetScript("OnLeave", function()
                        GameTooltip:Hide()
                    end)

                    if activity and isComplete and activity.rewardItemLevel then
                        local reward = ns.UI_RenderFontString(slotFrame, nil, "OVERLAY", "QuartermasterFontBody")
                        reward:SetPoint("CENTER", 0, 0)
                        reward:SetText(tostring(activity.rewardItemLevel))
                        reward:SetTextColor(unpack(ns.UI_COLORS.accent))
                    elseif activity and isComplete then
                        -- Complete: Show checkmark (centered)
                        local checkIcon = ns.UI_RenderTexture(slotFrame, nil, "OVERLAY")
                        checkIcon:SetSize(14, 14)
                        checkIcon:SetPoint("CENTER", 0, 0)
                        checkIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                    elseif activity and not isComplete then
                        -- Incomplete: Show progress numbers (centered)
                        local progressText = ns.UI_RenderFontString(slotFrame, nil, "OVERLAY", "QuartermasterFontBody")
                        progressText:SetPoint("CENTER", 0, 0)
                        progressText:SetText(string.format("|cffffcc00%d|r|cffffffff/|r|cffffcc00%d|r", 
                            progress, threshold))
                    else
                        -- No data: Show empty with threshold (centered)
                        local emptyText = ns.UI_RenderFontString(slotFrame, nil, "OVERLAY", "QuartermasterFontBody")
                        emptyText:SetPoint("CENTER", 0, 0)
                        if threshold > 0 then
                            emptyText:SetText(string.format("|cff888888%d|r|cff666666/|r|cff888888%d|r", 0, threshold))
                        else
                            emptyText:SetText(L["CFF666666_R_2"])
                        end
                    end
                end
                
                vaultY = vaultY + rowHeight
                rowIndex = rowIndex + 1
            end
        else
                local noVault = ns.UI_RenderFontString(vaultCard, nil, "OVERLAY", "QuartermasterFontSmall")
                noVault:SetPoint("CENTER", vaultCard, "CENTER", 0, 0)
            noVault:SetText(L["CFF666666NO_VAULT_DATA_R"])
            end
            
            -- === CARD 2: M+ DUNGEONS (35%) ===
            local mplusCard = CreateCard(cardContainer, cardHeight)
            mplusCard:SetPoint("TOPLEFT", 0, -cardHeight - 12)
            mplusCard:SetWidth(card2Width - cardSpacing)
            
            local mplusY = 15
            
            -- Overall Score (larger, at top)
            local totalScore = pve.mythicPlus.overallScore
            local scoreText = ns.UI_RenderFontString(mplusCard, nil, "OVERLAY", "QuartermasterFontHeading")
            scoreText:SetPoint("TOP", mplusCard, "TOP", 0, -mplusY)
            scoreText:SetText(totalScore and string.format("|cffffd700Overall Score: %d|r", totalScore) or L.ES_SCORE_UNKNOWN)
            mplusY = mplusY + 35  -- Space before grid
            
            if pve.mythicPlus.dungeons and #pve.mythicPlus.dungeons > 0 then
                local iconsPerRow = 4
                local iconSize = 42  -- Increased from 35 to 42
                local iconSpacing = 12  -- Increased from 8 to 12 for better distribution
                local totalDungeons = #pve.mythicPlus.dungeons
                
                -- Calculate grid dimensions
                local gridWidth = (iconsPerRow * iconSize) + ((iconsPerRow - 1) * iconSpacing)
                local cardWidth = card2Width - cardSpacing
                local startX = (cardWidth - gridWidth) / 2  -- Center the grid
                local gridY = mplusY
                
                for i, dungeon in ipairs(pve.mythicPlus.dungeons) do
                    local col = (i - 1) % iconsPerRow
                    local row = math.floor((i - 1) / iconsPerRow)
                    
                    local iconX = startX + (col * (iconSize + iconSpacing))
                    local iconY = gridY + (row * (iconSize + iconSpacing + 22))  -- Adjusted for larger icons
                    
                    local iconFrame = ns.UI_RenderFrame("Frame", nil, mplusCard)
                    iconFrame:SetSize(iconSize, iconSize)
                    iconFrame:SetPoint("TOPLEFT", iconX, -iconY)
                    iconFrame:EnableMouse(true)
                    
                    local texture = ns.UI_RenderTexture(iconFrame, nil, "ARTWORK")
                    texture:SetAllPoints()
                    if dungeon.texture then
                        texture:SetTexture(dungeon.texture)
                    else
                        texture:SetColorTexture(0.2, 0.2, 0.2, 1)
                    end
                    
                    if dungeon.bestLevel and dungeon.bestLevel > 0 then
                        -- Darken background overlay for better contrast
                        local overlay = ns.UI_RenderTexture(iconFrame, nil, "BORDER")
                        overlay:SetAllPoints()
                        overlay:SetColorTexture(0, 0, 0, 0.55)  -- Darker for better contrast  -- Semi-transparent black
                        
                        -- Key level INSIDE icon (centered, larger) - using GameFont
                        local textBg = ns.UI_RenderTexture(iconFrame, nil, "OVERLAY")
                        textBg:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
                        textBg:SetSize(34, 20)
                        textBg:SetColorTexture(0, 0, 0, 0.55)

                        -- Key level INSIDE icon (centered, larger, outlined)
                        local levelText = ns.UI_RenderFontString(iconFrame, nil, "OVERLAY")
                        levelText:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)  -- Centered in icon
                        do
                            local font, size, flags = GameFontNormalHuge:GetFont()
                            levelText:SetFont(font, (size or 18) + 2, "THICKOUTLINE")
                            levelText:SetShadowColor(0, 0, 0, 1)
                            levelText:SetShadowOffset(1, -1)
                        end
                        levelText:SetText(string.format("|cffffcc00+%d|r", dungeon.bestLevel))  -- Gold/yellow
                        
                        -- Score BELOW icon - using GameFont
                        local dungeonScore = ns.UI_RenderFontString(iconFrame, nil, "OVERLAY")
                        do
                            local font, size, flags = GameFontNormalLarge:GetFont()
                            dungeonScore:SetFont(font, size or 14, "OUTLINE")
                            dungeonScore:SetShadowColor(0, 0, 0, 1)
                            dungeonScore:SetShadowOffset(1, -1)
                        end
                        dungeonScore:SetPoint("TOP", iconFrame, "BOTTOM", 0, -3)
                        dungeonScore:SetText(string.format("|cffffffff%d|r", dungeon.score or 0))
                    else
                        -- Gray overlay for incomplete
                        local overlay = ns.UI_RenderTexture(iconFrame, nil, "BORDER")
                        overlay:SetAllPoints()
                        overlay:SetColorTexture(0, 0, 0, 0.6)  -- Darker for incomplete
                        
                        -- "Not Done" text inside icon - using GameFont
                        local notDone = ns.UI_RenderFontString(iconFrame, nil, "OVERLAY", "QuartermasterFontTitle")
                        notDone:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
                        notDone:SetText(L["CFF888888_R_2"])  -- Question mark instead of dash
                        
                        -- Dash below - using GameFont
                        local zeroScore = ns.UI_RenderFontString(iconFrame, nil, "OVERLAY", "QuartermasterFontHeading")
                        zeroScore:SetPoint("TOP", iconFrame, "BOTTOM", 0, -3)
                        zeroScore:SetText(L["CFF666666_R_2"])
                    end
                    
                    iconFrame:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(dungeon.name or "Unknown", 1, 1, 1)
                        if dungeon.bestLevel and dungeon.bestLevel > 0 then
                            GameTooltip:AddLine(string.format("Best: |cffff8000+%d|r", dungeon.bestLevel), 1, 0.5, 0)
                            GameTooltip:AddLine(string.format("Score: |cffffffff%d|r", dungeon.score or 0), 1, 1, 1)
                        else
                            GameTooltip:AddLine("|cff666666Not completed|r", 0.6, 0.6, 0.6)
                        end
                        GameTooltip:Show()
                    end)
                    iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
                end
            else
                local noData = ns.UI_RenderFontString(mplusCard, nil, "OVERLAY", "QuartermasterFontSmall")
                noData:SetPoint("TOPLEFT", 15, -mplusY)
                noData:SetText(L["CFF666666NO_DATA_R"])
            end
            
            cardContainer:SetHeight(cardHeight * 2 + 12)
            yOffset = sectionTop + cardHeight * 2 + 24
            local raidKey = "weekly-raids-" .. charKey
            local raidOpen = IsExpanded(raidKey, false)
            local raidHeader = CreateCollapsibleHeader(parent, L.WEEKLY_RAIDS, raidKey, raidOpen, function(value) ToggleExpand(raidKey, value) end)
            raidHeader:SetPoint("TOPLEFT", 22 + activityWidth, -yOffset); raidHeader:SetWidth(summaryWidth)
            yOffset = yOffset + 38
            if raidOpen then
            local lockoutCard = CreateCard(parent, 60)
            lockoutCard:SetPoint("TOPLEFT", 22 + activityWidth, -yOffset)
            lockoutCard:SetWidth(card3Width)
            -- Pull saved raid lockouts for this character (captured during scan)
            local lockouts = nil
            if char and char.pve and char.pve.lockouts then
                lockouts = pve.lockouts
            end

            local raids = {}
            if lockouts and type(lockouts) == "table" then
                for _, l in ipairs(lockouts) do
                    if l and l.isRaid then
                        table.insert(raids, l)
                    end
                end
            end

            -- Sort: soonest reset first, then higher difficulty
            table.sort(raids, function(a, b)
                local ar = tonumber(a.expiresAt) or math.huge
                local br = tonumber(b.expiresAt) or math.huge
                if ar ~= br then return ar < br end
                local ad = tonumber(a.difficultyID) or 0
                local bd = tonumber(b.difficultyID) or 0
                if ad ~= bd then return ad > bd end
                return (a.name or "") < (b.name or "")
            end)

	            local lockoutY = 12

            if #raids == 0 then
                local noLockouts = ns.UI_RenderFontString(lockoutCard, nil, "OVERLAY", "QuartermasterFontSmall")
                noLockouts:SetPoint("TOPLEFT", 15, -lockoutY)
                noLockouts:SetText(L[pve.scanState == "unavailable" and "PVE_SCAN_UNAVAILABLE" or "CFF666666NO_ACTIVE_RAID_LOCKOUTS_R"])
            else
                -- Keep every active recorded lockout available.
                local maxShow = #raids
                for i = 1, maxShow do
                    local l = raids[i]

                    local nameLine = ns.UI_RenderFontString(lockoutCard, nil, "OVERLAY", "QuartermasterFontBody")
                    nameLine:SetPoint("TOPLEFT", 15, -lockoutY)
                    nameLine:SetJustifyH("LEFT")
                    nameLine:SetWidth(card3Width - 30); nameLine:SetWordWrap(false)
                    nameLine:SetText(string.format("|cffffffff%s|r |cffaaaaaa(%s)|r", l.name or "Unknown", l.difficultyName or ""))

                    lockoutY = lockoutY + 18

                    local progress = tonumber(l.progress) or 0
                    local total = tonumber(l.total) or 0
                    local resetText = FormatResetTime(l.remaining)

                    local infoLine = ns.UI_RenderFontString(lockoutCard, nil, "OVERLAY", "QuartermasterFontSmall")
                    infoLine:SetPoint("TOPLEFT", 15, -lockoutY)
                    infoLine:SetJustifyH("LEFT")
                    infoLine:SetWidth(card3Width - 30); infoLine:SetWordWrap(false)
                    infoLine:SetText(string.format("|cff4DE64D%d/%d bosses|r |cff666666• Resets in %s|r", progress, total, resetText))

                    lockoutY = lockoutY + 22
                end
            end
lockoutCard:SetHeight(math.max(50, lockoutY + 12))
            yOffset = yOffset + math.max(50, lockoutY + 12) + 10
            end
            yOffset = math.max(yOffset, sectionTop + activityHeight)
        end
        
        yOffset = yOffset + 5
    end
    
    return pool:Finish(yOffset + 20)
end
