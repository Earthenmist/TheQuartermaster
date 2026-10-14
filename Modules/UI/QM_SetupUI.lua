local _, ns = ...
local Addon, L = ns.TheQuartermaster, ns.L
local function Text(parent, text, x, y, width, color)
    local label = ns.UI_RenderFontString(parent, nil, 'OVERLAY', 'QuartermasterFontSmall')
    label:SetPoint('TOPLEFT', x, -y); label:SetWidth(width); label:SetJustifyH('LEFT'); label:SetWordWrap(true)
    label:SetText(text); label:SetTextColor(unpack(color or ns.UI_COLORS.textNormal))
    return math.max(18, label:GetStringHeight())
end
local function State(check)
    if check.state == 'unknown' then return L.SETUP_VERIFY end
    if check.state == 'disabled' then return L.SETUP_DISABLED end
    if check.state == 'not_applicable' then return L.SETUP_NOT_APPLICABLE end
    return check.ready and L.SETUP_COLLECTED or L['COVERAGE_STATE_' .. check.state]
end
function Addon:DrawSetupChecklist(parent)
    self.setupPool = self.setupPool or ns.UI_NewRenderPool(parent)
    local width, y = parent:GetWidth() - 20, 10
    local pool = self.setupPool
    parent = pool:Begin(width)
    local rows, shared, complete, total = self:GetSetupChecklist()
    y = y + Text(parent, L.SETUP_INTRO, 10, y, width - 20) + 8
    y = y + Text(parent, string.format(L.SETUP_PROGRESS, complete, total), 10, y, width - 20, ns.UI_COLORS.accent) + 8
    local function Button(text, callback, height)
        local b = ns.UI_RenderFrame('Button', nil, parent, 'BackdropTemplate')
        b:SetPoint('TOPLEFT', 10, -y); b:SetSize(width - 20, height or 30)
        b:SetBackdrop({bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Buttons\\WHITE8X8', edgeSize = 1})
        b:SetBackdropColor(unpack(ns.UI_COLORS.bgCard)); b:SetBackdropBorderColor(unpack(ns.UI_COLORS.border))
        if text then Text(b, text, 10, 7, width - 40) end
        b:SetScript('OnClick', callback)
        return b
    end
    Button(self.setupMissingOnly and L.SETUP_SHOW_ALL or L.SETUP_SHOW_MISSING, function()
        self.setupMissingOnly = not self.setupMissingOnly; self:RefreshUI()
    end)
    y = y + 40
    y = y + Text(parent, shared.label .. ': ' .. State(shared) .. ' — ' .. shared.hint, 10, y, width - 20) + 12
    local shown = 0
    for _, row in ipairs(rows) do
        if not self.setupMissingOnly or not row.ready then
            shown = shown + 1
            local b = Button(nil, function() self.setupSelected = self.setupSelected ~= row.key and row.key or nil; self:RefreshUI() end, 52)
            Text(b, (self.setupSelected == row.key and '- ' or '+ ') .. row.key, 10, 14, 210)
            local cellWidth = math.max(40, (width - 250) / 4)
            for index, check in ipairs(row.checks) do
                local x = 230 + (index - 1) * cellWidth
                Text(b, check.label, x, 6, cellWidth - 6)
                Text(b, State(check), x, 26, cellWidth - 6, check.ready and ns.UI_COLORS.accent or {1, 0.65, 0.2})
            end
            y = y + 58
            if self.setupSelected == row.key then
                y = y + Text(parent, string.format(L.SETUP_CHARACTER_ACTION, row.key), 24, y, width - 48) + 6
                local details = {}
                for _, check in ipairs(row.checks) do if check.domain ~= 'recipes' or #row.recipeChecks == 0 then details[#details + 1] = check end end
                for _, check in ipairs(row.recipeChecks) do details[#details + 1] = check end
                for _, check in ipairs(details) do
                    local stamp = check.timestamp and (' — ' .. date('%d %b %Y %H:%M', check.timestamp)) or ''
                    y = y + Text(parent, check.label .. ': ' .. State(check) .. stamp .. '\n' .. check.hint, 24, y, width - 48) + 10
                end
            end
        end
    end
    if shown == 0 then y = y + Text(parent, #rows == 0 and L.SETUP_NO_CHARACTERS or L.SETUP_NONE_MISSING, 10, y, width - 20) + 10 end
    -- Re-evaluate only while this page is visible, and rebuild only when status changes.
    local function Signature()
        local values, bank = self:GetSetupChecklist()
        local parts = {bank.state, tostring(bank.timestamp)}
        for _, row in ipairs(values) do
            parts[#parts + 1] = row.key
            for _, checks in ipairs({row.checks, row.recipeChecks}) do
                for _, check in ipairs(checks) do parts[#parts + 1] = check.label .. check.state .. tostring(check.timestamp) end
            end
        end
        return table.concat(parts, '|')
    end
    local signature, elapsed = Signature(), 0
    parent:SetScript('OnUpdate', function(_, delta)
        if not parent:IsShown() then return end
        elapsed = elapsed + delta
        if elapsed >= 2 then elapsed = 0; if Signature() ~= signature then self:RefreshUI() end end
    end)
    pool:Finish(y + 10)
    return y + 10
end
