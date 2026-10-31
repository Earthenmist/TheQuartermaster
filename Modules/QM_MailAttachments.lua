local _, ns = ...
local Addon, L = ns.TheQuartermaster, ns.L

function Addon:CancelMailAttachmentScan()
    local job = self._mailAttachmentJob
    if job and job.timer then self:CancelTimer(job.timer) end
    if job and job.snapshot.state == "pending" then job.snapshot.state = "unavailable" end
    self._mailAttachmentJob = nil
end

function Addon:StartMailAttachmentScan(key, loaded, headers)
    self:CancelMailAttachmentScan()
    local cache = self:GetMailCache(key)
    if not cache then return end
    cache.attachments = cache.attachments or {rows = {}}
    local snapshot = cache.attachments
    snapshot.state = "pending"
    if self.InvalidateItemCache then self:InvalidateItemCache() end
    local job = {index = 1, rows = {}, retry = 0, snapshot = snapshot}
    self._mailAttachmentJob = job
    local function Fail()
        snapshot.state = "unavailable"
        self._mailAttachmentJob = nil
    end
    local function Step()
        job.timer = nil
        if self._mailAttachmentJob ~= job then return end
        if not self._mailboxOpen or self:GetCharacterKey() ~= key or self:GetMailCache(key) ~= cache then Fail(); return end
        if not HasInboxItem or not GetInboxItem or not GetInboxNumItems or GetInboxNumItems() ~= loaded then Fail(); return end
        for _ = 1, 4 do
            if job.index > loaded then
                cache.attachments = {state = "complete", rows = job.rows, lastScan = time()}
                self._mailAttachmentJob = nil
                if self.InvalidateItemCache then self:InvalidateItemCache() end
                if self.RefreshUI then self:RefreshUI() end
                return
            end
            local header, rows, incomplete = headers[job.index], {}, false
            local found = 0
            local expiresAt = header and (header.secondsLeft or (header.daysLeft and header.daysLeft * 86400))
            expiresAt = expiresAt and cache.lastScan + expiresAt
            for slot = 1, 16 do
                if HasInboxItem(job.index, slot) then
                    found = found + 1
                    local name, id, icon, count, quality, _, isCurrency = GetInboxItem(job.index, slot)
                    if not isCurrency then
                        if not name or not id or not count or count <= 0 or not expiresAt then incomplete = true; break end
                        rows[#rows + 1] = {expiresAt = expiresAt, cod = (header.CODAmount or 0) > 0,
                            item = {itemID = id, name = name, iconFileID = icon, stackCount = count, quality = quality,
                                itemLink = GetInboxItemLink and GetInboxItemLink(job.index, slot) or ("item:" .. id)}}
                    end
                end
            end
            local expected = tonumber(header and header.hasItem) or tonumber(header and header.itemCount) or 0
            if found < expected or (header and header.hasItem == true and found == 0) then incomplete = true end
            if incomplete then
                job.retry = job.retry + 1
                if job.retry > 2 then Fail(); return end
                job.timer = self:ScheduleTimer(Step, 0.15); return
            end
            for _, row in ipairs(rows) do job.rows[#job.rows + 1] = row end
            job.index, job.retry = job.index + 1, 0
        end
        job.timer = self:ScheduleTimer(Step, 0.05)
    end
    job.timer = self:ScheduleTimer(Step, 0.05)
end

-- Only verified, unexpired snapshots participate in search or stock totals.
function Addon:GetMailItemRows()
    local result, now = {}, time()
    for key, char in ns.OrderedCharacterPairs(self.db) do
        local cache = self:GetMailCache(key)
        local snapshot = cache and cache.attachments
        if snapshot and snapshot.state == "complete" then
            for _, row in ipairs(snapshot.rows or {}) do
                if row.expiresAt and row.expiresAt > now then
                    result[#result + 1] = {item = row.item, location = L.MAIL_SOURCE,
                        locationDetail = key .. (row.cod and (" - " .. L.MAIL_COD) or ""),
                        character = char.name, characterKey = key, mailExpiresAt = row.expiresAt,
                        mailLastScan = snapshot.lastScan, cod = row.cod}
                end
            end
        end
    end
    return result
end
