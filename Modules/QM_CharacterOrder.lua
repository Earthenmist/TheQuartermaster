local _, ns = ...
local Addon = ns.TheQuartermaster
function ns.CharacterOrderKey(char)
    return char._key or char.key or ((char.name or "Unknown") .. "-" .. (char.realm or "Unknown"))
end
local function FavoriteSet(db)
    local set = {}
    for _, key in ipairs((db.global or {}).favoriteCharacters or {}) do set[key] = true end
    return set
end
-- One order for every character view; never mutate the input array or character data.
function ns.SortCharacterRows(db, list, keyFor)
    keyFor = keyFor or ns.CharacterOrderKey
    local characters = (db.global or {}).characters or {}
    local favorites, ranks = FavoriteSet(db), {favorites = {}, regular = {}}
    local order = db.profile and db.profile.characterOrder or {}
    for group, rank in pairs(ranks) do
        for i, key in ipairs(order[group] or {}) do if not rank[key] then rank[key] = i end end
    end
    local result = {}; for i, row in ipairs(list or {}) do result[i] = row end
    table.sort(result, function(a, b)
        local ak, bk = keyFor(a), keyFor(b)
        local af, bf = favorites[ak] == true, favorites[bk] == true
        if af ~= bf then return af end
        local rank = ranks[af and "favorites" or "regular"]
        if (rank[ak] or math.huge) ~= (rank[bk] or math.huge) then return (rank[ak] or math.huge) < (rank[bk] or math.huge) end
        local ac, bc = characters[ak] or a, characters[bk] or b
        local al, bl = type(ac) == "table" and ac.level or 0, type(bc) == "table" and bc.level or 0
        if (al or 0) ~= (bl or 0) then return (al or 0) > (bl or 0) end
        local an, bn = type(ac) == "table" and ac.name or ak, type(bc) == "table" and bc.name or bk
        if (an or ak):lower() ~= (bn or bk):lower() then return (an or ak):lower() < (bn or bk):lower() end
        return ak < bk
    end)
    return result
end
function ns.OrderedCharacterPairs(db)
    local keys = {}; for key in pairs(db.global.characters or {}) do keys[#keys + 1] = key end
    keys = ns.SortCharacterRows(db, keys, function(key) return key end)
    local i = 0
    return function() i = i + 1; local key = keys[i]; if key then return key, db.global.characters[key] end end
end
function Addon:MoveCharacterBefore(source, target, after)
    local chars = self.db.global.characters or {}
    if source == target or not chars[source] or not chars[target] then return false end
    local favorites = FavoriteSet(self.db)
    if (favorites[source] == true) ~= (favorites[target] == true) then return false end
    local group = favorites[source] and "favorites" or "regular"
    local keys = {}
    for key in ns.OrderedCharacterPairs(self.db) do
        if (favorites[key] == true) == (favorites[source] == true) and key ~= source then keys[#keys + 1] = key end
    end
    for index, key in ipairs(keys) do
        if key == target then table.insert(keys, index + (after and 1 or 0), source); break end
    end
    self.db.profile.characterOrder = self.db.profile.characterOrder or {}
    self.db.profile.characterOrder[group] = keys
    if self.InvalidateCharacterCache then self:InvalidateCharacterCache() end
    return true
end
