-- One active audiobook: starts playback at the right place and keeps ABS in
-- step with the player. All collaborators are injected (see the plan).
local PositionMap = require("audiobookshelf/positionmap")
local Policy = require("audiobookshelf/progresspolicy")
local AbsProgress = require("audiobookshelf/absprogress")
local Store = require("audiobookshelf/audiostore")
local ResumePoint = require("audiobookshelf/resumepoint")

local Session = { TICK_SECONDS = 30, MAX_MISSES = 3, END_WINDOW = 60, LAND_POLL_SECONDS = 2, LAND_MAX_TRIES = 90 }
Session.__index = Session

-- Reasons that mean "the player is not playing our book right now". Paused is
-- not one of them: KinAMP stops refreshing its status while paused.
local MISS_REASONS = { no_daemon = true, not_active = true, path_mismatch = true }

function Session.new(deps)
    local self = setmetatable({ deps = deps, active = nil }, Session)
    self.tick_fn = function() self:_tick() end
    return self
end

function Session:isActive(item_id)
    return self.active ~= nil and (item_id == nil or self.active.entry.item_id == item_id)
end

function Session:_schedule()
    if not self.active then return end
    self.deps.sched.unschedule(self.tick_fn)
    self.deps.sched.scheduleIn(Session.TICK_SECONDS, self.tick_fn)
end

function Session:_end()
    self.deps.sched.unschedule(self.tick_fn)
    if self.active and self.active.poll_fn then self.deps.sched.unschedule(self.active.poll_fn) end
    self.active = nil
end

local function onOurBook(a, status)
    return status and (status.is_playing or status.is_paused) and status.index
        and a.paths[status.index] == status.path
end

-- After a cold start: wait until the seek has landed and our book is playing,
-- then (once) disconnect and reconnect Bluetooth. KinAMP cycled the radio to
-- start its player, which leaves the headset "connected" with a stale audio
-- link; reconnecting while audio is playing brings the link up and sound starts.
-- (Reconnecting before the seek does not work: the seek restarts the stream while
-- the link is still coming up, and that stream never gets an audio path.)
function Session:_pollLanding(a, tries)
    a.poll_fn = function() self:_waitForLanding(a, tries) end
    self.deps.sched.scheduleIn(Session.LAND_POLL_SECONDS, a.poll_fn)
end

function Session:_waitForLanding(a, tries)
    if self.active ~= a then return end
    local d = self.deps
    local status = d.kinamp.getStatus()
    local landed = onOurBook(a, status) and status.index == a.start_index
        and (tonumber(status.pos) or 0) >= a.start_offset - 2
    if landed then
        a.started = true
        if a.bt_fix and d.kinamp.reconnectBluetooth then
            a.bt_fix = false
            d.notify("Reconnecting Bluetooth...")
            d.kinamp.reconnectBluetooth(function()
                if self.active == a then self:_schedule() end
            end)
        else
            self:_schedule()
        end
    elseif tries >= Session.LAND_MAX_TRIES then
        a.bt_fix = false -- never landed: do not fiddle with Bluetooth, just sync normally
        self:_schedule()
    else
        self:_pollLanding(a, tries + 1)
    end
end

-- Runs inside a UIManager timer, where an uncaught error would close KOReader.
function Session:_tick()
    if not self.active then return end
    local ok, err = pcall(self._sync, self, false)
    if not ok and self.deps.log then self.deps.log(tostring(err)) end
    self:_schedule()
end

-- Send one position to ABS. Always kept locally for offline resume, and flagged
-- when ABS has not got it.
function Session:_send(a, pos)
    local d = self.deps
    local sent = d.api:setProgress(a.entry.item_id, AbsProgress.body(pos, a.entry.total)) and true or false
    d.store:setLastSent(a.entry.item_id, pos, not sent)
    if sent then a.last_sent = pos end
    return sent
end

-- The book ran out: ABS gets the full length and isFinished, then we stand down.
function Session:_finish()
    local a, d = self.active, self.deps
    local total = a.entry.total
    local ok = d.api:setProgress(a.entry.item_id, AbsProgress.body(total, total))
    d.store:setLastSent(a.entry.item_id, total, not ok)
    self:_end()
    if ok then return total, "finished" end
    return nil, "offline"
end

