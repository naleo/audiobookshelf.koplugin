local H = require("harness")
local PM = require("audiobookshelf/positionmap")

local function item(files) return { media = { audioFiles = files } } end
local function f(index, duration, extra)
    local t = {
        index = index, ino = "ino" .. index, duration = duration,
        metadata = { filename = "f" .. index .. ".mp3", size = 1000 * index },
    }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

H.test("buildTracks orders by index and accumulates offsets", function()
    local tracks, total = PM.buildTracks(item({ f(2, 50), f(1, 100), f(3, 25) }))
    H.eq(#tracks, 3)
    H.eq(tracks[1].ino, "ino1")
    H.eq(tracks[1].startOffset, 0)
    H.eq(tracks[2].startOffset, 100)
    H.eq(tracks[3].startOffset, 150)
    H.eq(total, 175)
    H.eq(tracks[2].name, "f2.mp3")
    H.eq(tracks[2].size, 2000)
end)

H.test("buildTracks skips excluded, invalid, zero and missing duration", function()
    local tracks, total = PM.buildTracks(item({
        f(1, 100), f(2, 50, { exclude = true }), f(3, 50, { invalid = true }),
        f(4, 0), f(5, nil), f(6, 10),
    }))
    H.eq(#tracks, 2)
    H.eq(total, 110)
    H.eq(tracks[2].ino, "ino6")
end)

H.test("buildTracks gives empty result for items with no audio", function()
    local t1, n1 = PM.buildTracks(item({}))
    H.eq(#t1, 0); H.eq(n1, 0)
    local t2, n2 = PM.buildTracks({ media = {} })
    H.eq(#t2, 0); H.eq(n2, 0)
    local t3, n3 = PM.buildTracks(nil)
    H.eq(#t3, 0); H.eq(n3, 0)
end)

local tracks = PM.buildTracks(item({ f(1, 100), f(2, 100) }))

H.test("toTrackPos maps inside a track", function()
    local i, o = PM.toTrackPos(tracks, 130)
    H.eq(i, 2); H.eq(o, 30)
end)

H.test("toTrackPos puts an exact boundary at the start of the next track", function()
    local i, o = PM.toTrackPos(tracks, 100)
    H.eq(i, 2); H.eq(o, 0)
end)

H.test("toTrackPos clamps negative, beyond-total and garbage input", function()
    local i, o = PM.toTrackPos(tracks, -5)
    H.eq(i, 1); H.eq(o, 0)
    i, o = PM.toTrackPos(tracks, 9999)
    H.eq(i, 2); H.eq(o, 100)
    i, o = PM.toTrackPos(tracks, "abc")
    H.eq(i, 1); H.eq(o, 0)
    i, o = PM.toTrackPos(tracks, nil)
    H.eq(i, 1); H.eq(o, 0)
end)

H.test("toTrackPos returns nil for no tracks", function()
    H.eq(PM.toTrackPos({}, 10), nil)
end)

H.test("toGlobal adds the start offset", function()
    H.eq(PM.toGlobal(tracks, 2, 30), 130)
    H.eq(PM.toGlobal(tracks, 1, 0), 0)
end)

H.test("toGlobal clamps pos and rejects unknown tracks", function()
    H.eq(PM.toGlobal(tracks, 1, 500), 100)
    H.eq(PM.toGlobal(tracks, 1, -3), 0)
    H.eq(PM.toGlobal(tracks, 3, 10), nil)
    H.eq(PM.toGlobal(tracks, nil, 10), nil)
end)

H.test("round trip", function()
    local i, o = PM.toTrackPos(tracks, 175)
    H.eq(PM.toGlobal(tracks, i, o), 175)
end)
