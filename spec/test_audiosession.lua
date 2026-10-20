local H = require("harness")
local Store = require("audiobookshelf/audiostore")
local Session = require("audiobookshelf/audiosession")

local tracks = {
    { ino = "a", name = "a.mp3", size = 10, duration = 100, startOffset = 0 },
    { ino = "b", name = "b.mp3", size = 20, duration = 100, startOffset = 100 },
}
local function newEntry() return Store.makeEntry("item1", "Book", "A", "/d/Book", tracks, 200) end
local paths = Store.paths(newEntry())

local function fakeSettings()
    local data = {}
    return {
        readSetting = function(_, k) return data[k] end,
        saveSetting = function(_, k, v) data[k] = v end,
        flush = function() end,
    }
end

local function st(index, pos, paused)
    return { is_playing = not paused, is_paused = paused or false, index = index, path = paths[index], pos = pos }
end

local function setup(o)
    o = o or {}
    local w = { played = {}, seeks = {}, stops = 0, progress = {}, notes = {}, scheduled = {}, status = o.status,
                events = {}, reconnects = 0,
                remote = o.remote, remote_code = o.remote_code, fail = o.fail, running = o.running ~= false,
                starts = o.starts ~= false }
    local store = Store.new(fakeSettings())
    w.entry = newEntry() -- a fresh copy per test: the store mutates it (last_sent)
    store:put(w.entry)
    if o.last_sent then store:setLastSent("item1", o.last_sent) end
    w.store = store
    local kinamp = {
        available = function() return o.available ~= false end,
        playFromIndex = function(index, p) w.played[#w.played + 1] = { index = index, paths = p }; return w.running end,
        seek = function(s) w.seeks[#w.seeks + 1] = s; w.events[#w.events + 1] = "seek" end,
        reconnectBluetooth = function(cb)
            w.events[#w.events + 1] = "reconnect"
            w.reconnects = w.reconnects + 1
            if o.hold_reconnect then w.reconnect_cb = cb else cb(o.reconnect_ok ~= false) end
        end,
        stop = function() w.stops = w.stops + 1 end,
        getStatus = function() return w.status end,
        waitUntilRunning = function(cb) cb(w.starts) end,
    }
    local api = {
        getProgress = function() return w.remote, w.remote_code end,
        setProgress = function(_, id, body)
            if w.raise then error("boom") end
            w.progress[#w.progress + 1] = body
            return not w.fail
        end,
    }
    local sched = {
        scheduleIn = function(s, fn) w.scheduled[#w.scheduled + 1] = { s = s, fn = fn } end,
        unschedule = function(fn)
            for i = #w.scheduled, 1, -1 do
                if w.scheduled[i].fn == fn then table.remove(w.scheduled, i) end
            end
        end,
    }
    w.session = Session.new({ api = api, store = store, kinamp = kinamp, sched = sched, rewind = o.rewind,
                              reconnect_on_cold_start = (o.reconnect ~= false),
                              notify = function(m) w.notes[#w.notes + 1] = m end })
    function w.runNext()
        local item = table.remove(w.scheduled, 1)
        item.fn()
    end
    return w
end

H.test("start resumes from the ABS position", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    H.eq(w.session:start(w.entry), true)
    H.eq(w.played[1].index, 2)
    H.eq(w.played[1].paths[2], "/d/Book/002-b.mp3")
    w.runNext() -- seek step
    H.eq(w.seeks[1], 30)
    H.eq(w.session:isActive("item1"), true)
    H.eq(w.session:isActive("other"), false)
end)

H.test("a finished book restarts from the beginning", function()
    local w = setup({ remote = { currentTime = 199, isFinished = true }, remote_code = 200 })
    w.session:start(w.entry)
    H.eq(w.played[1].index, 1)
    w.runNext()
    H.eq(#w.seeks, 0) -- offset 0: no seek needed
end)

H.test("an ABS position at or past the end restarts from the beginning", function()
    local w = setup({ remote = { currentTime = 99999 }, remote_code = 200 })
    w.session:start(w.entry)
    H.eq(w.played[1].index, 1)
    w.runNext()
    H.eq(#w.seeks, 0)
end)

H.test("a position inside the finish window also restarts from the beginning", function()
    local w = setup({ remote = { currentTime = 195 }, remote_code = 200 })
    w.session:start(w.entry)
    H.eq(w.played[1].index, 1)
    w.runNext()
    H.eq(#w.seeks, 0)
end)

H.test("no progress yet (404) starts at zero without an offline note", function()
    local w = setup({ remote = nil, remote_code = 404 })
    local ok, note = w.session:start(w.entry)
    H.eq(ok, true); H.eq(note, nil)
    H.eq(w.played[1].index, 1)
end)

H.test("unreachable ABS falls back to the saved position and says so", function()
    local w = setup({ remote = nil, remote_code = nil, last_sent = 150 })
    local _, note = w.session:start(w.entry)
    H.eq(note, "offline")
    H.eq(w.played[1].index, 2)
    w.runNext()
    H.eq(w.seeks[1], 50)
end)

H.test("cold start waits for the daemon before seeking", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200, running = false })
    w.session:start(w.entry)
    w.runNext() -- scheduled by waitUntilRunning callback
    H.eq(w.seeks[1], 30)
end)

H.test("a daemon that never starts ends the session", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200, running = false, starts = false })
    w.session:start(w.entry)
    H.eq(w.session:isActive(), false)
    H.eq(w.notes[#w.notes], "KinAMP did not start.")
end)

H.test("missing KinAMP is reported", function()
    local w = setup({ available = false })
    local ok, err = w.session:start(w.entry)
    H.eq(ok, nil); H.eq(err, "kinamp_missing")
end)

H.test("a tick sends progress once it moved far enough, then stays quiet", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext() -- seek step schedules the first tick
    w.status = st(2, 45) -- global 145, moved 15
    w.runNext()
    H.eq(#w.progress, 1)
    H.eq(w.progress[1].currentTime, 145)
    H.eq(w.store:get("item1").last_sent, 145)
    w.status = st(2, 48) -- moved 3: below threshold
    w.runNext()
    H.eq(#w.progress, 1)
end)

H.test("a failed ABS write is retried on the next tick and kept locally", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(2, 45)
    w.fail = true
    w.runNext()
    H.eq(#w.progress, 1)
    H.eq(w.store:get("item1").last_sent, 145) -- saved locally for offline resume
    w.fail = false
    w.runNext()
    H.eq(#w.progress, 2) -- retried
    H.eq(w.progress[2].currentTime, 145)
end)

H.test("pos 0 after a seek does not reset ABS", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(1, 0) -- global 0 right after progress was recorded at 130
    w.runNext()
    H.eq(#w.progress, 0)
end)

H.test("three ticks with no daemon end the session without writing", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext()
    w.status = nil
    w.runNext(); w.runNext(); w.runNext()
    H.eq(w.session:isActive(), false)
    H.eq(#w.progress, 0)
    H.eq(#w.scheduled, 0)
end)

H.test("stop does a final sync with a small threshold then stops playback", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(2, 33) -- moved 3 s: below normal threshold, enough for a final sync
    w.session:stop()
    H.eq(#w.progress, 1)
    H.eq(w.progress[1].currentTime, 133)
    H.eq(w.stops, 1)
    H.eq(w.session:isActive(), false)
    H.eq(#w.scheduled, 0)
end)

H.test("detach syncs but leaves playback running", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(2, 60)
    w.session:detach()
    H.eq(#w.progress, 1)
    H.eq(w.stops, 0)
    H.eq(w.session:isActive(), false)
end)

H.test("suspend syncs and stops the timer, resume syncs and restarts it", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(2, 60)
    w.session:suspend()
    H.eq(#w.progress, 1)
    H.eq(#w.scheduled, 0)
    w.status = st(2, 90)
    w.session:resume()
    H.eq(#w.progress, 2)
    H.eq(#w.scheduled, 1)
end)

H.test("starting another book first syncs the previous one", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(2, 60)
    w.session:start(w.entry)
    H.eq(#w.progress, 1)
    H.eq(w.progress[1].currentTime, 160)
end)

H.test("syncNow reports the reason when there is nothing to send", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext()
    w.status = nil
    local pos, why = w.session:syncNow()
    H.eq(pos, nil); H.eq(why, "no_daemon")
end)

H.test("a sync before the seek step has run writes nothing", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.status = st(2, 1) -- the player has just restarted the file near 0
    local pos, why = w.session:syncNow()
    H.eq(pos, nil); H.eq(why, "not_started")
    w.session:suspend()
    H.eq(#w.progress, 0)
    w.runNext() -- seek step: playback is now where we put it
    w.status = st(2, 45)
    w.runNext()
    H.eq(#w.progress, 1)
end)

H.test("a stopped player counts as a miss and ends the session", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext()
    w.status = { is_playing = false, is_paused = false, index = 1, path = paths[1], pos = 0 }
    w.runNext(); w.runNext(); w.runNext()
    H.eq(w.session:isActive(), false)
    H.eq(#w.progress, 0)
    H.eq(#w.scheduled, 0)
end)

H.test("a player on someone else's file counts as a miss and ends the session", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext()
    w.status = { is_playing = true, is_paused = false, index = 1, path = "/music/other.mp3", pos = 5 }
    w.runNext(); w.runNext(); w.runNext()
    H.eq(w.session:isActive(), false)
    H.eq(#w.progress, 0)
end)

H.test("a paused player does not end the session", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(2, 45, true)
    for _ = 1, 5 do w.runNext() end
    H.eq(w.session:isActive(), true)
end)

H.test("a book played to the end is marked finished and the session ends", function()
    local w = setup({ remote = { currentTime = 150 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext() -- seek to 50 in track 2
    w.status = st(2, 80) -- global 180
    w.runNext()
    H.eq(w.progress[#w.progress].currentTime, 180)
    w.status = { is_playing = false, is_paused = false, index = 2, path = paths[2], pos = 0 } -- ran out
    w.runNext()
    local last = w.progress[#w.progress]
    H.eq(last.currentTime, 200)
    H.eq(last.isFinished, true)
    H.eq(w.session:isActive(), false)
    H.eq(#w.scheduled, 0)
end)

H.test("a player stopped far from the end is not marked finished", function()
    local w = setup({ remote = { currentTime = 30 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(1, 55) -- global 55, 145 s from the end of a 200 s book
    w.runNext()
    H.eq(#w.progress, 1)
    w.status = { is_playing = false, is_paused = false, index = 1, path = paths[1], pos = 0 }
    w.runNext(); w.runNext(); w.runNext()
    H.eq(#w.progress, 1)
    H.eq(w.session:isActive(), false)
end)

H.test("starting a book that is already playing attaches instead of re-seeking", function()
    local w = setup({ remote = { currentTime = 10 }, remote_code = 200,
                      status = st(2, 45) }) -- the daemon kept playing this book after KOReader restarted
    local ok, note = w.session:start(w.entry)
    H.eq(ok, true); H.eq(note, "attached")
    H.eq(#w.played, 0)
    H.eq(#w.seeks, 0)
    w.runNext() -- first tick pushes the live position, not the stale ABS one
    H.eq(w.progress[1].currentTime, 145)
end)

H.test("progress saved while offline is pushed on the next start", function()
    local w = setup({ remote = { currentTime = 100 }, remote_code = 200, fail = false })
    w.entry.last_sent = 150
    w.entry.unsynced = true
    H.eq(w.session:start(w.entry), true)
    H.eq(w.progress[1].currentTime, 150) -- local position went to ABS first
    H.eq(w.store:get("item1").unsynced, false)
    H.eq(w.played[1].index, 2) -- and playback starts from it, not from ABS's 100
    w.runNext()
    H.eq(w.seeks[1], 50)
end)

H.test("unsynced progress that still cannot be pushed is kept and used", function()
    local w = setup({ remote = nil, remote_code = nil, fail = true })
    w.entry.last_sent = 150
    w.entry.unsynced = true
    local ok, note = w.session:start(w.entry)
    H.eq(ok, true); H.eq(note, "offline")
    H.eq(w.store:get("item1").unsynced, true)
    H.eq(w.played[1].index, 2)
end)

H.test("a failed sync marks progress unsynced, a successful one clears it", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(2, 45)
    w.fail = true
    w.runNext()
    H.eq(w.store:get("item1").unsynced, true)
    w.fail = false
    w.runNext()
    H.eq(w.store:get("item1").unsynced, false)
end)

H.test("an error inside a tick never escapes into the UI timer", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(2, 45)
    w.raise = true
    w.runNext() -- must not raise
    H.eq(w.session:isActive(), true)
    H.eq(#w.scheduled, 1)
end)

H.test("progress is not written until the seek has actually landed", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext() -- the seek command has been sent to KinAMP
    w.status = st(2, 0) -- but KinAMP is still decoding up to the position
    local pos, why = w.session:syncNow()
    H.eq(pos, nil); H.eq(why, "not_started")
    w.session:suspend()
    H.eq(#w.progress, 0)
    w.status = st(2, 45) -- the seek landed and playback moved on
    H.eq(w.session:syncNow(), 145)
    H.eq(#w.progress, 1)
end)

H.test("stopping while the seek is still pending does not overwrite ABS", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(2, 0)
    w.session:stop()
    H.eq(#w.progress, 0)
    H.eq(w.stops, 1)
end)

H.test("a seek that never lands writes nothing and does not end the session", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(2, 0)
    for _ = 1, 5 do w.runNext() end
    H.eq(#w.progress, 0)
    H.eq(w.session:isActive(), true)
end)

H.test("start reports the in-track offset so the UI can warn about slow seeks", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200 })
    local ok, note, offset = w.session:start(w.entry)
    H.eq(ok, true); H.eq(note, nil); H.eq(offset, 30)
end)

H.test("a player stopped from KinAMP's own screen still gets its last position sent once", function()
    local w = setup({ remote = { currentTime = 30 }, remote_code = 200 })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(1, 45) -- global 45, well away from the end of the 200 s book
    w.runNext()
    H.eq(w.progress[#w.progress].currentTime, 45)
    w.status = st(1, 52) -- global 52: moved 7 s, below the normal threshold
    w.runNext()
    H.eq(#w.progress, 1)
    w.status = { is_playing = false, is_paused = false, index = 1, path = paths[1], pos = 0 }
    w.runNext()
    H.eq(#w.progress, 2)
    H.eq(w.progress[2].currentTime, 52)
    w.runNext() -- still stopped: nothing new to send
    H.eq(#w.progress, 2)
end)

H.test("a cold start reconnects Bluetooth only once the seek has landed and audio is playing", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200, running = false })
    w.session:start(w.entry)
    w.runNext() -- afterStart: the seek is sent
    H.eq(w.events[1], "seek")
    H.eq(w.reconnects, 0)
    w.status = st(2, 0) -- KinAMP still decoding up to the position
    w.runNext()
    H.eq(w.reconnects, 0)
    w.status = st(2, 31) -- landed, playing
    w.runNext()
    H.eq(w.reconnects, 1)
    H.eq(w.events[2], "reconnect")
end)

H.test("a warm start does not touch Bluetooth", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200, running = true })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(2, 31)
    w.runNext()
    H.eq(w.reconnects, 0)
    H.eq(w.seeks[1], 30)
end)

H.test("a cold start from the very beginning also reconnects once playing", function()
    local w = setup({ remote = nil, remote_code = 404, running = false })
    w.session:start(w.entry)
    w.runNext()
    H.eq(#w.seeks, 0)
    w.status = st(1, 1)
    w.runNext()
    H.eq(w.reconnects, 1)
end)

H.test("the progress timer starts only after the reconnect has finished", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200, running = false, hold_reconnect = true })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(2, 31)
    w.runNext() -- landed: reconnect requested but not finished
    H.eq(w.reconnects, 1)
    H.eq(#w.scheduled, 0)
    w.reconnect_cb(true)
    H.eq(#w.scheduled, 1)
    w.status = st(2, 45)
    w.runNext() -- the first progress tick
    H.eq(#w.progress, 1)
    H.eq(w.progress[1].currentTime, 145)
end)

H.test("a failed Bluetooth reconnect still carries on to normal progress ticks", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200, running = false, reconnect_ok = false })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(2, 31)
    w.runNext()
    H.eq(w.reconnects, 1)
    H.eq(#w.scheduled, 1) -- the tick
end)

H.test("a seek that never lands stops waiting, never reconnects and falls back to ticks", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200, running = false })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(2, 0)
    local guard = 0
    while #w.scheduled > 0 and guard < 200 do
        local before = #w.progress
        w.runNext()
        guard = guard + 1
        if w.scheduled[1] and w.scheduled[1].s == Session.TICK_SECONDS then break end
    end
    H.eq(w.reconnects, 0)
    H.eq(#w.progress, 0)
    H.truthy(guard <= Session.LAND_MAX_TRIES + 2, "waited longer than allowed")
    H.eq(w.scheduled[1].s, Session.TICK_SECONDS)
end)

H.test("a reconnect that finishes after the session ended schedules nothing", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200, running = false, hold_reconnect = true })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(2, 31)
    w.runNext()
    w.session:stop()
    w.reconnect_cb(true)
    H.eq(#w.scheduled, 0)
end)

H.test("stopping while waiting for the seek cancels the wait", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200, running = false })
    w.session:start(w.entry)
    w.runNext()
    w.status = st(2, 0)
    w.session:stop()
    H.eq(#w.scheduled, 0)
    H.eq(w.reconnects, 0)
end)

H.test("playback resumes the configured number of seconds before the ABS position", function()
    local w = setup({ remote = { currentTime = 160 }, remote_code = 200, rewind = 30 })
    w.session:start(w.entry)
    H.eq(w.played[1].index, 2)
    w.runNext()
    H.eq(w.seeks[1], 30) -- 160 - 30 = 130: 30 s into file 2, not 60
end)

H.test("a rewind can cross into the previous file", function()
    local w = setup({ remote = { currentTime = 110 }, remote_code = 200, rewind = 30 })
    w.session:start(w.entry)
    H.eq(w.played[1].index, 1)
    w.runNext()
    H.eq(w.seeks[1], 80)
end)

H.test("unsent progress is pushed as the real position, not the rewound one", function()
    local w = setup({ remote = { currentTime = 20 }, remote_code = 200, rewind = 30 })
    w.entry.last_sent = 150
    w.entry.unsynced = true
    w.session:start(w.entry)
    H.eq(w.progress[1].currentTime, 150)
    w.runNext()
    H.eq(w.seeks[1], 20) -- resumes at 120
end)

H.test("a cold start tells the user KinAMP is starting", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200, running = false })
    w.session:start(w.entry)
    H.eq(w.notes[1], "Starting KinAMP...")
end)

H.test("a warm start shows no start-up message", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200, running = true })
    w.session:start(w.entry)
    H.eq(#w.notes, 0)
end)

H.test("with the reconnect switched off a cold start never touches Bluetooth and syncs normally", function()
    local w = setup({ remote = { currentTime = 130 }, remote_code = 200, running = false, reconnect = false })
    w.session:start(w.entry)
    w.runNext() -- afterStart: seek sent, progress tick scheduled straight away
    H.eq(w.seeks[1], 30)
    H.eq(#w.scheduled, 1)
    H.eq(w.scheduled[1].s, Session.TICK_SECONDS)
    w.status = st(2, 45)
    w.runNext()
    H.eq(w.reconnects, 0)
    H.eq(#w.progress, 1)
    H.eq(w.progress[1].currentTime, 145)
end)