-- KinAMP seeks by restarting the file and decoding up to the position, which
-- takes ~20 s deep into a long MP3. Until the player reports a position at or
-- near the requested one, its status is the pre-seek position, not progress.
function Session:_sync(force)
    local a = self.active
    if not a then return nil, "inactive" end
    local d = self.deps
    local status = d.kinamp.getStatus()
    if not a.started then
        if not a.seek_sent then return nil, "not_started" end
        if onOurBook(a, status) and status.index == a.start_index then
            if (tonumber(status.pos) or 0) >= a.start_offset - 2 then
                a.started = true -- the seek landed
            else
                return nil, "not_started" -- still decoding up to the position
            end
        end
        -- Anything else (no player, stopped, someone else's file, another track
        -- of this book) is handled by the normal path below.
    end
    local pos, reason = Policy.decide({
        status = status,
        tracks = a.entry.tracks,
        paths = a.paths,
        last_sent = a.last_sent,
        min_delta = force and 1 or nil,
    })
    -- Remember where we last saw our book playing, whatever the threshold said.
    if status and (status.is_playing or status.is_paused) and status.index
        and a.paths[status.index] == status.path then
        a.last_global = PositionMap.toGlobal(a.entry.tracks, status.index, status.pos) or a.last_global
    end
    if not pos then
        if MISS_REASONS[reason] then
            if reason == "not_active" and a.last_global
                and (a.entry.total or 0) - a.last_global <= Session.END_WINDOW then
                return self:_finish()
            end
            -- Stopped from the player's own screen between ticks: send the last
            -- position we saw it at, once.
            if reason == "not_active" and a.started and a.last_global
                and (a.last_sent == nil or math.abs(a.last_global - a.last_sent) >= 1) then
                self:_send(a, a.last_global)
            end
            a.misses = a.misses + 1
            if a.misses >= Session.MAX_MISSES then self:_end() end
        else
            a.misses = 0
        end
        return nil, reason
    end
    a.misses = 0
    if self:_send(a, pos) then return pos end
    return nil, "offline"
end

function Session:start(entry)
    local d = self.deps
    if not d.kinamp.available() then return nil, "kinamp_missing" end
    if not entry or not entry.tracks or #entry.tracks == 0 then return nil, "no_tracks" end
    if self.active then
        self:_sync(true)
        self:_end()
    end
    local paths = Store.paths(entry)

    -- KinAMP outlives KOReader. If it is still playing this book, join it
    -- instead of seeking back to an older ABS position.
    local live = d.kinamp.getStatus()
    if live and (live.is_playing or live.is_paused) and live.index and paths[live.index] == live.path then
        self.active = { entry = entry, paths = paths, last_sent = nil, misses = 0, started = true }
        self:_schedule()
        return true, "attached"
    end

    local remote, code
    local has_unsynced = entry.unsynced and entry.last_sent
    if not has_unsynced then remote, code = d.api:getProgress(entry.item_id) end
    local resume = ResumePoint.resolve(entry, remote, code, d.rewind)
    local seconds, last_sent, offline = resume.seconds, resume.last_sent, resume.offline
    if has_unsynced then
        -- Push the position that never reached ABS before it is overwritten.
        if d.api:setProgress(entry.item_id, AbsProgress.body(resume.raw, entry.total)) then
            d.store:setLastSent(entry.item_id, resume.raw, false)
            last_sent = resume.raw
        else
            offline = true
        end
    end
    if resume.source == "restart" then last_sent = nil end

    local index, offset = PositionMap.toTrackPos(entry.tracks, seconds)
    self.active = {
        entry = entry, paths = paths, last_sent = last_sent, misses = 0,
        started = false, seek_sent = false, start_index = index, start_offset = offset,
    }

    local function afterStart()
        if not self.active or self.active.entry ~= entry then return end
        if offset > 0 then d.kinamp.seek(offset) end
        self.active.seek_sent = true
        if self.active.bt_fix then
            -- Progress ticks start once playback has landed and Bluetooth is fixed.
            self:_pollLanding(self.active, 0)
        else
            if offset == 0 then self.active.started = true end -- nothing to wait for
            self:_schedule()
        end
    end

    if d.kinamp.playFromIndex(index, paths) then
        d.sched.scheduleIn(0.5, afterStart)
    else
        d.notify("Starting KinAMP...")
        d.kinamp.waitUntilRunning(function(up)
            if not up then
                self:_end()
                d.notify("KinAMP did not start.")
                return
            end
            -- If KinAMP's own startup cycled the Bluetooth radio, the headset's audio
            -- link needs a reconnect, done once playback is running. Not needed when
            -- the adapter starts the player directly (reconnect_on_cold_start off).
            if d.reconnect_on_cold_start and self.active and self.active.entry == entry then
                self.active.bt_fix = true
            end
            d.sched.scheduleIn(1.0, afterStart)
        end)
    end
    return true, offline and "offline" or nil, offset
end

function Session:stop()
    if not self.active then return end
    self:_sync(true)
    self:_end()
    self.deps.kinamp.stop()
end

function Session:detach()
    if not self.active then return end
    self:_sync(true)
    self:_end()
end

function Session:suspend()
    if not self.active then return end
    self:_sync(true)
    self.deps.sched.unschedule(self.tick_fn)
end

function Session:resume()
    if self.active then self:_tick() end
end

function Session:syncNow()
    return self:_sync(true)
end

return Session
