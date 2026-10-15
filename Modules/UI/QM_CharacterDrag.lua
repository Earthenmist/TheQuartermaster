local _, ns = ...
local Addon = ns.TheQuartermaster
function Addon:EnableCharacterRowDrag(row, key, group)
    self.characterDragRows = self.characterDragRows or {}
    row.orderKey, row.orderGroup = key, group
    self.characterDragRows[#self.characterDragRows + 1] = row
    row:RegisterForDrag("LeftButton")
    local function Cancel()
        row:SetScript("OnUpdate", nil); row:SetAlpha(1)
        if self.characterInsertionLine then self.characterInsertionLine:Hide() end
        if self.characterDragging and self.characterDragging.row == row then self.characterDragging = nil end
    end
    local function Target(elapsed)
        local drag = self.characterDragging
        if not drag or drag.row ~= row then return end
        drag.target = nil
        local x, y = GetCursorPosition()
        local scale = row:GetEffectiveScale(); x, y = x / scale, y / scale
        local scroll = self.UI and self.UI.mainFrame and self.UI.mainFrame.scroll
        if scroll then
            if x < scroll:GetLeft() or x > scroll:GetRight() or y > scroll:GetTop() or y < scroll:GetBottom() then
                self.characterInsertionLine:Hide(); return
            end
            if elapsed and scroll.GetVerticalScrollRange then
                local delta = y > scroll:GetTop() - 22 and -1 or (y < scroll:GetBottom() + 22 and 1 or 0)
                if delta ~= 0 then
                    scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange(), scroll:GetVerticalScroll() + delta * 260 * elapsed)))
                end
            end
        end
        for _, candidate in ipairs(self.characterDragRows) do
            if candidate ~= row and candidate:IsShown() and candidate.orderGroup == group then
                local top, bottom = candidate:GetTop(), candidate:GetBottom()
                if top and bottom and x >= candidate:GetLeft() and x <= candidate:GetRight() and y <= top and y >= bottom then
                    drag.target = candidate.orderKey
                    drag.after = y < (top + bottom) / 2
                    local edge = drag.after and "BOTTOM" or "TOP"
                    self.characterInsertionLine:ClearAllPoints()
                    self.characterInsertionLine:SetPoint("LEFT", candidate, edge .. "LEFT", 0, 0)
                    self.characterInsertionLine:SetPoint("RIGHT", candidate, edge .. "RIGHT", 0, 0)
                    self.characterInsertionLine:Show()
                    return
                end
            end
        end
        self.characterInsertionLine:Hide()
    end
    row:SetScript("OnDragStart", function()
        if self.characterDragging then return end
        if not self.characterInsertionLine then
            self.characterInsertionLine = row:GetParent():CreateTexture(nil, "OVERLAY")
            self.characterInsertionLine:SetHeight(2)
            self.characterInsertionLine:SetColorTexture(unpack(ns.UI_COLORS.accent))
        end
        self.characterDragging = {row = row, source = key}
        row:SetAlpha(0.55)
        GameTooltip:Hide()
        row:SetScript("OnUpdate", function(_, elapsed) Target(elapsed) end)
    end)
    row:SetScript("OnDragStop", function()
        Target()
        local drag = self.characterDragging
        local target, after = drag and drag.target, drag and drag.after
        Cancel()
        if target and self:MoveCharacterBefore(key, target, after) then self:RefreshUI() end
    end)
    row:HookScript("OnHide", Cancel)
end
