local config = require("audiobookshelf_config")
local T = require("ffi/util").template
local JSON = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local socket = require("socket")
local logger = require("logger")
local RenderImage = require("ui/renderimage")

local VERSION = require("audiobookshelf_version")

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
        local _, result = pcall(JSON.decode, response, JSON.decode.simple)
        return result.results
    end
    logger.warn("AudiobookshelfApi: cannot get library items for library", id ,status or code)
    logger.warn("AudiobookshelfApi: error:", response)
end

function AudiobookshelfApi:getLibraryItem(id)
    local sink = {}
    local request = {
        url = config.server .. "/api/items/" .. id .. "?expanded=1",
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
        local _, result = pcall(JSON.decode, response, JSON.decode.simple)
        return result
    end
    logger.warn("AudiobookshelfApi: cannot get library items for library", id ,status or code)
    logger.warn("AudiobookshelfApi: error:", response)
end

function AudiobookshelfApi:downloadFile(id, ino, local_path)
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local request = {
        url = config.server .. "/api/items/" .. id .. "/file/" .. ino .. "/download",
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. config.token,
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.file(io.open(local_path, "w")),
    }
    local code, _, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    if code ~= 200 then
        logger.warn("AudiobookshelfApi: cannot download file:", id , ino, status or code)
    end
    return code
end


function AudiobookshelfApi:getLibraryItemCover(id)
    local sink = {}
    local request = {
        url = config.server .. "/api/items/" .. id .. "/cover?format=webp",
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
        local result = RenderImage:renderImageData(response, #response)
        return result
    end
    logger.warn("AudiobookshelfApi: cannot get library items for library", id ,status or code)
    logger.warn("AudiobookshelfApi: error:", response)

end

return AudiobookshelfApi
