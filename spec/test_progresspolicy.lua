local H = require("harness")
local Policy = require("audiobookshelf/progresspolicy")

local tracks = { { startOffset = 0, duration = 100 }, { startOffset = 100, duration = 100 } }
local paths = { "/b/1.mp3", "/b/2.mp3" }

local function status(index, pos, state)
    return {
        is_playing = state == nil or state == "playing",
        is_paused = state == "paused",
        index = index, path = paths[index], pos = pos,
    }
end

local function decide(st, last, min_delta)
    return Policy.decide({ status = st, tracks = tracks, paths = paths, last_sent = last, min_delta = min_delta })
end

H.test("no status means no daemon", function()
    local pos, why = decide(nil, nil)
    H.eq(pos, nil); H.eq(why, "no_daemon")
end)

H.test("stopped daemon is not active", function()
    local st = status(1, 5); st.is_playing = false; st.is_paused = false
    local pos, why = decide(st, nil)
    H.eq(pos, nil); H.eq(why, "not_active")
end)

H.test("paused counts as active", function()
    H.eq(decide(status(2, 30, "paused"), nil), 130)
end)

H.test("no track index", function()
    local st = status(1, 5); st.index = nil
    local pos, why = decide(st, nil)
    H.eq(pos, nil); H.eq(why, "no_track")
end)

H.test("path that is not ours is ignored", function()
    local st = status(1, 5); st.path = "/music/other.mp3"
    local pos, why = decide(st, nil)
    H.eq(pos, nil); H.eq(why, "path_mismatch")
end)

H.test("first reading is sent", function()
    H.eq(decide(status(1, 42), nil), 42)
end)

H.test("movement below the threshold is not sent", function()
    local pos, why = decide(status(1, 45), 40)
    H.eq(pos, nil); H.eq(why, "below_threshold")
end)

H.test("movement at the threshold is sent, forward or back", function()
    H.eq(decide(status(1, 50), 40), 50)
    H.eq(decide(status(1, 30), 40), 30)
end)

H.test("a forced sync uses a smaller threshold", function()
    H.eq(decide(status(1, 45), 40, 1), 45)
end)

H.test("zero right after progress is ignored", function()
    local pos, why = decide(status(1, 0), 120)
    H.eq(pos, nil); H.eq(why, "zero_after_progress")
end)

H.test("zero is fine when nothing was sent yet or last was zero", function()
    H.eq(decide(status(1, 0), nil), 0)
    H.eq(decide(status(1, 0), 0, 0), 0)
end)

H.test("missing pos is treated as zero and guarded the same way", function()
    local st = status(1, nil)
    local pos, why = decide(st, 120)
    H.eq(pos, nil); H.eq(why, "zero_after_progress")
end)
