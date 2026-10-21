--[[----------------------------------------------------------------------------
    The Quartermaster - Played Time Requests
    Played time is requested at login and when the main window opens, never in
    combat, inside an instance or during a Mythic+ run.

    Chat windows print the reply from TIME_PLAYED_MSG. To keep it out of chat,
    the event is unregistered on the chat windows that listen for it and then
    registered again on exactly those windows. Blizzard's chat tables and
    handlers are never written or replaced, so chat handling stays untainted.
------------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

local REQUEST_INTERVAL = 60
local RESTORE_TIMEOUT = 5

local lastRequest
local mutedFrames
local restoreToken = 0

local function ShouldSuppress()
    local QM = ns and ns.TheQuartermaster
    if QM and QM.db and QM.db.profile and QM.db.profile.suppressPlayedTimeChat ~= nil then
        return QM.db.profile.suppressPlayedTimeChat
    end
    return true -- default ON
end

local function Blocked()
    if InCombatLockdown and InCombatLockdown() then return true end
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive() then return true end
    if IsInInstance and IsInInstance() then return true end
    return false
end

local function RestoreChat()
    restoreToken = restoreToken + 1
    if not mutedFrames then return end
    for _, frame in ipairs(mutedFrames) do
        if not frame:IsEventRegistered("TIME_PLAYED_MSG") then
            frame:RegisterEvent("TIME_PLAYED_MSG")
        end
    end
    mutedFrames = nil
end

local function MuteChat()
    if mutedFrames then return end
    mutedFrames = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.IsEventRegistered and frame:IsEventRegistered("TIME_PLAYED_MSG") then
            frame:UnregisterEvent("TIME_PLAYED_MSG")
            mutedFrames[#mutedFrames + 1] = frame
        end
    end
    -- Restore even if the reply never arrives.
    local token = restoreToken
    C_Timer.After(RESTORE_TIMEOUT, function()
        if token == restoreToken then RestoreChat() end
    end)
end

-- Requests played time unless blocked or recently requested. Pass force to skip
-- the interval (login).
function ns.QM_RequestPlayedTime(force)
    if not RequestTimePlayed or Blocked() then return false end
    local now = GetTime()
    if not force and lastRequest and now - lastRequest < REQUEST_INTERVAL then return false end
    lastRequest = now
    if ShouldSuppress() then MuteChat() end
    RequestTimePlayed()
    return true
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("TIME_PLAYED_MSG")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_LEAVING_WORLD")
    f:RegisterEvent("CHALLENGE_MODE_START")
    f:SetScript("OnEvent", function(_, event)
        if not mutedFrames then return end
        if event == "TIME_PLAYED_MSG" then
            -- Restore after this dispatch so muted windows do not print this reply.
            C_Timer.After(0, RestoreChat)
        else
            RestoreChat()
        end
    end)
end
