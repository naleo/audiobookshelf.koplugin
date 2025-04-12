local config = require("audiobookshelf_config")
local T = require("ffi/util").template
local JSON = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local socket = require("socket")
local logger = require("logger")

local VERSION = require("hardcover_version")

local AudiobookshelfApi = {
}

function AudiobookshelfApi:getLibraries()
    local sink = {}
    local request = {
        url = config.server .. "/api/libraries",
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. config.token,
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local code, _, status = socket.skip(1, http.request(request))
    local response = table.concat(sink)
    if code == 200 and response ~= "" then
        local _, result = pcall(JSON.decode, response)
        return result.libraries
    end
    logger.warn("AudiobookshelfApi: cannot get libraries", status or code)
    logger.warn("AudiobookshelfApi: error:", response)
end

function AudiobookshelfApi:getLibraryItems(id)
    local sink = {}
    local data
    -- this is "ebooks" base64 encoded, and the URL encoded, to only return library items with ebooks
    local filters = "ebooks." .. "ZWJvb2s%3D"
    local request = {
        url = config.server .. "/api/libraries/" .. id .. "/items?filter=" .. filters .. "&sort=media.metadata.title&limit=0",
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. config.token,
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local code, _, status = socket.skip(1, http.request(request))
    local response = table.concat(sink)
    if code == 200 and response ~= "" then
        local _, result = pcall(JSON.decode, response)
        return result.results
    end
    logger.warn("AudiobookshelfApi: cannot get library items for library", id ,status or code)
    logger.warn("AudiobookshelfApi: error:", response)
end

return AudiobookshelfApi
