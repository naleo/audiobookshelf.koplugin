local config = require("audiobookshelf_config")
local T = require("ffi/util").template
local JSON = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local socket = require("socket")
local logger = require("logger")
local RenderImage = require("ui/renderimage")
local util = require("util")
local LuaSettings = require("luasettings")

local VERSION = require("audiobookshelf_version")

local AudiobookshelfApi = {
    abs_settings = LuaSettings:open("plugins/audiobookshelf.koplugin/audiobookshelf_config.lua")
}

function AudiobookshelfApi:getLibraries()
    local sink = {}
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/libraries",
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.abs_settings:readSetting("token"),
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local ok, code, _, status = pcall(function() return socket.skip(1, http.request(request)) end)
    local response = table.concat(sink)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("AudiobookshelfApi: http request failed in getLibraries:", code)
        return nil
    end
    if code == 200 and response ~= "" then
        local _, result = pcall(JSON.decode, response)
        return result.libraries
    end
    logger.warn("AudiobookshelfApi: cannot get libraries", status or code)
    logger.warn("AudiobookshelfApi: error:", response)
    return nil
end

function AudiobookshelfApi:getLibraryItems(id)
    local sink = {}
    -- this is "ebooks" base64 encoded, and the URL encoded, to only return library items with ebooks
    local filters = "ebooks." .. "ZWJvb2s%3D"
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/libraries/" .. id .. "/items?filter=" .. filters .. "&sort=media.metadata.title&limit=0",
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.abs_settings:readSetting("token"),
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local ok, code, _, status = pcall(function() return socket.skip(1, http.request(request)) end)
    local response = table.concat(sink)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("AudiobookshelfApi: http request failed in getLibraryItems:", code)
        return nil
    end
    if code == 200 and response ~= "" then
        local _, result = pcall(JSON.decode, response, JSON.decode.simple)
        return result.results
    end
    logger.warn("AudiobookshelfApi: cannot get library items for library", id ,status or code)
    logger.warn("AudiobookshelfApi: error:", response)
    return nil
end

function AudiobookshelfApi:getLibraryItem(id)
    local sink = {}
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/items/" .. id .. "?expanded=1",
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.abs_settings:readSetting("token"),
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local ok, code, _, status = pcall(function() return socket.skip(1, http.request(request)) end)
    local response = table.concat(sink)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("AudiobookshelfApi: http request failed in getLibraryItem:", code)
        return nil
    end
    if code == 200 and response ~= "" then
        local _, result = pcall(JSON.decode, response, JSON.decode.simple)
        return result
    end
    logger.warn("AudiobookshelfApi: cannot get library item", id ,status or code)
    logger.warn("AudiobookshelfApi: error:", response)
    return nil
end

function AudiobookshelfApi:downloadFile(id, ino, filename, local_path)
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local outfile, err = io.open(local_path .. "/" .. filename, "w")
    if not outfile then
        logger.warn("AudiobookshelfApi: cannot open local file for writing:", local_path .. "/" .. filename, err)
        socketutil:reset_timeout()
        return nil
    end
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/items/" .. id .. "/file/" .. ino .. "/download",
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.abs_settings:readSetting("token"),
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.file(outfile),
    }
    local ok, code, _, status = pcall(function() return socket.skip(1, http.request(request)) end)
    socketutil:reset_timeout()
    if not ok or code ~= 200 then
        logger.warn("AudiobookshelfApi: cannot download file:", id , ino, status or code)
    end
    return code
end

function AudiobookshelfApi:getLibraryItemCover(id)
    local sink = {}
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/items/" .. id .. "/cover?format=webp",
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.abs_settings:readSetting("token"),
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local ok, code, _, status = pcall(function() return socket.skip(1, http.request(request)) end)
    local response = table.concat(sink)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("AudiobookshelfApi: http request failed in getLibraryItemCover:", code)
        return nil
    end
    if code == 200 and response ~= "" then
        local result = RenderImage:renderImageData(response, #response)
        return result
    end
    logger.warn("AudiobookshelfApi: cannot get library item cover", id ,status or code)
    logger.warn("AudiobookshelfApi: error:", response)
    return nil
end

function AudiobookshelfApi:getSearchResults(id, search_query)
    local sink = {}
    local url_encoded_search_string = util.urlEncode(search_query)
    -- this is "ebooks" base64 encoded, and the URL encoded, to only return library items with ebooks
    local filters = "ebooks." .. "ZWJvb2s%3D"
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/libraries/" .. id .. "/search?q=" .. url_encoded_search_string .. "&filter=" .. filters,
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.abs_settings:readSetting("token"),
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.table(sink),
    }
    socketutil:set_timeout()
    local ok, code, _, status = pcall(function() return socket.skip(1, http.request(request)) end)
    local response = table.concat(sink)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("AudiobookshelfApi: http request failed in getSearchResults:", code)
        return nil
    end
    if code == 200 and response ~= "" then
        local _, result = pcall(JSON.decode, response, JSON.decode.simple)
        return result
    end
    logger.warn("AudiobookshelfApi: cannot search library", id ,search_query, status or code)
    logger.warn("AudiobookshelfApi: error:", response)
    return nil
end

function AudiobookshelfApi:getProgress(library_item_id)
    local sink = {}
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/me/progress/" .. library_item_id,
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.abs_settings:readSetting("token"),
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
        },
        sink = ltn12.sink.table(sink),
    }
    socketutil:set_timeout(5, 10)
    local ok, code, _, status = pcall(function() return socket.skip(1, http.request(request)) end)
    local response = table.concat(sink)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("AudiobookshelfApi: http request failed in getProgress:", code)
        return nil, "network_error"
    end
    if code == 200 and response ~= "" then
        local _, result = pcall(JSON.decode, response)
        return result
    elseif code == 404 then
        return nil, "no_progress"
    end
    logger.warn("AudiobookshelfApi: cannot get progress", library_item_id, status or code)
    return nil, "api_error"
end

function AudiobookshelfApi:updateProgress(library_item_id, progress_data)
    local sink = {}
    local body = JSON.encode(progress_data)
    local request = {
        url = self.abs_settings:readSetting("server") .. "/api/me/progress/" .. library_item_id,
        method = "PATCH",
        headers = {
            ["Authorization"] = "Bearer " .. self.abs_settings:readSetting("token"),
            ["User-Agent"] = T("audiobookshelf.koplugin/%1", table.concat(VERSION, ".")),
            ["Content-Type"] = "application/json",
            ["Content-Length"] = #body,
        },
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(sink),
    }
    socketutil:set_timeout(5, 10)
    local ok, code, _, status = pcall(function() return socket.skip(1, http.request(request)) end)
    local response = table.concat(sink)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("AudiobookshelfApi: http request failed in updateProgress:", code)
        return nil, "network_error"
    end
    if code == 200 then
        local _, result = pcall(JSON.decode, response)
        return result
    end
    logger.warn("AudiobookshelfApi: cannot update progress", library_item_id, status or code)
    logger.warn("AudiobookshelfApi: error:", response)
    return nil, "api_error"
end

return AudiobookshelfApi