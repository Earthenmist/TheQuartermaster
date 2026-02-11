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
    if not TheQuartermaster or not TheQuartermaster.db then return end

    local charKey = GetCharKey()
    if not charKey then return end

    local perChar = EnsureMailDB()
    if not perChar then return end

    local num = GetInboxCount()
    local now = time()

        -- If no mail, keep a lightweight record (so UI can hide cleanly)
    if num <= 0 then
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

    local f = CreateFrame("Frame")
    self._mailFrame = f

    local function DelayedScan()
        -- Inbox info can update a moment after opening the mailbox
        C_Timer.After(0.20, ScanInboxNow)
    end

    f:RegisterEvent("MAIL_SHOW")
    f:RegisterEvent("MAIL_INBOX_UPDATE")

    f:SetScript("OnEvent", function(_, event)
        if event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
            DelayedScan()
        end
    end)
end