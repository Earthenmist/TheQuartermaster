--[[
    The Quartermaster - Mail Tracking
    Caches mailbox expiry information per character (requires opening a mailbox on that character).

    Notes:
    - WoW addons cannot read another character's mailbox unless you log that character in and open a mailbox.
    - We cache expiry timestamps and show them in the Characters UI.
]]

local ADDON_NAME, ns = ...
local TheQuartermaster = ns.TheQuartermaster
local L = ns.L

local time = time
local floor = math.floor



-- ============================================================
-- Mail debug (off by default)
-- Toggle in-game: /qm maildebug
-- ============================================================
local function QM_MailDebugEnabled()
    if not TheQuartermaster or not TheQuartermaster.db or not TheQuartermaster.db.global then
        return false
    end
    TheQuartermaster.db.global.debug = TheQuartermaster.db.global.debug or {}
    return TheQuartermaster.db.global.debug.mail == true
end

local function QM_MailDebug(msg)
    if not QM_MailDebugEnabled() then return end
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99[QM:Mail]|r %s", tostring(msg)))
end

SLASH_QM_MAILDEBUG1 = "/qm"
SlashCmdList["QM_MAILDEBUG"] = function(input)
    input = tostring(input or ""):lower()
    if input == "maildebug" then
        if not TheQuartermaster or not TheQuartermaster.db or not TheQuartermaster.db.global then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[QM]|r DB not ready yet.")
            return
        end
        TheQuartermaster.db.global.debug = TheQuartermaster.db.global.debug or {}
        TheQuartermaster.db.global.debug.mail = not TheQuartermaster.db.global.debug.mail
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99[QM]|r Mail debug: %s", TheQuartermaster.db.global.debug.mail and "ON" or "OFF"))
        return
    end
end

-- Mail scan robustness
local _qmMailLastShowTime = 0
local _qmMailLastNonZeroTime = 0
local _qmMailLastCount = 0
local function EnsureMailDB()
    if not TheQuartermaster or not TheQuartermaster.db then return nil end
    local g = TheQuartermaster.db.global
    if not g then return nil end
    g.mail = g.mail or {}
    g.mail.perCharacter = g.mail.perCharacter or {}
    return g.mail.perCharacter
end

local function GetCharKey()
    if not TheQuartermaster or not TheQuartermaster.GetCharacterKey then return nil end
    return TheQuartermaster:GetCharacterKey("player")
end

local function GetInboxCount()
    if type(GetInboxNumItems) == "function" then
        local num = GetInboxNumItems()
        return tonumber(num) or 0
    end
    return 0
end

local function GetHeaderInfo(i)
    -- Prefer modern API when available
    if C_Mail and type(C_Mail.GetInboxHeaderInfo) == "function" then
        return C_Mail.GetInboxHeaderInfo(i)
    end
    if type(GetInboxHeaderInfo) == "function" then
        local icon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, hasItem, wasRead, wasReturned, textCreated, canReply, isGM, itemCount = GetInboxHeaderInfo(i)
        return {
            sender = sender,
            subject = subject,
            money = money,
            CODAmount = CODAmount,
            daysLeft = daysLeft,
            hasItem = hasItem,
            wasReturned = wasReturned,
            canReply = canReply,
            itemCount = itemCount,
        }
    end
    return nil
end

local function SecondsLeftFromHeader(info)
    if not info then return nil end
    if type(info.secondsLeft) == "number" then
        return info.secondsLeft
    end
    if type(info.daysLeft) == "number" then
        -- daysLeft can be fractional
        return info.daysLeft * 86400
    end
    return nil
end

local function ClassifyMailType(info)
    -- Heuristic:
    -- - If reply is allowed, it's probably player mail -> returns
    -- - Otherwise, likely system mail -> deletes
    if info and info.canReply then
        return "RETURN"
    end
    return "DELETE"
end

-- Public: return cached entry for a character key
function TheQuartermaster:GetMailCache(charKey)
    local perChar = EnsureMailDB()
    if not perChar or not charKey then return nil end
    return perChar[charKey]
end

