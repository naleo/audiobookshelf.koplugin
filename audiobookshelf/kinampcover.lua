-- Gives KinAMP's floating player a cover for audiobooks. KinAMP only shows
-- artwork embedded in the audio file's tags and has no hook for anything else, so
-- this wraps setCover on that one player instance: when KinAMP reports no
-- artwork and our book is the active session, our cover is used instead.
-- Pure: no KOReader modules.
local M = {}

-- player: KinAMP's player widget; cover_path: our cover file; is_active: function
-- returning true while our audiobook session is the one playing.
-- Returns true when the player was patched.
function M.apply(player, cover_path, is_active)
    if type(player) ~= "table" or type(player.setCover) ~= "function" or not cover_path then
        return false
    end
    player._abs_cover_path = cover_path
    player._abs_cover_active = is_active
    if not rawget(player, "_abs_cover_wrapped") then
        local original = player.setCover
        player.setCover = function(self, path)
            if not path and self._abs_cover_active and self._abs_cover_active() then
                path = self._abs_cover_path
            end
            return original(self, path)
        end
        player._abs_cover_wrapped = true
    end
    player:setCover(nil) -- swap it in now, not on the next track change
    return true
end

return M
