local H = require("harness")
local Store = require("audiobookshelf/audiostore")
local Downloader = require("audiobookshelf/audiodownloader")

local tracks = {
    { ino = "a", name = "a.mp3", size = 10, duration = 100, startOffset = 0 },
    { ino = "b", name = "b.mp3", size = 20, duration = 50, startOffset = 100 },
}
local function newEntry() return Store.makeEntry("item1", "Book", "A", "/d/Book", tracks, 150) end

local function fakeFs(files)
    local fs = { files = files or {}, removed = {}, written = {} }
    function fs.mkdir_p(dir) fs.dir = dir; return true end
    function fs.size(path) return fs.files[path] end
    function fs.rename(a, b)
        if fs.files[a] == nil then return nil end
        fs.files[b] = fs.files[a]; fs.files[a] = nil
        return true
    end
    function fs.remove(path) fs.removed[#fs.removed + 1] = path; fs.files[path] = nil; return true end
    function fs.write(path, text) fs.written[path] = text; return true end
    return fs
end

local function fakeApi(fs, code, sizes)
    local api = { calls = {} }
    function api:downloadFile(id, ino, filename, dir)
        api.calls[#api.calls + 1] = ino .. ":" .. filename
        if code ~= 200 then return code end
        fs.files[dir .. "/" .. filename] = sizes[ino]
        return 200
    end
    return api
end

local SIZES = { a = 10, b = 20 }

H.test("downloads every missing file, writes the m3u and marks complete", function()
    local fs = fakeFs()
    local api = fakeApi(fs, 200, SIZES)
    local e = newEntry()
    local progress = {}
    local ok = Downloader.run({ api = api, fs = fs, entry = e,
        on_progress = function(i, n) progress[#progress + 1] = i .. "/" .. n end })
    H.eq(ok, true)
    H.eq(#api.calls, 2)
    H.eq(api.calls[1], "a:001-a.mp3.part")
    H.eq(fs.files["/d/Book/001-a.mp3"], 10)
    H.eq(fs.files["/d/Book/002-b.mp3"], 20)
    H.eq(fs.written["/d/Book/book.m3u"], "#EXTM3U\n/d/Book/001-a.mp3\n/d/Book/002-b.mp3\n")
    H.eq(e.complete, true)
    H.eq(progress[1], "1/2"); H.eq(progress[2], "2/2")
end)

H.test("skips files that are already complete", function()
    local fs = fakeFs({ ["/d/Book/001-a.mp3"] = 10 })
    local api = fakeApi(fs, 200, SIZES)
    H.eq(Downloader.run({ api = api, fs = fs, entry = newEntry() }), true)
    H.eq(#api.calls, 1)
    H.eq(api.calls[1], "b:002-b.mp3.part")
end)

H.test("replaces a file whose size is wrong", function()
    local fs = fakeFs({ ["/d/Book/001-a.mp3"] = 3 })
    local api = fakeApi(fs, 200, SIZES)
    H.eq(Downloader.run({ api = api, fs = fs, entry = newEntry() }), true)
    H.eq(fs.removed[1], "/d/Book/001-a.mp3")
    H.eq(fs.files["/d/Book/001-a.mp3"], 10)
end)

H.test("an http failure removes the partial file and reports the code", function()
    local fs = fakeFs()
    local api = fakeApi(fs, 500, SIZES)
    local e = newEntry()
    local ok, err = Downloader.run({ api = api, fs = fs, entry = e })
    H.eq(ok, nil); H.eq(err, "download_failed:500")
    H.eq(fs.removed[1], "/d/Book/001-a.mp3.part")
    H.eq(e.complete, false)
end)

H.test("a wrong downloaded size is rejected", function()
    local fs = fakeFs()
    local api = fakeApi(fs, 200, { a = 9, b = 20 })
    local ok, err = Downloader.run({ api = api, fs = fs, entry = newEntry() })
    H.eq(ok, nil); H.eq(err, "size_mismatch")
end)

H.test("cancelling stops before the next file", function()
    local fs = fakeFs()
    local api = fakeApi(fs, 200, SIZES)
    local ok, err = Downloader.run({ api = api, fs = fs, entry = newEntry(), cancelled = function() return true end })
    H.eq(ok, nil); H.eq(err, "cancelled")
    H.eq(#api.calls, 0)
end)

H.test("preflight refuses files over the FAT limit", function()
    local e = newEntry(); e.tracks[1].size = 4294967296
    local ok, err = Downloader.preflight(e, nil)
    H.eq(ok, nil); H.eq(err, "file_too_large")
end)

H.test("preflight refuses when there is not enough space, allows unknown space", function()
    local e = newEntry()
    local ok, err = Downloader.preflight(e, 29)
    H.eq(ok, nil); H.eq(err, "no_space")
    H.eq(Downloader.preflight(e, 30), true)
    H.eq(Downloader.preflight(e, nil), true)
end)

H.test("preflight only counts files that are not already on disk", function()
    local fs = fakeFs({ ["/d/Book/001-a.mp3"] = 10 })
    local e = newEntry()
    local ok, err = Downloader.preflight(e, 19, fs)
    H.eq(ok, nil); H.eq(err, "no_space")
    H.eq(Downloader.preflight(e, 20, fs), true)
end)

H.test("run can be driven step by step from a coroutine", function()
    local fs = fakeFs()
    local api = fakeApi(fs, 200, SIZES)
    local e = newEntry()
    local co = coroutine.create(function()
        return Downloader.run({ api = api, fs = fs, entry = e,
            on_progress = function() coroutine.yield("tick") end })
    end)
    local steps = 0
    while true do
        local ok, a = coroutine.resume(co)
        H.truthy(ok, tostring(a))
        if coroutine.status(co) == "dead" then H.eq(a, true); break end
        steps = steps + 1
    end
    H.eq(steps, 2)
    H.eq(e.complete, true)
end)

H.test("a cancel requested while paused between files prevents the next download", function()
    local fs = fakeFs()
    local api = fakeApi(fs, 200, SIZES)
    local cancelled = false
    local co = coroutine.create(function()
        return Downloader.run({ api = api, fs = fs, entry = newEntry(),
            cancelled = function() return cancelled end,
            on_progress = function() coroutine.yield("tick") end })
    end)
    coroutine.resume(co) -- paused in on_progress for file 1
    cancelled = true     -- the user taps while the UI has control
    local ok, result, err = coroutine.resume(co)
    H.truthy(ok)
    H.eq(result, nil); H.eq(err, "cancelled")
    H.eq(#api.calls, 0)
end)