-- Public: used by UI for formatting
function TheQuartermaster:FormatMailTimeLeft(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds <= 0 then
        return "0m"
    end
    local d = floor(seconds / 86400); seconds = seconds - d * 86400
    local h = floor(seconds / 3600);  seconds = seconds - h * 3600
    local m = floor(seconds / 60)

    if d > 0 then
        return string.format("%dd %dh", d, h)
    end
    if h > 0 then
        return string.format("%dh %dm", h, m)
    end
    return string.format("%dm", m)
end

local function ScanInboxNow()
    QM_MailDebug("ScanInboxNow()")
    if not TheQuartermaster or not TheQuartermaster.db then return end

    local charKey = GetCharKey()
    if not charKey then return end

    local perChar = EnsureMailDB()
    if not perChar then return end

    local num = GetInboxCount()
    QM_MailDebug("Inbox items: " .. tostring(num))
    _qmMailLastCount = tonumber(num) or 0
    if _qmMailLastCount > 0 then _qmMailLastNonZeroTime = GetTime() end
    local now = time()

        -- If no mail, keep a lightweight record (so UI can hide cleanly)
    if num <= 0 then
        QM_MailDebug("No mail found (count <= 0)")
        -- When a mailbox is first opened, GetInboxCount() often returns 0 briefly.
        -- Avoid overwriting a previously cached non-empty state with an empty scan during that window.
        local sinceShow = (GetTime() - (_qmMailLastShowTime or 0))
        if sinceShow >= 0 and sinceShow < 3 then
            -- We'll rescan shortly; do not write empty yet.
            return
        end
        QM_MailDebug("Writing cache for " .. tostring(charKey))

    perChar[charKey] = {
            count = 0,
            soonestAt = nil,
            soonestType = nil,
            returnSoonestAt = nil,
            deleteSoonestAt = nil,
            lastScan = now,
            details = {},
        }
        if TheQuartermaster.RefreshUI then
            TheQuartermaster:RefreshUI()
        end
        return
    end

    local soonestAt, returnSoonestAt, deleteSoonestAt
    local soonestType

    local details = {}
    for i = 1, num do
        local info = GetHeaderInfo(i)
        local secondsLeft = SecondsLeftFromHeader(info)

        if secondsLeft and secondsLeft > 0 then
            local expiresAt = now + secondsLeft
            local t = ClassifyMailType(info)

            table.insert(details, {
                sender = (info and info.sender) or "Unknown",
                expiresAt = expiresAt,
                type = t,
            })

            if not soonestAt or expiresAt < soonestAt then
                soonestAt = expiresAt
                soonestType = t
            end

            if t == "RETURN" then
                if not returnSoonestAt or expiresAt < returnSoonestAt then
                    returnSoonestAt = expiresAt
                end
            else
                if not deleteSoonestAt or expiresAt < deleteSoonestAt then
                    deleteSoonestAt = expiresAt
                end
            end
        end
    end

    table.sort(details, function(a, b)
        return (a.expiresAt or 0) < (b.expiresAt or 0)
    end)

    local detailsTop = {}
    local maxDetails = math.min(#details, 10)
    for i = 1, maxDetails do
        detailsTop[i] = details[i]
    end

    perChar[charKey] = {
        count = num,
        soonestAt = soonestAt,
        soonestType = soonestType,
        returnSoonestAt = returnSoonestAt,
        deleteSoonestAt = deleteSoonestAt,
        lastScan = now,
        details = detailsTop,
    }

    if TheQuartermaster.RefreshUI then
        TheQuartermaster:RefreshUI()
    end

end

function TheQuartermaster:InitializeMailTracking()
    if self._mailTrackingInitialized then return end
    self._mailTrackingInitialized = true
    QM_MailDebug("InitializeMailTracking()")

    local f = CreateFrame("Frame")
    self._mailFrame = f

    local function DelayedScan()
        -- Inbox info can update a moment after opening the mailbox
        C_Timer.After(0.20, ScanInboxNow)
    end

    f:RegisterEvent("MAIL_SHOW")
    f:RegisterEvent("MAIL_INBOX_UPDATE")

    f:SetScript("OnEvent", function(_, event)
        QM_MailDebug("Event: " .. tostring(event))

        if event == "MAIL_SHOW" then
            _qmMailLastShowTime = GetTime()
            ScanInboxNow()

            -- Delayed rescans to catch clients that don't fire MAIL_INBOX_UPDATE reliably
            -- or populate the inbox a moment later.
            if C_Timer and C_Timer.After then
                C_Timer.After(0.25, ScanInboxNow)
                C_Timer.After(1.00, ScanInboxNow)
                C_Timer.After(2.00, ScanInboxNow)
            end

        elseif event == "MAIL_INBOX_UPDATE" then
            ScanInboxNow()
        end
    end)
end