local config = require("audiobookshelf_config")
local T = require("ffi/util").template
local http = require("socket.http")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local socket = require("socket")
local logger = require("logger")

local VERSION = require("hardcover_version")

local AudiobookshelfApi = {
}

local API_GET_LIBRARIES = config.server .. "/api/libraries"
local API_GET_LIBRARY_ITEMS = config.server .. "/api/libraries/{id}/items"

function AudiobookshelfApi:getLibraries()
    local sink = {}
    local request = {
        url = API_GET_LIBRARIES,
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. config.token,
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local code, _, status = socket.skip(1, http.request(request))
    logger.warn(code)
    logger.warn(status)
    logger.warn(sink)
end

return AudiobookshelfApi
