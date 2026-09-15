-- Opt-in ownership for rebuilt, unprotected addon content. No global API hooks.
local _, ns = ...
local Pool = {}
Pool.__index = Pool
local scripts = {"OnClick", "OnEnter", "OnLeave", "OnShow", "OnHide", "OnUpdate"}

local function Reset(entry)
    local object = entry.object
    object:Hide() -- Run teardown (including ticker cancellation) before clearing scripts.
    if entry.kind == "Frame" or entry.kind == "Button" then
        for _, script in ipairs(scripts) do
            if object:HasScript(script) then object:SetScript(script, nil) end
        end
        object.compactCharacterKey = nil
        object.charKey = nil
        object:EnableMouse(entry.kind == "Button")
        object:SetScale(1)
        object:SetFrameLevel(object:GetParent():GetFrameLevel() + 1)
        if entry.template == "BackdropTemplate" then object:SetBackdrop(nil) end
    elseif entry.kind == "Texture" then
        object:SetTexture(nil)
        object:SetVertexColor(1, 1, 1, 1)
        object:SetDesaturated(false)
        object:SetTexCoord(0, 1, 0, 1)
        object:SetRotation(0)
        object:SetBlendMode("BLEND")
    else
        object:SetFontObject(entry.template or "QuartermasterFontBody")
        object:SetText("")
        object:SetTextColor(1, 1, 1, 1)
        object:SetJustifyH("CENTER")
        object:SetJustifyV("MIDDLE")
        object:SetWordWrap(true)
        object:SetShadowOffset(0, 0)
    end
    object:ClearAllPoints()
    object:SetSize(0, 0)
    object:SetAlpha(1)
end

function ns.UI_NewRenderPool(parent)
    local root = CreateFrame("Frame", nil, parent)
    local pool = setmetatable({root = root, buckets = {}, entries = {}, passes = 0}, Pool)
    root._qmRenderPool = pool
    root:SetScript("OnHide", function()
        local owner = GameTooltip and GameTooltip:GetOwner()
        if owner and owner._qmRenderPool == pool then GameTooltip:Hide() end
    end)
    root:SetPoint("TOPLEFT")
    return pool
end
function Pool:Begin(width)
    self.startedAt = debugprofilestop and debugprofilestop() or nil
    self.root:Hide()
    for _, entry in ipairs(self.entries) do Reset(entry); entry.active = false end
    for _, groups in pairs(self.buckets) do
        for _, bucket in pairs(groups) do bucket.cursor = 0 end
    end
    self.root:SetWidth(width)
    self.root:ClearAllPoints()
    self.root:SetPoint("TOPLEFT", self.root:GetParent(), "TOPLEFT")
    self.root:Show()
    self.passes = self.passes + 1
    return self.root
end
function Pool:Finish(height)
    self.root:SetHeight(height)
    if self.startedAt then self.lastBuildMS = debugprofilestop() - self.startedAt end
    return height
end
function Pool:Acquire(kind, parent, layer, template)
    assert(kind == "Frame" or kind == "Button" or kind == "Texture" or kind == "FontString", "Unsupported render-pool object")
    local key = kind .. ":" .. (layer or "") .. ":" .. (template or "")
    self.buckets[parent] = self.buckets[parent] or {}
    local groups = self.buckets[parent]
    groups[key] = groups[key] or {cursor = 0}
    local bucket = groups[key]
    bucket.cursor = bucket.cursor + 1
    local entry = bucket[bucket.cursor]
    if not entry then
        local object
        if kind == "Texture" then object = parent:CreateTexture(nil, layer, template)
        elseif kind == "FontString" then object = parent:CreateFontString(nil, layer, template)
        else object = CreateFrame(kind, nil, parent, template) end
        entry = {object = object, kind = kind, template = template}
        bucket[bucket.cursor] = entry
        self.entries[#self.entries + 1] = entry
        if kind == "Frame" or kind == "Button" then object._qmRenderPool = self end
        Reset(entry)
    end
    entry.active = true
    entry.object:Show()
    return entry.object
end
function Pool:GetStats()
    local stats = {frames = 1, textures = 0, fontStrings = 0, activeTickers = 0,
        passes = self.passes, lastBuildMS = self.lastBuildMS or 0}
    for _, entry in ipairs(self.entries) do
        local kind = entry.kind
        local field = kind == "Texture" and "textures" or kind == "FontString" and "fontStrings" or "frames"
        stats[field] = stats[field] + 1
        if entry.object.resetTicker then stats.activeTickers = stats.activeTickers + 1 end
    end
    return stats
end
function ns.UI_RenderFrame(kind, name, parent, template)
    if parent and parent._qmRenderPool and not name then
        return parent._qmRenderPool:Acquire(kind, parent, nil, template)
    end
    return CreateFrame(kind, name, parent, template)
end
function ns.UI_RenderTexture(parent, name, layer, template)
    if parent._qmRenderPool and not name then
        return parent._qmRenderPool:Acquire("Texture", parent, layer, template)
    end
    return parent:CreateTexture(name, layer, template)
end
function ns.UI_RenderFontString(parent, name, layer, template)
    if parent._qmRenderPool and not name then
        return parent._qmRenderPool:Acquire("FontString", parent, layer, template)
    end
    return parent:CreateFontString(name, layer, template)
end
