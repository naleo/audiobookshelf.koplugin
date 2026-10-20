local H = require("harness")
local KC = require("audiobookshelf/kinampcover")

-- Stands in for KinAMP's player widget: setCover lives on the class, instances inherit it.
local Class = {}
Class.__index = Class
function Class:setCover(path) self.calls[#self.calls + 1] = path or "nil" end
local function newPlayer() return setmetatable({ calls = {} }, Class) end

H.test("apply shows our cover straight away", function()
    local p = newPlayer()
    H.eq(KC.apply(p, "/d/Book/cover.jpg", function() return true end), true)
    H.eq(p.calls[1], "/d/Book/cover.jpg")
end)

H.test("a track with no artwork keeps getting our cover while the session is active", function()
    local p = newPlayer()
    KC.apply(p, "/d/Book/cover.jpg", function() return true end)
    p:setCover(nil) -- KinAMP reports no artwork on a track change
    H.eq(p.calls[#p.calls], "/d/Book/cover.jpg")
end)

H.test("embedded artwork that KinAMP found is never replaced", function()
    local p = newPlayer()
    KC.apply(p, "/d/Book/cover.jpg", function() return true end)
    p:setCover("/tmp/kinamp_cover.jpg")
    H.eq(p.calls[#p.calls], "/tmp/kinamp_cover.jpg")
end)

H.test("once the session is over KinAMP's own behaviour comes back", function()
    local active = true
    local p = newPlayer()
    KC.apply(p, "/d/Book/cover.jpg", function() return active end)
    active = false
    p:setCover(nil)
    H.eq(p.calls[#p.calls], "nil")
end)

H.test("applying twice wraps once and the latest book wins", function()
    local p = newPlayer()
    KC.apply(p, "/d/A/cover.jpg", function() return true end)
    local n = #p.calls
    KC.apply(p, "/d/B/cover.jpg", function() return true end)
    H.eq(#p.calls, n + 1) -- one original call per apply, not two
    H.eq(p.calls[#p.calls], "/d/B/cover.jpg")
    p:setCover(nil)
    H.eq(p.calls[#p.calls], "/d/B/cover.jpg")
end)

H.test("apply refuses things it cannot patch", function()
    H.eq(KC.apply(nil, "/c.jpg", function() return true end), false)
    H.eq(KC.apply({}, "/c.jpg", function() return true end), false)
    H.eq(KC.apply(newPlayer(), nil, function() return true end), false)
end)
