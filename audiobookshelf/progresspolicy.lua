-- Decides whether the player's current position should be sent to ABS.
local PositionMap = require("audiobookshelf/positionmap")

local M = { DEFAULT_MIN_DELTA = 10 }

function M.decide(o)
    local s = o.status
    if not s then return nil, "no_daemon" end
    if not (s.is_playing or s.is_paused) then return nil, "not_active" end
    if not s.index then return nil, "no_track" end
    local expected = o.paths[s.index]
    if not expected or s.path ~= expected then return nil, "path_mismatch" end
    local global = PositionMap.toGlobal(o.tracks, s.index, s.pos)
    if not global then return nil, "no_track" end
    local last = o.last_sent
    -- A restart after a seek can report pos=0 for a tick; never let that reset ABS.
    if global == 0 and last and last > 0 then return nil, "zero_after_progress" end
    if last and math.abs(global - last) < (o.min_delta or M.DEFAULT_MIN_DELTA) then
        return nil, "below_threshold"
    end
    return global
end

return M
