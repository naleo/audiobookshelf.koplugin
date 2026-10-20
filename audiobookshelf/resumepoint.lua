-- Where playback will resume, worked out in one place so the book page can show
-- exactly what Play will hand to KinAMP. Pure: no KOReader modules.
local PositionMap = require("audiobookshelf/positionmap")
local AbsProgress = require("audiobookshelf/absprogress")

local M = {}

-- 0:59, 33:18, 1:50:44
function M.fmt(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds < 0 then seconds = 0 end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

-- entry: the stored audiobook; remote, code: what ABS's progress call returned
-- (404 = no progress yet, any other nil = unreachable).
-- `rewind` (seconds, optional) starts playback that much before a real saved
-- position, so audio lost to the seek and the Bluetooth reconnect is not missed.
-- Returns { seconds, raw, rewind, last_sent, offline, source } where `seconds` is
-- where playback starts, `raw` the real position before the "restart near the
-- end" rule and the rewind, `rewind` how far it was actually moved back, and
-- `source` one of abs, local, unsynced, start, finished, restart.
function M.resolve(entry, remote, code, rewind)
    local total = entry.total or 0
    local raw, last_sent, source = 0, nil, "start"
    local offline = false
    if entry.unsynced and entry.last_sent then
        -- Progress made while ABS was unreachable beats ABS's older position.
        raw, source = entry.last_sent, "unsynced"
    else
        offline = (remote == nil and code ~= 404)
        if remote and remote.isFinished then
            raw, source = 0, "finished"
        elseif remote and remote.currentTime then
            raw, last_sent, source = remote.currentTime, remote.currentTime, "abs"
        elseif entry.last_sent then
            raw, last_sent, source = entry.last_sent, entry.last_sent, "local"
        end
    end
    local seconds = raw
    -- At or near the end there is nothing left to resume into: start over.
    if source ~= "finished" and total > 0 and raw >= total - AbsProgress.FINISHED_WITHIN then
        seconds, last_sent, source = 0, nil, "restart"
    end
    local rewound = 0
    if rewind and rewind > 0 and (source == "abs" or source == "local" or source == "unsynced") then
        seconds = math.max(0, raw - rewind)
        rewound = raw - seconds
    end
    return { seconds = seconds, raw = raw, rewind = rewound, last_sent = last_sent, offline = offline, source = source }
end

-- Display values for the book page.
function M.describe(tracks, total, resolved)
    local index, offset = PositionMap.toTrackPos(tracks, resolved.seconds)
    local percent = 0
    if (total or 0) > 0 then percent = math.floor(resolved.seconds / total * 100) end
    local note
    if resolved.source ~= "abs" and resolved.source ~= "start" then note = resolved.source end
    return {
        position = M.fmt(resolved.seconds),
        total = M.fmt(total),
        percent = percent,
        track_index = index,
        track_count = #tracks,
        track_time = M.fmt(offset),
        rewind = resolved.rewind or 0,
        note = note,
    }
end

return M
