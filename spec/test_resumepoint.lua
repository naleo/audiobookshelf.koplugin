local H = require("harness")
local RP = require("audiobookshelf/resumepoint")

local tracks = { { startOffset = 0, duration = 100 }, { startOffset = 100, duration = 100 } }
local function entry(o)
    local e = { total = 200, tracks = tracks }
    for k, v in pairs(o or {}) do e[k] = v end
    return e
end

H.test("an ABS position is used as is", function()
    local r = RP.resolve(entry(), { currentTime = 130 }, 200)
    H.eq(r.seconds, 130); H.eq(r.last_sent, 130); H.eq(r.source, "abs"); H.eq(r.offline, false)
end)

H.test("a finished book starts from the beginning", function()
    local r = RP.resolve(entry(), { currentTime = 199, isFinished = true }, 200)
    H.eq(r.seconds, 0); H.eq(r.last_sent, nil); H.eq(r.source, "finished")
end)

H.test("a position inside the finish window restarts", function()
    local r = RP.resolve(entry(), { currentTime = 195 }, 200)
    H.eq(r.seconds, 0); H.eq(r.raw, 195); H.eq(r.last_sent, nil); H.eq(r.source, "restart")
end)

H.test("no progress yet (404) starts at zero and is not offline", function()
    local r = RP.resolve(entry(), nil, 404)
    H.eq(r.seconds, 0); H.eq(r.source, "start"); H.eq(r.offline, false)
end)

H.test("an unreachable ABS falls back to the saved position and is offline", function()
    local r = RP.resolve(entry({ last_sent = 150 }), nil, nil)
    H.eq(r.seconds, 150); H.eq(r.last_sent, 150); H.eq(r.source, "local"); H.eq(r.offline, true)
    local none = RP.resolve(entry(), nil, nil)
    H.eq(none.seconds, 0); H.eq(none.source, "start"); H.eq(none.offline, true)
end)

H.test("progress not yet sent to ABS beats ABS's older position", function()
    local r = RP.resolve(entry({ last_sent = 150, unsynced = true }), { currentTime = 20 }, 200)
    H.eq(r.seconds, 150); H.eq(r.source, "unsynced"); H.eq(r.last_sent, nil)
end)

H.test("unsynced progress near the end also restarts", function()
    local r = RP.resolve(entry({ last_sent = 199, unsynced = true }), nil, nil)
    H.eq(r.seconds, 0); H.eq(r.raw, 199); H.eq(r.source, "restart")
end)

H.test("fmt shows m:ss under an hour and h:mm:ss from an hour", function()
    H.eq(RP.fmt(nil), "0:00")
    H.eq(RP.fmt(59), "0:59")
    H.eq(RP.fmt(1998), "33:18")
    H.eq(RP.fmt(3600), "1:00:00")
    H.eq(RP.fmt(6644), "1:50:44")
    H.eq(RP.fmt(-5), "0:00")
end)

H.test("describe gives overall position, percent, file and time inside the file", function()
    local d = RP.describe(tracks, 200, { seconds = 130, source = "abs" })
    H.eq(d.position, "2:10"); H.eq(d.total, "3:20"); H.eq(d.percent, 65)
    H.eq(d.track_index, 2); H.eq(d.track_count, 2); H.eq(d.track_time, "0:30")
    H.eq(d.note, nil)
end)

H.test("describe passes the source through as a note and handles the start", function()
    H.eq(RP.describe(tracks, 200, { seconds = 150, source = "local" }).note, "local")
    H.eq(RP.describe(tracks, 200, { seconds = 150, source = "unsynced" }).note, "unsynced")
    local d = RP.describe(tracks, 200, { seconds = 0, source = "finished" })
    H.eq(d.note, "finished"); H.eq(d.track_index, 1); H.eq(d.track_time, "0:00"); H.eq(d.percent, 0)
end)

H.test("a rewind moves the resume point back from an ABS position", function()
    local r = RP.resolve(entry(), { currentTime = 160 }, 200, 30)
    H.eq(r.seconds, 130); H.eq(r.raw, 160); H.eq(r.rewind, 30); H.eq(r.last_sent, 160); H.eq(r.source, "abs")
end)

H.test("a rewind never goes before the start and reports what it actually rewound", function()
    local r = RP.resolve(entry(), { currentTime = 20 }, 200, 30)
    H.eq(r.seconds, 0); H.eq(r.rewind, 20)
end)

H.test("saved and unsent positions are rewound too", function()
    local a = RP.resolve(entry({ last_sent = 150 }), nil, nil, 30)
    H.eq(a.seconds, 120); H.eq(a.source, "local")
    local b = RP.resolve(entry({ last_sent = 150, unsynced = true }), nil, nil, 30)
    H.eq(b.seconds, 120); H.eq(b.raw, 150); H.eq(b.source, "unsynced")
end)

H.test("starting over, finished and restart are never rewound", function()
    H.eq(RP.resolve(entry(), nil, 404, 30).rewind, 0)
    H.eq(RP.resolve(entry(), { currentTime = 199, isFinished = true }, 200, 30).rewind, 0)
    local r = RP.resolve(entry(), { currentTime = 195 }, 200, 30)
    H.eq(r.seconds, 0); H.eq(r.rewind, 0); H.eq(r.source, "restart")
end)

H.test("no rewind argument means no rewind", function()
    local r = RP.resolve(entry(), { currentTime = 160 }, 200)
    H.eq(r.seconds, 160); H.eq(r.rewind, 0)
end)

H.test("describe passes the rewind through", function()
    local d = RP.describe(tracks, 200, { seconds = 130, rewind = 30, source = "abs" })
    H.eq(d.rewind, 30)
end)
