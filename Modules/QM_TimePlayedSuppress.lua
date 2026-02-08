--[[----------------------------------------------------------------------------
    The Quartermaster - Suppress /played Chat Spam
    WoW prints system chat lines after RequestTimePlayed(). In some UI stacks/builds,
    CHAT_MSG_SYSTEM filters can be unreliable, so we also guard at the message handler.

    This suppresses (English client):
      - "Total time played: ..."
      - "Time played this level: ..."
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
local QM = ns and ns.TheQuartermaster

local function ShouldSuppress()
    if QM and QM.db and QM.db.profile and QM.db.profile.suppressPlayedTimeChat ~= nil then
        return QM.db.profile.suppressPlayedTimeChat
    end
    return true -- default ON
end

local function IsPlayedLine(msg)
    if type(msg) ~= "string" or msg == "" then return false end
    return msg:find("Total time played:") ~= nil
        or msg:find("Time played this level:") ~= nil
        or msg:find("Time played:") ~= nil
        or msg:find("Played this level:") ~= nil
end

-- 1) Standard system chat filter (best case)
local function ChatFilter(_, event, msg)
    if not ShouldSuppress() then return false end
    if event == "CHAT_MSG_SYSTEM" and IsPlayedLine(msg) then
        return true
    end
    return false
end

local function ApplyChatFilter()
    if not ChatFrame_AddMessageEventFilter then return end
    ChatFrame_RemoveMessageEventFilter("CHAT_MSG_SYSTEM", ChatFilter)
    if ShouldSuppress() then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", ChatFilter)
    end
end

-- 2) Fallback: guard at the message handler level (works even if filters are bypassed/reset)
local Original_ChatFrame_MessageEventHandler
local function ApplyHandlerGuard()
    if Original_ChatFrame_MessageEventHandler then return end
    if type(ChatFrame_MessageEventHandler) ~= "function" then return end

    Original_ChatFrame_MessageEventHandler = ChatFrame_MessageEventHandler
    ChatFrame_MessageEventHandler = function(frame, event, msg, ...)
        if ShouldSuppress() and event == "CHAT_MSG_SYSTEM" and IsPlayedLine(msg) then
            return -- swallow
        end
        return Original_ChatFrame_MessageEventHandler(frame, event, msg, ...)
    end
end

local function RemoveHandlerGuard()
    if Original_ChatFrame_MessageEventHandler and ChatFrame_MessageEventHandler == nil then
        return
    end
    if Original_ChatFrame_MessageEventHandler then
        ChatFrame_MessageEventHandler = Original_ChatFrame_MessageEventHandler
        Original_ChatFrame_MessageEventHandler = nil
    end
end

function ns.QM_ApplyPlayedSuppression()
    QM = ns and ns.TheQuartermaster
    ApplyChatFilter()
    if ShouldSuppress() then
        ApplyHandlerGuard()
    else
        RemoveHandlerGuard()
    end
end

-- Apply on key points (covers login + UI addons re-initialising chat)
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(_, event, addon)
        if event == "ADDON_LOADED" and addon ~= ADDON_NAME then return end
        ns.QM_ApplyPlayedSuppression()
        if C_Timer and C_Timer.After then
            C_Timer.After(1, ns.QM_ApplyPlayedSuppression)
        end
    end)
end
