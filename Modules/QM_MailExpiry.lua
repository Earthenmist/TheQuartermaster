local _, ns = ...
local Addon, L = ns.TheQuartermaster, ns.L
local DAY = 86400

-- Derive active mail without deleting the last observed snapshot.
function Addon:GetActiveMail(charKey, now)
    local raw = self:GetMailCache(charKey)
    if not raw then return nil end
    now = now or time()
    local view = {count = 0, details = {}, lastScan = raw.lastScan}
    local known = 0
    for _, entry in ipairs(raw.details or {}) do
        if type(entry.expiresAt) == "number" then
            known = known + 1
            if entry.expiresAt > now then
                view.count = view.count + 1
                view.details[#view.details + 1] = entry
                if not view.soonestAt or entry.expiresAt < view.soonestAt then view.soonestAt = entry.expiresAt end
            end
        end
    end
    -- Older caches may have only the ten earliest messages. Unobserved expiry is unknown.
    view.unknownCount = math.max(0, (tonumber(raw.count) or 0) - known)
    view.count = view.count + view.unknownCount
    if known == 0 and raw.soonestAt and raw.soonestAt > now then view.soonestAt = raw.soonestAt end
    table.sort(view.details, function(a, b) return a.expiresAt < b.expiresAt end)
    local remaining = view.soonestAt and view.soonestAt - now
    view.stage = remaining and (remaining <= DAY and 2 or (remaining <= 3 * DAY and 1 or 0)) or 0
    view.color = view.stage == 2 and {1, 0.2, 0.2} or (view.stage == 1 and {1, 0.55, 0.1} or {1, 1, 1})
    return view
end

function Addon:StopMailExpiry()
    if self._mailExpiryTimer then self:CancelTimer(self._mailExpiryTimer); self._mailExpiryTimer = nil end
end

function Addon:CheckMailExpiry(skipRefresh)
    self:StopMailExpiry()
    if not self.db or not self.db.global or self.db.profile.enabled == false then return end
    local now, nextAt = time(), nil
    local settings = self.db.profile.notifications or {}
    settings.mailExpiryNotified = settings.mailExpiryNotified or {}
    local marks, messages = settings.mailExpiryNotified, {}
    for key in ns.OrderedCharacterPairs(self.db) do
        local view = self:GetActiveMail(key, now)
        if view and view.count > 0 then
            if view.soonestAt then
                local at = view.soonestAt
                local boundary = at > now + 3 * DAY and at - 3 * DAY or (at > now + DAY and at - DAY or at)
                if boundary > now and (not nextAt or boundary < nextAt) then nextAt = boundary end
                local previous = marks[key]
                if settings.enabled ~= false and settings.showMailExpiry ~= false and view.stage > 0
                    and (not previous or view.stage > previous.stage or at > previous.expiresAt + 60) then
                    messages[#messages + 1] = string.format(L.MAIL_EXPIRY_ALERT, key, self:FormatMailTimeLeft(at - now))
                    marks[key] = {stage = view.stage, expiresAt = at}
                end
            end
        else marks[key] = nil end
    end
    for _, message in ipairs(messages) do self:Print(message) end
    if #messages > 0 and self.ShowToastNotification and self.activeToasts then
        local message = messages[1]
        if #messages > 1 then message = message .. "\n" .. string.format(L.MAIL_EXPIRY_MORE, #messages - 1) end
        self:ShowToastNotification({icon = "Interface\\Minimap\\Tracking\\Mailbox", title = L.MAIL_EXPIRY_TITLE,
            message = message, autoDismiss = 12})
    end
    local frame = self.UI and self.UI.mainFrame
    local mailView = frame and (frame.currentTab == "chars" or frame.currentTab == "search" or frame.currentTab == "watchlist" or frame.currentTab == "recipes")
    if not skipRefresh and frame and frame:IsShown() and mailView then self:RefreshUI() end
    -- One timer for the next actual colour/expiry boundary, rather than periodic scans.
    if nextAt then self._mailExpiryTimer = self:ScheduleTimer("CheckMailExpiry", math.max(1, nextAt - now)) end
end
