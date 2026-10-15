-- Shared visual roles. Saved legacy theme preferences are intentionally untouched.
local _, ns = ...
local Theme = {}
ns.Theme = Theme

Theme.colors = {
    bg = {0.078, 0.086, 0.106, 0.97},
    bgLight = {0.145, 0.157, 0.192, 1},
    bgCard = {0.114, 0.125, 0.157, 1},
    border = {0.180, 0.196, 0.235, 1},
    borderLight = {0.322, 0.341, 0.384, 1},
    accent = {0.243, 0.851, 0.753, 1},
    accentDark = {0.145, 0.157, 0.192, 1},
    tabActive = {0.145, 0.157, 0.192, 1},
    tabHover = {0.145, 0.157, 0.192, 1},
    tabInactive = {0.114, 0.125, 0.157, 1},
    gold = {1, 0.82, 0, 1},
    green = {0.298, 0.843, 0.529, 1},
    red = {1, 0.365, 0.365, 1},
    warning = {1, 0.706, 0.329, 1},
    info = {0.310, 0.659, 1, 1},
    textBright = {0.910, 0.918, 0.941, 1},
    textNormal = {0.910, 0.918, 0.941, 1},
    textDim = {0.541, 0.561, 0.612, 1},
    textDisabled = {0.322, 0.341, 0.384, 1},
}
Theme.layout = {padding = 16, gutter = 8, sidebarWidth = 150, headerHeight = 40, rowHeight = 24, navHeight = 30}

function Theme.GetColors()
    local colors = {}
    for role, value in pairs(Theme.colors) do
        colors[role] = {unpack(value)}
    end
    return colors
end

-- Addon-owned font objects never change Blizzard or another addon's fonts.
for name, size in pairs({Title = 16, Heading = 13, Body = 12, Small = 10, Emphasis = 11, Close = 24}) do
    local font = CreateFont("QuartermasterFont" .. name)
    font:SetFont(STANDARD_TEXT_FONT, size, name == "Emphasis" and "OUTLINE" or "")
    font:SetTextColor(unpack(Theme.colors.textNormal))
end
