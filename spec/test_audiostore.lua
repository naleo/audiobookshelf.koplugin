local H = require("harness")
local Store = require("audiobookshelf/audiostore")

local function fakeSettings()
    local data = {}
    return {
        readSetting = function(_, k) return data[k] end,
        saveSetting = function(_, k, v) data[k] = v end,
        flush = function() end,
    }
end

H.test("sanitize replaces unsafe characters", function()
    H.eq(Store.sanitize('A/B:C*D?E"F<G>H|I\\J'), "A_B_C_D_E_F_G_H_I_J")
    H.eq(Store.sanitize("tab\there"), "tab_here")
end)

H.test("sanitize trims, strips leading dots and falls back", function()
    H.eq(Store.sanitize("  hello  "), "hello")
    H.eq(Store.sanitize("..hidden"), "hidden")
    H.eq(Store.sanitize(""), "audiobook")
    H.eq(Store.sanitize(nil), "audiobook")
    H.eq(Store.sanitize("..."), "audiobook")
end)

H.test("sanitize caps long unicode names on a character boundary", function()
    local name = Store.sanitize(string.rep("\195\169", 200)) -- 200 x "e acute", 2 bytes each
    H.truthy(#name <= 120, "too long")
    H.eq(#name % 2, 0, "cut a character in half")
end)

H.test("trackFilename pads the index and keeps the extension", function()
    H.eq(Store.trackFilename(1, "Chapter 1.mp3"), "001-Chapter 1.mp3")
    H.eq(Store.trackFilename(12, "dir/sub/x:y.m4b"), "012-x_y.m4b")
    H.eq(Store.trackFilename(3, nil), "003-track")
end)

H.test("trackFilename gives the same name different files for different indexes", function()
    H.truthy(Store.trackFilename(1, "same.mp3") ~= Store.trackFilename(2, "same.mp3"))
end)

H.test("buildM3u writes a header and one path per line", function()
    H.eq(Store.buildM3u({ "/a/1.mp3", "/a/2.mp3" }), "#EXTM3U\n/a/1.mp3\n/a/2.mp3\n")
    H.eq(Store.buildM3u({ "/a/bad\nname.mp3" }), "#EXTM3U\n/a/badname.mp3\n")
end)

local tracks = {
    { ino = "a", name = "a.mp3", size = 10, duration = 100, startOffset = 0 },
    { ino = "b", name = "b.mp3", size = 20, duration = 50, startOffset = 100 },
}

H.test("makeEntry assigns filenames and absolute paths", function()
    local e = Store.makeEntry("item1", "Book", "Author", "/d/Book", tracks, 150)
    H.eq(e.item_id, "item1"); H.eq(e.total, 150); H.eq(e.complete, false)
    H.eq(e.m3u, "/d/Book/book.m3u")
    H.eq(e.tracks[2].path, "/d/Book/002-b.mp3")
    H.eq(e.tracks[2].startOffset, 100)
    local p = Store.paths(e)
    H.eq(#p, 2); H.eq(p[1], "/d/Book/001-a.mp3")
end)

H.test("store persists, updates last_sent and removes", function()
    local s = Store.new(fakeSettings())
    local e = Store.makeEntry("item1", "Book", "A", "/d/Book", tracks, 150)
    s:put(e)
    H.eq(s:get("item1").title, "Book")
    s:setLastSent("item1", 77)
    H.eq(s:get("item1").last_sent, 77)
    s:setLastSent("missing", 5) -- no entry: must not create one
    H.eq(s:get("missing"), nil)
    s:remove("item1")
    H.eq(s:get("item1"), nil)
end)

H.test("dirFor trims slashes and disambiguates clashing titles", function()
    local s = Store.new(fakeSettings())
    H.eq(s:dirFor("/d//", "Book", "id-one"), "/d/Book")
    s:put(Store.makeEntry("id-one", "Book", "A", "/d/Book", tracks, 150))
    H.eq(s:dirFor("/d", "Book", "id-one"), "/d/Book")
    H.eq(s:dirFor("/d", "Book", "id-two-xyz"), "/d/Book (id-two-x)")
end)

H.test("setLastSent records whether the position still needs sending", function()
    local s = Store.new(fakeSettings())
    s:put(Store.makeEntry("item1", "Book", "A", "/d/Book", tracks, 150))
    s:setLastSent("item1", 40, true)
    H.eq(s:get("item1").unsynced, true)
    s:setLastSent("item1", 40, false)
    H.eq(s:get("item1").unsynced, false)
    s:setLastSent("item1", 41)
    H.eq(s:get("item1").unsynced, false)
end)
