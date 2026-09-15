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
        local num, total = GetInboxNumItems()
        return tonumber(num), tonumber(total)
    end
    return nil
end

local function GetHeaderInfo(i)
    -- Prefer modern API when available
    if C_Mail and type(C_Mail.GetInboxHeaderInfo) == "function" then
        return C_Mail.GetInboxHeaderInfo(i)
    end
    if type(GetInboxHeaderInfo) == "function" then
        local icon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, hasItem, wasRead, wasReturned, textCreated, canReply, isGM, itemCount = GetInboxHeaderInfo(i)
        if sender == nil and subject == nil and daysLeft == nil then return nil end
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
    if perChar[charKey] then return perChar[charKey] end
    -- Read older normalized keys until that character next logs in to reconcile.
    local name, realm = charKey:match("^([^-]+)%-(.+)$")
    local legacyKey = name and (name .. "-" .. realm:gsub("[%s%-' ]", ""))
    return legacyKey and perChar[legacyKey] or nil
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
    if not TheQuartermaster or not TheQuartermaster.db or not TheQuartermaster._mailboxOpen then return end

    local charKey = GetCharKey()
    if not charKey then return end

    local perChar = EnsureMailDB()
    if not perChar then return end

    if TheQuartermaster.CancelMailAttachmentScan then TheQuartermaster:CancelMailAttachmentScan() end
    local oldAttachments = perChar[charKey] and perChar[charKey].attachments
    if oldAttachments then oldAttachments.state = "unavailable" end
    if TheQuartermaster.InvalidateItemCache then TheQuartermaster:InvalidateItemCache() end

    local num, total = GetInboxCount()
    if not num then return end
    total = math.max(num, total or num)
    if num == 0 and total > 0 then return end
    QM_MailDebug("Inbox items: " .. tostring(num))
    _qmMailLastCount = tonumber(num) or 0
    if _qmMailLastCount > 0 then _qmMailLastNonZeroTime = GetTime() end
    local now = time()

    -- If no mail, keep a lightweight record (so UI can hide cleanly)
    if num <= 0 then
        QM_MailDebug("No mail found (count <= 0)")

        -- When a mailbox is first opened, GetInboxCount() can briefly return 0 while the
        -- client finishes populating the inbox. We only want to protect against clearing a
        -- *previously non-empty* cached state during that brief window.
        local existing = perChar[charKey]
        local existingCount = (existing and existing.count) and tonumber(existing.count) or 0

        local sinceShow = (GetTime() - (_qmMailLastShowTime or 0))
        if existingCount > 0 and sinceShow >= 0 and sinceShow < 3 then
            -- We'll rescan once we're outside the "initial open" window.
            if C_Timer and C_Timer.After then
                C_Timer.After((3 - sinceShow) + 0.05, ScanInboxNow)
            end
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
            attachments = {state = "complete", rows = {}, lastScan = now},
        }
        if TheQuartermaster.CheckMailExpiry then TheQuartermaster:CheckMailExpiry(true) end
        if TheQuartermaster.RefreshUI then
            TheQuartermaster:RefreshUI()
        end
        return
    end

    local soonestAt, returnSoonestAt, deleteSoonestAt
    local soonestType

    local details, headers = {}, {}
    for i = 1, num do
        local info = GetHeaderInfo(i)
        if not info then return end -- Preserve the last complete snapshot while inbox headers load.
        headers[i] = info
        local secondsLeft = SecondsLeftFromHeader(info)

        if secondsLeft then
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

    perChar[charKey] = {
        count = total,
        soonestAt = soonestAt,
        soonestType = soonestType,
        returnSoonestAt = returnSoonestAt,
        deleteSoonestAt = deleteSoonestAt,
        lastScan = now,
        details = details,
        attachments = oldAttachments,
    }

    if TheQuartermaster.StartMailAttachmentScan then TheQuartermaster:StartMailAttachmentScan(charKey, num, headers) end

    if TheQuartermaster.CheckMailExpiry then TheQuartermaster:CheckMailExpiry(true) end

    if TheQuartermaster.RefreshUI then
        TheQuartermaster:RefreshUI()
    end

end

function TheQuartermaster:InitializeMailTracking()
    if not self.db or self.db.profile.enabled == false then return end
    if self._mailTrackingInitialized then return end
    self._mailTrackingInitialized = true
    if self.CheckMailExpiry then self:CheckMailExpiry() end
    QM_MailDebug("InitializeMailTracking()")

    local f = CreateFrame("Frame")
    self._mailFrame = f

    local function DelayedScan()
        -- Inbox info can update a moment after opening the mailbox
        C_Timer.After(0.20, ScanInboxNow)
    end

    f:RegisterEvent("MAIL_SHOW")
    f:RegisterEvent("MAIL_INBOX_UPDATE")
    f:RegisterEvent("MAIL_CLOSED")

    f:SetScript("OnEvent", function(_, event)
        QM_MailDebug("Event: " .. tostring(event))

        if event == "MAIL_SHOW" then
            TheQuartermaster._mailboxOpen = true
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
        elseif event == "MAIL_CLOSED" then
            TheQuartermaster._mailboxOpen = false
            if TheQuartermaster.CancelMailAttachmentScan then TheQuartermaster:CancelMailAttachmentScan() end
        end
    end)
end
