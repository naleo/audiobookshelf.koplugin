-- Pure position arithmetic for multi-file audiobooks. No KOReader modules here.
local M = {}

function M.buildTracks(item)
    local files = (type(item) == "table" and item.media and item.media.audioFiles) or {}
    local usable = {}
    for _, f in ipairs(files) do
        if type(f) == "table" and not f.exclude and not f.invalid
            and type(f.duration) == "number" and f.duration > 0 then
            usable[#usable + 1] = f
        end
    end
    table.sort(usable, function(a, b)
        local ai, bi = a.index or 0, b.index or 0
        if ai ~= bi then return ai < bi end
        local an = (a.metadata and a.metadata.filename) or ""
        local bn = (b.metadata and b.metadata.filename) or ""
        return an < bn
    end)
    local tracks, offset = {}, 0
    for i, f in ipairs(usable) do
        local meta = f.metadata or {}
        tracks[i] = {
            ino = f.ino,
            name = meta.filename or ("track" .. i),
            size = meta.size,
            duration = f.duration,
            startOffset = offset,
        }
        offset = offset + f.duration
    end
    return tracks, offset
end

-- seconds into the whole book -> (1-based track index, whole seconds into it)
function M.toTrackPos(tracks, seconds)
    local n = #tracks
    if n == 0 then return nil end
    local total = tracks[n].startOffset + tracks[n].duration
    seconds = tonumber(seconds) or 0
    if seconds < 0 then seconds = 0 end
    if seconds > total then seconds = total end
    for i = n, 1, -1 do
        local t = tracks[i]
        if seconds >= t.startOffset then
            local offset = seconds - t.startOffset
            if offset > t.duration then offset = t.duration end
            return i, math.floor(offset)
        end
    end
    return 1, 0
end

-- (1-based track index, seconds into that track) -> seconds into the whole book
function M.toGlobal(tracks, index, pos)
    local t = index and tracks[index]
    if not t then return nil end
    pos = tonumber(pos) or 0
    if pos < 0 then pos = 0 end
    if pos > t.duration then pos = t.duration end
    return t.startOffset + pos
end

return M
