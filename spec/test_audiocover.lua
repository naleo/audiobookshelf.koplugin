local H = require("harness")
local Cover = require("audiobookshelf/audiocover")

local JPEG = "\255\216\255\224" .. string.rep("x", 200) -- JPEG magic plus filler
local entry = { item_id = "item1", dir = "/d/Book" }

local function fakeFs(files)
    local fs = { files = files or {}, writes = 0, fail_write = false }
    function fs.size(path) return fs.files[path] and #fs.files[path] or nil end
    function fs.read_bytes(path) return fs.files[path] end
    function fs.write_bytes(path, data)
        if fs.fail_write then return nil end
        fs.writes = fs.writes + 1
        fs.files[path] = data
        return true
    end
    return fs
end

local function fakeApi(bytes)
    local api = { calls = 0, widths = {} }
    function api:getCoverBytes(id, width)
        api.calls = api.calls + 1
        api.widths[#api.widths + 1] = width
        return bytes
    end
    return api
end

H.test("path is cover.jpg inside the book folder", function()
    H.eq(Cover.path(entry), "/d/Book/cover.jpg")
    H.eq(Cover.path({}), nil)
    H.eq(Cover.path(nil), nil)
end)

H.test("fetch returns JPEG bytes and asks ABS for a small image", function()
    local api = fakeApi(JPEG)
    H.eq(Cover.fetch(api, "item1"), JPEG)
    H.eq(api.widths[1], Cover.WIDTH)
end)

H.test("fetch rejects anything that is not a JPEG", function()
    H.eq(Cover.fetch(fakeApi("<html>error</html>"), "item1"), nil)
    H.eq(Cover.fetch(fakeApi(""), "item1"), nil)
    H.eq(Cover.fetch(fakeApi(nil), "item1"), nil)
    H.eq(Cover.fetch(fakeApi("\255\216"), "item1"), nil) -- too short to be an image
end)

H.test("ensure writes the cover once and reuses the file afterwards", function()
    local fs, api = fakeFs(), fakeApi(JPEG)
    H.eq(Cover.ensure(entry, api, fs), "/d/Book/cover.jpg")
    H.eq(fs.writes, 1)
    H.eq(Cover.ensure(entry, api, fs), "/d/Book/cover.jpg")
    H.eq(fs.writes, 1)
    H.eq(api.calls, 1)
end)

H.test("ensure gives nothing when the cover cannot be fetched or written", function()
    local fs = fakeFs()
    H.eq(Cover.ensure(entry, fakeApi(nil), fs), nil)
    H.eq(fs.writes, 0)
    local fs2 = fakeFs(); fs2.fail_write = true
    H.eq(Cover.ensure(entry, fakeApi(JPEG), fs2), nil)
end)

H.test("ensure ignores an empty or broken file on disk and fetches again", function()
    local fs = fakeFs({ ["/d/Book/cover.jpg"] = "" })
    local api = fakeApi(JPEG)
    H.eq(Cover.ensure(entry, api, fs), "/d/Book/cover.jpg")
    H.eq(api.calls, 1)
end)

H.test("ensure needs a folder", function()
    H.eq(Cover.ensure({ item_id = "i" }, fakeApi(JPEG), fakeFs()), nil)
    H.eq(Cover.ensure(nil, fakeApi(JPEG), fakeFs()), nil)
end)

H.test("bytes prefers the downloaded file over the network", function()
    local fs = fakeFs({ ["/d/Book/cover.jpg"] = JPEG })
    local api = fakeApi("other")
    H.eq(Cover.bytes(entry, "item1", api, fs), JPEG)
    H.eq(api.calls, 0)
end)

H.test("bytes falls back to the network for a book that is not downloaded", function()
    local api = fakeApi(JPEG)
    H.eq(Cover.bytes(nil, "item1", api, fakeFs()), JPEG)
    H.eq(api.calls, 1)
end)
