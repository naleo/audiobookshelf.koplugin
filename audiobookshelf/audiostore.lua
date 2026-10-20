-- Where downloaded audiobooks live and what we know about them. Pure: the
-- settings object (LuaSettings on device) is injected.
local Store = {}
Store.__index = Store

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Cut `s` to at most `max` bytes without splitting a UTF-8 character.
local function cut(s, max)
    if #s <= max then return s end
    local n = max
    while n > 0 do
        local b = s:byte(n + 1)
        if b and b >= 128 and b < 192 then n = n - 1 else break end
    end
    return s:sub(1, n)
end

function Store.sanitize(name)
    name = tostring(name or "")
    name = name:gsub("[%c/\\:%*%?\"<>|]", "_")
    name = trim(name)
    name = name:gsub("^%.+", "")
    name = trim(cut(name, 120))
    if name == "" then return "audiobook" end
    return name
end

function Store.trackFilename(index, name)
    local base = tostring(name or ""):match("([^/\\]+)$") or "track"
    local stem, ext = base:match("^(.*)(%.[%w]+)$")
    if not stem then stem, ext = base, "" end
    stem = trim(cut((stem:gsub("[%c/\\:%*%?\"<>|]", "_")), 100))
    if stem == "" then stem = "track" end
    return string.format("%03d-%s%s", index, stem, ext)
end

function Store.buildM3u(paths)
    local lines = { "#EXTM3U" }
    for _, p in ipairs(paths) do
        lines[#lines + 1] = (tostring(p):gsub("[\r\n]", ""))
    end
    return table.concat(lines, "\n") .. "\n"
end

function Store.makeEntry(item_id, title, author, dir, tracks, total)
    local out = {}
    for i, t in ipairs(tracks) do
        local filename = Store.trackFilename(i, t.name)
        out[i] = {
            ino = t.ino, name = t.name, size = t.size,
            duration = t.duration, startOffset = t.startOffset,
            filename = filename, path = dir .. "/" .. filename,
        }
    end
    return {
        item_id = item_id, title = title, author = author, dir = dir,
        tracks = out, total = total, m3u = dir .. "/book.m3u", complete = false,
    }
end

function Store.paths(entry)
    local p = {}
    for i, t in ipairs(entry.tracks) do p[i] = t.path end
    return p
end

function Store.new(settings)
    return setmetatable({ settings = settings }, Store)
end

function Store:_all()
    return self.settings:readSetting("audiobooks") or {}
end

function Store:get(item_id)
    return self:_all()[item_id]
end

function Store:put(entry)
    local all = self:_all()
    all[entry.item_id] = entry
    self.settings:saveSetting("audiobooks", all)
    self.settings:flush()
end

function Store:remove(item_id)
    local all = self:_all()
    all[item_id] = nil
    self.settings:saveSetting("audiobooks", all)
    self.settings:flush()
end

-- `unsynced` is true when `seconds` has not reached ABS yet (so the next Play
-- pushes it instead of letting ABS's older position overwrite it).
function Store:setLastSent(item_id, seconds, unsynced)
    local e = self:get(item_id)
    if e then
        e.last_sent = seconds
        e.unsynced = unsynced and true or false
        self:put(e)
    end
end

function Store:dirFor(download_dir, title, item_id)
    local base = (download_dir:gsub("/+$", "")) .. "/" .. Store.sanitize(title)
    for id, e in pairs(self:_all()) do
        if id ~= item_id and e.dir == base then
            return base .. " (" .. tostring(item_id):sub(1, 8) .. ")"
        end
    end
    return base
end

return Store
